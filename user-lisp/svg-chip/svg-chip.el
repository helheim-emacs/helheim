;;; svg-chip.el --- -*- lexical-binding: t -*-
;;
;; Copyright © 2026 Yuriy Artemyev
;;
;; Author: Yuriy Artemyev <anuvyklack@gmail.com>
;; Maintainer: Yuriy Artemyev <anuvyklack@gmail.com>
;; Created: August 4, 2026
;; Version: 0.0.1
;; Homepage: https://github.com/helheim-emacs/helheim
;; Package-Requires: ((emacs "29.1") (dash "2.19.1") (svg-lib "0.3"))
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Draw pieces of a buffer as rounded SVG chips -- a keyword, a tag, a date,
;; anything a regexp can find. The code does not depend on any major mode:
;; `svg-chip-rules' says what to draw, and `svg-chip-mode' draws it. A major
;; mode that wants chips sets the rules buffer-locally and turns the mode on.
;;
;; `svg-lib' does the actual drawing: given a string and a style, it returns
;; an SVG image. This package adds the following things on top of it:
;;
;;   `svg-chip'          Turn a string plus a style into the image
;;   `svg-chip-rules'    What text to match, and what to draw over it
;;   `svg-chip-mode'     Puts the images on a `display' property, and
;;                       shows the underlying text again when the cursor
;;                       reaches it

;;; Code:

