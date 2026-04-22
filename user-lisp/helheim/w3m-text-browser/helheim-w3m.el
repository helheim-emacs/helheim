;;; helheim-w3m.el                -*- lexical-binding: t; no-byte-compile: t -*-

(setup w3m
  (:install t)
  (:setopt w3m-key-binding nil ;; use Lynx like keys
           w3m-display-mode 'tabbed
           ;; w3m-new-session-in-background t
           )
  (:after-load
    (:keymap w3m-mode-map
      (:unbind "g")
      (:bind
        "C-c RET" 'w3m-goto-url
        ;; "C-c RET" 'w3m-goto-url-new-session
        "g g" 'beginning-of-buffer
        "G"   'end-of-buffer))))

;;; .
(provide 'helheim-w3m)
;;; helheim-w3m.el ends here
