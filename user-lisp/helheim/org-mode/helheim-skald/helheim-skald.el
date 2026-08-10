;;; helheim-skald.el -*- lexical-binding: t; no-byte-compile: t -*-

(setup skald
  (:install skald :repo "~/code/helheim/skald/")
  (:after org)
  ;; Every command is autoloaded, so the package is loaded on first use.
  (:global-bind
    "C-c n s" (cons "skald"
                    (define-keymap
                      "t" '("tag table" . skald-table)
                      "l" '("tag list" . skald-list)
                      "b" '("insert block" . skald-insert-dblock))))
  (with-eval-after-load 'org-keys
    ;; The Org insert map, reached at ", i"
    (:keymap helheim-org-insert-map
      (:bind
        "f" '("set field" . skald-set-field))))
  (skald-mode 1))

;;; Pixel-exact vtable headers

;; This advice changes a built-in for every vtable in the session, which is
;; why it lives here rather than in Skald: a package may not reshape another
;; package's tables, and a configuration may.
;;
;; FIX: `vtable--insert-header-line' insets the sort indicator by half
;;   a character on each side of a header cell, written as two separate
;;   `(space :width FLOAT)' specs. Emacs truncates each spec on its own, so when
;;   a character is an odd number of pixels wide the two halves no longer add
;;   back up: every header column comes out one pixel narrower than the body
;;   column below it, and the error accumulates across the table.
;;
;;   An even character width makes both halves whole numbers, and they cancel
;;   exactly. Rounding up rather than down, because this width also scales the
;;   `ex' column widths, and a column one pixel too wide shows everything while
;;   one pixel too narrow truncates it.
(define-advice vtable--char-width (:filter-return (width) helheim)
  "Round WIDTH up to a whole even number of pixels."
  (if (zerop (mod width 2)) width (1+ width)))

;;; .
(provide 'helheim-skald)
;;; helheim-skald.el ends here