(require 'dash)
(require 'subr-x)
(require 'svg)
(require 'svg-lib)
(require 'cursor-sensor)

(defgroup svg-chip nil
  "Draw pieces of a buffer as rounded SVG chips."
  :group 'convenience
  :prefix "svg-chip-")

;;; Cache

(defcustom svg-chip-cache-size 2000
  "How many chip images to keep before the cache is emptied.
An entry holds about half a kilobyte of SVG, so the default bounds the cache
at roughly a megabyte. Going over the limit throws the whole cache away and
refills it on demand, which costs a redraw of the chips currently on screen."
  :type 'natnum
  :group 'svg-chip)

(defvar svg-chip--cache (make-hash-table :test #'equal)
  "The chip images drawn so far. See `svg-chip-with-cache'.")

(defun svg-chip-clear-cache ()
  "Throw away every chip image drawn so far, so that they are drawn again.
Nothing invalidates the cache on its own, so this is how to pick up a
change it cannot see -- an icon that failed to download while the machine
was offline, for one.

The cache is shared by every buffer, so every buffer drawing chips is
refontified, not just this one."
  (interactive)
  (clrhash svg-chip--cache)
  (-each (buffer-list)
    (lambda (buffer)
      (with-current-buffer buffer
        (when (bound-and-true-p svg-chip-mode)
          (font-lock-flush))))))

(defmacro svg-chip-with-cache (key &rest body)
  "Return the chip image kept under KEY, drawing it with BODY if there is none.

Drawing a chip takes around 260 microseconds, and font-lock draws every
visible chip again on each re-fontification, so any renderer is worth
wrapping in this. `svg-chip' already wraps itself.

KEY must name everything the image depends on: the label, the style, and the
*resolved* attributes of every face the renderer reads -- resolved, not the
face symbol, so that a new theme produces a new key instead of a stale image.
That is what lets the cache go without any invalidation.

The font metrics are added to KEY here, so that a caller cannot leave them
out. `default-font-width' and `default-font-height' read the current buffer's
default face, and so follow `face-remapping-alist' -- which is what
`text-scale-adjust' changes. They are also about ten times cheaper than the
`window-font-width' svg-lib itself calls, and this key is built on every
single lookup."
  (declare (indent 1)
           (debug (form body)))
  (cl-with-gensyms (k)
    `(let ((,k (append ,key (list (default-font-width)
                                  (default-font-height)
                                  line-spacing))))
       (when (>= (hash-table-count svg-chip--cache) svg-chip-cache-size)
         (clrhash svg-chip--cache))
       (with-memoization (gethash ,k svg-chip--cache)
         ,@body))))

;;; Drawing a chip

(defvar svg-chip-background nil
  "Colour to fill a chip with, in place of the one its face gives it.

A chip is drawn to sit on the buffer's own background: it takes it from the
`:background' of the face the chip is drawn in, which for most faces is the
default background. Bind this around a call that draws a chip somewhere
else -- on the band of a table, say, where a chip filled with the default
background would read as a hole in it.")

(defun svg-chip (label &rest args)
  "Draw LABEL as a rounded chip and return the image.

ARGS are the style keywords that `svg-lib-text-tag' accepts -- see
`svg-lib-style-default' for the full list -- plus three keywords of our own:

  `:face'     A face, a property list, or a colour string, used to colour
              the chip.
  `:inverse'  Fill the chip with the foreground colour instead of just
              outlining it.
  `:icon'     Name of an icon to draw. With an empty LABEL, only the icon
              is drawn. `:collection' names which collection the icon comes
              from; see `svg-lib-icon-collections' for the choices."
  ;; Strip the properties: only the characters are drawn, and a label kept as
  ;; a cache key would otherwise hold on to the major mode's faces and keymaps.
  (setq label (substring-no-properties (string-trim label)))
  (let* ((face (plist-get args :face))
         (foreground (svg-chip--face-attribute face :foreground))
         (background (or svg-chip-background
                         (svg-chip--face-attribute face :background)))
         (icon (plist-get args :icon))
         ;; `svg-lib-style' uses the first value it finds for a key, so putting
         ;; ARGS first lets the caller's values override our defaults below.
         ;; It also only looks for keys it knows about, so our three extra
         ;; keys (`:face', `:inverse', `:icon') just get ignored, unharmed.
         (style (append args
                        (if (plist-get args :inverse)
                            (list :foreground background :background foreground
                                  :stroke 0 :font-weight 'semibold)
                          (list :foreground foreground :background background
                                :stroke 2 :font-weight 'regular))
                        (list :margin 0 :radius 5))))
    (svg-chip-with-cache (list label args foreground background)
      (if icon
          (svg-chip--icon icon label style)
        ;; We use `svg-lib-text-tag', not `svg-lib-tag': `svg-lib-tag' treats
        ;; a label like "[star]" as the name of an icon and tries to look it up.
        (apply #'svg-lib-text-tag label nil style)))))

(defun svg-chip--face-attribute (face attribute)
  "Return the value of ATTRIBUTE for FACE.
FACE can be anything a face variable may hold: a face symbol, a property
list, or a string naming a foreground colour."
  (cond ((facep face)
         (face-attribute face attribute nil 'default))
        ((and (stringp face) (eq attribute :foreground))
         face)
        ;; `plist-member', not `plist-get': a plist that names an attribute
        ;; owns it, even where the value it gives is nil.  A plist that leaves
        ;; one out says nothing about it and falls through to the default,
        ;; which is how `(:foreground "red")' draws red on whatever background
        ;; the buffer already has.
        ((and (consp face) (plist-member face attribute))
         (plist-get face attribute))
        (t
         (face-attribute 'default attribute nil 'default))))

(defun svg-chip--icon (icon label style)
  "Draw ICON, with LABEL next to it unless LABEL is empty.
STYLE is a style plist, passed to `svg-lib-icon'."
  ;; Drawing an icon for the first time downloads it and saves it under
  ;; `svg-lib-icons-dir'. This fails if the collection does not have that
  ;; icon name. An error here would stop font-lock from fontifying the rest
  ;; of the buffer, so we catch it below and fall back to a plain text chip.
  (condition-case error
      (if (string-empty-p label)
          (apply #'svg-lib-icon icon nil style)
        (apply #'svg-lib-icon+tag icon label nil style))
    (error
     ;; `svg-lib--icon-get-data' caches whatever the server sent back -- even
     ;; a 404 error page -- and never checks it again. We delete that cached
     ;; file here, otherwise one failed download would break this icon forever.
     (let* ((collection (or (plist-get style :collection)
                            (plist-get (svg-lib-style-default--get) :collection)))
            (file (-> (format "%s_%s.svg" collection icon)
                      (expand-file-name svg-lib-icons-dir))))
       (when (file-exists-p file)
         (delete-file file)))
     (message "svg-chip: icon %S: %s" icon (error-message-string error))
     ;; This fallback is cached like any other image, so a download is tried
     ;; once per key rather than on every redraw -- a download runs inside
     ;; font-lock and freezes Emacs while it waits. A new theme or a
     ;; `text-scale-adjust' makes a new key and so tries again; nothing else
     ;; does, short of `svg-chip-clear-cache'.
     (apply #'svg-lib-text-tag
            (if (string-empty-p label) icon label)
            nil style))))

;;; Rules

(defvar-local svg-chip-rules nil
  "What to draw as a chip in this buffer, and how.

A list of (MATCHER . SPEC) rules. `svg-chip-mode' turns them into font-lock
keywords once per buffer, when it starts. Earlier rules win over later ones.

MATCHER is the same as in `font-lock-keywords': either the regexp to search for,
or the function name to call to make the search (called with one argument, the
limit of the search; it should return non-nil, move point, and set `match-data'
appropriately if it succeeds; like `re-search-forward' would).

Group 1 of the match is the text the chip covers: the chip is drawn over
exactly that text, and nothing outside it is touched.

SPEC says what to draw over that text. It is either:

- a plist of `svg-chip' arguments. The chip is labelled with group 2 if the
  regexp has one, and with group 1 otherwise. This is how a rule draws less
  text than it covers: with \"<2026-08-08>\" as group 1 and \"2026-08-08\" as
  group 2, the angle brackets disappear behind the chip without being drawn
  on it.

- a renderer -- a function that returns the image to draw. It is called with
  the whole of group 1, exactly as it stands in the buffer, and decides for
  itself what to make of it. The match data is still in place while it runs,
  so a renderer is also free to read further groups, or the text around the
  match, with `match-string' and friends.

SPEC can also include a `:predicate' function. If it returns nil, the match
is skipped and no chip is drawn.

The rules are buffer-local. Set them in a major-mode hook, and then turn on
`svg-chip-mode'.")

(defvar-local svg-chip-extra-font-lock-keywords nil
  "Extra `font-lock-keywords' entries, for anything `svg-chip-rules' cannot
express. Take priority over the rules.")

(defvar-local svg-chip-predicate #'svg-chip-not-in-string-p
  "The default predicate for whether a match from `svg-chip-rules' should
become a chip. A rule can override this with its own `:predicate' instead.

The predicate takes three arguments (START END TEXT): the START and END
positions of the matched text, and the TEXT itself.")

(defun svg-chip-not-in-string-p (start _end _text)
  "Return non-nil unless START is inside a string."
  (not (or (memq 'font-lock-string-face
                 (ensure-list (get-text-property start 'face)))
           (if font-lock-keywords-only
               (nth 3 (syntax-ppss start))))))

(defun svg-chip-render (renderer &optional predicate)
  "Return the text properties that draw this match as a chip with RENDERER,
or nil if PREDICATE rejects the match.

RENDERER is called with the whole of group 1, and with the match data still
describing this match, so it may read the other groups itself.

Point and the match data are restored before this returns, so a caller may go
on using `match-beginning' and friends."
  (let ((beg (match-beginning 1))
        (end (match-end 1))
        ;; Without `-no-properties', a renderer caching this text as part of
        ;; a key would keep the major mode's faces and keymaps alive with it.
        (text (match-string-no-properties 1))
        (predicate (or predicate svg-chip-predicate)))
    (save-excursion
      ;; The two `save-match-data' serve two different readers. The outer one
      ;; puts the match back for whoever called us, since a renderer is free
      ;; to search -- `string-trim' alone is enough to lose it. The inner one
      ;; does the same for the renderer, whose match must survive the
      ;; predicate; `syntax-ppss' searches too.
      (save-match-data
        (when (and (save-match-data (funcall predicate beg end text))
                   ;; Nothing at all, not even the cursor sensor: the text is
                   ;; somebody else's to draw, and theirs to put back when the
                   ;; cursor reaches it.
                   (not (svg-chip--drawn-p beg end)))
          `(,@(unless (svg-chip--region-revealed-p beg end)
                `(display ,(funcall renderer text)))
            cursor-sensor-functions (svg-chip--cursor-sensor-function)))))))

(defun svg-chip--drawn-p (beg end)
  "Non-nil when something already draws the text from BEG to END.

A `display' property on that text belongs to whoever put it there first, and
a chip on top of it takes a bite out of the middle of their run. The display
engine draws a replacing string once per run, so the text they replaced then
appears twice, once on each side of the chip.

Such a match is left alone completely, the cursor sensor included. Revealing
the text under a chip means taking the `display' property off it, and taking
one off that this package did not put on would tear a hole in whatever the
other one is drawing.

This is what makes the promise in `svg-chip-rules' true, that an earlier rule
wins over a later one. It also keeps chips out of a region another package
draws whole -- a folded Org property drawer shown as a table, say."
  (and (text-property-not-all beg end 'display nil) t))

(defun svg-chip--highlight (renderer &optional predicate)
  "Return a font-lock FACENAME value drawing this match as a chip with RENDERER.
This is `svg-chip-render' in the shape font-lock wants. The leading `face'
is what makes `font-lock-apply-highlight' add the rest of the list as text
properties; the nil after it is what stops it setting a face of its own."
  (when-let* ((props (svg-chip-render renderer predicate)))
    `(face nil . ,props)))

(defun svg-chip--rule-parts (rule)
  "Return RULE from `svg-chip-rules' as (MATCHER RENDERER PREDICATE).
RENDERER is nil for a rule that says nothing this package understands."
  (-let* (((matcher . spec) rule)
          ((renderer predicate) (pcase spec
                                  ;; A style plist has no code of its own to
                                  ;; put the choice of label in, so the regexp
                                  ;; makes it: group 2 is the label when the
                                  ;; rule marks one out, group 1 when it does
                                  ;; not.
                                  ((pred plistp)
                                   (list (lambda (text)
                                           (apply #'svg-chip
                                                  (or (match-string-no-properties 2)
                                                      text)
                                                  spec))
                                         (plist-get spec :predicate)))
                                  ((and `(,fun . ,options)
                                        (guard (functionp fun)))
                                   (list fun (plist-get options :predicate))))))
    (list matcher renderer predicate)))

(defun svg-chip--convert-rule-to-font-lock-keyword (rule)
  "Return `font-lock-keywords' entry for RULE from `svg-chip-rules', or nil.
The rule's matcher is handed to font-lock as it is, so a regexp and a search
function both mean there exactly what they mean in `font-lock-keywords'."
  (-let [(matcher renderer predicate) (svg-chip--rule-parts rule)]
    (when renderer
      `(,matcher
        (1 (svg-chip--highlight ',renderer ',predicate))))))

(defun svg-chip--search (matcher limit)
  "Search forward up to LIMIT with MATCHER, from `svg-chip-rules'.
A matcher is what `font-lock-keywords' takes: the regexp to search for, or
the function to call with the limit of the search."
  (if (stringp matcher)
      (re-search-forward matcher limit t)
    (funcall matcher limit)))

(defun svg-chip-spans (beg end)
  "Return the chips `svg-chip-rules' would draw between BEG and END.

A list of (START END IMAGE): the text one chip covers, and the image drawn
over it. They come in buffer order and never overlap, an earlier rule
winning over a later one, and a match reaching outside BEG..END is left out.
`svg-chip-extra-font-lock-keywords' is not consulted -- only the rules are.

Nothing is put on the buffer here. This is for a caller that draws that
stretch of buffer itself and wants the chips in what it draws: a folded
property drawer shown as a table, say, where the images have to be placed by
whoever owns the region.  Bind `svg-chip-background' around the call to draw
them on a background of that caller's own."
  (let (spans)
    (save-excursion
      (save-match-data
        (dolist (rule svg-chip-rules)
          (-let [(matcher renderer predicate) (svg-chip--rule-parts rule)]
            (when renderer
              (let ((from beg))
                (while (and (< from end)
                            (progn (goto-char from)
                                   (svg-chip--search matcher end)))
                  (let ((start (match-beginning 1))
                        (finish (match-end 1)))
                    (when (and start
                               (<= beg start) (<= finish end)
                               (not (svg-chip--spanned-p spans start finish))
                               (save-match-data
                                 (funcall (or predicate svg-chip-predicate)
                                          start finish
                                          (match-string-no-properties 1))))
                      (push (list start finish
                                  (funcall renderer
                                           (match-string-no-properties 1)))
                            spans))
                    ;; A rule that can match the empty string would search
                    ;; from where it started for as long as it is let to.
                    (setq from (if (> (point) from) (point) (1+ from)))))))))))
    (sort spans (lambda (a b) (< (car a) (car b))))))

(defun svg-chip--spanned-p (spans start end)
  "Non-nil when one of SPANS already covers part of START to END."
  (--any? (and (< start (nth 1 it)) (< (nth 0 it) end)) spans))

;;; Revealing the chip under the cursor

(defcustom svg-chip-action-at-point 'edit
  "What to do when the cursor lands on a chip.
`edit' puts the chip's text back in place so it can be read and edited.
`echo' shows the text in the echo area. nil does nothing."
  :type '(radio (const :tag "Show the text in place" edit)
                (const :tag "Echo the text" echo)
                (const :tag "Do nothing" nil))
  :group 'svg-chip)

(defvar-local svg-chip--revealed-region nil
  "The (START . END) markers of the chip currently shown as plain text.")

(defun svg-chip--region-revealed-p (beg end)
  "Non-nil if the region from BEG to END overlaps `svg-chip--revealed-region'."
  (-when-let* (((revealed-beg . revealed-end) svg-chip--revealed-region))
    (and (< revealed-beg end)
         (< beg revealed-end))))

(defun svg-chip--cursor-sensor-function (_window _position direction)
  "Act on the chip the cursor just entered, according to `svg-chip-action-at-point'.
A `cursor-sensor-functions' entry. DIRECTION is documented there."
  (if (eq direction 'left)
      (svg-chip--redraw)
    ;; `svg-chip--bounds' finds a chip by its `display' property, which is
    ;; exactly the property a revealed chip lacks. Hence the bounds are saved
    ;; here rather than recomputed when the chip is redrawn.
    (-when-let* (((beg . end) (svg-chip--bounds)))
      (pcase svg-chip-action-at-point
        ('edit
         (unless (or view-read-only
                     buffer-read-only)
           (svg-chip--redraw)
           (setq svg-chip--revealed-region (cons (copy-marker beg)
                                                 (copy-marker end t)))
           (with-silent-modifications
             (remove-text-properties beg end '(display nil)))))
        ('echo
         (let ((message-log-max nil))
           (message "CHIP: %s"
                    (string-trim (buffer-substring-no-properties beg end)))))))))

(defun svg-chip--redraw ()
  "Redraw the last-revealed chip."
  (-when-let* (((beg . end) svg-chip--revealed-region))
    (setq svg-chip--revealed-region nil)
    (font-lock-flush beg end)
    (set-marker beg nil)
    (set-marker end nil)))

(cl-defun svg-chip--bounds (&optional (position (point)))
  "Return the bounds of the chip at POSITION, or nil if there is none.
POSITION counts as being on a chip both inside the chip's `display' region
and right after it, because `cursor-sensor-functions' is rear-sticky."
  (when-let* ((pos (cond ((get-text-property position 'display)
                          position)
                         ((if (< (point-min) position)
                              (get-text-property (1- position) 'display))
                          (1- position)))))
    (cons (or (previous-single-property-change (1+ pos) 'display)
              (point-min))
          (or (next-single-property-change pos 'display)
              (point-max)))))

;;; Entry point

(defvar-local svg-chip-mode--font-lock-keywords nil
  "The buffer-local `font-lock-keywords' entries installed by `svg-chip-mode'.")

;;;###autoload
(define-minor-mode svg-chip-mode
  "Draw the SVG chips according to `svg-chip-rules'."
  :lighter nil
  (if svg-chip-mode
      (progn
        (setq svg-chip-mode--font-lock-keywords
              (append svg-chip-extra-font-lock-keywords
                      (->> svg-chip-rules
                           (-map #'svg-chip--convert-rule-to-font-lock-keyword)
                           (delq nil))))
        ;; Append so our keywords run after the major mode's own.
        ;; This matters for `org-fontify-meta-lines-and-blocks': it strips
        ;; the `display' property off keyword lines, and would take our
        ;; `#+filetags:' chips with it if it ran after us.
        (font-lock-add-keywords nil svg-chip-mode--font-lock-keywords 'append)
        (setq-local font-lock-extra-managed-props
                    (-cons* 'display
                            'cursor-sensor-functions
                            font-lock-extra-managed-props))
        (add-hook 'text-scale-mode-hook #'font-lock-flush nil :local)
        (add-hook 'read-only-mode-hook #'font-lock-flush nil :local)
        (cursor-sensor-mode 1))
    ;; else
    (svg-chip--redraw)
    (font-lock-remove-keywords nil svg-chip-mode--font-lock-keywords)
    (setq svg-chip-mode--font-lock-keywords nil)
    ;; Remove the chip images from the buffer before `kill-local-variable',
    ;; while `display' property is still in `font-lock-extra-managed-props'.
    (save-restriction
      (widen)
      (font-lock-unfontify-region (point-min) (point-max)))
    (kill-local-variable 'font-lock-extra-managed-props)
    (remove-hook 'text-scale-mode-hook #'font-lock-flush :local)
    (remove-hook 'read-only-mode-hook #'font-lock-flush :local)
    (cursor-sensor-mode -1))
  (font-lock-flush))

;;; .
(provide 'svg-chip)
;;; svg-chip.el ends here
