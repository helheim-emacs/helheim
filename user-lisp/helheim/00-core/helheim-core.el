;;; helheim-core.el               -*- lexical-binding: t; no-byte-compile: t -*-
;;; Customization

(defgroup helheim nil
  "Helheim specific settings."
  :prefix 'helheim-)

(defcustom helheim-package-manager 'straight
  "Package manager Helheim will use to install packages.
Supported values:
- `elpaca'
- `straight'

Must be set before `helheim-core' is loaded!"
  :type '(radio (symbol :tag "elpaca"      'elpaca)
                (symbol :tag "straight.el" 'straight))
  :group 'helheim)

(defcustom helheim-id-format "%Y%m%dT%H%M%S"
  "The format string of timebased ID as `format-time-string' accepts."
  :type 'string
  :group 'helheim)

(defcustom helheim-file-id-regexp "\\`\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)--"
  "File name ID regexp."
  :type 'string
  :group 'helheim)

;;; Package management

(pcase helheim-package-manager
  ('elpaca   (require 'helheim-elpaca))
  ('straight (require 'helheim-straight)))
(require 'dash)
(require 'f)
(require 'helheim-lib)
(require 'helheim-setup)

;; Compiles .el files before they are loaded with `load' or `require'.
(setup compile-angel
  (:install t)
  (:require t)
  (:setopt compile-angel-verbose t)
  (cl-callf nconc compile-angel-excluded-files
    '("/init.el"
      "/custom.el"))
  (blackout 'compile-angel-on-load-mode)
  ;; Start compile-angel only after Elpaca has finished, so its just-in-time
  ;; byte-compilation doesn't pile onto Elpaca's own source builds during
  ;; a fresh install.
  (:after-init compile-angel-on-load-mode))

;; We disable byte-compilation by setting `user-lisp-auto-scrape' to nil in
;; early-init.el, because it runs too early, before dependencies are installed.
;; This also disables autoload cookie scanning, so we perform it manually here.
(helheim-regenerate-autoloads)

;;; External dependencies

(setup avy
  (:install t)
  (:setopt avy-keys '( ?a ?s ?d ?f ?g ?h ?j ?k ?l    ; middle layer
                       ?q ?w ?e ?r ?t ?y ?u ?i ?o ?p ; top layer
                       ?z ?x ?c ?v ?b ?n ?m)         ; bottom layer
           avy-style 'at-full
           avy-all-windows nil
           avy-all-windows-alt t
           avy-background t
           ;; The unpredictability of such behavior (when enabled) makes it
           ;; a poor default.
           avy-single-candidate-jump nil))

(setup hel
  (:install t)
  (hel-mode))

(setup hel-collection
  (:install hel-collection
            :host github :repo "helheim-emacs/hel-collection"
            :files (:defaults "modes"))
  (hel-collection-init))

(setup compat (:install t))
(setup cond-let (:install t))

(setup transient
  (:install t)
  (:setopt transient-common-command-prefix "SPC"
           ;; Pop up transient windows at the bottom of the current window
           ;; instead of entire frame. This is more ergonomic for users with
           ;; large displays or many splits.
           transient-display-buffer-action '(display-buffer-below-selected
                                             (dedicated . t)
                                             (inhibit-same-window . t))
           transient-show-during-minibuffer-read t
           ;; transient-default-level 5
           )
  (:after-load
    ;; Close transient menus with ESC.
    (keymap-set transient-map "<escape>" #'transient-quit-one)))

(setup svg-lib (:install t))

(setup nerd-icons
  (:install t)
  (:after-load
    ;; Add some missing icons
    (-each '((fundamental-mode nerd-icons-faicon "nf-fa-file_o" :face nerd-icons-dsilver)
             (deadgrep-mode nerd-icons-faicon "nf-fa-search"))
      (-lambda ((mode . icon-spec))
        (setf (alist-get mode nerd-icons-mode-icon-alist) icon-spec)))))

;; `+wrap-line-mode' dependencies: its file is autoloaded, so we should install
;; its dependences out of it.
(setup adaptive-wrap (:install t))
(setup visual-fill-column (:install t))

;; Required by:
;; - `markdown-mode', or it will install it via package.el if it isn't present
;;    on call of `markdown-edit-code-block'.
;; - `helheim-edit-indirect'
(setup edit-indirect
  (:install t)
  (:after-load
    (:keymap edit-indirect-mode-map
      (:bind :state normal
        "Z Z" 'edit-indirect-commit
        "Z Q" 'edit-indirect-abort))))

(setup wgrep (:install t))

(elpaca-wait)

;;; UI
;;;; Misc

;; Show current key-sequence in minibuffer ala 'set showcmd' in vim.
;; Any feedback after typing is better UX than no feedback at all.
(setq echo-keystrokes 0.02)

;; Accept shorter responses: "y" for yes and "n" for no.
(setq use-short-answers t
      read-answer-short 'auto)

(setq prettify-symbols-unprettify-at-point 'right-edge)

;; Position underlines at the descent line instead of the baseline.
(setq x-underline-at-descent-line t)

(setq truncate-string-ellipsis "…")

;; No beeping or blinking
(setq visible-bell nil
      ring-bell-function #'ignore)

;; Disable truncation of printed s-expressions in the message buffer.
(setq eval-expression-print-length nil
      eval-expression-print-level nil)

(setq which-func-update-delay 1.0)

;; Omit the load average from `display-time-mode'.
(setq display-time-default-load-average nil)

;; Avoid automatic frame resizing when changing the global text scale.
(setq global-text-scale-adjust-resizes-frames nil)

;;;; Mouse

;; middle-click paste at point, not at click
(setq mouse-yank-at-point t)

;; Context menu on right mouse button click.
(when (and (display-graphic-p)
           (memq 'context-menu helheim-emacs-ui-elements))
  (add-hook 'after-init-hook #'context-menu-mode))

;;;; Cursor

;; I anable blinking cursor, but it may interferes with cursor settings in some
;; minor modes that try to change it buffer-locally (e.g., Treemacs).
(blink-cursor-mode)

;; Do not extend the cursor to fit wide characters.
(setq x-stretch-cursor nil)

;; Show cursor in non-selected window.
(setq-default cursor-in-non-selected-windows nil)

;; Show active region in non-selected window.
(setq highlight-nonselected-windows nil)

;;;; Highlight current line

;; `hl-line-mode' was obsoleted in Emacs 31 by the `window' value of
;; `global-hl-line-sticky-flag' that uses `pre-redisplay-functions'.
;; (bug#80007)

(when (< emacs-major-version 31)
  (defcustom global-hl-line-buffers nil
    "Whether the Global HL-Line mode should be enabled in a buffer.
The predicate is passed as argument to `buffer-match-p', which see."
    :type '(buffer-predicate :tag "Predicate for `buffer-match-p'"))
  ;;
  (advice-add 'global-hl-line-highlight :around
              #'helheim-global-hl-line-highlight-a))

(setup hl-line
  (:setopt global-hl-line-sticky-flag 'window ;; Emacs 31
           ;; I want current line highlighting only in special modes that are in
           ;; Hel Emacs state, and temporary disable it when region is active.
           ;; In text editing modes disable it, because it interferes with Hel
           ;; selections.
           global-hl-line-buffers '(and (or (derived-mode . special-mode)
                                            ;; For `define-compilation-mode'
                                            (derived-mode . compilation-mode)
                                            ;; Follow major modes doesn't inherit
                                            ;; from `special-mode'.
                                            (derived-mode . dired-mode)
                                            (derived-mode . org-agenda-mode)
                                            (derived-mode . notmuch-search-mode)
                                            (derived-mode . notmuch-tree-mode)
                                            (derived-mode . notmuch-show-mode))
                                        (not (derived-mode . image-dired-thumbnail-mode))
                                        ;; According to my measures, compiled
                                        ;; function is two times faster.
                                        helheim--global-hl-line-buffers-p))
  (global-hl-line-mode))

;;;; Display line numbers

(setup display-line-numbers
  (:hook (prog-mode-hook conf-mode-hook))
  (:setopt display-line-numbers-width 3
           display-line-numbers-type t
           display-line-numbers-width-start t
           display-line-numbers-grow-only t
           ;; Show absolute line numbers for narrowed regions to make it easier
           ;; to tell the buffer is narrowed, and where you are, exactly.
           display-line-numbers-widen t))

;; (setopt indicate-empty-lines t)

;;;; Fill-Column indicator

(add-hook 'prog-mode-hook 'helheim-show-fill-column-indicator)

(defun helheim-show-trailing-whitespace ()
  "Highlight trailing whitespaces with `trailing-whitespace' face.
Use `delete-trailing-whitespace' command."
  (setq-local show-trailing-whitespace t))

;; TODO: report this
;; BUG: In `display-fill-column-indicator-mode': two strings are compared with
;;   `eq' instead of `equal' and result is always nil.
(defun helheim-show-fill-column-indicator ()
  "Display `fill-column' indicator."
  (setq-local display-fill-column-indicator t
              display-fill-column-indicator-character ?\u2502))

;;;; Fringes

;; Disable visual indicators in the fringe for buffer boundaries and empty lines.
(setq indicate-buffer-boundaries nil
      indicate-empty-lines nil)

(setq-default left-fringe-width  8
              right-fringe-width 8)

;;;; Modeline

;; Show (line,column) indicator in modeline.
(add-hook 'after-init-hook #'line-number-mode)
(add-hook 'after-init-hook #'column-number-mode)

;;;; Windows

;; Prefer vertical splits over horizontal ones.
(setq split-width-threshold 150
      split-height-threshold nil
      window-combination-resize t)

;; Prefer open new buffer in current window, all else being equal.
(setq pop-up-windows nil)
(setq display-buffer-base-action
      '((display-buffer-reuse-mode-window
         display-buffer-in-previous-window
         display-buffer-use-some-window
         display-buffer-pop-up-window)))

;; If I trying to switch buffer in dedicated window, put it somewhere
;; instead of error out.
(setq switch-to-buffer-in-dedicated-window 'pop)

(setq window-resize-pixelwise t)

;; FIX: The native border "consumes" a pixel of the fringe on righter-most
;;   splits, `window-divider' does not.
(setq window-divider-default-places t
      window-divider-default-bottom-width 1
      window-divider-default-right-width 1)
(add-hook 'after-init-hook #'window-divider-mode)

;; (setq even-window-sizes 'height-only)
;; (setq window-sides-vertical nil)
(setq fit-window-to-buffer-horizontally t)
(setq fit-frame-to-buffer t)

;;;; Scrolling

;; ;; Move point to top/bottom of buffer before signaling a scrolling error.
;; (setq scroll-error-top-bottom t)

;; Enables faster scrolling. This may result in brief periods of inaccurate
;; syntax highlighting, which should quickly self-correct.
(setq fast-but-imprecise-scrolling t
      redisplay-skip-fontification-on-input t)

;; Keep screen position if scroll command moved it vertically out of the window.
(setq scroll-preserve-screen-position t)

;; 1. Preventing automatic adjustments to `window-vscroll' for long lines.
;; 2. Resolving the issue of random half-screen jumps during scrolling.
(setq auto-window-vscroll nil)

;; Number of lines of margin at the top and bottom of a window.
(setq scroll-margin 0)

;; Number of lines of continuity when scrolling by screenfuls.
(setq next-screen-context-lines 0)

;; Horizontal scrolling
(setq hscroll-margin 2
      hscroll-step 1)

;; Disable auto-adding a new line at the bottom when scrolling.
(setq next-line-add-newlines nil)

;; Why is `jit-lock-stealth-time' nil by default?
;; https://lists.gnu.org/archive/html/help-gnu-emacs/2022-02/msg00352.html
(setq jit-lock-stealth-time 0.75 ; Calculate fonts when idle for N seconds
      jit-lock-stealth-nice 0.5  ; Seconds between font locking
      jit-lock-chunk-size 4096)

;; Avoid fontification while typing
(setq jit-lock-defer-time 0)
(add-hook 'hel-insert-state-enter-hook (lambda () (setq jit-lock-defer-time 0.25)))
(add-hook 'hel-insert-state-exit-hook  (lambda () (setq jit-lock-defer-time 0)))

;;;;; Scrolling with mouse wheel and touchpad

(setup ultra-scroll
  (:install t)
  (:after-init ultra-scroll-mode)
  (:setopt mouse-wheel-tilt-scroll t ; Scroll horizontally with mouse side wheel.
           mouse-wheel-progressive-speed nil))

;;; Text editing
;;;; Clipboard

;; Preserve the system clipboard before Emacs delete/kill operations.
;;
;; By default, deleting text in Emacs overwrites your system clipboard.
;; For example, if you copy a link from a browser, switch to Emacs, and delete
;; some text, your copied link is lost. This setting fixes that by pushing the
;; clipboard contents into your paste history right before the deletion,
;; ensuring external data remains retrievable via `hel-paste-pop'.
(setq save-interprogram-paste-before-kill t)

;; Remove duplicates from the kill ring to reduce clutter.
(setq kill-do-not-save-duplicates t)

;;;; Undo/redo

(setq undo-limit (* 13 160000)
      undo-strong-limit (* 13 240000)
      undo-outer-limit (* 13 24000000))

(setup vundo (:install t))

;;;; Formatting

(setq-default fill-column 80)

;; Prefer spaces over tabs.
(setq-default indent-tabs-mode nil
              tab-width 4)

;; Only indent the line when at BOL or in a line's indentation. Anywhere else,
;; insert literal indentation.
(setq-default tab-always-indent 'complete
              tab-first-completion 'word)

;; Make `tabify' and `untabify' only affect indentation. Not tabs/spaces in the
;; middle of a line.
(setq tabify-regexp "^\t* [ \t]+")

;; Wrap lines at whitespace, rather than in the middle of a word.
(setq-default word-wrap t)
;; Don't wrap lines by default.
;; - `visual-line-mode' :: soft line-wrapping
;; - `auto-fill-mode'   :: hard line-wrapping
(setq-default truncate-lines t)
;; ;; If enabled (and `truncate-lines' is disabled), soft wrapping no longer
;; ;; occurs when that window is less than `truncate-partial-width-windows'
;; ;; characters wide. We don't need this.
;; (setq truncate-partial-width-windows nil)

;; This was a widespread practice in the days of typewriters, but it is obsolete
;; nowadays.
(setq sentence-end-double-space nil)

;; The POSIX standard defines a line is "a sequence of zero or more non-newline
;; characters followed by a terminating newline".
(setq require-final-newline t)

;; Don’t break after a one-letter word preceded by a whitespace character
(add-hook 'fill-nobreak-predicate #'fill-single-char-nobreak-p)

;; Don’t break after the first word of a sentence or before the last
(add-hook 'fill-nobreak-predicate #'fill-single-word-nobreak-p)

;; Don't break lines inside hidden text.
(setq fill-nobreak-invisible t)

;;;; Parens

;; Don't blink the paren matching the one at point, it's too distracting.
(setq blink-matching-paren nil)

(setopt show-paren-delay 0.1
        show-paren-highlight-openparen t
        ;; show-paren-when-point-inside-paren t
        ;; show-paren-when-point-in-periphery t
        )

(setup rainbow-delimiters
  (:install t)
  (:hook (prog-mode-hook conf-mode-hook)))

;;;; Prog-mode

(setq comment-empty-lines t
      comment-multi-line t)

(add-hook 'prog-mode-hook 'helheim-show-trailing-whitespace)

;;;; Text-mode

;; (setup text-mode
;;   (:hook text-mode-hook (display-line-numbers-mode
;;                          rainbow-delimiters-mode
;;                          ;; visual-line-mode
;;                          +wrap-line-mode)))

;;;; Tree-sitter

(setup treesit
  (:when (treesit-available-p))
  (:setopt treesit-font-lock-level 4
           treesit-enabled-modes t) ;; Emacs 31
  ;; XXX: Since Emacs 31 a missing grammar is installed when a file needing
  ;;   it is visited (see `treesit-auto-install-grammar'). Remove when we
  ;;   drop Emacs 30 support.
  (when (< emacs-major-version 31)
    (:after-init helheim-install-missing-treesit-grammars))
  (let ((abi<15 (< (treesit-library-abi-version) 15)))
    (:treesit c
      "https://github.com/tree-sitter/tree-sitter-c"
      :revision (if abi<15 "v0.23.6")) ;; "v0.24.1"
    (:treesit cpp
      "https://github.com/tree-sitter/tree-sitter-cpp"
      :revision (if abi<15 "v0.23.4"))
    (:treesit c-sharp
      "https://github.com/tree-sitter/tree-sitter-c-sharp"
      :revision (if abi<15 "v0.20.0")) ;; "v0.23.1"
    (:treesit css
      "https://github.com/tree-sitter/tree-sitter-css"
      :revision (if abi<15 "v0.23.0")) ;; "v0.23.2"
    (:treesit commonlisp
      "https://github.com/tree-sitter-grammars/tree-sitter-commonlisp"
      :revision "v0.4.1")
    (:treesit dockerfile
      "https://github.com/camdencheek/tree-sitter-dockerfile")
    (:treesit elixir
      "https://github.com/elixir-lang/tree-sitter-elixir")
    (:treesit go
      "https://github.com/tree-sitter/tree-sitter-go"
      :revision (if abi<15 "v0.20.0")) ;; "v0.25.0"
    (:treesit gomod
      "https://github.com/camdencheek/tree-sitter-go-mod"
      :revision "v1.0.2")
    (:treesit gowork
      "https://github.com/omertuc/tree-sitter-go-work")
    (:treesit html
      "https://github.com/tree-sitter/tree-sitter-html"
      :revision (if abi<15 "v0.23.0")) ;; "v0.23.2"
    (:treesit java
      "https://github.com/tree-sitter/tree-sitter-java")
    (:treesit javascript
      "https://github.com/tree-sitter/tree-sitter-javascript"
      :revision (if abi<15 "v0.23.0"))
    (:treesit latex
      "https://github.com/latex-lsp/tree-sitter-latex"
      :revision "v0.3.0")
    ;; (:treesit bibtex "https://github.com/latex-lsp/tree-sitter-bibtex")
    (:treesit make
      "https://github.com/tree-sitter-grammars/tree-sitter-make")
    (:treesit nix
      "https://github.com/nix-community/tree-sitter-nix")
    (:treesit perl
      "https://github.com/ganezdragon/tree-sitter-perl")
    (:treesit python
      "https://github.com/tree-sitter/tree-sitter-python"
      :revision (if abi<15 "v0.23.6")) ;; "v0.25.0"
    (:treesit r
      "https://github.com/r-lib/tree-sitter-r")
    (:treesit ruby
      "https://github.com/tree-sitter/tree-sitter-ruby")
    (:treesit rust
      "https://github.com/tree-sitter/tree-sitter-rust"
      :revision (if abi<15 "v0.23.2")) ;; "v0.24.2"
    (:treesit sql
      "https://github.com/DerekStride/tree-sitter-sql"
      :revision "gh-pages")
    (:treesit typescript
      "https://github.com/tree-sitter/tree-sitter-typescript"
      :revision "v0.23.2"
      :source-dir "typescript/src")
    (:treesit tsx
      "https://github.com/tree-sitter/tree-sitter-typescript"
      :revision "v0.23.2"
      :source-dir "tsx/src")
    (:treesit toml
      "https://github.com/tree-sitter-grammars/tree-sitter-toml")
    (:treesit yaml
      "https://github.com/tree-sitter-grammars/tree-sitter-yaml"
      :revision (if abi<15 "v0.7.0")) ;; "v0.7.2"
    (:treesit zig
      "https://github.com/tree-sitter-grammars/tree-sitter-zig"
      ;; :revision "v1.1.2"
      ))
  (:mode
   ;; BUG: Emacs provides this setting in yaml-ts-mode.el, but it only works
   ;;   after the package is loaded, defeating autoloading. So, we duplicate
   ;;   them here.
   ("\\.ya?ml\\'" . yaml-ts-mode)
   ("clang.format\\'" . yaml-ts-mode)))

;;;; Extra file extensions to support

(add-to-list 'auto-mode-alist '("/LICENSE\\'" . text-mode))
(add-to-list 'auto-mode-alist '("rc\\'" . conf-mode) :append)

;;;; Editing files with very long lines

(setup so-long
  (:require t)
  (:after-init global-so-long-mode)
  ;;
  ;; Don't disable syntax highlighting and line numbers, or make the buffer
  ;; read-only, in `so-long-minor-mode', so we can have a basic editing
  ;; experience in them, at least. It will remain off in `so-long-mode',
  ;; however, because long files have a far bigger impact on Emacs performance.
  (cl-callf2 delq 'font-lock-mode so-long-minor-modes)
  (cl-callf2 delq 'display-line-numbers-mode so-long-minor-modes)
  (setf (alist-get 'buffer-read-only so-long-variable-overrides nil t) nil)
  ;; ...but at least reduce the level of syntax highlighting
  (add-to-list 'so-long-variable-overrides '(font-lock-maximum-decoration . 1))
  ;; ...and insist that save-place not operate in large/long files
  (add-to-list 'so-long-variable-overrides '(save-place-alist . nil))
  ;; But disable everything else that may be unnecessary/expensive for large
  ;; or wide buffers.
  (cl-callf nconc so-long-minor-modes '(eldoc-mode
                                        auto-composition-mode
                                        hl-fill-column-mode
                                        spell-fu-mode
                                        undo-tree-mode
                                        ws-butler-mode
                                        highlight-indent-guides-mode)))

;;; Emacs built-in packages

;; This setting forces Emacs to save bookmarks immediately after each change,
;; to make you never lose bookmarks if Emacs crashes.
(setq bookmark-save-flag 1)

;;;; Security

;; Say gpg-agent to redirect all Pinentry queries to the caller, so Emacs can
;; query passphrase through the minibuffer, instead of external Pinentry program
(setq epg-pinentry-mode 'loopback)

;;;; Custom

(setup custom
  (:setopt custom-file (expand-file-name "custom.el" helheim-root-directory)
           custom-theme-directory (expand-file-name "themes/" helheim-root-directory)
           custom-buffer-done-kill t)
  (:after-init
    (load custom-file t t)))

;;;; Help

;; Enhance `apropos' and related functions to perform more extensive searches
(setq apropos-do-all t)

(setup help
  (:setopt help-enable-autoload nil
           help-enable-completion-autoload nil
           help-enable-symbol-autoload nil
           help-window-select t)) ;; Focus new help windows on open.

(setup helpful
  (:install t)
  ;; (:hook helpful-mode-hook outline-minor-mode)
  (:global-bind
    [remap describe-function] 'helpful-callable
    [remap describe-variable] 'helpful-variable
    [remap describe-command]  'helpful-command
    [remap describe-key]      'helpful-key
    [remap describe-symbol]   'helpful-symbol))

(add-to-list 'display-buffer-alist
             '((or (derived-mode . help-mode)
                   (derived-mode . helpful-mode))
               (display-buffer-reuse-mode-window
                +display-buffer-based-on-window-count
                display-buffer-use-some-window)
               (mode help-mode helpful-mode Info-mode)
               (body-function . select-window)))

;;;; Minibuffer

;; Allow opening new minibuffers from inside existing minibuffers.
(setq enable-recursive-minibuffers t)
(minibuffer-depth-indicate-mode)

(setq resize-mini-windows 'grow-only
      max-mini-window-height 0.33
      history-delete-duplicates t)

;; Keep the cursor out of the read-only portions of the minibuffer.
(setq minibuffer-prompt-properties '( read-only t
                                      intangible t
                                      cursor-intangible t
                                      face minibuffer-prompt))
(add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)

;;;;; Save minibuffer history between sessions

(setup savehist
  (:require t)
  (:setopt history-length 300
           savehist-additional-variables '(kill-ring
                                           mark-ring
                                           global-mark-ring
                                           register-alist
                                           search-ring
                                           regexp-search-ring))
  (:hook savehist-save-hook (helheim-savehist-unpropertize-variables-h
                             helheim-savehist-remove-unprintable-registers-h))
  (:after-init savehist-mode))

;;;; Buffers

(setq uniquify-buffer-name-style 'forward)

;; ;; BUG: This setting breaks `project-kill-buffers' command.
;; ;; "C-x C-b" (`list-buffers') and `M-x buffer-menu'.
;; (when (version<= "30.2" emacs-version)
;;   (setopt Buffer-menu-group-by #'Buffer-menu-group-by-root))

;; ;; The initial buffer is created during startup even in non-interactive
;; ;; sessions, and its major mode is fully initialized. Modes like `text-mode',
;; ;; `org-mode', or even the default `lisp-interaction-mode' load extra packages
;; ;; and run hooks, which can slow down startup.
;; ;;
;; ;; Using `fundamental-mode' for the initial buffer to avoid unnecessary
;; ;; startup overhead.
;; (setq initial-major-mode 'fundamental-mode
;;       initial-scratch-message nil)

;;;; Files

;; ;; Resolve symlinks when opening files, so that any operations are conducted
;; ;; from the file's true directory (like `find-file').
(setq find-file-visit-truename t
      vc-follow-symlinks t)
;; (setq vc-follow-symlinks 'ask)

;; ;; Disable the warning "X and Y are the same file". It's fine to ignore this
;; ;; warning as it will redirect you to the existing buffer anyway.
;; (setq find-file-suppress-same-file-warnings t)

;; ;; Skip confirmation prompts when creating a new file or buffer
;; (setq confirm-nonexistent-file-or-buffer nil)

;; Delete by moving to trash in interactive mode
(setq delete-by-moving-to-trash (not noninteractive)
      remote-file-name-inhibit-delete-by-moving-to-trash t)

;; Create missing directories when we open a file that doesn't exist under
;; a directory tree that may not exist.
(add-hook 'find-file-not-found-functions #'helheim-create-missing-directories-h)

;;;;; Backup files

;; Don't generate backups or lockfiles. While auto-save maintains a copy so long
;; as a buffer is unsaved, backups create copies once, when the file is first
;; written, and never again until it is killed and reopened. This is better
;; suited to version control, and it is not a good idead to have world-readable
;; copies of potentially sensitive material floating around our filesystem.
(setq create-lockfiles nil
      make-backup-files nil
      ;; But in case the user does enable it, some sensible defaults:
      version-control t     ; number each backup file
      backup-by-copying t   ; instead of renaming current file (clobbers links)
      delete-old-versions t ; clean up after itself
      kept-old-versions 5
      kept-new-versions 5
      backup-directory-alist `(("." . ,(locate-user-emacs-file "backup")))
      tramp-backup-directory-alist backup-directory-alist)

;;;;; Auto save changes in files
;; Use `recover-file' or `recover-session' commands to restore auto-saved data.

(setq auto-save-default t
      auto-save-no-message t
      auto-save-include-big-deletions t
      kill-buffer-delete-auto-save-files t
      auto-save-list-file-prefix (locate-user-emacs-file "autosave/")
      ;; This resolves two issue while ensuring auto-save files are still
      ;; reasonably recognizable at a glance:
      ;;
      ;; 1. Emacs generates long file paths for its auto-save files; long is:
      ;;    `auto-save-list-file-prefix' + `buffer-file-name'. If too long, the
      ;;    filesystem will murder your cat. `sha1' compresses the path into a
      ;;    ~40 character hash!
      ;; 2. The default transform rule writes TRAMP auto-save files to
      ;;    `temporary-file-directory', which TRAMP doesn't like! It'll prompt
      ;;    you about it every time an auto-save file is written, unless
      ;;    `tramp-allow-unsafe-temporary-files' is set. A more sensible default
      ;;    transform is better:
      auto-save-file-name-transforms
      `(("\\`/[^/]*:\\([^/]*/\\)*\\([^/]*\\)\\'"
         ,(file-name-concat auto-save-list-file-prefix "tramp-\\2-")
         sha1)
        ("\\`/\\([^/]+/\\)*\\([^/]+\\)\\'"
         ,(file-name-concat auto-save-list-file-prefix "\\2-")
         sha1)))

(add-hook 'auto-save-hook (defun helheim-ensure-auto-save-prefix-exists-h ()
                            (with-file-modes #o700
                              (make-directory auto-save-list-file-prefix t))))

;; HACK: Make sure backup files (like `undo-tree's) don't have ridiculously long
;;   file names that some filesystems will refuse.
(advice-add 'make-backup-file-name-1 :around
            #'helheim-make-hashed-backup-file-name-a)

;;;;; Auto revert

;; Automatically revert the buffer when its visited file changes on disk.
;; Auto Revert will not revert a buffer if it has unsaved changes, or if
;; its file on disk is deleted or renamed.
(setup autorevert
  (:after-init global-auto-revert-mode)
  (:setopt auto-revert-stop-on-user-input nil
           auto-revert-verbose t ; let us know when it happens
           auto-revert-use-notify nil
           auto-revert-stop-on-user-input nil
           ;; Only prompts for confirmation when buffer is unsaved.
           revert-without-query '(".")
           global-auto-revert-non-file-buffers t ; e.g, Dired
           global-auto-revert-ignore-modes '(ibuffer-mode ; has its own `ibuffer-auto-mode'
                                             Buffer-menu-mode)))

;;;;; Keep track of recently opened files and places in them

;; Keep track of opened files.
(setup recentf
  (:setopt recentf-max-saved-items 300 ; default is 20
           ;; Auto clean up recent files only in long-running daemon sessions,
           ;; else do it on quiting Emacs.
           recentf-auto-cleanup (if (daemonp) 300))
  (:after-init
    (let ((inhibit-message t))
      (recentf-mode 1)))
  (:after-load
    (:hook kill-emacs-hook recentf-cleanup)
    ;; Don't remember files in runtime folders.
    (require 'xdg)
    (add-to-list 'recentf-exclude (concat "^" (regexp-quote (or (xdg-runtime-dir)
                                                                "/run"))))
    ;; PERF: Text properties inflate the size of recentf's files, and there is no
    ;;   reason to persist them (must be first in `recentf-filename-handlers'!)
    (add-to-list 'recentf-filename-handlers #'substring-no-properties)))

;; Save the last location within a file upon reopening.
(setup saveplace
  (:setopt save-place-limit 600)
  (:after-init save-place-mode)
  ;; (setq save-place-file (locate-user-emacs-file "saveplace"))
  )

;;;; TRAMP

(setopt remote-file-name-inhibit-cache 60
        remote-file-name-inhibit-auto-save-visited t
        tramp-default-method "ssh" ; faster than the default "scp"
        tramp-copy-size-limit (* 1024 1024) ; 1mb
        tramp-use-scp-direct-remote-copying t
        ;; tramp-verbose 1 ; Reduce verbosity
        tramp-completion-reread-directory-timeout 60)

;;;; Imenu

;; Automatically rescan the buffer for Imenu entries when `imenu' is invoked.
;; This ensures the index reflects recent edits.
(setq imenu-auto-rescan t)

;; Prevent truncation of long function names in `imenu' listings.
(setq imenu-max-item-length 160)

;;;; Isearch

(setopt isearch-lazy-count t
        isearch-lazy-highlight 'all-windows)

;;;; Calendar

(setup calendar
  (:setopt calendar-week-start-day 1) ;; Monday
  (:hook calendar-mode-hook
         (defun helheim-calendar-mode-h ()
           (setq-local revert-buffer-function (lambda (&rest _)
                                                (calendar-redraw)))))
  (add-to-list 'display-buffer-alist
               '((major-mode . calendar-mode)
                 ;; display-buffer-at-bottom ;; display-buffer-below-selected
                 ;; (window-height . shrink-window-if-larger-than-buffer)
                 display-buffer-in-side-window
                 (side . bottom)
                 ;; (slot . -1) ;; -1 == L  0 == Mid 1 == R
                 (body-function . select-window))))

;;;; Completion

;; Ignore cases
(setq completion-ignore-case t
      read-file-name-completion-ignore-case t
      read-buffer-completion-ignore-case t)

;; Hide in `M-x' menu commands irrelevant to current buffer's mode.
(setq read-extended-command-predicate #'command-completion-default-include-p)

;;;;; hippie-expand

(setup hippie-exp
  (:global-bind
    [remap dabbrev-expand] 'hippie-expand)
  (:after-load
    (:setopt hippie-expand-try-functions-list
             '( try-expand-dabbrev
                try-expand-dabbrev-all-buffers
                try-expand-dabbrev-from-kill
                try-complete-file-name-partially
                try-complete-file-name
                try-expand-all-abbrevs
                try-expand-list
                try-expand-line
                try-complete-lisp-symbol-partially
                try-complete-lisp-symbol))))

;;;;; dabbrev

(setup dabbrev
  (:setopt dabbrev-upcase-means-case-search t
           dabbrev-ignored-buffer-modes '( archive-mode image-mode docview-mode
                                           pdf-view-mode tags-table-mode))
  (:setopt dabbrev-ignored-buffer-regexps
           '(;; Buffers starting with a space (internal/temporary buffers).
             "\\` "
             ;; Tags files: ETAGS, GTAGS, RTAGS, TAGS, e?tags, GPATH, including
             ;; numbered variants like <123>.
             "\\(?:\\(?:[EG]?\\|GR\\)TAGS\\|e?tags\\|GPATH\\)\\(<[0-9]+>\\)?")))

;;;;; abbrev

;; Keep `abbrev_defs' under `user-emacs-directory'. Otherwise it defaults to
;; ~/.emacs.d/abbrev_defs regardless of our redirection.
(setup abbrev
  (:setopt abbrev-file-name (locate-user-emacs-file "abbrev_defs")
           save-abbrevs 'silently))

;;;; Spell checking

;; Don't display a message for each word when checking the whole buffer.
;; This markedly improves `flyspell' performance.
(setq flyspell-issue-message-flag nil
      flyspell-issue-welcome-flag nil)

;; Save the personal dictionary without confirmation.
(setq ispell-silently-savep t)

;;;; Comint (COMmand INTerpreter)

(setq ansi-color-for-comint-mode t
      comint-prompt-read-only t
      comint-buffer-maximum-size 4096)

(add-to-list 'comint-output-filter-functions 'comint-osc-process-output)

;;;; Compile

(setq next-error-message-highlight t)

(setq compilation-ask-about-save nil ; save all buffers on `compile' without asking
      compilation-always-kill t ; kill compilation process before starting another
      compilation-scroll-output 'first-error)

(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)

;; Automatically truncate compilation buffers so they don't accumulate too
;; much data and bog down the rest of Emacs.
(setup comint
  (:command comint-truncate-buffer)
  (:hook compilation-filter-hook comint-truncate-buffer))

;;;; Eldoc

(setup eldoc
  (:blackout t)
  (:setopt eldoc-documentation-strategy 'eldoc-documentation-compose-eagerly))

(add-hook 'edebug-mode-hook
          (defun +edebug-inhibit-eldoc-h ()
            "Disable Eldoc during Edebug session so it doesn't clobber the result."
            ;; Edebug prints its stepping result ("Result: ...") to the echo
            ;; area with a plain `message', which is not an Eldoc backend, so
            ;; Eldoc's function-argument hint clobbers it.
            (eldoc-mode (if edebug-mode -1 1))))

;;;; image-mode

(setq image-animate-loop t
      image-auto-resize 'fit-window)

;; image-mode
(add-to-list 'display-buffer-alist
             '((derived-mode . image-mode)
               (display-buffer-reuse-window
                display-buffer-use-some-window
                display-buffer-pop-up-window)
               (inhibit-same-window . t)))

;;;; occur-mode

;; Create separate *Occur* buffer for each search.
(add-hook 'occur-hook 'occur-rename-buffer)

;; Open `occur-mode' buffer in another window.
(add-to-list 'display-buffer-alist
             '((major-mode . occur-mode)
               (display-buffer-use-some-window display-buffer-pop-up-window)
               (inhibit-same-window . t)
               (body-function . select-window)))

;;;; project.el

(setup project
  (:install nil)
  (:setopt project-vc-extra-root-markers '(".project")
           project-vc-merge-submodules nil
           project-kill-buffers-display-buffer-list t
           ;; project-mode-line t
           project-switch-commands '((project-dired "Dired")
                                     (project-find-file "Find file")
                                     ;; (project-find-regexp "Find regexp")
                                     (project-find-dir "Find directory")
                                     (project-vc-dir "VC-Dir")
                                     (project-eshell "Eshell")
                                     (project-any-command "Other"))))

;;;; Version Control

(setup vc
  (:setopt vc-git-print-log-follow t
           ;; Do not backup version controlled files.
           vc-make-backup-files nil
           ;; Faster algorithm for diffing.
           vc-git-diff-switches '("--histogram")
           ;; Remove RCS, CVS, SCCS, and Bzr, because it's a lot less work for vc
           ;; to check them all (especially in TRAMP buffers), and who uses any of
           ;; these?
           vc-handled-backends '(Git Hg SVN SRC)
           ;; PERF: Ignore node_modules (expensive for vc ops to index).
           vc-ignore-dir-regexp (format "%s\\|%s"
                                        locate-dominating-stop-dir-regexp
                                        "[/\\\\]node_modules")))

(with-eval-after-load 'vc-annotate
  (keymap-set vc-annotate-mode-map "<remap> <quit-window>" #'kill-current-buffer))

;; (setup vc-annotate
;;   (:after-load
;;     (:keymap vc-annotate-mode-map
;;       (:bind [remap quit-window] #'kill-current-buffer))))

;;;; Diff

;; Move the +/- indicators into the fringe for cleaner-looking diffs.
(setq diff-font-lock-prettify t)

;;;; Ediff
;;
;; Restore windows configuration after quitting ediff

(let (wconf) ; Private variable shared by two functions.
  ;;
  (defun helheim-ediff--save-window-configuration ()
    (setq wconf (current-window-configuration)))
  ;;
  (defun helheim-ediff--restore-window-configuration ()
    (when (window-configuration-p wconf)
      (set-window-configuration wconf))))

(add-hook 'ediff-before-setup-hook #'helheim-ediff--save-window-configuration)
(add-hook 'ediff-quit-hook    #'helheim-ediff--restore-window-configuration 90)
(add-hook 'ediff-suspend-hook #'helheim-ediff--restore-window-configuration 90)

(provide 'helheim-ediff)

;;;; Which-Key

(setup which-key
  (:after-init which-key-mode)
  (:setopt which-key-lighter nil
           which-key-sort-order 'which-key-key-order-alpha
           which-key-idle-delay 1.5
           which-key-idle-secondary-delay 0.25
           which-key-add-column-padding 1
           which-key-max-description-length 40
           which-key-show-remaining-keys t
           which-key-ellipsis "…"
           which-key-allow-multiple-replacements nil)
  ;; WARN: Following `which-key-replacement-alist' is tailored for
  ;;   `which-key-allow-multiple-replacements' set to nil.
  (setq which-key-replacement-alist
        `(((nil . "which-key-show-next-page-no-cycle") . (nil . "wk next pg"))
          (("RET\\|<return>" . nil) . ("Enter" . nil))
          (("<backtab>" . nil) . ("S-tab" . nil))
          ;; DEL -> Bsp
          ;; M-DEL -> M-Bsp
          (("\\([[:word:]-]*\\)DEL" . nil) . ("\\1Bsp" . nil))
          ;; <left> -> left
          ;; <C-m>  -> C-m
          (("<\\([[:alnum:]-]+\\)>") . ("\\1"))
          ;; ((nil . "copy-as-kill") . (nil . "copy"))
          ;; Strip meaningless packages prefixes.
          ,(cons `(nil . ,(rx line-start
                              (or "consult-" "hel-" "helheim-"
                                  "elisp-" "pp-" ;; elisp pretty print
                                  "xref-" "my-")))
                 '(nil . ""))
          ;; Display embark specific commands literally...
          ;; WARN: If `which-key-allow-multiple-replacements' is t all follwing
          ;;   settings will break and "embark-" prefix will be stripped from
          ;;   ALL commands!
          ,(cons `(nil . ,(rx line-start
                              (or "embark-act" "embark-dwim" "embark-become"
                                  "embark-export" "embark-collect"
                                  "embark-cycle" "embark-live")
                              line-end))
                 '(nil . nil))
          ((nil . "embark-copy-as-kill") . (nil . "copy"))
          ;; ... for other commands strip "embark-" prefix.
          ((nil . "^embark-") . (nil . "")))))

(setup which-key-posframe
  (:install t)
  (:after which-key)
  (:hook which-key-mode-hook which-key-posframe-mode)
  (:setopt which-key-max-display-columns 1
           which-key-posframe-poshandler '+posframe-poshandler-window-bottom-right-corner-with-padding))

;;; .
(provide 'helheim-core)
;;; helheim-core.el ends here
