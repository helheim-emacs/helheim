;;; init.el -*- lexical-binding: t; no-byte-compile: t -*-
;;; Fonts
;;
;; Set up fonts before anything else so error messages during startup
;; were readable.
;;
;; Press "ga" to see information about the character at the position, font used,
;; faces, overlays, etc. (Press "<F1> k ga" to find out which command is bound
;; to "ga".)

(let* ((font "Cascadia Code") ;; <- replace with you font
       (spec (font-spec :family font :size 13.0 :weight 'normal)))
  (set-face-font 'default spec)
  (set-face-font 'fixed-pitch spec)
  ;; Prepend our font to the default fontset to make it the first fallback
  ;; candidate for itself. This matters when text is bold or italic and the
  ;; default font lacks glyphs for those styles but does provide them for the
  ;; regular style. With this change, Emacs will use the regular glyphs from
  ;; the default font when bold or italic variants are unavailable, instead of
  ;; falling back to a different font.
  ;;   BUG: Using `font-spec' with `set-fontset-font' doesn't work, despite
  ;; documentation claims it is.
  (set-fontset-font t 'unicode font nil 'prepend))

(require 'cl-macs)

(cl-defun helheim-set-fontset-font (font charsets &key (fontset t) add)
  "Force some code point diapasons to use particular FONT."
  (declare (indent 1))
  (dolist (charset charsets)
    (set-fontset-font fontset charset font nil add)))

(helheim-set-fontset-font "Symbols Nerd Font Mono"
  '((#xe5fa . #xe6b7) ;; Seti-UI + Custom  
    (#xe700 . #xe8ef) ;; Devicons  
    (#xed00 . #xf2ff) ;; Font Awesome  
    (#xe200 . #xe2a9) ;; Font Awesome Extension  
    (#xe300 . #xe3e3) ;; Weather  
    (#xf400 . #xf533) #x2665 #x26A1 ;; Octicons   ♥ ⚡
    (#x23fb . #x23fe) #x2b58 ;; IEC Power Symbols ⏻ ⏾ ⭘
    (#xf300 . #xf381) ;; Font Logos   
    (#xe000 . #xe00a) ;; Pomicons  
    (#xea60 . #xec1e) ;; Codicons  
    (#x276c . #x2771) ;; Heavy Angle Brackets ❬ ❱
    (#xee00 . #xee0b) ;; Progress  
    (#xf0001 . #xf1af0))) ;; Material Design Icons 󰀁 󱫰

;; In the modeline, we’re not restricted by a rigid grid, and non-monospace
;; Powerline symbols look better.
(helheim-set-fontset-font "Symbols Nerd Font"
  `(;; Powerline Symbols
    (#xe0a0 . #xe0a2) ;;  
    (#xe0b0 . #xe0b3) ;;  
    ;; Powerline Extra Symbols
    (#xe0b4 . #xe0c8) ;;  
    (#xe0cc . #xe0d7) ;;  
    #xe0a3 #xe0ca))   ;;  

;;; Helheim core

;; In case you use VPN. Also Emacs populates `url-proxy-services' variable
;; from: `https_proxy', `socks_proxy', `no_proxy' environment variables.
;; (setopt url-proxy-services '(("socks" . "127.0.0.1:10808")
;;                              ("https" . "127.0.0.1:10809"))
;;         gnutls-algorithm-priority "NORMAL:-VERS-TLS1.3")

(setq helheim-package-manager 'elpaca) ;; or 'straight
(require 'helheim-core)

;;; Color theme

(setup helheim-modus-themes
  (:require t)
  (load-theme 'modus-operandi t))

;; I can recommend `leuven' theme for org-mode work. It has so many nice little
;; touches to spruce up org-mode elements that some users switch to it from
;; their usual dark doom or modus themes when working on org-mode projects.
;;   You may try it with ": load-theme" then type "leuven".
(setup leuven-theme (:install t))

;;; Essentials

(require 'helheim-minibuffer) ; Vertico + Marginalia
(require 'helheim-completion) ; Corfu + Orderless + Cape
(require 'helheim-search)     ; Consult + Deadgrep
(require 'helheim-keybindings)

(require 'helheim-ibuffer)    ; Buffers menu
(require 'helheim-dired)      ; File-manager
(require 'helheim-embark)     ; Context-aware action menus
(require 'helheim-modeline)   ; Normal people call this "status line"
(require 'helheim-outline)    ; See "Outline Mode" in Emacs manual
(require 'helheim-tab-bar)    ; Each tab represents a set of windows, as in Vim

;;; Search

(require 'helheim-consult)  ; A set of search commands with preview
(require 'helheim-deadgrep) ; Interface for Ripgrep in Emacs

;;; IDE

(require 'helheim-xref)     ; Go to definition framework
(require 'helheim-snippets) ; Snippets engine

(require 'helheim-eglot)    ; eglot + flymake (both built-in)
;; or
;; (require 'helheim-flycheck) ; Diagnostics
;; (require 'helheim-lsp-mode) ; Lsp-mode

;;; Version control

(require 'helheim-magit)
(require 'helheim-diff-hl)  ; git gutter indicators

;;; Org mode

;; These variables must be set before `org' is loaded!
(setopt org-directory (expand-file-name "~/notes/")
        ;; Which modules to load.
        ;; Place cursor on variable and press "M" to see all possible values.
        org-modules '(ol-bibtex ol-docview ol-info))

(require 'helheim-org)
(require 'helheim-pretty-org)
(require 'helheim-org-node)
(require 'helheim-daily-notes)

;;; Major modes

(require 'helheim-cpp)
(require 'helheim-emacs-lisp)
(require 'helheim-json)
(require 'helheim-markdown)
(require 'helheim-lua)
(require 'helheim-sh)

;;; Terminal emulators

; (require 'helheim-eat)     ; written in emacs-lisp
; (require 'helheim-ghostel) ; based on libghostty (Zig) -- same as in Ghostty
; (require 'helheim-vterm)   ; based on libvterm (C) -- same as in Neovim

;;; LLM

; (require 'helheim-agent-shell)
; (require 'helheim-mcp-server)

;;; Extra ficilities

; (require 'helheim-browser) ; Synchronize online text editor with Emacs buffer
; (require 'helheim-notmuch) ; Notmuch email client
; (require 'helheim-whisper) ; Speech to text conversion
; (require 'helheim-edit-indirect) ; Alternative "zn" binding

;;; init.el ends here
