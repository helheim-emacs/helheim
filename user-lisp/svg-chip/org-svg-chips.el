;;; org-svg-chips.el --- -*- lexical-binding: t; -*-
;;
;; Copyright © 2026 Yuriy Artemyev
;;
;; Author: Yuriy Artemyev <anuvyklack@gmail.com>
;; Maintainer: Yuriy Artemyev <anuvyklack@gmail.com>
;; Created: August 9, 2026
;; Version: 0.0.1
;; Homepage: https://github.com/helheim-emacs/helheim
;; Package-Requires: ((emacs "29.1") (dash "2.19.1") (org "9.6") (svg-chip "0.0.1"))
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

;; Draw Org TODO keywords, tags, cookies and timestamps as rounded SVG chips.
;;
;; `svg-chip' does the actual drawing and the font-lock plumbing, and does
;; not know about any major mode. This package is the Org-specific half: the
;; rules, the renderer functions behind them, the tag keyword, and the pass
;; over a finished agenda buffer.
;;
;; A major mode wanting chips sets `svg-chip-rules' buffer-locally and turns
;; `svg-chip-mode' on; here that wiring is done for Org:
;;
;;   (add-hook 'org-mode-hook #'org-svg-chips-mode)
;;   (add-hook 'org-agenda-finalize-hook #'org-svg-chips-agenda)

;;; Code:

(require 'dash)
(require 'subr-x)
(require 'svg-chip)
(require 'dom)
(require 'xml)
(require 'svg)
(require 'org)

(defgroup org-svg-chips nil
  "Draw Org keywords, tags, cookies and timestamps as SVG chips."
  :group 'org
  :group 'svg-chip
  :prefix "org-svg-chips-")

;;; Customization

(defcustom org-svg-chips-todo-styles nil
  "Chip style per Org TODO keyword, as an alist of (KEYWORD . STYLE).
STYLE is a plist of `svg-chip' arguments.

  (setopt org-svg-chips-todo-styles
          \\='((\"NEXT\" :inverse t)
            (\"BUG\"  :icon \"bug\")))

Keywords with no entry here are drawn according to `org-todo-keyword-faces'."
  :type '(alist :key-type (string :tag "TODO keyword")
                :value-type (plist :tag "Chip style"))
  :group 'org-svg-chips)

(defcustom org-svg-chips-tag-styles nil
  "Chip style per Org tag, as an alist of (TAG . STYLE).
STYLE is a plist of `svg-chip' arguments. It overrides the default style
that every tag chip gets. A tag styled with `:icon' is drawn as that
icon alone, with no tag name next to it:

  (setopt org-svg-chips-tag-styles
          \\='((\"attach\" :icon \"paperclip\")
            (\"cpp\"    :icon \"language-cpp\" :collection \"material\")
            (\"urgent\" :inverse t)))

Tags with no entry here are drawn in the `org-tag' face."
  :type '(alist :key-type (string :tag "Tag")
                :value-type (plist :tag "Chip style"))
  :group 'org-svg-chips)

;;; TODO keyword

(defun org-svg-chips-search-todo (limit)
  "Search forward up to LIMIT for a TODO keyword starting a headline.
A matcher function for `org-svg-chips-rules', with the calling
convention of a `font-lock-keywords' MATCHER."
  (when org-todo-regexp
    (re-search-forward (rx bol (+ "*") (+ " ")
                           (group-n 1 (regexp org-todo-regexp))
                           (or " " eol))
                       limit t)))

(defun org-svg-chips-render-todo (keyword)
  "Render the Org TODO KEYWORD as a chip."
  (let ((keyword-style (alist-get keyword org-svg-chips-todo-styles
                                  nil nil #'string-equal-ignore-case)))
    (apply #'svg-chip keyword (append keyword-style
                                      `(:face ,(org-get-todo-face keyword))))))

;;; Priority

(defconst org-svg-chips-priority-re
  (rx (group-n 1 "[#" (+ (any "A-Z" "0-9")) "]"))
  "Regexp matching an Org priority cookie.")

(defun org-svg-chips-render-priority (cookie)
  "Render the priority COOKIE as a chip."
  (svg-chip (string-trim cookie "\\[#" "\\]") :face 'org-priority))

;;; Statistics cookies [1/3] and [42%]

(defun org-svg-chips-render-progress (cookie)
  "Render the statistics COOKIE as a bar plus its text."
  (cl-callf string-trim cookie "\\[" "\\]")
  (svg-chip-with-cache (list 'progress cookie
                             (face-attribute 'org-done :foreground nil 'default)
                             (face-attribute 'default :foreground nil 'default)
                             (face-attribute 'default :background nil 'default))
    (let* ((value (if (string-suffix-p "%" cookie)
                      (/ (string-to-number cookie) 100.0)
                    (-let [(n m) (split-string cookie "/")]
                      (setq n (float (string-to-number n))
                            m (string-to-number m))
                      (if (zerop m) 0.0 (/ n m))))))
      (svg-image (svg-lib-concat
                  (svg-lib-progress-bar value 'org-done
                                        :margin 0 :stroke 2 :radius 3
                                        :padding 2 :width 6)
                  (svg-lib-text-tag cookie nil :stroke 0 :margin 0))
                 :ascent 'center))))

;;; Timestamp

;; The date part of an Org timestamp: ISO date plus the optional day name.
(let ((date "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\(?: [A-Za-z]\\{3\\}\\)?"))
  ;;
  ;; Group 2 matches the date, group 3 matches the time or repeater after it,
  ;; if there is one.
  (defconst org-svg-chips-active-timestamp-re
    (rx (group-n 1
          "<"
          (group-n 2 (regexp date))
          (opt " " (group-n 3 (regexp "[0-9+-][^>\n]*")))
          ">"))
    "Regexp matching org active timestamp.")
  ;;
  (defconst org-svg-chips-inactive-timestamp-re
    (rx (group-n 1
          "["
          (group-n 2 (regexp date))
          (opt " " (group-n 3 (regexp "[0-9+-][^]\n]*")))
          "]"))
    "Regexp matching org inactive timestamp."))

(defun org-svg-chips-render-timestamp (timestamp)
  "Render TIMESTAMP chip.
A timestamp that carries a time or a repeater -- \"<2026-08-08 Sat 14:00>\",
\"<2026-08-08 Sat +1w>\" -- is drawn as two tags glued into one image.

The date is read from group 2 of the match and the tail from group 3."
  (let* ((date (match-string-no-properties 2))
         (tail (match-string-no-properties 3))
         (face (if (string-prefix-p "<" timestamp) 'org-date 'shadow))
         (radius 5)) ; (plist-get (svg-lib-style-default--get) :radius)
    (if (not tail)
        (svg-chip date :face face :radius radius)
      (svg-chip-with-cache (list 'timestamp date tail
                                 (face-attribute face :foreground nil 'default)
                                 (face-attribute face :background nil 'default))
        ;; `:crop-right' widens the date's frame by one character, past the
        ;; seam, so that the frame's top and bottom lines carry on over the
        ;; tail instead of curving in. The overhang itself is hidden: the
        ;; tail is drawn second, on top of it.
        (let* ((left  (svg-chip date :face face :radius radius :crop-right t))
               (right (svg-chip tail :face face :radius radius :inverse t))
               (svg (svg-lib-concat left right))
               (seam (org-svg-chips--svg-width left)))
          ;; The tail's own two left corners are rounded, which would leave
          ;; the seam pinched. `:crop-left' cannot square them here: it works
          ;; by pushing the corners outside the image, and `svg-lib-concat'
          ;; copies both images onto one wider canvas, where there is no edge
          ;; left to cut them off. So they are painted over instead.
          (svg-rectangle svg seam 0 radius (dom-attr svg 'height)
                         :fill (face-attribute face :foreground nil 'default))
          (svg-image svg :ascent 'center))))))

(defun org-svg-chips--svg-width (image)
  "Return the width of IMAGE, an SVG image, in pixels."
  (with-temp-buffer
    (insert (plist-get (cdr image) :data))
    (-> (xml-parse-region (point-min) (point-max))
        (car)
        (dom-attr 'width)
        (string-to-number))))

;;; Tags

;; Tags cannot be express with the rules in `org-svg-chips-rules': one
;; regexp there produces one image, but a run of tags needs one image per tag.
;; A bare `:tag' regexp would match one tag, but with nothing to its left for
;; context it would also match `14:00', `[[id:...]]', `:results output' and
;; `localhost:8080'. So tags get their own font-lock keyword instead, anchored
;; to the headline, with its own loop over the tag run.
(defvar org-svg-chips--tags-font-lock-keywords
  (let* ((tags (rx (1+ ":" (regexp org-tag-re)) ":"))
         (heading-tags (rx bol (1+ "*") " " (*? nonl) (any " \t")
                           (group (regexp tags))
                           (0+ (any " \t")) eol))
         (filetags (rx bol (or "#+filetags:" "#+FILETAGS:") (1+ " ")
                       (group (regexp tags))
                       (0+ (any " \t")) eol)))
    `((,heading-tags
       (1 (org-svg-chips-fontify-tags)))
      (,filetags
       (1 (org-svg-chips-fontify-tags)))))
  "See `font-lock-keywords'.")

(defconst org-svg-chips--tag-re
  (rx (group-n 1 (opt ":") (regexp org-tag-re) ":"))
  "Regexp matching one Org tag, in the group layout `svg-chip-render' expects:
group 1 is the whole `:tag:' that the chip covers. The leading colon is
optional because the tag before this one has usually claimed it already.")

(defun org-svg-chips-render-tag (tag)
  "Return the chip image drawn for TAG, written as it is in the buffer:
\":work:\", or \"work:\" where the tag before it has already claimed the
leading colon.
`svg-chip' caches the image, so a tag drawn once is not drawn again."
  (let* ((tag (string-trim tag ":" ":"))
         (style (alist-get tag org-svg-chips-tag-styles
                           nil nil #'string-equal-ignore-case))
         (label (if (plist-get style :icon) "" tag)))
    (apply #'svg-chip label (append style '(:face org-tag :margin 1)))))

(defun org-svg-chips-fontify-tags ()
  "Draw one chip per tag, over the tag string that group 1 matched.
This is a font-lock FACENAME form: it applies the images itself and
returns nil, so font-lock does not add any face on top."
  (let ((end (match-end 1)))
    (save-excursion
      (goto-char (match-beginning 1))
      (while (re-search-forward org-svg-chips--tag-re end t)
        (when-let* ((props (svg-chip-render #'org-svg-chips-render-tag)))
          (add-text-properties (match-beginning 1) (match-end 1) props)))
      ;; In the agenda, a final tag that is entirely inherited gets an extra
      ;; trailing colon from `org-agenda-fix-displayed-tags'. That colon
      ;; belongs to no tag, since there is nothing after it to share it with.
      (when (< (point) end)
        (put-text-property (point) end 'display ""))))
  nil)

;;; Agenda
;;
;; An agenda buffer is not an Org buffer, so none of our font-lock keywords
;; reach it. Instead, it is walked once by hand, after `org-agenda-finalize'
;; has built it.

;;;###autoload
(defun org-svg-chips-agenda ()
  "Draw the chips in a finalized Org agenda buffer.
Meant for `org-agenda-finalize-hook', which runs with `inhibit-read-only'
already bound."
  (save-excursion
    (save-match-data
      (let ((case-fold-search nil))
        ;; TODO keywords
        (goto-char (point-min))
        (while (< (point) (point-max))
          ;; Every line carries the keyword regexp of the file it came from as
          ;; a text property.
          (when-let* ((re (get-text-property (point) 'org-todo-regexp))
                      ((re-search-forward (concat "[: ]" re " ")
                                          (pos-eol) t)))
            (put-text-property (match-beginning 1) (match-end 1)
                               'display (org-svg-chips-render-todo
                                         (match-string-no-properties 1))))
          (goto-char (min (1+ (pos-eol))
                          (point-max))))
        ;;
        ;; Tags
        (goto-char (point-min))
        (let ((re (rx " "
                      (group (1+ (opt ":") ":" (regexp org-tag-re))
                             ":" (opt ":"))
                      (0+ (any " \t")) eol)))
          (while (re-search-forward re nil t)
            (org-svg-chips-fontify-tags)))
        ;;
        ;; Priorities
        (goto-char (point-min))
        (while (re-search-forward org-svg-chips-priority-re nil t)
          (put-text-property (match-beginning 1) (match-end 1)
                             'display (org-svg-chips-render-priority
                                       (match-string-no-properties 1)))
          ;; `org-agenda-fontify-priorities' puts an overlay on these. We
          ;; blank its face here so it does not get painted over the chip.
          (dolist (ov (overlays-at (match-beginning 1)))
            (overlay-put ov 'face nil)))))))

;;; Entry point

(defvar org-svg-chips-predicate
  (lambda (beg _end _text)
    ;; `svg-chip-mode' appends its keywords after Org's own, so Org has already
    ;; fontified this text and the faces on it can simply be read.
    (not (-intersection (ensure-list (get-text-property beg 'face))
                        '(org-block org-code org-verbatim org-link))))
  "See `svg-chip-predicate'.
By default, it prevents chips from being rendered inside Org blocks, code,
verbatim text, and links.")

;; A matcher reaches font-lock as it stands, and font-lock reads it as either
;; a regexp string or a function to call. A symbol holding a regexp is not a
;; case it knows, so the named regexps are spliced in by value.
(defvar org-svg-chips-rules
  `(;; TODO keyword
    (org-svg-chips-search-todo org-svg-chips-render-todo)

    ;; Priority cookie
    (,org-svg-chips-priority-re org-svg-chips-render-priority)

    ;; Statistics cookies: [1/3] and [42%]
    ("\\(\\[[0-9]+/[0-9]+\\]\\)"   org-svg-chips-render-progress)
    ("\\(\\[[0-9]\\{1,3\\}%\\]\\)" org-svg-chips-render-progress)

    ;; Timestamp
    (,org-svg-chips-active-timestamp-re   org-svg-chips-render-timestamp)
    (,org-svg-chips-inactive-timestamp-re org-svg-chips-render-timestamp))
  "See `svg-chip-rules'.")

;;;###autoload
(define-minor-mode org-svg-chips-mode
  "Draw Org TODO keywords, tags, cookies and timestamps as SVG chips.
This is a thin front end for `svg-chip-mode': it hands over the Org
rules, the tag keyword, and the predicate, and lets that mode do the
actual drawing."
  :lighter nil
  (if org-svg-chips-mode
      (progn
        (setq-local svg-chip-rules org-svg-chips-rules)
        (setq-local svg-chip-extra-font-lock-keywords
                    org-svg-chips--tags-font-lock-keywords)
        (setq-local svg-chip-predicate org-svg-chips-predicate)
        (svg-chip-mode 1))
    ;; else
    (svg-chip-mode -1)
    (kill-local-variable 'svg-chip-rules)
    (kill-local-variable 'svg-chip-predicate)
    (kill-local-variable 'svg-chip-extra-font-lock-keywords)))

;;; .
(provide 'org-svg-chips)
;;; org-svg-chips.el ends here
