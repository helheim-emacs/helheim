;;; melange-light-theme.el --- Melange theme -*- lexical-binding: t; no-byte-compile: t -*-

;; Author: built with Claude Code
;; Keywords: faces, theme

;;; Commentary:
;;
;; A port of Melange <https://github.com/savq/melange-nvim>, light variant,
;; from its Neovim source to Emacs.
;;
;; Structure:
;;   1. Ground palette   -- the only place hex colours appear.
;;   2. Semantic layer   -- one level of indirection; retune the theme by
;;      repointing these rather than editing faces.
;;   3. Overrides         -- `melange-light-palette-overrides' shadows both.
;;   4. Resolver + tree walker -- expand bare palette symbols in face specs
;;      into hex, so `melange-light-faces' below can stay symbolic.
;;   5. Face table        -- one big quoted list, grouped by package.
;;
;; Source of truth for colours:
;;   ~/code/melange-nvim/lua/melange/palettes/light.lua
;; Source of truth for the mapping:
;;   ~/code/melange-nvim/colors/melange.lua
;;
;;; Code:

(deftheme melange-light
  "Light variant of the Melange colour scheme, ported from Neovim."
  :background-mode 'light
  :kind 'color-scheme
  :family 'melange)

;;; Ground palette

(defconst melange-light-palette
  '(;; ── Ground: grays (upstream `a') ──────────────────────────
    (bg              "#F1F1F1")   ; a.bg     page
    (bg-float        "#E9E1DB")   ; a.float  child frames, mode line
    (bg-sel          "#D9D3CE")   ; a.sel    selection
    (ui              "#A98A78")   ; a.ui     line numbers, borders
    (comment         "#7D6658")   ; a.com    comments, dimmed text
    (fg              "#54433A")   ; a.fg     body text

    ;; ── Ground: strong foregrounds (upstream `b') ─────────────
    (red-strong      "#BF0021")
    (yellow-strong   "#A06D00")
    (green-strong    "#3A684A")
    (cyan-strong     "#3D6568")
    (blue-strong     "#465AA4")
    (magenta-strong  "#904180")

    ;; ── Ground: foregrounds (upstream `c') ────────────────────
    (red             "#C77B8B")
    (yellow          "#BC5C00")
    (green           "#6E9B72")
    (cyan            "#739797")
    (blue            "#7892BD")
    (magenta         "#BE79BB")

    ;; ── Ground: backgrounds (upstream `d') ────────────────────
    (bg-red          "#F1DEDF")
    (bg-yellow       "#CCA478")   ; NB: upstream also uses this as a *fg*
    (bg-green        "#D0E9D1")
    (bg-cyan         "#CDE8E7")
    (bg-blue         "#E0E2E8")
    (bg-magenta      "#E8E0E8")

    ;; ── Semantic layer: one level of indirection ──────────────
    ;; Values here are palette keys, not hex.  Retune the theme by
    ;; repointing these rather than by editing faces.
    (fg-comment      comment)
    (fg-string       blue-strong)
    (fg-doc          blue-strong)
    (fg-keyword      yellow)
    (fg-function     yellow-strong)
    (fg-variable     fg)
    (fg-type         cyan)
    (fg-constant     magenta)
    (fg-number       magenta-strong)
    (fg-preprocessor green-strong)
    ;; Emacs's `font-lock-builtin-face' catches builtin *functions* (`len'
    ;; in Python), which upstream keeps warm: @function.builtin = @function.
    ;; Named apart from `fg-preprocessor' so it can be repointed at
    ;; `fg-function' without dragging `import'/`define' along.
    (fg-builtin      fg-preprocessor)
    (fg-operator     red-strong)
    (fg-delimiter    ui)             ; was bg-yellow, 2.03 -> 2.82
    (fg-punctuation  red)            ; @punctuation.delimiter = c.red
    (fg-escape       blue)
    (fg-regexp       blue-strong)
    (fg-directory    green)
    (fg-title        yellow)
    (fg-link         blue-strong)    ; was blue,      2.80 -> 5.71
    (fg-error        red-strong)     ; was red,       2.80 -> 5.74
    (fg-warning      yellow-strong)
    (fg-info         blue)
    (fg-hint         cyan)
    (fg-success      green)

    ;; ── Semantic layer: chrome ─────────────────────────────────
    ;; Upstream collapses most of these onto `bg-float'/`bg-sel'.
    ;; They are named apart so the planes can be stepped later.
    (bg-page                bg)
    (bg-popup               bg-float)   ; child frames, corfu, tooltip
    (bg-hl-line             bg-float)   ; CursorLine / ColorColumn
    (bg-region              bg-sel)     ; Visual
    (bg-completion          bg-sel)     ; PmenuSel, vertico-current
    (bg-inactive            bg-float)   ; unfocused window
    (bg-fold                bg-cyan)    ; upstream Folded
    (bg-mode-line           bg-float)
    (fg-mode-line           fg)
    (bg-mode-line-inactive  bg-float)
    (fg-mode-line-inactive  comment)
    (bg-header-line         bg-float)
    (fg-header-line         fg)
    (bg-fringe              bg)
    (bg-line-number         bg)
    (fg-line-number         ui)
    (bg-line-number-active  bg)
    (fg-line-number-active  fg-keyword)
    (bg-tab                 bg-float)
    (fg-tab                 comment)
    (bg-tab-active          bg-float)
    (fg-tab-active          fg)
    (border                 ui)         ; dividers, child-frame border
    (bg-search              bg-yellow)  ; Search
    (fg-search              bg)
    (bg-search-current      yellow-strong) ; CurSearch
    (bg-match               bg-red))    ; MatchParen / Substitute
  "Ground palette for the `melange-light' theme.
Grouped the way upstream Melange groups them: grays (`a'), strong
foregrounds (`b'), foregrounds (`c'), backgrounds (`d'), followed by a
semantic layer that points at the ground colours by name.  This is the
only place hex literals may appear in this file; every face below
refers to a palette symbol, which `melange-light--resolve' expands.")

;;; Overrides

(defcustom melange-light-palette-overrides nil
  "Alist of palette overrides, same shape as `melange-light-palette'.
Entries here shadow those in the base palette.  A value may be a hex
string or another palette key."
  :type '(repeat (list symbol sexp))
  :group 'melange)

;;; Resolution

(defun melange-light--resolve (key &optional depth)
  "Resolve palette KEY to a hex colour string.
Looks in `melange-light-palette-overrides' first, then
`melange-light-palette'.  If the stored value is a string, return it.
If it is a symbol, recurse.  DEPTH guards against reference cycles."
  (let ((depth (or depth 0)))
    (when (> depth 16)
      (error "melange-light: palette cycle detected resolving `%s'" key))
    (let ((entry (or (assq key melange-light-palette-overrides)
                      (assq key melange-light-palette))))
      (unless entry
        (error "melange-light: unknown palette key `%s'" key))
      (let ((value (cadr entry)))
        (if (stringp value)
            value
          (melange-light--resolve value (1+ depth)))))))

;;; Face-spec expansion

(defconst melange-light--color-keywords
  '(:foreground :background :color :underline :overline :strike-through
    :distant-foreground :box)
  "Attribute keywords whose values may name a palette colour.")

(defun melange-light--expand-attribute-value (value)
  "Resolve VALUE, found under a colour keyword, to hex.
A bare symbol is resolved through the palette.  A cons cell is a
nested attribute plist (e.g. `:underline (:style wave :color red)' or
`:box (:line-width -1 :color ui)') and is walked recursively.
Anything else (nil, t, an already-literal hex string) passes through
unchanged."
  (cond
   ((and value (symbolp value) (not (eq value t)))
    (melange-light--resolve value))
   ((consp value)
    (melange-light--expand-plist value))
   (t value)))

(defun melange-light--expand-plist (plist)
  "Return a copy of PLIST with palette symbols under colour keywords resolved.
Keys not in `melange-light--color-keywords' (e.g. `:weight', `:slant',
`:inherit', `:height', `:extend') and their values are passed through
untouched."
  (let (result)
    (while plist
      (let ((key (pop plist))
            (val (pop plist)))
        (push key result)
        (push (if (memq key melange-light--color-keywords)
                  (melange-light--expand-attribute-value val)
                val)
              result)))
    (nreverse result)))

(defun melange-light--expand-face-spec (spec)
  "Expand SPEC, the (DISPLAY . PLIST)... list of a single face entry."
  (mapcar (lambda (display-atts)
            (cons (car display-atts)
                  (melange-light--expand-plist (cdr display-atts))))
          spec))

(defun melange-light--expand (faces)
  "Expand FACES, a list of (NAME SPEC) entries, for `custom-theme-set-faces'.
Errors from unresolved palette symbols are re-signalled with the
offending face name attached, so a typo in `melange-light-faces' is
easy to trace back."
  (mapcar
   (lambda (entry)
     (let ((name (car entry)))
       (condition-case err
           (list name (melange-light--expand-face-spec (cadr entry)))
         (error (error "melange-light: %s (face `%s')"
                        (error-message-string err) name)))))
   faces))

