;;; helheim-latex.el -*- lexical-binding: t; no-byte-compile: t -*-
;;; Commentary:
;;
;; Fast LaTeX-math entry for Org notes (math study). This follows what
;; Karthink calls the "moderate" stack:
;;
;;   CDLaTeX   — the workhorse. Insertion triggered by a key:
;;               `a -> \alpha, '^ -> \hat{}, auto-braced after _ or ^, and
;;               equ<TAB> -> environment. (Modifier keys are ^ for hat,
;;               - for bar, > for vec, b for mathbf, and so on — see
;;               `cdlatex-math-modify-alist-comb'. There is no 'h.)
;;   aas       — a small, curated set of snippets that expand automatically
;;               as you type, gated on `+latex-in-math-p' so they only
;;               trigger inside math (// -> \frac, sr -> ^2, -> -> \to,
;;               ...), plus two context-sensitive behaviours ported from
;;               `laas': automatic subscripts (x 1 -> x_1, then 2 ->
;;               x_{12}) and wrapping fractions (x^2// -> \frac{x^2}{}).
;;   math-delimiters — `$' inserts or toggles between \( \) and \[ \]
;;   lazytab   — amsmath matrix / array entry via orgtbl syntax
;;               (provisional in Org; see the note below).
;;
;;
;;; Code:
;;;; texmathp (via AUCTeX)

;; Org's `org-cdlatex-mode' calls (org-require-package 'texmathp "Auctex") and
;; signals a `user-error' when texmathp is missing. This aborts `org-mode-hook',
;; taking every hook after it down with it. CDLaTeX degrades gracefully on its
;; own (it falls back to `cdlatex--texmathp' = `ignore'), but Org does not
;; tolerate texmathp's absence, so AUCTeX is a hard dependency here.
(setup auctex
  (:install t)
  ;; Load texmathp EAGERLY, and before cdlatex, because cdlatex resolves its
  ;; math predicate only once, at load time.
  (:require texmathp)
  ;; Just in case cdlatex still wins the race, re-point the alias afterward.
  (with-eval-after-load 'cdlatex
    (when (and (fboundp 'texmathp)
               (eq (symbol-function 'cdlatex--texmathp) #'ignore))
      (defalias 'cdlatex--texmathp #'texmathp))))

;;;; CDLaTeX

(setup cdlatex
  (:install t)
  (:setopt cdlatex-auto-help-delay 0.5)
  (:hook org-mode-hook turn-on-org-cdlatex))

(setup corfu
  (add-hook '+corfu-inhibit-auto-functions #'+latex-inhibit-corfu-auto-p)
  (:after-load
    (:keymap corfu-map
      (:bind
        "<tab>" `( menu-item "Next candidate, or expand a CDLaTeX keyword"
                   corfu-next :filter ,(lambda (cmd)
                                         (if (+latex-cdlatex-keyword-before-point)
                                             #'cdlatex-tab
                                           cmd)))))))

;;;; Auto-expanding snippets (curated, math-context-gated)

(setup aas
  (:install t)
  (:hook org-mode-hook aas-activate-for-major-mode)
  (:after-load
    ;; Only the multi-character expansions that CDLaTeX does not already
    ;; cover with a single keypress. All gated on being inside math, so they
    ;; never fire in prose. Prune to taste.
    (aas-set-snippets 'org-mode
      :cond #'+latex-in-math-p
      "//"  #'+latex-frac
      "sr"  "^{2}"
      "cb"  "^{3}"
      "ooo" "\\infty"
      "..." "\\dots"
      "->"  "\\to"
      "|->" "\\mapsto"
      "!="  "\\neq"
      "=="  "\\equiv"
      ">="  "\\geq"
      "<="  "\\leq"
      "EE"  "\\exists"
      "AA"  "\\forall"
      "inn" "\\in"
      "notin" "\\notin"

      ;; Sized delimiters. Doubled, like `//', so a single `(' still stays a
      ;; plain paren. `<<' is left out -- it is more often wanted as \ll.
      "((" #'+latex-insert-delimiters
      "[[" #'+latex-insert-delimiters
      "{{" #'+latex-insert-delimiters
      "||" #'+latex-insert-delimiters

      ;; Automatic subscripts. Note the different condition: these expand
      ;; only where a script makes sense, and that same condition also tells
      ;; the expander whether to open, widen, or extend the script.
      ;;
      ;; Add index arithmetic here if you want it, e.g. "np1" "_{n+1}".
      :cond #'+latex--auto-script-condition
      "0"  #'+latex-insert-script
      "1"  #'+latex-insert-script
      "2"  #'+latex-insert-script
      "3"  #'+latex-insert-script
      "4"  #'+latex-insert-script
      "5"  #'+latex-insert-script
      "6"  #'+latex-insert-script
      "7"  #'+latex-insert-script
      "8"  #'+latex-insert-script
      "9"  #'+latex-insert-script
      "ii" #'+latex-insert-script
      "jj" #'+latex-insert-script
      "nn" #'+latex-insert-script
      "kk" #'+latex-insert-script)))

;;;; math-delimiters — smart `$'

(setup math-delimiters
  (:install math-delimiters :host github :repo "oantolin/math-delimiters")
  (:require t)
  (:setopt cdlatex-use-dollar-to-ensure-math nil
           math-delimiters-inline  '("\\(" . "\\)")
           math-delimiters-display '("\\[" . "\\]")
           math-delimiters-compressed-display-math nil))

;;;; lazytab — matrix / array entry

;; lazytab is undocumented and built primarily for LaTeX-mode buffers,
;; where orgtbl-mode provides the tabular entry surface. In Org it hooks
;; into `cdlatex-tab' and adds matrix templates to `cdlatex-command-alist'.
;; Insert a matrix with `+latex-insert-matrix' or by typing e.g. `bmat' and
;; invoking `cdlatex-tab'.
(setup lazytab
  (:install lazytab :host github :repo "karthink/lazytab")
  (:after cdlatex)
  (:require t)
  (:hook org-mode-hook lazytab-mode)
  (:after-load
    (setq cdlatex-command-alist
          (-cons* '("smat" "Insert smallmatrix env"
                    "\\left(\\begin{smallmatrix} ? \\end{smallmatrix}\\right)"
                    lazytab-position-cursor-and-edit nil nil t)
                  '("bmat" "Insert bmatrix env"
                    "\\begin{bmatrix} ? \\end{bmatrix}"
                    lazytab-position-cursor-and-edit nil nil t)
                  '("pmat" "Insert pmatrix env"
                    "\\begin{pmatrix} ? \\end{pmatrix}"
                    lazytab-position-cursor-and-edit nil nil t)
                  '("mat" "Insert matrix env"
                    "\\begin{matrix} ? \\end{matrix}"
                    lazytab-position-cursor-and-edit nil nil t)
                  cdlatex-command-alist))))

(defun +latex-insert-matrix ()
  "Insert a bmatrix template and start lazytab's orgtbl entry."
  (interactive)
  (insert "bmat")
  (cdlatex-tab))

;;;; Preview

;; Requires Org 10.0
(setup org-latex-preview
  (:hook org-mode-hook org-latex-preview-mode)
  (:setopt org-startup-with-latex-preview t
           org-latex-preview-process-default 'dvisvgm
           org-latex-preview-mode-display-live t
           org-latex-preview-mode-update-delay 0.25
           org-latex-packages-alist
           '(("T2A" "fontenc" t ("pdflatex"))
             "\\ifdefined\\XeTeXrevision\\def\\pgfsysdriver{pgfsys-dvisvgm.def}\\fi"
             ("" "tikz" t)
             "\\usetikzlibrary{arrows.meta,positioning,calc,decorations.pathreplacing,patterns,matrix,fit,backgrounds}")))

;;;; Keys

(defvar-keymap helheim-latex-math-map
  :doc "LaTeX-math commands for Org buffers."
  :prefix 'helheim-latex-math-map
  "l"  '("latex environment" . cdlatex-environment)
  "m"  '("matrix" . +latex-insert-matrix)
  "$"  '("math delimiters" . math-delimiters-insert)
  "?"  'cdlatex-command-help
  ;; Sized delimiters: surround the selection, or the object before point.
  ;; An opening character puts each delimiter on a line of its own; a closing
  ;; one keeps the pair on one line. Outside math, ( and ) open inline math
  ;; and [ and ] open display math; there the fragment sets the layout.
  "("  '("block  ( )" . +latex-surround)
  ")"  '("inline ( )" . +latex-surround)
  "["  '("block  [ ]" . +latex-surround)
  "]"  '("inline [ ]" . +latex-surround)
  "{"  '("block  { }" . +latex-surround)
  "}"  '("inline { }" . +latex-surround)
  "<"  '("block  < >" . +latex-surround)
  ">"  '("inline < >" . +latex-surround)
  "|"  '("inline | |" . +latex-surround))

(setup org
  (:after-load
    (:keymap org-mode-map
      (:bind :state normal
        "m l" `("latex" . helheim-latex-math-map))
      (:bind :state insert
        "$" 'math-delimiters-insert))))

;;; .
(provide 'helheim-latex)
;;; helheim-latex.el ends here
