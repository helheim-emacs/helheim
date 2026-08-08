;;; helheim-pretty-org.el -*- lexical-binding: t; no-byte-compile: t -*-

;; Add padding to headings
(defcustom helheim-org-heading-padding '(0.5 . 0.25)
  "Blank space above and below an Org mode heading line.
The value is a fraction of the heading's own line height, so 0.3 adds
about a third of a line. Body lines keep their normal spacing.

A single number pads both sides equally. A cons cell (ABOVE . BELOW)
sets each side on its own, so (0.45 . 0.15) leaves a wide gap above the
heading and a narrow one below it.

If nil — extra padding will be disabled.

Must be set with `setopt' function!"
  :type '(choice (number :tag "Same on both sides")
                 (cons :tag "Above and below"
                       (number :tag "Above")
                       (number :tag "Below"))
                 (const :tag "No padding" nil))
  :group 'helheim
  :set (lambda (symbol value)
         (set-default symbol value)
         (if value
             (add-hook 'org-mode-hook 'helheim-org--setup-heading-padding)
           (remove-hook 'org-mode-hook 'helheim-org--setup-heading-padding))
         (dolist (buffer (buffer-list))
           (with-current-buffer buffer
             (when (derived-mode-p 'org-mode)
               (if value
                   (helheim-org--setup-heading-padding)
                 (font-lock-remove-keywords nil helheim-org--heading-padding-keywords))
               (font-lock-flush))))))

(setup org
  ;; You may delete the hooks you don't like with:
  ;;   (remove-hook 'org-mode-hook 'helheim-org-prettify-todo-keywords)
  (:hook org-mode-hook org-svg-chips-mode)
  (:hook org-agenda-finalize-hook org-svg-chips-agenda)
  (:hook org-mode-hook (prettify-symbols-mode
                        ;; helheim-org-prettify-todo-keywords
                        helheim-org-prettify-blocks))
  (:setopt org-todo-keywords
           '((sequence "MAYBE" "TODO" "NEXT" "WAIT" "|" "DONE" "ARCHIVED" "SKIP" "CANCELLED")
             (sequence "READ" "NEXT" "|" "DONE")))
  (:after-load
    (load "helheim-pretty-org-lib" nil t)))

;; (defun helheim-org-prettify-todo-keywords ()
;;   "Beautify org mode \"todo\" keywords using `prettify-symbols-mode'."
;;   (setq-local prettify-symbols-compose-predicate #'helheim-org-prettify-compose-p)
;;   (cl-callf append prettify-symbols-alist
;;     '(("MAYBE"     . ?󰒅) ; 󰔌
;;       ("TODO"      . ?󰄱) ; 󰝣
;;       ("NEXT"      . ?󰡖) ; 󱗝
;;       ("WAIT"      . ?)
;;       ("DONE"      . ?󰄵) ; 󰱒 
;;       ("CANCELLED" . ?󰅘)
;;       ("READ"      . ?󰃃))))

(defun helheim-org-prettify-blocks ()
  "Beautify org mode block keywords using `prettify-symbols-mode'."
  (setq-local prettify-symbols-compose-predicate #'helheim-org-prettify-compose-p)
  (cl-callf append prettify-symbols-alist
    (eval-when-compile
      (mapcan (lambda (x) (list x (cons (upcase (car x)) (cdr x))))
              '(("#+begin_src"     . ?)
                ("#+end_src"       . ?)
                ("#+begin_example" . ?)
                ("#+end_example"   . ?)
                ("#+begin_quote"   . ?)
                ("#+end_quote"     . ?))))))

(setup org-superstar
  (:install t)
  (:after org)
  (:hook org-mode-hook org-superstar-mode)
  (setopt org-superstar-remove-leading-stars nil
          org-superstar-headline-bullets-list '("●")
          org-superstar-item-bullet-alist '((?- . ?•)
                                            (?+ . ?◦)
                                            (?* . ?‣))))

(setup org-appear
  (:install t)
  (:after org)
  (:hook org-mode-hook org-appear-mode)
  (setopt org-hide-emphasis-markers t))

;;; .
(provide 'helheim-pretty-org)
;;; helheim-pretty-org.el ends here