;;; Face table

(defconst melange-light-faces
  '(
;;;; Core font-lock

    (default                              ((t :foreground fg :background bg)))
    (font-lock-comment-face               ((t :foreground fg-comment :slant italic)))
    (font-lock-comment-delimiter-face     ((t :inherit font-lock-comment-face)))
    (font-lock-doc-face                   ((t :foreground fg-doc)))
    (font-lock-doc-markup-face            ((t :foreground cyan-strong)))
    (font-lock-string-face                ((t :foreground fg-string :slant italic)))
    (font-lock-constant-face              ((t :foreground fg-constant)))
    (font-lock-number-face                ((t :foreground fg-number)))
    (font-lock-keyword-face               ((t :foreground fg-keyword)))
    (font-lock-function-name-face         ((t :foreground fg-function)))
    (font-lock-function-call-face         ((t :inherit font-lock-function-name-face)))
    (font-lock-variable-name-face         ((t :foreground fg-variable)))
    (font-lock-variable-use-face          ((t :inherit font-lock-variable-name-face)))
    (font-lock-property-name-face         ((t :foreground fg-variable)))
    (font-lock-property-use-face          ((t :inherit font-lock-property-name-face)))
    (font-lock-type-face                  ((t :foreground fg-type)))
    (font-lock-preprocessor-face          ((t :foreground fg-preprocessor)))
    (font-lock-builtin-face               ((t :foreground fg-builtin)))
    (font-lock-operator-face              ((t :foreground fg-operator)))
    (font-lock-negation-char-face         ((t :inherit font-lock-operator-face)))
    (font-lock-delimiter-face             ((t :foreground fg-delimiter)))
    (font-lock-bracket-face               ((t :inherit font-lock-delimiter-face)))
    (font-lock-punctuation-face           ((t :foreground fg-punctuation)))
    (font-lock-misc-punctuation-face      ((t :inherit font-lock-punctuation-face)))
    (font-lock-escape-face                ((t :foreground fg-escape)))
    (font-lock-regexp-face                ((t :foreground fg-regexp)))
    (font-lock-regexp-grouping-backslash  ((t :foreground fg-escape)))
    (font-lock-regexp-grouping-construct  ((t :foreground fg-escape)))
    (font-lock-warning-face               ((t :foreground fg-error)))

;;;; LSP semantic tokens -- Eglot

    ;; Only the deltas from Eglot's own default table
    ;; (eglot.el:687-722) are listed.  Everything else already
    ;; inherits a `font-lock-*' face this theme styles directly.
    (eglot-semantic-enumMember            ((t :inherit font-lock-constant-face)))
    (eglot-semantic-namespace             ((t :foreground fg-directory)))
    (eglot-semantic-parameter             ((t :foreground fg-variable :weight bold)))
    ;; eglot-semantic-macro: intentionally not defined -- upstream
    ;; clears `@lsp.type.macro' too, and Eglot's own default already
    ;; inherits `font-lock-preprocessor-face', which this theme styles.
    (eglot-semantic-documentation         ((t :inherit font-lock-doc-face)))
    (eglot-semantic-defaultLibrary        ((t :inherit font-lock-builtin-face)))
    (eglot-semantic-deprecated            ((t :strike-through fg-error)))
    (eglot-semantic-readonly              ((t :inherit font-lock-constant-face)))

    (eglot-highlight-symbol-face          ((t :background bg-hl-line :underline t)))
    (eglot-inlay-hint-face                ((t :foreground fg-comment :height 0.8)))
    (eglot-type-hint-face                 ((t :inherit eglot-inlay-hint-face)))
    (eglot-parameter-hint-face            ((t :inherit eglot-inlay-hint-face)))
    (eglot-diagnostic-tag-unnecessary-face ((t :underline (:style wave :color fg-comment))))
    (eglot-diagnostic-tag-deprecated-face ((t :strike-through fg-comment)))
    (eglot-mode-line                      ((t :inherit font-lock-constant-face :weight bold)))
    (eglot-code-action-indicator-face     ((t :foreground fg-warning :weight bold)))

;;;; LSP semantic tokens -- lsp-mode

    ;; lsp-semantic-token-faces / lsp-semantic-token-modifier-faces
    ;; already default every other token to a `font-lock-*' face this
    ;; theme styles; only the deltas below are needed.
    (lsp-face-semhl-namespace             ((t :foreground fg-directory)))
    (lsp-face-semhl-parameter             ((t :foreground fg-variable :weight bold)))
    ;; lsp-face-semhl-macro left at its default (inherits
    ;; font-lock-preprocessor-face), same reasoning as Eglot above.

;;;; Diagnostics

    (error                                ((t :inherit bold :foreground fg-error)))
    (warning                              ((t :inherit bold :foreground fg-warning)))
    (success                              ((t :inherit bold :foreground fg-success)))

    (flycheck-error                       ((t :underline (:style wave :color fg-error))))
    (flycheck-warning                     ((t :underline (:style wave :color fg-warning))))
    (flycheck-info                        ((t :underline (:style wave :color fg-info))))
    (flycheck-fringe-error                ((t :foreground fg-error)))
    (flycheck-fringe-warning              ((t :foreground fg-warning)))
    (flycheck-fringe-info                 ((t :foreground fg-info)))
    (flycheck-verify-select-checker       ((t :box (:style released-button))))
    (flycheck-error-list-error            ((t :inherit error)))
    (flycheck-error-list-warning          ((t :inherit warning)))
    (flycheck-error-list-info             ((t :foreground fg-info)))
    (flycheck-error-list-filename         ((t :inherit bold)))
    (flycheck-error-list-id               ((t :inherit font-lock-type-face)))
    (flycheck-error-list-id-with-explainer ((t :inherit flycheck-error-list-id
                                              :box (:style released-button))))
    (flycheck-error-list-checker-name     ((t :inherit font-lock-function-name-face)))
    (flycheck-error-list-highlight        ((t :background bg-completion :extend t)))

    (flymake-error                        ((t :underline (:style wave :color fg-error))))
    (flymake-warning                      ((t :underline (:style wave :color fg-warning))))
    (flymake-note                         ((t :underline (:style wave :color fg-hint))))
    (flymake-error-echo                   ((t :inherit error)))
    (flymake-warning-echo                 ((t :inherit warning)))
    (flymake-note-echo                    ((t :foreground fg-hint)))
    (flymake-end-of-line-diagnostics-face ((t :inherit italic :height 0.85 :box ui)))
    (flymake-error-echo-at-eol            ((t :inherit flymake-end-of-line-diagnostics-face
                                              :foreground fg-error)))
    (flymake-note-echo-at-eol             ((t :inherit flymake-end-of-line-diagnostics-face
                                              :foreground fg-hint)))

    (flyspell-incorrect                   ((t :underline (:style wave :color fg-error))))
    (jinx-misspelled                      ((t :underline (:style wave :color fg-warning))))

    (compilation-error                    ((t :inherit error)))
    (compilation-warning                  ((t :inherit warning)))
    (compilation-info                     ((t :inherit bold :foreground fg-success)))
    (compilation-line-number              ((t :inherit shadow)))
    (compilation-column-number            ((t :inherit compilation-line-number)))
    (compilation-mode-line-exit           ((t :inherit bold :foreground fg-success)))
    (compilation-mode-line-fail           ((t :inherit bold :foreground fg-error)))
    (compilation-mode-line-run            ((t :inherit bold :foreground fg-warning)))

;;;; UI chrome

    (cursor                               ((t :background fg)))
    (region                               ((t :background bg-region)))
    (secondary-selection                  ((t :background bg-region)))
    (highlight                            ((t :background bg-hl-line)))
    (hl-line                              ((t :background bg-hl-line :extend t)))
    ;; `pulse-reset-face' copies the background and :extend of
    ;; `pulse-highlight-start-face' onto `pulse-highlight-face' at the
    ;; start of every pulse, then fades it toward the frame background.
    ;; The start face is therefore the only one worth theming; the other
    ;; is set to match only so it is coherent before the first pulse.
    (pulse-highlight-start-face           ((t :background bg-yellow :extend t)))
    (pulse-highlight-face                 ((t :background bg-yellow :extend t)))
    (fringe                               ((t :background bg-fringe)))
    (line-number                          ((t :foreground fg-line-number :background bg-line-number)))
    (line-number-current-line             ((t :foreground fg-line-number-active :background bg-line-number-active)))
    (mode-line                            ((t :foreground fg-mode-line :background bg-mode-line :box nil)))
    (mode-line-active                     ((t :foreground fg-mode-line :background bg-mode-line :box nil)))
    (mode-line-inactive                   ((t :foreground fg-mode-line-inactive :background bg-mode-line-inactive)))
    (mode-line-buffer-id                  ((t :weight bold)))
    (mode-line-emphasis                   ((t :foreground fg-function :weight bold)))
    (mode-line-highlight                  ((t :background bg-completion :box nil)))
    (header-line                          ((t :foreground fg-header-line :background bg-header-line)))
    (header-line-highlight                ((t :inherit highlight)))
    (vertical-border                      ((t :foreground border)))
    (window-divider                       ((t :foreground border)))
    (window-divider-first-pixel           ((t :foreground border)))
    (window-divider-last-pixel            ((t :foreground border)))
    (child-frame-border                   ((t :background border)))
    (fill-column-indicator                ((t :foreground bg-sel)))
    (widget-field                         ((t :background bg-sel)))
    (tooltip                              ((t :foreground fg :background bg-popup)))

    (isearch                              ((t :foreground fg-search :background bg-search-current :weight bold)))
    (isearch-fail                         ((t :background bg-red)))
    (isearch-group-1                      ((t :foreground bg :background cyan-strong :weight bold)))
    (isearch-group-2                      ((t :foreground bg :background green-strong :weight bold)))
    (lazy-highlight                       ((t :foreground fg-search :background bg-search :weight bold)))
    (match                                ((t :foreground fg-function :weight bold)))
    (query-replace                        ((t :foreground bg :background red-strong :weight bold)))

    (show-paren-match                     ((t :background bg-match :weight bold)))
    (show-paren-match-expression          ((t :background bg-sel)))
    (show-paren-mismatch                  ((t :foreground bg :background red-strong :weight bold)))

    (minibuffer-prompt                    ((t :foreground fg-keyword)))
    (shadow                               ((t :foreground ui)))
    (link                                 ((t :foreground fg-link :underline t)))
    (link-visited                         ((t :foreground magenta :underline t)))
    (escape-glyph                         ((t :foreground fg-escape)))
    (trailing-whitespace                  ((t :background bg-red)))
    (button                               ((t :inherit link)))

    (whitespace-big-indent                ((t :foreground ui)))
    (whitespace-empty                     ((t :foreground ui)))
    (whitespace-hspace                    ((t :foreground ui)))
    (whitespace-indentation               ((t :foreground ui)))
    (whitespace-line                      ((t :foreground ui)))
    (whitespace-newline                   ((t :foreground ui)))
    (whitespace-space                     ((t :foreground ui)))
    (whitespace-space-after-tab           ((t :foreground ui)))
    (whitespace-space-before-tab          ((t :foreground ui)))
    (whitespace-tab                       ((t :foreground ui)))
    (whitespace-trailing                  ((t :foreground ui)))

;;;; ANSI colours (comint / compilation / eshell -- ansi-color.el)

    ;; `ansi-color-names-vector' is obsolete (ansi-color.el:245); modern
    ;; ansi-color.el renders off these 16 faces instead.  Each upstream
    ;; `defface' sets :foreground and :background to the same value, so
    ;; we do too.  Mapped from `~/code/melange-nvim/melange_light.json'
    ;; by key name -- every value below is already a palette entry
    ;; (json "black".."white" = the `c'/`a' families, "bright_*" = `b').
    (ansi-color-black                     ((t :foreground bg-float :background bg-float)))
    (ansi-color-red                       ((t :foreground red :background red)))
    (ansi-color-green                     ((t :foreground green :background green)))
    (ansi-color-yellow                    ((t :foreground yellow :background yellow)))
    (ansi-color-blue                      ((t :foreground blue :background blue)))
    (ansi-color-magenta                   ((t :foreground magenta :background magenta)))
    (ansi-color-cyan                      ((t :foreground cyan :background cyan)))
    (ansi-color-white                     ((t :foreground comment :background comment)))
    (ansi-color-bright-black              ((t :foreground ui :background ui)))
    (ansi-color-bright-red                ((t :foreground red-strong :background red-strong)))
    (ansi-color-bright-green              ((t :foreground green-strong :background green-strong)))
    (ansi-color-bright-yellow             ((t :foreground yellow-strong :background yellow-strong)))
    (ansi-color-bright-blue               ((t :foreground blue-strong :background blue-strong)))
    (ansi-color-bright-magenta            ((t :foreground magenta-strong :background magenta-strong)))
    (ansi-color-bright-cyan               ((t :foreground cyan-strong :background cyan-strong)))
    (ansi-color-bright-white              ((t :foreground fg :background fg)))
    ;; `-bold' / `-faint' / `-italic' / `-underline' / `-inverse' /
    ;; `-slow-blink' / `-fast-blink' are attribute-only upstream (no
    ;; foreground/background of their own) -- left at their Emacs
    ;; defaults rather than given colours they were never meant to carry.

