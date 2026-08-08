;;; helheim-pretty-org.el                             -*- lexical-binding: t -*-
;;; Code:

(require 'dash)
(require 'org)
(require 'hel)

;;; Add padding to headings

;; The padding is one tall, invisible stretch glyph: a `display' property of the
;; form (space ...) on the single space between the stars and the heading text.
;; A display line is as tall as its tallest glyph, so the heading line grows
;; around that space.
;;
;; The glyph has to sit on the heading line itself, not on the newline that ends
;; it. Folding a heading hides that newline: the fold overlay runs from the end
;; of the heading line to the last newline of the subtree, so a `line-height'
;; property there is skipped while the heading is folded, and the spacing
;; changes every time the fold opens and closes. The stars and the space after
;; them stay visible in both states.
;;
;; `:ascent' is what a scaled face cannot give. A face makes a character taller
;; in the proportion its font uses — for a typical font about four parts above
;; the baseline to one below — so the heading ends up with a wide gap above and
;; a thin one below. Naming the ascent as a percentage of the glyph height
;; decides that split instead:
;;
;;   glyph height = (1 + pa + pb) * H     glyph ascent = (a + pa) * H
;;   gap above    = (a+pa)H - aH                      = pa * H
;;   gap below    = (1+pa+pb)H - (a+pa)H - (1-a)H     = pb * H
;;
;; where H is the line height of the heading's face, `a' its font's ascent
;; ratio, and `pa' and `pb' the wanted padding above and below. The ratio `a'
;; cancels out, so each gap follows its own fraction whatever the font is.
;;
;; Both `:relative-width' and `:relative-height' are measured against the
;; heading's own face, so a theme that scales `org-level-N' keeps the padding
;; in proportion.

(defconst helheim-org--heading-padding-keywords
  '(("^\\*+\\( \\)"
     (1 (helheim-org--heading-padding-spec))))
  "Font-lock keywords that pad Org heading lines.
The match group is the space between the stars and the heading text.")

(defvar helheim-org--font-ascent-ratio 0.8
  "Ascent of the default font as a fraction of its full height.
Scaling a face keeps this ratio, so one value fits every heading level.
`helheim-org--setup-heading-padding' keeps it up to date.")

(defun helheim-org--update-font-ascent-ratio ()
  "Measure the default font and update `helheim-org--font-ascent-ratio'."
  (when-let* ((info (ignore-errors (font-info (face-font 'default))))
              (height (aref info 3)))
    (setq helheim-org--font-ascent-ratio (/ (float (aref info 8)) height))))

(defun helheim-org--heading-padding-spec ()
  "Return the `display' property that pads a heading line.
Returns nil when `helheim-org-heading-padding' is nil, which leaves the
line untouched."
  (when helheim-org-heading-padding
    (let* ((padding helheim-org-heading-padding)
           (above (if (consp padding) (car padding) padding))
           (below (if (consp padding) (cdr padding) padding))
           ;; The glyph carries the text plus one padding on each side.
           (height (+ 1 above below))
           ;; Of that height, the text's own ascent plus the padding above it
           ;; goes above the baseline.
           (ascent (/ (* 100.0 (+ helheim-org--font-ascent-ratio above))
                      height)))
      (list 'face nil 'display
            (list 'space :relative-width 1
                  :relative-height height
                  :ascent ascent)))))

(defun helheim-org--setup-heading-padding ()
  "Pad the heading lines of the current buffer."
  (helheim-org--update-font-ascent-ratio)
  (unless (memq 'display font-lock-extra-managed-props)
    ;; So that `font-lock-default-unfontify-region' drops the property again.
    (setq-local font-lock-extra-managed-props
                (cons 'display font-lock-extra-managed-props)))
  (font-lock-remove-keywords nil helheim-org--heading-padding-keywords)
  (font-lock-add-keywords nil helheim-org--heading-padding-keywords 'append))

;;; Prettify symbols mode

(defun helheim-org-prettify-compose-p (start end _match)
  "Like `prettify-symbols-default-compose-p', but ignore strings.
The default predicate refuses to compose anything for which `syntax-ppss'
reports that point is inside a string or comment. If you have an
unmatched quote, everything after the last quote in the buffer will be
treated as being inside a string and will be displayed unprettified."
  (let ((syntaxes-beg (if (memq (char-syntax (char-after start)) '(?w ?_))
                          '(?w ?_) '(?. ?\\)))
        (syntaxes-end (if (memq (char-syntax (char-before end)) '(?w ?_))
                          '(?w ?_) '(?. ?\\))))
    (not (or (memq (char-syntax (or (char-before start) ?\s)) syntaxes-beg)
             (memq (char-syntax (or (char-after end) ?\s)) syntaxes-end)))))

;;; .
(provide 'helheim-pretty-org '(lib))
;;; helheim-pretty-org.el ends here
