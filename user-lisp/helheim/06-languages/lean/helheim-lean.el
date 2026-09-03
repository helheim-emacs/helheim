;;; helheim-lean.el -*- lexical-binding: t; no-byte-compile: t -*-
;;; Commentary:
;;
;; Lean 4 — a programming language in which types are propositions and
;; programs are their proofs.  Two pieces:
;;
;;   lean4-mode  — the major mode.  Font-lock, indentation, the "Lean" input
;;                 method that turns `\alpha' into `α', and the *Lean Goal*
;;                 buffer: the Emacs counterpart of the VS Code infoview.
;;   lake serve  — the language server.  It ships inside the Lean toolchain,
;;                 so `elan' puts it on PATH along with `lean' itself.
;;
;; The goal buffer is the reason to edit Lean inside an editor at all. It lists
;; the hypotheses in scope and what is left to prove at point, and it refreshes
;; after every tactic.
;;
;; lean4-mode speaks to the server through lsp-mode alone. It registers an
;; lsp-mode client and reads Lean's own LSP extensions — `$/lean/plainGoal',
;; `$/lean/plainTermGoal', `$/lean/fileProgress' — with `lsp-defun'. Eglot
;; cannot drive it, so `init.el' must require `helheim-lsp-mode'.
;;
;;; Code:
;;;; The Lean toolchain on PATH

;; elan installs into ~/.elan and appends ~/.elan/bin to PATH from ~/.profile.
;; A graphical Emacs is not started from a login shell, so that line never runs
;; and `lake serve' cannot be found.  `exec-path' is what `executable-find' and
;; `start-process' read; the PATH variable is what the server's own child
;; processes read.  Both need the directory.
(let ((dir (expand-file-name "~/.elan/bin")))
  (when (and (file-directory-p dir)
             (not (member dir exec-path)))
    (add-to-list 'exec-path dir)
    (setenv "PATH" (concat dir path-separator (getenv "PATH")))))

;;;; lean4-mode

(helheim-setup lean4-mode
  ;; No package archive carries lean4-mode, so the recipe names the repository.
  ;; The "data" directory holds the translation table of the "Lean" input
  ;; method: `lean4-input-data-directory' looks for it beside the file being
  ;; loaded, so it has to be part of the build.
  (:install lean4-mode
            :host github
            :repo "leanprover-community/lean4-mode"
            :files (:defaults "data"))
  ;; The goal buffer is a companion pane, not somewhere to jump to. Give it
  ;; a fixed side window on the right, as the VS Code infoview has.
  (add-to-list 'display-buffer-alist
               `(,(rx string-start "*Lean Goal*" string-end)
                 (display-buffer-reuse-window
                  display-buffer-in-side-window)
                 (side . right)
                 (window-width . 0.4)
                 (reusable-frames . visible)))
  (:after-load
    (:keymap lean4-mode-map
      (:bind :state normal
        ", g"  '("goals — toggle infoview" . lean4-toggle-info)
        ", b"  '("lake build" . lean4-lake-build)
        ", c"  '("get Mathlib cache" . helheim-lean-mathlib-cache)
        ", x"  '("run lean on this file" . lean4-std-exe)
        ", r"  '("reload imports" . lean4-refresh-file-dependencies)
        ", R"  '("restart server" . lsp-workspace-restart)
        ", k"  '("how to type this symbol" . quail-show-key)
        ", v"  '("lean version" . lean4-show-version))
      (:bind
        ;; The shared toggle group.
        "C-c t g" '("Lean goals" . lean4-toggle-info)))))

;;;; Mathlib

(defun helheim-lean-mathlib-cache ()
  "Download the prebuilt Mathlib object files for the current project.
Compiling Mathlib from source takes hours. `lake exe cache get' fetches the same
`.olean' files from Mathlib's build cache in minutes. The project must depend on
Mathlib, which is what provides the `cache' executable."
  (interactive)
  (if-let* ((default-directory (lean4-lake-find-dir)))
      (compile "lake exe cache get")
    (user-error "Not inside a Lean project")))

;;; .
(provide 'helheim-lean)
;;; helheim-lean.el ends here