;;;; hel (modal states)

    ;; `hel-normal-state-main-cursor' is kept in lockstep with `cursor'
    ;; at runtime by `hel--handle-theme-change' (hel-integration.el),
    ;; which re-runs `set-face-attribute' on every `enable-theme-functions'
    ;; call.  Whatever this theme says here is immediately overwritten
    ;; with `(face-background 'cursor)', so it is set to `fg' to match
    ;; `cursor' exactly rather than leave a value that would never
    ;; actually be seen.
    (hel-normal-state-main-cursor         ((t :background fg)))
    (hel-insert-state-main-cursor         ((t :background green-strong)))
    (hel-emacs-state-main-cursor          ((t :background magenta-strong)))
    (hel-extend-selection-cursor          ((t :background yellow-strong)))
    (hel-normal-state-fake-cursor         ((t :foreground bg :background red-strong)))
    (hel-insert-state-fake-cursor         ((t :foreground bg :background cyan-strong)))
    (hel-search-highlight                 ((t :inherit lazy-highlight)))

;;;; Diff family

    (diff-added                           ((t :background bg-green)))
    (diff-removed                         ((t :foreground fg-comment :background bg-red)))
    (diff-changed                         ((t :background bg-magenta)))
    (diff-changed-unspecified             ((t :inherit diff-changed)))
    (diff-refine-added                    ((t :foreground green :background bg-green)))
    (diff-refine-removed                  ((t :foreground red :background bg-red)))
    (diff-refine-changed                  ((t :foreground magenta :background bg-magenta)))
    (diff-indicator-added                 ((t :inherit diff-added)))
    (diff-indicator-changed               ((t :inherit diff-changed)))
    (diff-indicator-removed               ((t :inherit diff-removed)))
    (diff-header                          ((t :background bg-float)))
    (diff-file-header                     ((t :background bg-float :weight bold)))
    (diff-hunk-header                     ((t :foreground fg-comment :background bg-float)))
    (diff-function                        ((t :background bg-float)))
    (diff-index                           ((t :inherit italic)))
    (diff-nonexistent                     ((t :inherit bold)))
    (diff-error                           ((t :inherit error)))

    (diff-hl-insert                       ((t :foreground green :background bg)))
    (diff-hl-delete                       ((t :foreground red :background bg)))
    (diff-hl-change                       ((t :foreground magenta :background bg)))
    (diff-hl-reverted-hunk-highlight      ((t :foreground bg :background fg)))

    (smerge-upper                         ((t :background bg-red)))
    (smerge-lower                         ((t :background bg-green)))
    (smerge-base                          ((t :background bg-yellow)))
    (smerge-markers                       ((t :background bg-float)))
    (smerge-refined-added                 ((t :inherit diff-refine-added)))
    (smerge-refined-removed               ((t :inherit diff-refine-removed)))

    ;; A = removed hue, B = added hue, C = changed hue; fine variants
    ;; get the stronger (`c'-family foreground over `d'-family
    ;; background) colour, matching the diff-refine-* treatment above.
    (ediff-current-diff-A                 ((t :background bg-red)))
    (ediff-current-diff-B                 ((t :background bg-green)))
    (ediff-current-diff-C                 ((t :background bg-magenta)))
    (ediff-current-diff-Ancestor          ((t :background bg-blue)))
    (ediff-fine-diff-A                    ((t :foreground red :background bg-red)))
    (ediff-fine-diff-B                    ((t :foreground green :background bg-green)))
    (ediff-fine-diff-C                    ((t :foreground magenta :background bg-magenta)))
    (ediff-fine-diff-Ancestor             ((t :foreground blue :background bg-blue)))
    (ediff-even-diff-A                    ((t :background bg-float)))
    (ediff-even-diff-B                    ((t :background bg-float)))
    (ediff-even-diff-C                    ((t :background bg-float)))
    (ediff-even-diff-Ancestor             ((t :background bg-float)))
    (ediff-odd-diff-A                     ((t :inherit ediff-even-diff-A)))
    (ediff-odd-diff-B                     ((t :inherit ediff-even-diff-B)))
    (ediff-odd-diff-C                     ((t :inherit ediff-even-diff-C)))
    (ediff-odd-diff-Ancestor              ((t :inherit ediff-even-diff-Ancestor)))

    ;; magit-diff-*: context/added/removed/base wash the background;
    ;; the -highlight variant is the hunk under point.  Context has no
    ;; wash of its own, so its highlight is the one place that visibly
    ;; steps toward `bg-float'; the coloured variants keep their wash
    ;; unchanged since blending it further would mean inventing a hex
    ;; outside the palette block.
    (magit-diff-added                     ((t :background bg-green)))
    (magit-diff-added-highlight           ((t :background bg-green)))
    (magit-diff-removed                   ((t :foreground fg-comment :background bg-red)))
    (magit-diff-removed-highlight         ((t :foreground fg-comment :background bg-red)))
    (magit-diff-base                      ((t :background bg-yellow)))
    (magit-diff-base-highlight            ((t :background bg-yellow)))
    (magit-diff-context                   ((t :foreground fg-comment)))
    (magit-diff-context-highlight         ((t :foreground fg :background bg-float)))
    (magit-diff-file-heading              ((t :inherit bold)))
    (magit-diff-file-heading-highlight    ((t :inherit bold :background bg-float)))
    (magit-diff-file-heading-selection    ((t :inherit bold :foreground fg-warning)))
    (magit-diff-hunk-heading              ((t :foreground fg-comment :background bg-float)))
    (magit-diff-hunk-heading-highlight    ((t :foreground fg :background bg-sel)))
    (magit-diff-hunk-heading-selection    ((t :foreground fg-warning :background bg-sel)))
    (magit-diff-hunk-region               ((t :inherit bold)))
    (magit-diff-lines-boundary            ((t :inherit magit-diff-hunk-heading)))
    (magit-diff-lines-heading             ((t :inherit magit-diff-hunk-heading-highlight)))

;;;; Completion (corfu, vertico, marginalia, orderless, embark, consult, tempel)

    (corfu-default                        ((t :background bg-popup)))
    (corfu-current                        ((t :background bg-completion)))
    (corfu-bar                            ((t :background border)))
    (corfu-border                         ((t :background border)))

    (vertico-current                      ((t :background bg-completion)))
    (vertico-group-title                  ((t :foreground fg-comment :weight bold)))
    (vertico-quick1                       ((t :foreground bg :background yellow-strong :weight bold)))
    (vertico-quick2                       ((t :foreground bg :background cyan-strong :weight bold)))

    (completions-annotations              ((t :foreground fg-comment :inherit italic)))
    (completions-common-part              ((t :foreground fg-function :inherit bold)))
    (completions-first-difference         ((t :foreground fg-operator :inherit bold)))
    (completions-group-title              ((t :foreground fg-title :inherit bold)))
    (completions-highlight                ((t :background bg-completion)))

    (orderless-match-face-0               ((t :foreground yellow-strong :weight bold)))
    (orderless-match-face-1               ((t :foreground green-strong :weight bold)))
    (orderless-match-face-2               ((t :foreground cyan-strong :weight bold)))
    (orderless-match-face-3               ((t :foreground magenta-strong :weight bold)))

    (marginalia-archive                   ((t :foreground fg-comment)))
    (marginalia-char                      ((t :foreground fg-constant)))
    (marginalia-date                      ((t :foreground fg-link)))
    (marginalia-documentation             ((t :foreground fg-doc :inherit italic)))
    (marginalia-file-owner                ((t :foreground fg-comment)))
    (marginalia-file-priv-exec            ((t :foreground fg-success)))
    (marginalia-file-priv-link            ((t :foreground fg-constant)))
    (marginalia-file-priv-no              ((t :foreground ui)))
    (marginalia-file-priv-other           ((t :foreground ui)))
    (marginalia-file-priv-rare            ((t :foreground fg-warning)))
    (marginalia-file-priv-read            ((t :foreground fg-info)))
    (marginalia-file-priv-write           ((t :foreground fg-constant)))
    (marginalia-function                  ((t :foreground fg-function)))
    (marginalia-key                       ((t :foreground fg-function :weight bold)))
    (marginalia-lighter                   ((t :foreground fg-comment)))
    (marginalia-mode                      ((t :foreground fg-type)))
    (marginalia-modified                  ((t :foreground fg-warning)))
    (marginalia-null                      ((t :foreground ui)))
    (marginalia-number                    ((t :foreground fg-number)))
    (marginalia-size                      ((t :foreground fg-comment)))
    (marginalia-string                    ((t :foreground fg-string)))
    (marginalia-symbol                    ((t :foreground fg-type)))
    (marginalia-type                      ((t :foreground fg-type)))
    (marginalia-value                     ((t :foreground fg-constant)))
    (marginalia-version                   ((t :foreground fg-comment)))

    (embark-collect-group-title           ((t :foreground fg-title :inherit bold)))
    (embark-keybinding                    ((t :foreground fg-function :inherit bold)))
    (embark-keybinding-repeat             ((t :inherit bold)))
    (embark-selected                      ((t :foreground fg-success :background bg-green)))

    (consult-async-split                  ((t :inherit warning)))
    (consult-file                         ((t :foreground fg-link)))
    (consult-key                          ((t :foreground fg-function :inherit bold)))
    (consult-imenu-prefix                 ((t :inherit shadow)))
    (consult-line-number                  ((t :inherit shadow)))
    (consult-line-number-prefix           ((t :inherit shadow)))
    (consult-separator                    ((t :foreground ui)))

    (tempel-default                       ((t :foreground fg-comment :inherit italic)))
    (tempel-field                         ((t :background bg-sel)))
    (tempel-form                          ((t :background bg-blue)))

    (vundo-default                        ((t :foreground fg-comment)))
    (vundo-highlight                      ((t :foreground fg-function :weight bold)))
    (vundo-last-saved                     ((t :foreground fg-success :weight bold)))
    (vundo-saved                          ((t :foreground fg-info)))

;;;; rainbow-delimiters

    (rainbow-delimiters-base-face         ((t :foreground fg-comment)))
    (rainbow-delimiters-base-error-face   ((t :foreground fg-error)))
    (rainbow-delimiters-depth-1-face      ((t :foreground yellow)))
    (rainbow-delimiters-depth-2-face      ((t :foreground green)))
    (rainbow-delimiters-depth-3-face      ((t :foreground cyan)))
    (rainbow-delimiters-depth-4-face      ((t :foreground blue)))
    (rainbow-delimiters-depth-5-face      ((t :foreground magenta)))
    (rainbow-delimiters-depth-6-face      ((t :foreground red)))
    (rainbow-delimiters-depth-7-face      ((t :foreground yellow)))
    (rainbow-delimiters-depth-8-face      ((t :foreground green)))
    (rainbow-delimiters-depth-9-face      ((t :foreground cyan)))
    (rainbow-delimiters-mismatched-face   ((t :foreground red-strong :weight bold)))
    (rainbow-delimiters-unmatched-face    ((t :foreground red-strong :weight bold)))

;;;; avy

    (avy-background-face                  ((t :foreground fg-comment)))
    (avy-goto-char-timer-face             ((t :inherit bold :background bg-sel)))
    (avy-lead-face                        ((t :foreground bg :background red-strong :weight bold)))
    (avy-lead-face-0                      ((t :foreground bg :background blue-strong :weight bold)))
    (avy-lead-face-1                      ((t :foreground bg :background green-strong :weight bold)))
    (avy-lead-face-2                      ((t :foreground bg :background magenta-strong :weight bold)))

;;;; which-key

    (which-key-key-face                   ((t :foreground fg-function :weight bold)))
    (which-key-group-description-face     ((t :foreground fg-directory)))
    (which-key-command-description-face   ((t :foreground fg)))
    (which-key-local-map-description-face ((t :foreground fg-type)))
    (which-key-highlighted-command-face   ((t :foreground fg-warning :weight bold)))
    (which-key-note-face                  ((t :foreground fg-comment :inherit italic)))
    (which-key-separator-face             ((t :foreground fg-comment)))
    (which-key-special-key-face           ((t :foreground fg-error :weight bold)))

;;;; outline-mode

    (outline-1                            ((t :foreground fg-title :weight bold)))
    (outline-2                            ((t :foreground yellow-strong :weight bold)))
    (outline-3                            ((t :foreground green-strong :weight bold)))
    (outline-4                            ((t :inherit outline-1)))
    (outline-5                            ((t :inherit outline-2)))
    (outline-6                            ((t :inherit outline-3)))
    (outline-7                            ((t :inherit outline-1)))
    (outline-8                            ((t :inherit outline-2)))

;;;; imenu-list

    (imenu-list-entry-face-0              ((t :foreground fg-link)))
    (imenu-list-entry-face-1              ((t :foreground fg-constant)))
    (imenu-list-entry-face-2              ((t :foreground green)))
    (imenu-list-entry-face-3              ((t :foreground yellow)))
    (imenu-list-entry-subalist-face-0     ((t :inherit (bold imenu-list-entry-face-0) :underline t)))
    (imenu-list-entry-subalist-face-1     ((t :inherit (bold imenu-list-entry-face-1) :underline t)))
    (imenu-list-entry-subalist-face-2     ((t :inherit (bold imenu-list-entry-face-2) :underline t)))
    (imenu-list-entry-subalist-face-3     ((t :inherit (bold imenu-list-entry-face-3) :underline t)))

;;;; tab-bar-mode

    (tab-bar                              ((t :background bg-tab)))
    (tab-bar-tab                          ((t :foreground fg-tab-active :background bg-tab-active :weight bold)))
    (tab-bar-tab-inactive                 ((t :foreground fg-tab :background bg-tab)))
    (tab-bar-tab-group-current            ((t :foreground fg :weight bold)))
    (tab-bar-tab-group-inactive           ((t :foreground fg-comment)))
    (tab-bar-tab-ungrouped                ((t :foreground fg-comment)))

;;;; show-paren-mode / isearch extras already set above


;;;; org

    (org-level-1                          ((t :foreground fg-title :weight bold)))
    (org-level-2                          ((t :foreground yellow-strong :weight bold)))
    (org-level-3                          ((t :foreground green-strong :weight bold)))
    (org-level-4                          ((t :inherit org-level-1)))
    (org-level-5                          ((t :inherit org-level-2)))
    (org-level-6                          ((t :inherit org-level-3)))
    (org-level-7                          ((t :inherit org-level-1)))
    (org-level-8                          ((t :inherit org-level-2)))
    (org-document-title                   ((t :foreground fg-title :weight bold :height 1.3)))
    (org-document-info                    ((t :foreground fg-comment)))
    (org-document-info-keyword            ((t :foreground fg-comment)))
    (org-node-context-origin-title        ((t :foreground fg-title :weight bold)))

    (org-block                            ((t :background bg-float)))
    (org-block-begin-line                 ((t :foreground fg-comment :background bg-float)))
    (org-block-end-line                   ((t :inherit org-block-begin-line)))
    (org-meta-line                        ((t :foreground fg-comment)))
    (org-drawer                           ((t :foreground fg-comment)))
    (org-special-keyword                  ((t :foreground fg-comment)))
    (org-verbatim                         ((t :foreground cyan-strong)))
    (org-code                             ((t :foreground cyan-strong)))
    (org-table                            ((t :foreground fg-type)))
    (org-table-header                     ((t :foreground fg-type :weight bold)))
    (org-formula                          ((t :foreground fg-constant)))
    (org-property-value                   ((t :foreground fg-string)))

    (org-link                             ((t :inherit link)))
    (org-footnote                         ((t :foreground fg-link)))
    (org-target                           ((t :foreground fg-link :underline t)))
    (org-date                             ((t :foreground fg-link)))
    (org-date-selected                    ((t :foreground fg :background bg-sel :weight bold)))
    (org-sexp-date                        ((t :foreground fg-comment)))

    (org-todo                             ((t :foreground fg-error :weight bold)))
    (org-done                             ((t :foreground fg-success :weight bold)))
    (org-headline-todo                    ((t :foreground fg-error)))
    (org-headline-done                    ((t :foreground fg-comment)))
    (org-tag                              ((t :foreground ui)))
    (org-tag-group                        ((t :foreground ui :weight bold)))
    (org-checkbox                         ((t :foreground fg-delimiter)))
    (org-checkbox-statistics-done         ((t :foreground fg-success)))
    (org-checkbox-statistics-todo         ((t :foreground fg-error)))
    (org-priority                         ((t :foreground fg-warning :weight bold)))
    (org-list-dt                          ((t :foreground fg :weight bold)))
    (org-macro                            ((t :foreground fg-preprocessor)))
    (org-latex-and-related                ((t :foreground fg-type)))
    (org-warning                          ((t :foreground fg-error :weight bold)))
    (org-archived                         ((t :foreground fg-comment)))
    (org-quote                            ((t :inherit (italic org-block))))
    (org-verse                            ((t :inherit (italic org-block))))
    (org-column                           ((t :background bg-float)))
    (org-column-title                     ((t :background bg-float :weight bold)))
    (org-clock-overlay                    ((t :background bg-sel)))
    (org-mode-line-clock-overrun          ((t :foreground fg-error :weight bold)))
    (org-dispatcher-highlight             ((t :foreground fg-warning :weight bold)))

    (org-scheduled                        ((t :foreground fg-comment)))
    (org-scheduled-today                  ((t :foreground fg-warning)))
    (org-scheduled-previously             ((t :foreground fg-error)))
    (org-upcoming-deadline                ((t :foreground fg-warning)))
    (org-upcoming-distant-deadline        ((t :foreground fg-comment)))
    (org-imminent-deadline                ((t :foreground fg-error :weight bold)))
    (org-time-grid                        ((t :foreground fg-comment)))

    (org-hide                             ((t :foreground bg)))
    (org-indent                           ((t :inherit org-hide)))
    (org-ellipsis                         ((t :foreground fg-comment :background bg-fold)))

    (org-agenda-structure                 ((t :foreground fg-title :weight bold)))
    (org-agenda-structure-filter          ((t :foreground fg-error)))
    (org-agenda-structure-secondary       ((t :foreground fg-comment)))
    (org-agenda-date                      ((t :foreground fg-link)))
    (org-agenda-date-today                ((t :foreground fg :weight bold :underline t)))
    (org-agenda-date-weekend               ((t :foreground fg-comment)))
    (org-agenda-date-weekend-today        ((t :foreground fg-warning :weight bold)))
    (org-agenda-current-time              ((t :foreground fg-error)))
    (org-agenda-clocking                  ((t :background bg-sel)))
    (org-agenda-done                      ((t :foreground fg-success)))
    (org-agenda-diary                     ((t :foreground fg-comment)))
    (org-agenda-dimmed-todo-face          ((t :foreground ui)))
    (org-agenda-filter-category           ((t :foreground fg-warning)))
    (org-agenda-filter-effort             ((t :foreground fg-warning)))
    (org-agenda-filter-regexp             ((t :foreground fg-warning)))
    (org-agenda-filter-tags               ((t :foreground fg-warning)))
    (org-agenda-restriction-lock          ((t :background bg-yellow)))
    (org-agenda-column-dateline           ((t :foreground fg-comment)))
    (org-agenda-calendar-daterange        ((t :foreground fg-comment)))
    (org-agenda-calendar-event            ((t :foreground fg)))
    (org-agenda-calendar-sexp             ((t :foreground fg-comment)))

    (org-habit-clear-face                 ((t :background bg-blue)))
    (org-habit-clear-future-face          ((t :background bg-float)))
    (org-habit-ready-face                 ((t :background bg-green)))
    (org-habit-ready-future-face          ((t :background bg-green)))
    (org-habit-alert-face                 ((t :background bg-yellow)))
    (org-habit-alert-future-face          ((t :background bg-yellow)))
    (org-habit-overdue-face               ((t :background bg-red)))
    (org-habit-overdue-future-face        ((t :background bg-red)))

;;;; markdown-mode

    (markdown-header-face-1               ((t :inherit org-level-1)))
    (markdown-header-face-2               ((t :inherit org-level-2)))
    (markdown-header-face-3               ((t :inherit org-level-3)))
    (markdown-header-face-4               ((t :inherit org-level-1)))
    (markdown-header-face-5               ((t :inherit org-level-2)))
    (markdown-header-face-6               ((t :inherit org-level-3)))
    (markdown-bold-face                   ((t :inherit bold)))
    (markdown-italic-face                 ((t :inherit italic)))
    (markdown-code-face                   ((t :foreground cyan-strong)))
    (markdown-inline-code-face            ((t :foreground cyan-strong)))
    (markdown-pre-face                    ((t :foreground fg-comment)))
    (markdown-blockquote-face             ((t :foreground fg-comment :inherit italic)))
    (markdown-gfm-checkbox-face           ((t :foreground fg-delimiter)))
    (markdown-highlighting-face           ((t :background bg-sel)))
    (markdown-language-keyword-face       ((t :foreground fg-keyword)))
    (markdown-line-break-face             ((t :foreground ui)))
    (markdown-link-face                   ((t :inherit link)))
    (markdown-markup-face                 ((t :foreground fg-delimiter)))
    (markdown-metadata-key-face           ((t :foreground fg-keyword)))
    (markdown-metadata-value-face         ((t :foreground fg-string)))
    (markdown-missing-link-face           ((t :foreground fg-error :underline t)))
    (markdown-table-face                  ((t :foreground fg-type)))
    (markdown-url-face                    ((t :foreground fg-link)))

;;;; dired / diredfl / dirvish

    (dired-directory                      ((t :foreground fg-directory)))
    (dired-symlink                        ((t :inherit link)))
    (dired-broken-symlink                 ((t :inherit (error link))))
    (dired-flagged                        ((t :inherit bold :foreground fg-error :background bg-red :extend t)))
    (dired-marked                         ((t :inherit bold :foreground fg-warning :background bg-yellow :extend t)))
    (dired-header                         ((t :foreground fg-title :weight bold)))
    (dired-ignored                        ((t :inherit shadow)))
    (dired-mark                           ((t :foreground fg-error)))
    (dired-warning                        ((t :inherit warning)))

    (diredfl-dir-heading                  ((t :inherit dired-header)))
    (diredfl-dir-name                     ((t :inherit dired-directory)))
    (diredfl-dir-priv                     ((t :inherit dired-directory)))
    (diredfl-file-name                    ((t :foreground fg)))
    (diredfl-file-suffix                  ((t :foreground fg-comment)))
    (diredfl-symlink                      ((t :inherit dired-symlink)))
    (diredfl-executable-tag               ((t :foreground fg-success)))
    (diredfl-exec-priv                    ((t :foreground fg-success)))
    (diredfl-read-priv                    ((t :foreground fg-info)))
    (diredfl-write-priv                   ((t :foreground fg-constant)))
    (diredfl-no-priv                      ((t :foreground ui)))
    (diredfl-other-priv                   ((t :foreground fg-warning)))
    (diredfl-rare-priv                    ((t :foreground fg-warning)))
    (diredfl-number                       ((t :foreground fg-number)))
    (diredfl-date-time                    ((t :foreground fg-comment)))
    (diredfl-compressed-file-name         ((t :foreground fg-warning)))
    (diredfl-compressed-file-suffix       ((t :foreground fg-warning)))
    (diredfl-ignored-file-name            ((t :inherit shadow)))
    (diredfl-deletion                     ((t :inherit dired-flagged)))
    (diredfl-deletion-file-name           ((t :inherit dired-flagged)))
    (diredfl-flag-mark                    ((t :inherit dired-marked)))
    (diredfl-flag-mark-line               ((t :inherit dired-marked)))
    (diredfl-autofile-name                ((t :background bg-float)))
    (diredfl-tagged-autofile-name         ((t :inherit (diredfl-autofile-name dired-marked))))
    (diredfl-link-priv                    ((t :foreground fg-link)))

    (dirvish-hl-line                      ((t :background bg-float :extend t)))

;;;; ibuffer

    ;; Real face names from `ibuffer.el' (built-in); mirrors the dired
    ;; treatment above since ibuffer is a buffer-listing analogue of dired.
    (ibuffer-marked                       ((t :inherit dired-marked)))
    (ibuffer-deletion                     ((t :inherit dired-flagged)))
    (ibuffer-title                        ((t :inherit dired-header)))
    (ibuffer-filter-group-name            ((t :foreground fg-title :weight bold)))
    (ibuffer-locked-buffer                ((t :foreground fg-warning)))

