;;; helheim-lsp-mode.el -*- lexical-binding: t; no-byte-compile: t -*-

(setup lsp-mode
  (:install t)
  (:setopt lsp-keymap-prefix "C-c l"
           lsp-log-io nil
           lsp-enable-indentation t
           lsp-enable-imenu t
           lsp-file-watch-threshold 1000)
  (:after-load
    (lsp-enable-which-key-integration)
    (:hook hel-insert-state-exit-hook +lsp-close-signature)
    (:keymap lsp-mode-map
      (:bind :state normal
        "K"     'lsp-describe-thing-at-point
        "M"     'lsp-describe-thing-at-point)
      (:bind
        "C-c l" (cons "LSP" lsp-command-map)))))

(define-advice lsp-completion--filter-candidates
    (:filter-return (candidates) helheim-drop-empty-labels)
  "Drop candidates whose label is the empty string.
A string of length zero carries no text properties, so such a candidate
reaches `lsp-completion--company-match' without the
`lsp-completion-start-point' property that it needs."
  (-remove #'string-empty-p candidates))

(defun +lsp-close-signature ()
  "Close the displayed `lsp-signature'."
  (when lsp-signature-mode
    (lsp-signature-stop)
    t))

(setup lsp-ui
  (:install t)
  (:setopt lsp-ui-doc-enable t
           lsp-ui-doc-position 'at-point
           lsp-ui-sideline-enable t
           lsp-ui-peek-enable t
           lsp-ui-imenu-enable t
           lsp-ui-flycheck-enable t))

(setup consult-lsp
  (:install t)
  (:after lsp-mode)
  (:keymap lsp-mode-map
    (:bind [remap xref-find-apropos] 'consult-lsp-symbols)))

;;; .
(provide 'helheim-lsp-mode)
;;; helheim-lsp-mode.el ends here
