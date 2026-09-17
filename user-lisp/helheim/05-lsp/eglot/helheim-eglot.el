;;; helheim-eglot.el              -*- lexical-binding: t; no-byte-compile: t -*-
;;; Commentary:
;;
;; TODO:
;; - eglot-booster
;; - eglot-momentary-inlay-hints
;;
;;; Keybindings

(setup eglot
  (:keymap prog-mode-map
    (:bind "C-c l RET" 'eglot))
  (:after-load
    (:keymap eglot-mode-map
      (:bind :state normal
        "<f2>" 'eglot-rename
        "K"    'eldoc-box-help-at-point
        "M"    'eldoc-box-help-at-point
        "g d"  '("definition" . xref-find-definitions)
        "g r"  '("references" . xref-find-references)
        "g D"  '("declaration" . eglot-find-declaration)
        "g t"  '("type definition" . eglot-find-typeDefinition)
        "g i"  '("implementations" . eglot-find-implementation))
      (:bind
        ;; Toggle
        "C-c t h" 'eglot-inlay-hints-mode
        "C-c t s" 'eglot-semantic-tokens-mode
        ;; LSP
        "C-c l" (cons "LSP"
                      (define-keymap
                        "RET" '("LSP reconnect" . eglot-reconnect)
                        "Q"   '("LSP shutdown" . eglot-shutdown)
                        "r"   '("rename" . eglot-rename)
                        "f"   '("format" . eglot-format)
                        "="   '("format" . eglot-format)
                        "a"   '("code actions" . eglot-code-actions)
                        "o"   '("organize imports" . eglot-code-action-organize-imports)
                        "q"   '("quickfix" . eglot-code-action-quickfix)
                        "e"   '("refactor extract" . eglot-code-action-extract)
                        "i"   '("rewrite inline" . eglot-code-action-inline)
                        "R"   '("refactor rewrite" eglot-code-action-rewrite)
                        "t"   '("type hierarchy" . eglot-show-type-hierarchy)
                        "c"   '("call hierarchy" . eglot-show-call-hierarchy)))))))

(setup flymake
  (:after-load
    (:keymap flymake-mode-map
      (:bind :state normal
        "] d"  '("Next diagnostic" . flymake-goto-next-error)
        "[ d"  '("Prev diagnostic" . flymake-goto-prev-error))
      (:bind
        "C-c l d"  '("diagnostics" . flymake-show-buffer-diagnostics)
        "C-c l D"  '("project diagnostics" . flymake-show-project-diagnostics)))
    ;; Flymake buffer
    (:keymap flymake-diagnostics-buffer-mode-map
      (:bind
        "RET"      'flymake-goto-diagnostic
        "S-RET"    'flymake-show-diagnostic
        "M-RET"    'flymake-show-diagnostic
        "o"        'flymake-show-diagnostic
        "g o"      'flymake-show-diagnostic))))

;;; Config

(setup flymake
  (:install nil)
  (:hook prog-mode-hook flymake-mode)
  (setopt flymake-mode-line-lighter nil
          flymake-show-diagnostics-at-end-of-line nil
          flymake-wrap-around t))

;; (setup flymake-popon
;;   (:install t)
;;   (:hook flymake-mode-hook flymake-popon-mode))

(setup jsonrpc
  (:install nil))

(setup eglot
  (:install nil)
  (require 'helheim-markdown) ;; For on hover documentation formatting.
  (setopt
   ;; A setting of nil or 0 means Eglot will not block the UI at all, allowing
   ;; Emacs to remain fully responsive, although LSP features will only become
   ;; available once the connection is established in the background.
   eglot-sync-connect 0
   ;; Shut down server after killing last managed buffer
   eglot-autoshutdown t
   eglot-confirm-server-edits '((t . maybe-diff))
   ;; Margin indicator may increase line height due to glyph display
   ;; failures or emoji font height differences.
   eglot-code-action-indications '(eldoc-hint)
   eglot-code-action-indicator "" ;; 💡   󰌵 󱠂 󱠃
   eglot-extend-to-xref t)
  (:after-load
    ;; PERF: Disable the eglot-events-buffer, so Emacs doesn't churn GC and
    ;;   CPU cycles on pretty-printing the events buffer in the background
    ;;   (once it reaches max size).
    (unless init-file-debug
      (cl-callf plist-put eglot-events-buffer-config :size 0)
      (setq jsonrpc-event-hook nil))))

(setup eldoc-box
  (:install t)
  (setopt eldoc-box-self-insert-command-list '(self-insert-command)))

;; Eglot expands the snippets a language server sends by calling
;; `yas-expand-snippet', and asks the server for snippets only when
;; YASnippet is installed. `helheim-snippets' configures it for your own
;; snippets.
(setup yasnippet
  (:install t))

(setup consult-eglot
  (:install t)
  (:after eglot)
  (:keymap eglot-mode-map
    (:bind "<remap> <xref-find-apropos>" 'consult-eglot-symbols)))

(setup sideline
  (:install t)
  (:blackout t)
  (:hook flymake-mode-hook sideline-mode)
  (setopt sideline-format-right "  %s"
          sideline-backends-right-skip-current-line nil
          sideline-display-backend-name t))

(setup sideline-flymake
  (:install t)
  (:after sideline)
  (setopt sideline-flymake-display-mode 'line) ;; 'line or 'point
  (:hook sideline-backends-right sideline-flymake)
  ;; (add-to-list 'sideline-backends-right 'sideline-flymake)
  )

(setup sideline-eglot
  (:install t)
  (:after sideline)
  (setopt sideline-eglot-code-actions-prefix "󰌵 ") ;; 💡   󰌵 󱠂 󱠃
  (:hook sideline-backends-right sideline-eglot)
  ;; (add-to-list 'sideline-backends-right 'sideline-eglot)
  )

(setup breadcrumb
  (:install t)
  (:hook (c-mode-hook
          c++-mode-hook
          c-ts-mode-hook
          c++-ts-mode-hook) breadcrumb-local-mode))

;;; .
(provide 'helheim-eglot)
;;; helheim-eglot.el ends here