;;;; git-commit / git-gutter / git-gutter-fr / git-rebase

    (git-commit-comment-action            ((t :inherit font-lock-comment-face)))
    (git-commit-comment-branch-local      ((t :inherit font-lock-comment-face :foreground fg-link)))
    (git-commit-comment-branch-remote     ((t :inherit font-lock-comment-face :foreground fg-success)))
    (git-commit-comment-heading           ((t :inherit (bold font-lock-comment-face))))
    (git-commit-comment-file              ((t :inherit font-lock-comment-face :foreground fg-constant)))
    (git-commit-keyword                   ((t :foreground fg-constant)))
    (git-commit-nonempty-second-line      ((t :foreground fg-error)))
    (git-commit-overlong-summary          ((t :foreground fg-warning)))
    (git-commit-summary                   ((t :inherit success)))

    (git-gutter:added                     ((t :foreground green :background bg-green)))
    (git-gutter:deleted                   ((t :foreground red :background bg-red)))
    (git-gutter:modified                  ((t :foreground magenta :background bg-magenta)))
    (git-gutter:separator                 ((t :inherit success)))
    (git-gutter:unchanged                 ((t :inherit bold)))

    (git-gutter-fr:added                  ((t :foreground green :background bg-green)))
    (git-gutter-fr:deleted                ((t :foreground red :background bg-red)))
    (git-gutter-fr:modified               ((t :foreground magenta :background bg-magenta)))

    (git-rebase-comment-hash              ((t :inherit (bold font-lock-comment-face) :foreground fg-constant)))
    (git-rebase-comment-heading           ((t :inherit (bold font-lock-comment-face))))
    (git-rebase-description               ((t :foreground fg)))
    (git-rebase-hash                      ((t :foreground fg-constant)))

