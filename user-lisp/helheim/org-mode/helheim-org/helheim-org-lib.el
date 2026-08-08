;;; helheim-org-lib.el                                -*- lexical-binding: t -*-

(eval-when-compile (require 'cl-macs))
(require 'dash)
(require 'org)
(require 'hel)

;;; org-attach

(defun helheim-org-attach-id-ts-folder-format (id)
  "Translate an ID based on a ISO8601 timestamp to a folder-path.
Place the attachment folder into year folder: 2025/20251104T161807"
  (if (< 4 (length id))
      (format "%s/%s"
              (substring id 0 4)
              id)))

(defvar org-attach-commands)
(declare-function org-attach-dir "org-attach" (&optional create-if-not-exists-p no-fs-check))

(defun helheim-org-attach ()
  "The dispatcher for attachment commands.
Like `org-attach' but tuned for Emacs Helheim."
  (interactive)
  (let (marker)
    (when (eq major-mode 'org-agenda-mode)
      (setq marker (or (get-text-property (point) 'org-hd-marker)
                       (get-text-property (point) 'org-marker)))
      (unless marker
        (error "No item in current line")))
    (org-with-point-at marker
      (let ((dir (org-attach-dir nil :no-fs-check)))
        (cl-assert dir nil "Cannot derive attachment directory from ID")
        (deactivate-mark)
        (if (not (featurep 'org-inlinetask))
            (org-back-to-heading-or-point-min t)
          ;; else
          (if (org-inlinetask-in-task-p)
              (org-inlinetask-goto-beginning)
            ;; else
            (org-with-limited-levels
             (org-back-to-heading-or-point-min t))))
        (let (key)
          (save-excursion
            (save-window-excursion
              (unless org-attach-expert
                (helheimg--org-attach-buffer dir)
                (org-fit-window-to-buffer (get-buffer-window "*Org Attach*")))
              (unwind-protect
                  (progn
                    (message "Select command: [%s]"
                             (concat (mapcar #'caar org-attach-commands)))
                    (while (and (setq key (read-char-exclusive))
                                (memq key '(?\C-f ?\C-b)))
	              (org-scroll (alist-get key '((?\C-f . ?\C-n)
                                                   (?\C-b . ?\C-p))))))
                (-some->> (get-buffer-window "*Org Attach*" t)
                  (quit-window :kill))
	        (-some-> (get-buffer "*Org Attach*")
                  (kill-buffer)))))
          (if-let* ((command (-some (lambda (entry)
				      (and (memq key (nth 0 entry))
                                           (nth 1 entry)))
			            org-attach-commands))
                    ((commandp command)))
	      (command-execute command)
	    (error "No such attachment command: %c" key)))))))

(defun helheimg--org-attach-buffer (dir)
  (switch-to-buffer-other-window "*Org Attach*")
  (erase-buffer)
  (setq cursor-type nil)
  (setq header-line-format (format "Use %s and %s for scrolling"
                                   (propertize "C-f" 'face 'help-key-binding)
                                   (propertize "C-b" 'face 'help-key-binding)))
  (insert
   (concat "Attachment folder:\n\n"
           (propertize (abbreviate-file-name dir)
                       'face 'font-lock-string-face)
           "\n\n  "
           (if (file-directory-p dir)
               (propertize "Exist" 'face 'success)
             (propertize "Does not exist" 'face 'warning))
           "\n\n"
           "Select an Attachment Command:\n\n"
           (mapconcat (lambda (entry)
	                (pcase entry
		          (`((,key . ,_) ,_ ,docstring)
		           (format "%s       %s"
                                   (-> (char-to-string key)
                                       (propertize 'face 'help-key-binding))
                                   (replace-regexp-in-string "\n\\([\t ]*\\)"
                                                             "        "
                                                             docstring nil nil 1)))
		          (_
		           (user-error "Invalid `org-attach-commands' item: %S"
			               entry))))
	              org-attach-commands
	              "\n")))
  (goto-char (point-min)))

;;; org-cliplink

