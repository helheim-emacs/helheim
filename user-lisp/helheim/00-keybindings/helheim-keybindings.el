;;; helheim-keybindings.el        -*- lexical-binding: t; no-byte-compile: t -*-
;;; Commentary:
;;
;; If you want to see all key bindings in a keymap, place point (cursor) on it
;; and press "M", or press "<F1> M" and type the name of the keymap.
;;
;;; General

(setup hel-leader
  (:install hel-leader :host github :repo "helheim-emacs/hel-leader")
  (:require t))

(setup helheim
  (:global-bind :state normal
    "z SPC" 'cycle-spacing
    "z ."   'set-fill-prefix)
  (:global-bind :state insert
    "C-/"   'hippie-expand)
  (:global-bind
    [remap keyboard-quit] 'helheim-keyboard-quit ; "C-g"
    ;;
    "C-x C-b" 'ibuffer-jump  ;; override `list-buffers'
    "C-x C-r" 'recentf-open  ;; override `find-file-read-only'
    "C-x C-d" 'dired-jump))  ;; override `list-directory'

;;; <Leader>

(which-key-add-key-based-replacements
  "C-c a"  "ai"
  "C-c b"  "buffer / bookmark"
  "C-c d"  "diagnostic"
  "C-c f"  "file"
  "C-c i"  "insert"
  "C-c o"  "open"
  "C-c p"  "project"
  "C-c t"  "toggle"
  "C-c s"  "search"
  "C-c v"  "version control"
  "C-c y"  "copy")

(hel-keymap-set mode-specific-map
  "RET"   'dired-jump
  ","     'switch-to-buffer
  "/"     'consult-ripgrep ;; "/" is for search in Hel
  "u"     'vundo
  ;; Buffer
  "b b"   '("ibuffer" . ibuffer-jump) ;; "<leader> bb"
  "b n"   'switch-to-buffer    ; next key after "b"
  "b s"   'save-buffer
  "b c"   '("copy buffers file" . bufferfile-copy)
  "b w"   '("write buffer to file" . write-file)
  "b d"   '("delete buffers file" . bufferfile-delete)
  "b g"   'revert-buffer       ; also "C-w r"
  "b r"   '("rename buffer's file" . bufferfile-rename)
  "b R"   'rename-buffer
  "b x"   'scratch-buffer
  "b z"   'bury-buffer         ; also "C-w z"
  ;; Bookmarks
  "b RET" 'bookmark-jump
  "b m"   'bookmark-set
  "b M"   'bookmark-delete
  ;; File
  "f b"   'switch-to-buffer
  "f f"   'find-file  ;; select file in current dir or create new one
  "f /"   'consult-fd ;; or `consult-find'
  "f d"   'dired
  "f l"   'locate
  "f r"   '("Recent files" . recentf-open)
  "f w"   'write-file
  ;; Open
  ;; "o f"   'treemacs ; for future
  ;; "o i"   'imenu-list-smart-toggle
  ;; Project
  "p"     (hel-keymap-set project-prefix-map
            "RET" 'project-dired
            ","   'project-switch-to-buffer
            "/"   'project-find-regexp
            "B"   'project-list-buffers)
  ;; Toggle
  "t d"   'display-line-numbers-mode
  "t r"   'read-only-mode        ;; "C-x C-q"
  "t v"   'visual-line-mode
  "t w"   '+wrap-line-mode
  "t $"   'set-selective-display ;; "C-x $"
  ;; Copy
  "y y"   '("copy file reference" . +copy-file-reference)
  "y c"   '("copy code with reference" . +copy-code-with-reference)
  ;; Search
  "s"     (hel-keymap-set search-map
            "a" 'xref-find-apropos
            "r" 'query-replace
            "R" 'query-replace-regexp))

;;; Buffer

(setup bufferfile
  (:install t)
  (:command bufferfile-copy)
  (:setopt bufferfile-verbose t
           bufferfile-use-vc t
           bufferfile-delete-switch-to 'parent-directory))

;;; Button

(hel-keymap-set button-buffer-map
  "C-j" 'forward-button
  "C-k" 'backward-button)

;;; Customize

(setup cus-edit
  (hel-set-initial-state 'Custom-mode 'normal)
  (:after-load
    (:keymap custom-mode-map
      (:bind :state normal
        "z j" 'widget-forward
        "z k" 'widget-backward
        "z u" 'Custom-goto-parent
        "q"   'Custom-buffer-done))))

;;; Elpaca
;; `elpaca-manager' and `elpaca-log' are the main entry points to the UI.

(hel-set-initial-state 'elpaca-info-mode 'normal)

;;; HTML

(setup sgml-mode
  (:after-load
    (:keymap html-mode-map
      (:unbind "C-c C-m")
      (:bind "C-c C-<m>" #'html-paragraph))))

;;; Info

(setup info
  (:after-load
    (:keymap Info-mode-map
      (:bind "C-c s a" 'info-apropos))))

;;; Repeat mode

(put 'other-window 'repeat-map nil) ;; Use "." key instead.

;;; tab-bar

(setup tab-bar
  (:after-load
    (:keymap tab-bar-history-mode-map
      (:unbind
        "C-c <left>"
        "C-c <right>"))))

;;; .
(provide 'helheim-keybindings)
;;; helheim-keybindings.el ends here