;;;; vc

    (vc-dir-file                          ((t :foreground fg)))
    (vc-dir-header                        ((t :foreground fg-title :weight bold)))
    (vc-dir-header-value                  ((t :foreground fg)))
    (vc-dir-mark-indicator                ((t :foreground fg-warning)))
    (vc-dir-status-edited                 ((t :foreground fg-warning)))
    (vc-dir-status-ignored                ((t :inherit shadow)))
    (vc-dir-status-up-to-date             ((t :inherit success)))
    (vc-dir-status-warning                ((t :inherit warning)))
    (vc-conflict-state                    ((t :foreground fg-error :weight bold)))
    (vc-edited-state                      ((t :foreground fg-warning)))
    (vc-git-log-edit-summary-max-warning  ((t :foreground fg-error :weight bold)))
    (vc-git-log-edit-summary-target-warning ((t :foreground fg-warning :weight bold)))
    (vc-locally-added-state               ((t :foreground fg-success)))
    (vc-locked-state                      ((t :foreground fg-error)))
    (vc-missing-state                     ((t :foreground fg-error :weight bold)))
    (vc-needs-update-state                ((t :foreground fg-warning :weight bold)))
    (vc-removed-state                     ((t :foreground fg-error)))

;;;; transient

    (transient-heading                    ((t :foreground fg-title :weight bold)))
    (transient-key                        ((t :foreground fg-function :weight bold)))
    (transient-key-exit                   ((t :foreground fg-error :weight bold)))
    (transient-key-return                 ((t :foreground fg-success :weight bold)))
    (transient-key-stay                   ((t :foreground fg-info :weight bold)))
    (transient-key-noop                   ((t :foreground ui)))
    (transient-argument                   ((t :foreground fg-constant :weight bold)))
    (transient-value                      ((t :foreground fg-string)))
    (transient-active-infix               ((t :background bg-sel)))
    (transient-inactive-argument          ((t :foreground ui)))
    (transient-inactive-value             ((t :foreground ui)))
    (transient-unreachable                ((t :foreground ui)))
    (transient-unreachable-key            ((t :foreground ui)))
    (transient-nonstandard-key            ((t :foreground fg-warning :weight bold)))
    (transient-mismatched-key             ((t :foreground fg-error :weight bold)))
    (transient-disabled-suffix            ((t :foreground ui :strike-through t)))
    (transient-enabled-suffix             ((t :foreground fg-success)))
    (transient-red                        ((t :foreground fg-error :weight bold)))
    (transient-blue                       ((t :foreground fg-info :weight bold)))
    (transient-pink                       ((t :foreground fg-constant :weight bold)))
    (transient-purple                     ((t :foreground magenta-strong :weight bold)))
    (transient-teal                       ((t :foreground cyan-strong :weight bold)))
    (transient-amaranth                   ((t :foreground red-strong :weight bold)))

