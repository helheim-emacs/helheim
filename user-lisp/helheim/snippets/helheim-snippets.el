;;; helheim-snippets.el -*- lexical-binding: t; no-byte-compile: t -*-

(setup yasnippet
  (:install t)
  ;; The default snippet directory is under `user-emacs-directory', which
  ;; Helheim points at var/ and use for generated files only.
  (:setopt yas-snippet-dirs `(,(expand-file-name "snippets" helheim-root-directory))
           yas-verbosity (if debug-on-error 3 2)
           yas-wrap-around-region t)
  (yas-global-mode)
  ;; (:hook (prog-mode
  ;;         text-mode
  ;;         conf-mode) yas-minor-mode-on)
  ;;
  (:after-load
    (:keymap yas-minor-mode-map
      (:unbind
        "C-c & C-s"
        "C-c & C-n"
        "C-c & C-v"
        "C-c &") ; `org-mark-ring-goto' in Org buffers
      (:bind
        "C-c i i" '("insert snippet" . yas-insert-snippet)
        "C-c i n" '("create new snippet" . yas-new-snippet)
        "C-c i v" '("visit snippet" . yas-visit-snippet-file))))
  ;;
  (with-eval-after-load 'hippie-exp
    (add-to-list 'hippie-expand-try-functions-list 'yas-hippie-try-expand)))

(setup yasnippet-capf
  (:install t)
  ;; How far back `thing-at-point-looking-at' scans for the word to complete.
  ;; The default, nil, makes search till `point-min' on every keystroke.
  (:setopt yasnippet-capf-max-search-distance 20)
  (:hook (prog-mode-hook
          text-mode-hook
          conf-mode-hook
          lsp-completion-mode-hook) helheim-yas-setup-capf))

(defun helheim-yas-setup-capf ()
  "Show snippets in the completion menu."
  ;; Type "/" to open the completion menu with snippets.
  (setq-local corfu-auto-trigger "/")
  (add-hook 'completion-at-point-functions #'helheim-yas-trigger-capf -100 t)
  ;; Also add snippets to the general completion menu.
  (add-hook 'completion-at-point-functions #'helheim-yas-capf -90 t))

;;; .
(provide 'helheim-snippets)
;;; helheim-snippets.el ends here