(declare-function org-cliplink "org-cliplink")
(declare-function org-cliplink-retrieve-title-synchronously "org-cliplink")
(declare-function org-cliplink-org-mode-link-transformer "org-cliplink")

;; Based on https://xenodium.com/emacs-dwim-do-what-i-mean/
(hel-define-command helheim-org-insert-link ()
  "Like `org-insert-link' but with some \"do what i mean\" behavior.
- If URL is in clipboard — use it.
- If selection is active — use it as link description.
- Automatically fetch URL title from its HTML tag.
- Fallback to `org-insert-link'."
  :multiple-cursors t
  (interactive)
  (let ((deactivate-mark nil)
        (point-at-link? (org-in-regexp org-link-any-re 1))
        (clipboard-url (if-let* ((kill-ring)
                                 (kill (current-kill 0))
                                 ((string-match-p "^http" kill)))
                           kill))
        (region-content (if (use-region-p)
                            (buffer-substring-no-properties (region-beginning)
                                                            (region-end)))))
    (cond ((and region-content clipboard-url (not point-at-link?))
           (delete-region (region-beginning) (region-end))
           (insert (org-make-link-string clipboard-url region-content)))
          ((and clipboard-url (not point-at-link?))
           (set-mark (point))
           (if hel-multiple-cursors-mode
               ;; With multiple cursors fetch each title synchronously.
               (insert (org-cliplink-org-mode-link-transformer
                        clipboard-url
                        (org-cliplink-retrieve-title-synchronously clipboard-url)))
             ;; else
             (org-cliplink)))
          (t
           (call-interactively 'org-insert-link))))
  (hel-extend-selection -1))

;;; Agenda tag alignment

(defvar org-agenda-tags-column)

;;;###autoload
(defun helheim-org-agenda-align-tags-h ()
  "Align the tag by pixel, not by column.
`org-agenda-align-tags' pads the tag with space characters and counts them in
columns, which assumes every glyph on the line is `default-font-width' wide.
This function meant to be run in `org-agenda-finalize-hook' after everything
that changes how the tags are drawn (like `org-pretty-tags') and align them
pixel perfect."
  (let ((inhibit-read-only t))
    (save-excursion
      (save-match-data
        (goto-char (point-min))
        (while (re-search-forward org-tag-group-re nil t)
          (let* ((beg (match-beginning 1))
                 (end (match-end 1))
                 (width (string-pixel-width (buffer-substring beg end)))
                 (align (cond ((eq org-agenda-tags-column 'auto)
                               `(- right (,width)))
                              ((< org-agenda-tags-column 0)
                               `(- ,(abs org-agenda-tags-column) (,width)))
                              (t org-agenda-tags-column)))
                 (props (-doto (copy-sequence (text-properties-at beg))
                          (plist-put 'face nil)
                          (plist-put 'display nil)
                          (plist-put 'cursor-sensor-functions nil))))
            (goto-char beg)
            (delete-region (save-excursion (skip-chars-backward " \t") (point))
                           beg)
            (insert (apply #'propertize " " props)
                    (apply #'propertize " "
                           (-doto (copy-sequence props)
                             (plist-put 'display `(space :align-to ,align)))))
            (goto-char (line-end-position))))))))

;;; Convert markdown to org-mode

;;;###autoload
(defun +markdown-to-org-region (start end)
  "Convert region (START, END) from Markdown to Org-mode using pandoc."
  (interactive "r")
  (unless (executable-find "pandoc")
    (user-error "No pandoc executable found"))
  (shell-command-on-region start end
                           "pandoc --from=markdown --to=org"
                           ;; "pandoc --from=markdown --to=org --wrap=preserve"
                           t t))

;;;###autoload
(defun +org-to-markdown-region (start end)
  "Convert region (START, END) from Org-mode to Markdown using pandoc."
  (interactive "r")
  (unless (executable-find "pandoc")
    (user-error "No pandoc executable found"))
  (shell-command-on-region start end
                           "pandoc --from=org --to=markdown"
                           t t))

;;; .
(provide 'helheim-org '(lib))
;;; helheim-org-lib.el ends here