;;;; magit (sections, branches, log, process, sequence, signatures)
;;;; -- magit-diff-* faces are set alongside the diff family, above.

    (magit-bisect-bad                     ((t :inherit error)))
    (magit-bisect-good                    ((t :inherit success)))
    (magit-bisect-skip                    ((t :inherit warning)))
    (magit-blame-dimmed                   ((t :inherit shadow)))
    (magit-blame-highlight                ((t :background bg-sel)))
    (magit-branch-local                   ((t :foreground fg-link)))
    (magit-branch-remote                  ((t :foreground fg-success)))
    (magit-branch-upstream                ((t :inherit italic)))
    (magit-branch-warning                 ((t :inherit warning)))
    (magit-cherry-equivalent              ((t :foreground fg-constant)))
    (magit-cherry-unmatched               ((t :foreground fg-info)))
    (magit-diffstat-added                 ((t :foreground fg-success)))
    (magit-diffstat-removed               ((t :foreground fg-error)))
    (magit-dimmed                         ((t :inherit shadow)))
    (magit-filename                       ((t :foreground fg-directory)))
    (magit-hash                           ((t :foreground fg-comment)))
    (magit-head                           ((t :inherit magit-branch-local)))
    (magit-header-line                    ((t :inherit bold)))
    (magit-header-line-key                ((t :foreground fg-function :weight bold)))
    (magit-header-line-log-select         ((t :inherit bold)))
    (magit-keyword                        ((t :foreground fg-constant)))
    (magit-keyword-squash                 ((t :foreground fg-warning :weight bold)))
    (magit-log-author                     ((t :foreground fg-constant)))
    (magit-log-date                       ((t :foreground fg-comment)))
    (magit-log-graph                      ((t :foreground fg-comment)))
    (magit-mode-line-process              ((t :foreground fg-warning :weight bold)))
    (magit-mode-line-process-error        ((t :foreground fg-error :weight bold)))
    (magit-process-ng                     ((t :inherit error)))
    (magit-process-ok                     ((t :inherit success)))
    (magit-reflog-amend                   ((t :foreground fg-warning)))
    (magit-reflog-checkout                ((t :foreground fg-link)))
    (magit-reflog-cherry-pick             ((t :foreground fg-constant)))
    (magit-reflog-commit                  ((t :foreground fg-success)))
    (magit-reflog-merge                   ((t :foreground fg-success)))
    (magit-reflog-other                   ((t :foreground fg-info)))
    (magit-reflog-rebase                  ((t :foreground fg-warning)))
    (magit-reflog-remote                  ((t :foreground fg-link)))
    (magit-reflog-reset                   ((t :foreground fg-error)))
    (magit-refname                        ((t :foreground fg-comment)))
    (magit-refname-pullreq                ((t :foreground fg-success)))
    (magit-refname-stash                  ((t :foreground fg-constant)))
    (magit-refname-wip                    ((t :foreground fg-comment)))
    (magit-section                        ((t :foreground fg)))
    (magit-section-heading                ((t :foreground fg-title :weight bold)))
    (magit-section-heading-selection      ((t :foreground fg-warning :weight bold)))
    (magit-section-highlight              ((t :background bg-float)))
    (magit-sequence-done                  ((t :inherit success)))
    (magit-sequence-drop                  ((t :inherit error)))
    (magit-sequence-exec                  ((t :foreground fg-constant)))
    (magit-sequence-head                  ((t :foreground fg-link)))
    (magit-sequence-onto                  ((t :inherit shadow)))
    (magit-sequence-part                  ((t :foreground fg-warning)))
    (magit-sequence-pick                  ((t :foreground fg)))
    (magit-sequence-stop                  ((t :inherit error)))
    (magit-signature-bad                  ((t :inherit error)))
    (magit-signature-error                ((t :inherit error)))
    (magit-signature-expired              ((t :foreground fg-warning)))
    (magit-signature-expired-key          ((t :foreground fg-warning)))
    (magit-signature-good                 ((t :inherit success)))
    (magit-signature-revoked              ((t :foreground fg-constant)))
    (magit-signature-untrusted            ((t :foreground fg-warning)))
    (magit-tag                            ((t :foreground fg-warning)))

