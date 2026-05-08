;;; helheim-eat.el                -*- lexical-binding: t; no-byte-compile: t -*-

(setup eat
  (:install t)
  (:hook eshell-load-hook (eat-eshell-mode
                           eat-eshell-visual-command-mode))
  ;; https://codeberg.org/akib/emacs-eat/issues/119"
  (:setopt eat-term-name "xterm-256color")
  (:setopt eat-kill-buffer-on-exit t
           eat-enable-auto-line-mode t
           eat-shell-prompt-annotation-success-margin-indicator "0"
           eat-shell-prompt-annotation-running-margin-indicator "-"
           eat-shell-prompt-annotation-failure-margin-indicator "X"
           ;; This is disabled by default for security reasons.
           ;; eat-enable-yank-to-terminal t
           )
  (:global-bind
    "C-c o t" 'eat
    "C-c o T" 'eat-other-window))

(setup project
  (:after-load
    (add-to-list 'project-switch-commands '(eat-project "Eat terminal") t)
    (add-to-list 'project-kill-buffer-conditions '(major-mode . eat-mode))
    (:keymap project-prefix-map
      (:bind
        "t" 'eat-project
        "T" 'eat-project-other-window))))

;;; hel-eat.el

(with-eval-after-load 'eat
  (require 'eat)

  ;; Hel uses "M-u" for `universal-argument' instead of "C-u", so replace "C-u"
  ;; with "M-u" in Eat Semi-char map.
  ;;
  ;; Semi-char mode
  (setopt eat-semi-char-non-bound-keys (->> eat-semi-char-non-bound-keys
                                            (-replace [?\C-u] [?\e ?u]))
          eat-eshell-semi-char-non-bound-keys (->> eat-eshell-semi-char-non-bound-keys
                                                   (-replace [?\C-u] [?\e ?u])))

  (hel-keymap-set eat-semi-char-mode-map
    "<escape>" 'eat-self-input
    "C-y" 'eat-self-input ;; `eat-yank'
    "M-y" 'eat-self-input ;; `eat-yank-from-kill-ring'
    "C-p" 'eat-yank
    "M-p" 'eat-yank-from-kill-ring
    )

  ;; (eat-update-semi-char-mode-map)
  )

;;; .
(provide 'helheim-eat)
;;; helheim-eat.el ends here
