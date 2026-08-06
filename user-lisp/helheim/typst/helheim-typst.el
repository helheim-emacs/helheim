;;; helheim-typst.el              -*- lexical-binding: t; no-byte-compile: t -*-
;;; Commentary:
;;
;; Typst authoring.  Four pieces, each owning one job:
;;
;;   typst-ts-mode  — the major mode.  Tree-sitter font-lock and indentation,
;;                    imenu + outline over `=' headings, raw blocks fontified
;;                    in the embedded language's own mode, sub/superscripts
;;                    displayed raised/lowered, structural editing of headings,
;;                    lists and grids on M-<arrows>, a symbol/emoji picker, and
;;                    drivers for `typst compile' / `typst watch'.
;;   tinymist       — the language server: completion, hover, goto, rename,
;;                    diagnostics, `typstyle' formatting.  lsp-mode ships the
;;                    `lsp-typst' client (10.0.0+); Eglot has no Typst entry of
;;                    its own, so this module registers one.
;;   typst-preview  — live preview.  `tinymist preview' renders to a websocket
;;                    that the buffer is pushed to on every keystroke, with
;;                    source <-> preview jumping.  Browser or xwidget.
;;   ox-typst       — Org export back-end, under `y' in `org-export-dispatch'.
;;                    Additive: `ox-latex' is untouched.  Plus the org-src
;;                    mapping that makes `#+begin_src typst' editable.
;;
;; ---------------------------------------------------------------------------
;; Why this is *not* a port of `helheim-latex'
;;
;; helheim-latex is, in the main, an input-acceleration layer: CDLaTeX symbol
;; and modifier keys, `aas' snippets, wrapping fractions, sized-delimiter
;; triggers.  All of it exists because LaTeX math is verbose — `\alpha',
;; `\frac{a}{b}', `x^{2}', `\left( \right)', `\to', `\neq'.
;;
;; Typst's math syntax is already what those layers simulate:
;;
;;   \alpha            -> alpha              (bare identifier)
;;   \frac{a+b}{5}     -> (a+b)/5            (`/' *is* the fraction operator)
;;   x^{2}, x_{1}      -> x^2, x_1           (no braces; `(..)' groups)
;;   \to \neq \leq     -> -> != <=           (shorthands, native)
;;   \left( .. \right) -> ( .. )             (delimiters scale automatically)
;;   \begin{align}     -> $ .. & .. \ .. $   (`&' aligns, `\' breaks)
;;
;; So there is no `aas' block here and no CDLaTeX equivalent: adding one would
;; mean typing *more* characters to produce the same output.  What genuinely
;; has no shorthand — the ~1700 named symbols and emoji — is covered by
;; `typst-ts-editing-symbol-picker', bound below.  See the README.
;;
;; The one thing helheim-latex has that Typst still lacks is preview *inside*
;; the buffer, `org-fragtog'-style.  See "Upgrade A" at the end of the file.
;; ---------------------------------------------------------------------------
;;
;;; Code:

;;;; Tree-sitter grammar

;; `typst-ts-mc-install-grammar' installs this same repository, but we
;; register it in `treesit-language-source-alist' instead, so Helheim's own
;; path (`helheim-install-missing-treesit-grammars', run from
;; `after-init-hook') picks it up.  It is uben0's grammar — the one upstream
;; typst-ts-mode targets — installed through the maintainer's fork.  That
;; fork tracks uben0's grammar and is what upstream's own installer uses too.
(helheim-setup treesit
  (:when (treesit-available-p))
  (:treesit typst "https://github.com/Ziqi-Yang/tree-sitter-typst"))

;;;; typst-ts-mode

(helheim-setup typst-ts-mode
  ;; NonGNU ELPA carries this package, but its tarball lags the repository by
  ;; a long way, so track `main' directly.  This is upstream's own recommended
  ;; Elpaca recipe.
  (:elpaca typst-ts-mode
   :type git :host codeberg :repo "meow_king/typst-ts-mode" :branch "main")
  (:mode ("\\.typ\\'" . typst-ts-mode))
  (:command typst-ts-mode)

  (:setopt
   ;; Fontify ```rust ... ``` raw blocks in the embedded language's own mode.
   ;; Must be set before the first .typ file is opened — which it is, since
   ;; this code runs inside the Elpaca install closure, not through the
   ;; package's autoloads.
   typst-ts-enable-raw-blocks-highlight t
   ;; Where Helheim installs grammars.  Only consulted by
   ;; `typst-ts-check-grammar-version', which warns when the built grammar
   ;; predates the minimum version typst-ts-mode's queries need.  Left nil
   ;; upstream, i.e. no check at all.
   typst-ts-grammar-location
   (expand-file-name "tree-sitter/libtree-sitter-typst.so" user-emacs-directory))

  ;; Soft-wrap prose, as in `helheim-markdown'.  Swap for `auto-fill-mode' if
  ;; you would rather hard-wrap.
  (:hook typst-ts-mode-hook +wrap-line-mode)
  ;; Start the language server — `helheim-lsp' dispatches to Eglot or lsp-mode
  ;; depending on which one you required in init.el.
  (:hook typst-ts-mode-hook helheim-lsp))

;;;; tinymist — the language server

;; lsp-mode 10.0.0 ships `lsp-typst.el', a full tinymist client, and already
;; maps `typst-ts-mode' in `lsp-language-id-configuration'.  Nothing to
;; register; only the server settings below.
;; `:after-load' rather than `:after lsp-mode': lsp-mode pulls its client
;; packages in lazily (`lsp--require-packages'), so waiting on lsp-mode itself
;; would run this code too early — before the `lsp-defcustom' forms below are
;; even defined.
(helheim-setup lsp-typst
  (:after-load
    (:setopt
     ;; PDF export is the preview module's job (or `typst watch'), not the
     ;; server's.  "never" is already the default; stated because turning it to
     ;; "onType" is the usual first thing people reach for and it fights
     ;; `typst-preview'.
     lsp-typst-export-pdf "never"
     ;; tinymist's own lint pass, on top of compiler diagnostics.
     lsp-typst-lint-enabled t)))

;; Eglot has no Typst entry — upstream typst-ts-mode deliberately ships none
;; either, to avoid clobbering a user's own.  Appended rather than pushed for
;; the same reason: an entry you add yourself still wins.
(helheim-setup eglot
  (:after-load
    (add-to-list 'eglot-server-programs
                 '((typst-ts-mode) . ("tinymist"))
                 'append)))

;;;; typst-preview — live preview

;; Spawns its own `tinymist preview' process, independent of the LSP server,
;; and drives it over a websocket: the buffer is pushed on every keystroke, so
;; the preview tracks unsaved text.  `typst-preview-mode' starts and stops it.
(helheim-setup typst-preview
  (:install t)
  (:setopt
   ;; Render only the visible part of the document.  Off upstream; on a long
   ;; document the difference is the whole point of a live preview.
   typst-preview-partial-rendering t
   ;; "default" hands the URL to `browse-url'.  "xwidget" keeps the preview
   ;; inside Emacs (needs an --with-xwidgets build); "eaf-browser" is the third
   ;; option.  To keep it in Emacs:
   ;;   (setopt typst-preview-browser "xwidget")
   typst-preview-browser "default"
   ;; Follow the system light/dark setting.
   typst-preview-invert-colors "auto"))

;;;; Org integration

;;;;; ox-typst — Org export back-end

;; Registers a `typst' back-end under `y' in `org-export-dispatch' (Typst
;; buffer / .typ file / PDF / PDF-and-open).  Additive: `ox-latex' is
;; untouched, so `C-c C-e l' still goes through LaTeX.
;;
;; `org-export-define-backend' is *not* autoloaded, so the back-end does not
;; appear in the dispatcher until the file is loaded — hence `:require'.
(helheim-setup ox-typst
  (:install t)
  (:after org)
  (:require t)

  ;; The one real friction point.  Org's math syntax is LaTeX; Typst's is not,
  ;; and the two are not compatible, so every `\(..\)', `\[..\]' and
  ;; `\begin{align}..' has to be translated on the way out.  ox-typst offers
  ;; two strategies, and the choice is global — they cannot be mixed within a
  ;; document:
  ;;
  ;;   `...-with-pandoc'  pipes the fragment through `pandoc -f latex -t typst'.
  ;;                      Real translation: \frac{a+b}{5} -> frac(a + b, 5),
  ;;                      \mathbf{v} -> upright(bold(v)), and an align
  ;;                      environment becomes `$ x & = .. \ y & = .. $'.
  ;;   `...-with-naive'   (upstream default) assumes the fragment is *already*
  ;;                      Typst and only swaps the delimiters for `$'.  Right if
  ;;                      you type Typst math into your Org files; otherwise it
  ;;                      passes LaTeX straight through, and note that it drops
  ;;                      `\begin{..}' environments completely.
  ;;
  ;; Since `helheim-latex' exists to make you type *LaTeX* math into Org, the
  ;; pandoc route is the one that matches this configuration — when pandoc is
  ;; there to do it.
  (:setopt
   org-typst-from-latex-fragment
   (if (executable-find "pandoc")
       #'org-typst-from-latex-with-pandoc
     #'org-typst-from-latex-with-naive)
   org-typst-from-latex-environment
   (if (executable-find "pandoc")
       #'org-typst-from-latex-with-pandoc
     #'org-typst-from-latex-with-naive)))

;;;;; Typst source blocks inside Org

;; Without this, `#+begin_src typst' edits (`C-c '' / `z '') open in
;; `fundamental-mode': `org-src-get-lang-mode' appends "-mode" to the language
;; name and there is no `typst-mode'.  The alist takes the mode name *without*
;; the suffix.
(helheim-setup org-src
  (:after-load
    (add-to-list 'org-src-lang-modes '("typst" . typst-ts))))

;;;; Keys — local leader + toggles (Hel)

(helheim-setup typst-ts-mode
  (:after-load
    (:keymap typst-ts-mode-map
      (:bind :state normal
        ;; Local leader.  `typst-ts-tmenu' is the full transient, including the
        ;; online symbol/package searches that have no key of their own.
        ", ,"  '("typst menu"        . typst-ts-tmenu)
        ", c"  '("compile"           . typst-ts-compile)
        ", C"  '("compile & open"    . typst-ts-compile-and-preview)
        ", o"  '("open PDF"          . typst-ts-preview)
        ", m"  '("set main file"     . typst-ts-main-file-ask)
        ", w"  '("watch"             . typst-ts-watch-mode)
        ", p"  '("live preview"      . typst-preview-mode)
        ", j"  '("jump to preview"   . typst-preview-send-position)
        ", s"  '("symbol / emoji"    . typst-ts-editing-symbol-picker)
        ", l"  '("insert file link"  . typst-ts-mc-insert-link)
        ", e"  '("export markdown"   . typst-ts-mc-export-to-markdown)
        ;; Follow the link / label / file reference at point.
        "g o"  'typst-ts-mc-open-at-point
        ;; Edit the code or raw block at point in its own buffer — the same key
        ;; `helheim-markdown' uses, shadowing the global `separedit' binding.
        "z '"  'typst-ts-edit-indirect
        ;; Outline navigation over `=' headings, as in `helheim-markdown'.
        "C-j"   'outline-next-heading
        "C-k"   'outline-previous-heading
        "z u"   'outline-up-heading
        "z C-j" 'outline-forward-same-level
        "z C-k" 'outline-backward-same-level)
      (:bind
        ;; The shared toggle group.
        "C-c t p" '("live preview" . typst-preview-mode)
        "C-c t w" '("typst watch"  . typst-ts-watch-mode)))))

;; ===========================================================================
;; Upgrade A — inline previews in the buffer (`tip')
;; ===========================================================================
;;
;; `tip' (Typst Inline Preview) is the one piece of the helheim-latex
;; experience Typst has no equivalent for: equations rendered as images in the
;; buffer, revealed as source when the cursor enters them — what
;; `org-latex-preview' + `org-fragtog' do for Org.
;;
;; It is left out of the base install because it does not stand alone: it
;; talks to a separate Python JSON-RPC server (`tip-server-py') that you must
;; clone and start yourself, and upstream calls the project "very early stage".
;; Revisit when the server is bundled or automated.
;;
;; (helheim-setup tip
;;   (:elpaca tip :type git :host sourcehut :repo "mafty/tip")
;;   (:setopt tip-server-basedir "~/src/tip-server-py/"
;;            tip-scale 1.5)
;;   (:hook typst-ts-mode-hook tip-mode))

;; ===========================================================================
;; Upgrade B — `typst watch' instead of a live preview
;; ===========================================================================
;;
;; `typst-ts-watch-mode' (built into typst-ts-mode, bound above) is the
;; lighter-weight alternative: it runs `typst watch' in the background, so the
;; PDF on disk is rebuilt on every save, and whatever PDF viewer you already
;; use refreshes it.  No tinymist, no websocket, no browser.  It updates on
;; *save* rather than on every keystroke, and gives no source <-> preview
;; jumping.  To have the watch open the PDF as soon as it starts:
;;
;; (setopt typst-ts-watch-options '("--open"))

;;; .
(provide 'helheim-typst)
;;; helheim-typst.el ends here