;;;; message.el (shared by gnus and notmuch)

    (message-cited-text-1                 ((t :foreground green)))
    (message-cited-text-2                 ((t :foreground blue)))
    (message-cited-text-3                 ((t :foreground magenta)))
    (message-cited-text-4                 ((t :foreground yellow)))
    (message-header-name                  ((t :foreground fg-keyword :weight bold)))
    (message-header-to                    ((t :foreground fg-function :weight bold)))
    (message-header-cc                    ((t :foreground fg-function)))
    (message-header-newsgroups            ((t :foreground fg-function)))
    (message-header-subject               ((t :foreground fg :weight bold)))
    (message-header-xheader               ((t :foreground fg-comment)))
    (message-header-other                 ((t :foreground fg-comment)))
    (message-mml                          ((t :foreground fg-preprocessor)))
    (message-separator                    ((t :inherit shadow)))

;;;; gnus

    (gnus-button                          ((t :inherit button :underline nil)))
    (gnus-cite-1                          ((t :inherit message-cited-text-1)))
    (gnus-cite-2                          ((t :inherit message-cited-text-2)))
    (gnus-cite-3                          ((t :inherit message-cited-text-3)))
    (gnus-cite-4                          ((t :inherit message-cited-text-4)))
    (gnus-cite-5                          ((t :inherit message-cited-text-1)))
    (gnus-cite-6                          ((t :inherit message-cited-text-2)))
    (gnus-cite-7                          ((t :inherit message-cited-text-3)))
    (gnus-cite-8                          ((t :inherit message-cited-text-4)))
    (gnus-cite-9                          ((t :inherit message-cited-text-1)))
    (gnus-cite-10                         ((t :inherit message-cited-text-2)))
    (gnus-cite-11                         ((t :inherit message-cited-text-3)))
    (gnus-cite-attribution                ((t :inherit italic)))
    (gnus-emphasis-bold                   ((t :inherit bold)))
    (gnus-emphasis-bold-italic            ((t :inherit bold-italic)))
    (gnus-emphasis-italic                 ((t :inherit italic)))
    (gnus-emphasis-underline-bold         ((t :inherit gnus-emphasis-bold :underline t)))
    (gnus-emphasis-underline-bold-italic  ((t :inherit gnus-emphasis-bold-italic :underline t)))
    (gnus-emphasis-underline-italic       ((t :inherit gnus-emphasis-italic :underline t)))
    (gnus-emphasis-highlight-words        ((t :inherit warning)))
    (gnus-group-mail-1                    ((t :foreground fg-link :weight bold)))
    (gnus-group-mail-1-empty              ((t :foreground fg-link)))
    (gnus-group-mail-2                    ((t :foreground fg-constant :weight bold)))
    (gnus-group-mail-2-empty              ((t :foreground fg-constant)))
    (gnus-group-mail-3                    ((t :foreground fg-info :weight bold)))
    (gnus-group-mail-3-empty              ((t :foreground fg-info)))
    (gnus-group-mail-low                  ((t :foreground fg-comment :weight bold)))
    (gnus-group-mail-low-empty            ((t :foreground fg-comment)))
    (gnus-group-news-1                    ((t :foreground blue-strong :weight bold)))
    (gnus-group-news-1-empty              ((t :foreground blue-strong)))
    (gnus-group-news-2                    ((t :foreground magenta-strong :weight bold)))
    (gnus-group-news-2-empty              ((t :foreground magenta-strong)))
    (gnus-group-news-3                    ((t :foreground cyan-strong :weight bold)))
    (gnus-group-news-3-empty              ((t :foreground cyan-strong)))
    (gnus-group-news-4                    ((t :foreground green-strong :weight bold)))
    (gnus-group-news-4-empty              ((t :foreground green-strong)))
    (gnus-group-news-5                    ((t :foreground yellow-strong :weight bold)))
    (gnus-group-news-5-empty              ((t :foreground yellow-strong)))
    (gnus-group-news-6                    ((t :foreground red-strong :weight bold)))
    (gnus-group-news-6-empty              ((t :foreground red-strong)))
    (gnus-group-news-low                  ((t :foreground fg-comment :weight bold)))
    (gnus-group-news-low-empty            ((t :foreground fg-comment)))
    (gnus-header-content                  ((t :inherit message-header-other)))
    (gnus-header-from                     ((t :inherit message-header-to :underline nil)))
    (gnus-header-name                     ((t :inherit message-header-name)))
    (gnus-header-newsgroups               ((t :inherit message-header-newsgroups)))
    (gnus-header-subject                  ((t :inherit message-header-subject)))
    (gnus-server-agent                    ((t :inherit bold)))
    (gnus-server-closed                   ((t :inherit italic)))
    (gnus-server-cloud                    ((t :foreground fg-info :weight bold)))
    (gnus-server-cloud-host               ((t :foreground fg-info :weight bold :underline t)))
    (gnus-server-denied                   ((t :inherit error)))
    (gnus-server-offline                  ((t :inherit shadow)))
    (gnus-server-opened                   ((t :inherit success)))
    (gnus-summary-cancelled               ((t :foreground fg-warning :background bg-yellow)))
    (gnus-summary-high-ancient            ((t :foreground fg-comment :weight bold)))
    (gnus-summary-high-read               ((t :foreground fg-comment :weight bold)))
    (gnus-summary-high-ticked             ((t :foreground fg-error :weight bold)))
    (gnus-summary-high-undownloaded       ((t :inherit bold-italic :foreground fg-warning)))
    (gnus-summary-high-unread             ((t :inherit bold)))
    (gnus-summary-low-ancient             ((t :inherit italic)))
    (gnus-summary-low-read                ((t :inherit (shadow italic))))
    (gnus-summary-low-ticked              ((t :inherit italic :foreground fg-error)))
    (gnus-summary-low-undownloaded        ((t :inherit italic :foreground fg-warning)))
    (gnus-summary-low-unread              ((t :inherit italic)))
    (gnus-summary-normal-read             ((t :inherit shadow)))
    (gnus-summary-normal-ticked           ((t :foreground fg-error)))
    (gnus-summary-normal-undownloaded     ((t :foreground fg-warning)))
    (gnus-summary-selected                ((t :inherit highlight)))

