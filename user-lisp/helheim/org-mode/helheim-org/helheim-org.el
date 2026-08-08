;;; helheim-org.el                -*- lexical-binding: t; no-byte-compile: t -*-
;;; Config

(setup org
  (:install t)
  ;; (:install nil)
  (:setopt org-insert-heading-respect-content nil
           org-M-RET-may-split-line '((default . t)
                                      (item . nil))
           org-return-follows-link t
           org-special-ctrl-a/e t
           org-pretty-entities t
           org-edit-keep-region t
           org-preview-latex-image-directory (expand-file-name "ltximg/" user-emacs-directory)
           org-latex-mathml-directory (expand-file-name "ltxmathml/" user-emacs-directory)
           ;; Make `org-goto' (C-c C-j) command usable. But actually
           ;; `consult-org-heading' (gp) provides the same interface but better.
           org-goto-interface 'outline-path-completion
           org-outline-path-complete-in-steps nil
           org-cycle-emulate-tab nil) ; don't insert TAB in non-insert state
  (:require helheim-org-keys)
  (:after-load
    (load "helheim-org-lib" nil t)))

(setup ol
  (:after-load
    ;; Open org links in the same window. Use "C-c &" to back to the link.
    (setf (alist-get 'file org-link-frame-setup) #'find-file)))

(setup org-indent
  (:blackout t))

(setup hel-org
  (:install hel-org :host github :repo "helheim-emacs/hel-org")
  (:after org)
  (:require t))

(setup ox-html
  (:setopt org-html-prefer-user-labels t))

(setup org-eldoc
  (:install org-contrib)
  (:after org)
  (:require t)
  (:setopt org-eldoc-breadcrumb-separator " → ")
  (:after-load
    ;; Show target for link at point.
    (if (<= 31 emacs-major-version)
        (add-hook 'org-mode-hook
                  (defun helheim-org-show-link-target-h ()
                    "Show the target for link at point in echo area."
                    ;; See `eldoc-help-at-pt'
                    (add-hook 'eldoc-documentation-functions
                              #'eldoc-show-help-at-pt 90 t)))
      ;; Emacs version < 31
      (define-advice org-eldoc-documentation-function (:before-until (&rest _) helheim)
        "Display link target in echo area when cursor/mouse is over it."
        (if-let* ((url (thing-at-point 'url t)))
            (format "LINK: %s" url))))
    ;; HACK Fix #2972: infinite recursion when eldoc kicks in 'org' or 'python'
    ;;   src blocks.
    ;; TODO Should be reported upstream!
    (puthash "org" #'ignore org-eldoc-local-functions-cache)
    (puthash "plantuml" #'ignore org-eldoc-local-functions-cache)
    (puthash "python" #'python-eldoc-function org-eldoc-local-functions-cache)))

;;; ID format

;; Use ISO 8601 timestamp.
(setup org-id
  (:setopt org-id-method 'ts
           org-id-ts-format helheim-id-format
           org-id-link-to-org-use-id 'create-if-interactive))

;;; images

(setup org
  (:setopt org-startup-with-inline-images t
           org-cycle-inline-images-display t
           ;; 85% of fill-column width
           org-image-actual-width (list (round (* 0.85 fill-column (default-font-width))))))

;;; org-attach

;; FIX: Link to attachment can't be oppend before `org-attach' is loaded,
;;   and `org-open-at-point' loads it only for headings, but not for links.
(add-to-list 'org-modules 'org-attach)

(setup org-attach
  (:after org)
  (:setopt org-attach-id-dir (expand-file-name "org-attach/" org-directory)
           org-attach-method 'mv ;; move
           org-attach-store-link-p 'attached
           org-attach-preferred-new-method 'id
           org-attach-dir-relative t
           org-attach-sync-delete-empty-dir t
           org-attach-id-to-path-function-list '(helheim-org-attach-id-ts-folder-format
                                                 org-attach-id-uuid-folder-format
                                                 identity)
           org-attach-auto-tag "ATTACH")
  (add-to-list 'org-tags-exclude-from-inheritance org-attach-auto-tag)
  ;;
  (with-eval-after-load 'org-keys
    (:keymap org-mode-map
      (:bind [remap org-attach] 'helheim-org-attach)))
  ;;
  (:after-load
    ;; Swap "f" and "F" keys.
    (setcdr (assoc '(?f ?\C-f) org-attach-commands)
            '(org-attach-reveal-in-emacs
              "Open current node's attachment directory in Dired.  Create if missing."))
    (setcdr (assoc '(?F) org-attach-commands)
            '(org-attach-reveal
              "Like \"f\", but try to open in system file manager.\n"))))

;;; org-cliplink

(setup org-cliplink
  (:install t)
  (:command org-cliplink-retrieve-title-synchronously
            org-cliplink-org-mode-link-transformer)
  (:setopt org-cliplink-max-length nil
           org-cliplink-ellipsis "…")
  (with-eval-after-load 'org-keys
    (:keymap org-mode-map
      (:bind [remap org-insert-link] 'helheim-org-insert-link))))

;;; Agenda

(setup org-agenda
  ;; Depth 90 to run after anything that changes tags appearence.
  (add-hook 'org-agenda-finalize-hook #'helheim-org-agenda-align-tags-h 90)
  (:hook org-agenda-mode-hook
         (defun helheim-org-agenda-mode-h ()
           ;; Use "C-w r" to revert org agenda buffer.
           (setq-local revert-buffer-function (lambda (&rest _)
                                                (org-agenda-redo))))))

;;; .
(provide 'helheim-org)
;;; helheim-org.el ends here