;;;; notmuch

    (notmuch-crypto-decryption            ((t :foreground fg-info)))
    (notmuch-crypto-part-header           ((t :foreground fg-comment :weight bold)))
    (notmuch-crypto-signature-bad         ((t :inherit error)))
    (notmuch-crypto-signature-good        ((t :inherit success)))
    (notmuch-crypto-signature-good-key    ((t :foreground fg-success)))
    (notmuch-crypto-signature-unknown     ((t :inherit warning)))
    (notmuch-jump-key                     ((t :foreground fg-function :weight bold)))
    (notmuch-message-summary-face         ((t :foreground fg-comment :inherit italic)))
    (notmuch-search-count                 ((t :foreground fg-comment)))
    (notmuch-search-date                  ((t :foreground fg-link)))
    (notmuch-search-flagged-face          ((t :foreground fg-error)))
    (notmuch-search-matching-authors      ((t :foreground fg)))
    (notmuch-search-non-matching-authors  ((t :foreground fg-comment)))
    (notmuch-search-subject               ((t :foreground fg)))
    (notmuch-search-unread-face           ((t :inherit bold)))
    (notmuch-tag-added                    ((t :foreground fg-success)))
    (notmuch-tag-deleted                  ((t :foreground fg-error :strike-through t)))
    (notmuch-tag-face                     ((t :foreground fg-link)))
    (notmuch-tag-flagged                  ((t :foreground fg-warning :weight bold)))
    (notmuch-tag-unread                   ((t :foreground fg-error :weight bold)))
    (notmuch-tree-match-author-face       ((t :foreground fg)))
    (notmuch-tree-match-date-face         ((t :foreground fg-link)))
    (notmuch-tree-match-face              ((t :foreground fg-comment)))
    (notmuch-tree-match-tag-face          ((t :foreground fg-link)))
    (notmuch-tree-no-match-face           ((t :inherit shadow)))
    (notmuch-tree-no-match-date-face      ((t :inherit shadow)))
    (notmuch-wash-cited-text              ((t :inherit message-cited-text-1)))
    (notmuch-wash-toggle-button           ((t :foreground fg-comment :box ui)))
    )
  "The full `melange-light' face table, in `custom-theme-set-faces' shape.
Every colour value is a bare symbol from `melange-light-palette' (or
`melange-light-palette-overrides'); `melange-light--expand' resolves
them to hex before this is handed to `custom-theme-set-faces'.")

(apply #'custom-theme-set-faces 'melange-light
       (melange-light--expand melange-light-faces))

(provide-theme 'melange-light)
(provide 'melange-light-theme)

;;; melange-light-theme.el ends here
