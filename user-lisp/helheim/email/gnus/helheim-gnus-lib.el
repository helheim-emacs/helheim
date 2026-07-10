;;; helheim-gnus-lib.el -*- lexical-binding: t -*-
;;; Commentary:
;;
;; Gmail -> lieer -> notmuch -> gnus (as frontend)
;;
;; Lieer stores all mail in one flat maildir, so there are no folders to map
;; onto Gnus groups.  Instead a single `nnmaildir' group holds every message,
;; and each group the user reads is an `nnselect' group whose contents are the
;; live result of a notmuch query.
;;
;;; Code:

(require 'dash)
(require 'gnus)
(require 'gnus-art)
(require 'gnus-group)
(require 'gnus-search)
(require 'gnus-sum)
(require 'nnheader)
(require 'nnselect)

(defvar helheim-gnus-notmuch-config)
(defvar helheim-gnus-server)
(defvar helheim-gnus-saved-searches)
(defvar helheim-gnus-archive-tags)
(defvar helheim-gnus-trash-tags)
(defvar helheim-gnus-spam-tags)
(defvar helheim-gnus-summary-hidden-tags)
(defvar helheim-gnus-tag-icons)
(defvar helheim-gnus-archived-mark)
(defvar helheim-gnus-trashed-mark)
(defvar helheim-gnus-spam-mark)

;;; Saved searches as nnselect groups

(defconst helheim-gnus--method '(nnselect "nnselect")
  "The select method backing every saved search.")

(defun helheim-gnus--make-group (name query level)
  "Create or refresh the nnselect group NAME running QUERY at LEVEL."
  (let* ((group (gnus-group-prefixed-name name helheim-gnus--method))
         (nnselect-specs
          `((nnselect-function . gnus-search-run-query)
            (nnselect-args . ((search-query-spec (query . ,query)
                                                 (raw . t))
                              ;; A (SERVER) element carrying no groups searches
                              ;; the whole server, which skips the group filter
                              ;; when parsing output.
                              (search-group-spec (,helheim-gnus-server)))))))
    (if (gnus-group-entry group)
        (gnus-group-set-parameter group 'nnselect-specs nnselect-specs)
      (gnus-group-make-group name helheim-gnus--method nil
                             `((nnselect-specs . ,nnselect-specs)
                               (nnselect-always-regenerate . t))))
    (gnus-group-change-level (gnus-group-entry group) level)))

;;;###autoload
(defun helheim-gnus-build-groups ()
  "Create the groups listed in `helheim-gnus-saved-searches'.
Idempotent: an existing group has its query refreshed instead of being
recreated. Meant for `gnus-started-hook'."
  (-each helheim-gnus-saved-searches
    (-lambda ((name query level))
      (helheim-gnus--make-group name query level)))
  ;; The raw maildir group servse as a source of every search. Assign it
  ;; level 6 which is the default `gnus-activate-level', so it stays out
  ;; of the way while remaining reachable.
  (when-let* ((group (gnus-group-full-name "mail" helheim-gnus-server))
              (entry (gnus-group-entry group)))
    (gnus-group-change-level entry 6))
  (gnus-group-sort-groups-by-level))

;;; Syncing

;;;###autoload
(defun helheim-gnus-sync ()
  "Fetch mail and refresh Gnus.

Runs `notmuch new', whose pre-new hook pulls from Gmail via lieer and
whose post-new hook pushes local tag changes back.

Gnus writes marks to the filesystem when the summary buffer commits
them, not on every keypress, so exit the summary buffer first."
  (interactive)
  (message "Syncing mail...")
  (let* ((buffer (get-buffer-create "*helheim-gnus-sync*"))
         (exit (call-process "notmuch" nil buffer nil
                             (concat "--config=" helheim-gnus-notmuch-config)
                             "new")))
    (unless (zerop exit)
      (display-buffer buffer)
      (user-error "`notmuch new' failed with status %d" exit)))
  (when (and (featurep 'gnus) (gnus-alive-p))
    (gnus-group-get-new-news))
  (message "Syncing mail...done"))

;;; Saving on exit

;;;###autoload
(defun helheim-gnus-save-newsrc-on-exit-h ()
  "Commit open summaries and save Gnus state. Meant for `kill-emacs-hook'."
  (when (and (featurep 'gnus) (gnus-alive-p))
    (->> (buffer-list)
         (-filter (lambda (buffer)
                    (with-current-buffer buffer
                      (derived-mode-p 'gnus-summary-mode))))
         (mapc (lambda (buffer)
                 (with-current-buffer buffer
                   (with-demoted-errors "helheim-gnus exit flush: %S"
                     (gnus-summary-update-info))))))
    (gnus-save-newsrc-file)))

;;; Reading articles

;;;###autoload
(defun helheim-gnus-summary-quit-dwim ()
  "DWIM quit for the summary buffer.
When an article window is visible, dismiss it and stay in the
summary. Otherwise exit the group and return to the group buffer."
  (interactive nil gnus-summary-mode)
  (if (and (gnus-buffer-live-p gnus-article-buffer)
           (get-buffer-window gnus-article-buffer))
      ;; FORCE: the summary window is already visible inside the article split,
      ;; so `gnus-configure-windows' would otherwise just select it and leave
      ;; the article window alone.
      (gnus-configure-windows 'summary t)
    (gnus-summary-exit)))

;;;###autoload
(defun helheim-gnus-open-article ()
  "Display the article at point and move focus to the article window."
  (interactive nil gnus-summary-mode)
  ;; `gnus-summary-select-article-buffer' skips redisplay whenever an article
  ;; window merely exists, so on its own it would focus a window still showing
  ;; the previously read article.
  (gnus-summary-select-article)
  (gnus-summary-select-article-buffer))

;;;###autoload
(defun helheim-gnus-article-quit ()
  "Close the article window and return to the summary buffer."
  (interactive nil gnus-article-mode)
  (unless (gnus-buffer-live-p gnus-summary-buffer)
    (user-error "There is no summary buffer for this article buffer"))
  (gnus-article-set-globals)
  ;; FORCE is needed: the summary window is already visible inside the article
  ;; split, and `gnus-configure-windows' would otherwise just select it.
  (gnus-configure-windows 'summary t)
  (gnus-summary-goto-subject gnus-current-article)
  (gnus-summary-position-point))

;;; Tagging
;;
;; Archive and delete through Notmuch tags.

(defun helheim-gnus--article-at-point ()
  "Return the article number on the current line in summary buffer, or nil.
Unlike `gnus-summary-article-number', this never falls back to the
last article in the buffer: off an article line (an empty summary, or
the trailing line below the last article) it returns nil."
  (get-text-property (line-beginning-position) 'gnus-number))

(defun helheim-gnus--message-id (&optional article)
  "Return the Message-ID of ARTICLE, without its angle brackets.
ARTICLE defaults to the article on the current summary line. Callers
pass it explicitly as nil, so resolve the default here with `or' rather
than via an argument default, which a supplied nil would bypass."
  (let ((article (or article (helheim-gnus--article-at-point))))
    (unless article
      (user-error "No article at point"))
    (if-let* ((header (gnus-summary-article-header article))
              (id (mail-header-id header)))
        (string-trim id "<" ">")
      (user-error "No Message-ID for article %s" article))))

(defun helheim-gnus--notmuch (&rest args)
  "Run notmuch with ARGS against `helheim-gnus-notmuch-config'."
  (with-temp-buffer
    (let ((exit (apply #'call-process "notmuch" nil t nil
                       (concat "--config=" helheim-gnus-notmuch-config)
                       args)))
      (unless (zerop exit)
        (user-error "Notmuch %s failed: %s"
                    (car args) (string-trim (buffer-string))))
      (buffer-string))))

(defun helheim-gnus--tag-message (id tag-changes)
  "Apply notmuch TAG-CHANGES to the message with Message-ID ID.
TAG-CHANGES is a list of \"+tag\" and \"-tag\" strings."
  (apply #'helheim-gnus--notmuch "tag"
         (-snoc tag-changes "--" (concat "id:" id))))

(defun helheim-gnus--tag (tags &optional article)
  "Apply notmuch TAGS to ARTICLE, defaulting to the current article.
TAGS is a list of \"+tag\" and \"-tag\" strings."
  (helheim-gnus--tag-message (helheim-gnus--message-id article) tags))

(defun helheim-gnus--tagged-p (tag &optional article)
  "Return non-nil when ARTICLE carries the notmuch TAG."
  (let* ((id (helheim-gnus--message-id article))
         (count (string-to-number
                 (helheim-gnus--notmuch "count" "--"
                                        (format "tag:%s and id:%s" tag id)))))
    (< 0 count)))

;;; Immediate tagging with in-place refresh and undo
;;
;; A tag change is committed to notmuch at once, but the summary is not
;; regenerated: the row stays, its tags cache and line are updated in place,
;; and the reverting change is pushed on an undo ring. `helheim-gnus-redisplay'
;; rebuilds from the database when you want the handled rows to actually leave.

(defvar-local helheim-gnus--undo-stack nil
  "Stack of recorded tag changes, newest first, for `helheim-gnus-undo'.
Each entry is one action's batch: a list of per-message records, each
\(ARTICLE MESSAGE-ID INVERSE OVERLAYS) — the summary article number, its
Message-ID, the notmuch tag changes that revert it, and the feedback
overlays to delete on undo. `helheim-gnus-undo' reverts a whole batch at
once, matching the granularity of the original archive/trash/spam action.")

(defvar-local helheim-gnus--row-overlays nil
  "List of transient row-highlight overlays, for bulk removal on redisplay.")

(defun helheim-gnus--mark-cell-position ()
  "Return the buffer position of the primary mark cell on the current line.
That is where the `%U' mark character sits, from `gnus-summary-mark-positions'.
Return nil when the position is unknown."
  (when-let* ((forward (cdr (assq 'unread gnus-summary-mark-positions))))
    (save-excursion
      (beginning-of-line)
      (when (looking-at-p "\r") (setq forward (1+ forward)))
      (+ (point) forward))))

(defun helheim-gnus--flag-row (face mark)
  "Lay transient overlays over the current summary row for feedback.
FACE highlights the whole line edge to edge; MARK is a character shown
display-only in the mark cell, replacing the visible mark without touching
the article's read/unread state or its cached `gnus-data-mark'. Both
overlays are recorded on `helheim-gnus--row-overlays' so redisplay can
clear them; the list of overlays is returned for the undo record."
  (let* ((line (make-overlay (line-beginning-position) (line-beginning-position 2)))
         (overlays (list line))
         (pos (helheim-gnus--mark-cell-position)))
    (overlay-put line 'face face)
    (overlay-put line 'evaporate t)
    (when pos
      (let ((cell (make-overlay pos (1+ pos))))
        (overlay-put cell 'display (char-to-string mark))
        (overlay-put cell 'evaporate t)
        (push cell overlays)))
    (setq helheim-gnus--row-overlays (append overlays helheim-gnus--row-overlays))
    overlays))

(defun helheim-gnus--apply-tag-changes (tags tag-changes)
  "Return the tag list TAGS with TAG-CHANGES (\"+tag\"/\"-tag\") applied."
  (let ((result (copy-sequence tags)))
    (dolist (change tag-changes result)
      (let ((tag (substring change 1)))
        (pcase (aref change 0)
          (?+ (unless (member tag result)
                (setq result (cons tag result))))
          (?- (setq result (delete tag result))))))))

(defun helheim-gnus--invert-tag-changes (tags tag-changes)
  "Return the changes reverting TAG-CHANGES, given the message has TAGS.
Only genuine changes are inverted: adding a tag already present, or
removing one already absent, contributes nothing, so undo cannot clobber
state the change never touched."
  (-keep (lambda (change)
           (let ((tag (substring change 1)))
             (pcase (aref change 0)
               (?+ (unless (member tag tags) (concat "-" tag)))
               (?- (when (member tag tags) (concat "+" tag))))))
         tag-changes))

(defun helheim-gnus--retag (tag-changes &optional article)
  "Commit notmuch TAG-CHANGES for ARTICLE now, updating the tag cache.
ARTICLE defaults to the article at point. The tag cache backing the tag
column is updated in place; the visible column itself re-renders on the
next `helheim-gnus-redisplay' (Gnus keeps summary line text immutable
after generation, refreshing only marks). Immediate feedback comes from
the summary mark set by the caller. Returns the Message-ID."
  (let* ((article (or article (helheim-gnus--article-at-point)))
         (id (helheim-gnus--message-id article)))
    (helheim-gnus--tag-message id tag-changes)
    (when helheim-gnus--tags-table
      (puthash id (helheim-gnus--apply-tag-changes
                   (gethash id helheim-gnus--tags-table) tag-changes)
               helheim-gnus--tags-table))
    id))

(defun helheim-gnus--retag-and-record (tag-changes face mark &optional count)
  "Apply notmuch TAG-CHANGES to every message in the work set and record undo.
The work set is COUNT messages from point when COUNT is non-nil, else the
process-marked messages, else the message at point (see
`gnus-summary-work-articles'). Each handled row gets, for immediate
feedback, a transient FACE over the whole line and the character MARK shown
display-only in the mark cell; it also loses its process mark. The
read/unread state is left untouched, so archiving or trashing never marks a
message read (matching Gmail). The whole work set is recorded as a single
batch on `helheim-gnus--undo-stack', so `helheim-gnus-undo' takes it back in
one step. Point lands on the row after the last handled message."
  (let ((articles (gnus-summary-work-articles count))
        batch)
    (dolist (article articles)
      (let* ((id (helheim-gnus--message-id article))
             (inverse (helheim-gnus--invert-tag-changes
                       (and helheim-gnus--tags-table
                            (gethash id helheim-gnus--tags-table))
                       tag-changes)))
        (helheim-gnus--retag tag-changes article)
        (gnus-summary-goto-subject article)
        (push (list article id inverse (helheim-gnus--flag-row face mark)) batch)
        (gnus-summary-remove-process-mark article)))
    (when articles
      (push (nreverse batch) helheim-gnus--undo-stack)
      (gnus-summary-next-subject 1))))

;;;###autoload
(defun helheim-gnus-archive (&optional count)
  "Archive the message, removing the messages from the inbox."
  (interactive "P" gnus-summary-mode)
  (helheim-gnus--retag-and-record helheim-gnus-archive-tags
                                  'helheim-gnus-archived-face
                                  helheim-gnus-archived-mark count))

;;;###autoload
(defun helheim-gnus-trash (&optional count)
  "Mark message for deletion."
  (interactive "P" gnus-summary-mode)
  (helheim-gnus--retag-and-record helheim-gnus-trash-tags
                                  'helheim-gnus-trashed-face
                                  helheim-gnus-trashed-mark count))

;;;###autoload
(defun helheim-gnus-spam (&optional count)
  "Mark message as spam.
Apply `helheim-gnus-spam-tags'. With a numeric prefix COUNT, act on that
many messages from point; otherwise act on the process-marked messages,
or the message at point."
  (interactive "P" gnus-summary-mode)
  (helheim-gnus--retag-and-record helheim-gnus-spam-tags
                                  'helheim-gnus-spam-face
                                  helheim-gnus-spam-mark count))

;;;###autoload
(defun helheim-gnus-archive-thread ()
  "Archive every message in the thread at point.
Process-marks the whole thread, then archives it as one undoable batch."
  (interactive nil gnus-summary-mode)
  (gnus-uu-mark-thread)
  (helheim-gnus-archive))

;;;###autoload
(defun helheim-gnus-trash-thread ()
  "Trash every message in the thread at point.
Process-marks the whole thread, then trashes it as one undoable batch."
  (interactive nil gnus-summary-mode)
  (gnus-uu-mark-thread)
  (helheim-gnus-trash))

;;;###autoload
(defun helheim-gnus-spam-thread ()
  "Mark every message in the thread at point as spam.
Process-marks the whole thread, then spams it as one undoable batch."
  (interactive nil gnus-summary-mode)
  (gnus-uu-mark-thread)
  (helheim-gnus-spam))

;;;###autoload
(defun helheim-gnus-toggle-process-mark (&optional count)
  "Toggle the process mark on COUNT articles from point.
Marks an unmarked article and unmarks a marked one, so a single key
covers both directions. `gnus-summary-mark-as-processable' and
`gnus-summary-unmark-as-processable' both advance point, so a numeric
prefix toggles a run."
  (interactive "p" gnus-summary-mode)
  (if-let* ((article (gnus-summary-article-number))
            ((memq article gnus-newsgroup-processable)))
      (gnus-summary-unmark-as-processable count)
    (gnus-summary-mark-as-processable count)))

;;;###autoload
(defun helheim-gnus-toggle-flagged ()
  "Toggle the notmuch \"flagged\" tag, that corresponds to the Gmail star.
Refreshes the star in the tag column at once. Not recorded on the undo
ring: a flag is trivially re-toggled."
  (interactive nil gnus-summary-mode)
  (if (helheim-gnus--tagged-p "flagged")
      (progn (helheim-gnus--retag '("-flagged"))
             (gnus-summary-clear-mark-forward 1))
    (helheim-gnus--retag '("+flagged"))
    (gnus-summary-tick-article-forward 1)))

;;;###autoload
(defun helheim-gnus-undo ()
  "Revert the last archive, trash or spam action, whole batch at once.
One action's entire work set is undone in a single step: the reverting
notmuch tags are applied and every row's feedback overlays are cleared.
Read/unread state was never touched, so nothing to restore there. Point
moves to the first reverted row. Last `helheim-gnus-redisplay' is the undo
border, which this command can't reach across."
  (interactive nil gnus-summary-mode)
  (unless helheim-gnus--undo-stack
    (user-error "Nothing to undo"))
  (let ((batch (pop helheim-gnus--undo-stack))
        first-article)
    (dolist (record batch)
      (pcase-let ((`(,article ,_ ,inverse ,overlays) record))
        (when inverse
          (helheim-gnus--retag inverse article))
        (dolist (overlay overlays)
          (when (overlayp overlay)
            (setq helheim-gnus--row-overlays (delq overlay helheim-gnus--row-overlays))
            (delete-overlay overlay)))
        (unless first-article (setq first-article article))))
    (when first-article
      (gnus-summary-goto-subject first-article))
    (message "Reverted %d message%s" (length batch)
             (if (= (length batch) 1) "" "s"))))

;;;###autoload
(defun helheim-gnus-redisplay ()
  "Rebuild the summary from the notmuch database. Clears the undo ring."
  (interactive nil gnus-summary-mode)
  (setq helheim-gnus--undo-stack nil)
  (mapc #'delete-overlay helheim-gnus--row-overlays)
  (setq helheim-gnus--row-overlays nil)
  (gnus-summary-rescan-group))

;;; Notmuch tags in the summary line
;;
;; The summary tag column is a function of the notmuch database, not of Gnus
;; marks: one `notmuch dump' per group build fills a Message-ID -> tags table,
;; which `%u&notmuch-tags;' (`gnus-user-format-function-notmuch-tags') reads
;; for each line.

(defun helheim-gnus--tag-icon (tag)
  "Return the display string for notmuch TAG.
Its ICON when the entry sets one, otherwise the tag's own name -- so an
entry may leave ICON nil to show the name while still giving it a FACE.
An explicit empty string renders nothing."
  (or (cadr (assoc tag helheim-gnus-tag-icons)) tag))

(defun helheim-gnus--tag-face (tag)
  "Return the face for notmuch TAG: its own, or `helheim-gnus-tag'.
The face is whatever the entry's third element holds -- a face name or
an inline spec (a plist of attributes), as accepted by `propertize'."
  (or (caddr (assoc tag helheim-gnus-tag-icons))
      'helheim-gnus-tag))

(defun helheim-gnus--tag-box (face)
  "Return a `:box' anonymous face matching FACE's background, or nil.
Drawn with a negative `:line-width', the box grows inward into the glyph
cell instead of outward -- so it adds no width -- and at half the default
font height its lines meet in the middle, filling the cell with the
background's own color.  Under normal display that fill is the background
color, so it is invisible; on the current line, where
`global-hl-line-mode' overlays its own background, the box survives -- an
overlay outranks our text-property `face' and replaces the background,
but leaves `:box' untouched -- so the chip stays filled in its own color
beneath the glyph.  Half the font height tracks the cell across font
sizes: much less leaves an outline over the overlay, much more spills the
fill into neighboring cells (a negative box is not clamped to the glyph).
FACE is what `helheim-gnus--tag-face' returns -- a face name or an inline
spec; a face with no background yields nil (nothing to keep)."
  (when-let* ((bg (if (symbolp face)
                      (face-attribute face :background nil t)
                    (plist-get face :background)))
              ((not (memq bg '(nil unspecified)))))
    (let ((n (- (/ (default-font-height) 2))))
      (list :box (list :line-width (cons n n) :color bg)))))

(defvar-local helheim-gnus--tags-table nil
  "Hash table mapping a bracket-less Message-ID to its list of notmuch tags.
Rebuilt per group by `helheim-gnus--build-tags-cache' and read by the
`%u&notmuch-tags;' summary line format function
`gnus-user-format-function-notmuch-tags'.")

(defun helheim-gnus--group-notmuch-query (&optional group)
  "Return the raw notmuch query backing the nnselect GROUP.
GROUP defaults to the current `gnus-newsgroup-name'. Return nil for a
group that is not one of our notmuch-backed nnselect groups."
  (when-let* ((group (or group gnus-newsgroup-name))
              (specs (gnus-group-find-parameter group 'nnselect-specs t)))
    (alist-get 'query
               (alist-get 'search-query-spec
                          (alist-get 'nnselect-args specs)))))

(defun helheim-gnus--decode-tag (string)
  "Decode a notmuch batch-tag hex-encoded STRING."
  (decode-coding-string (url-unhex-string string) 'utf-8))

(defun helheim-gnus--build-tags-cache ()
  "Rebuild `helheim-gnus--tags-table' for the current group.
One `notmuch dump' over the group's query yields every message's full
tag set in a single call."
  (setq helheim-gnus--tags-table (make-hash-table :test 'equal))
  (when-let* ((query (helheim-gnus--group-notmuch-query))
              (table helheim-gnus--tags-table))
    (with-temp-buffer
      (when (zerop (call-process
                    "notmuch" nil t nil
                    (concat "--config=" helheim-gnus-notmuch-config)
                    "dump" "--include=tags" "--format=batch-tag" "--" query))
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))))
            ;; Each line is "+tag +tag -- id:MESSAGE-ID"; skip the leading
            ;; "#notmuch-dump ..." header comment.
            (when (and (not (string-prefix-p "#" line))
                       (string-match "\\`\\(.*\\) -- id:\\(.*\\)\\'" line))
              ;; Capture both groups before any regex-using call (split-string,
              ;; url-unhex-string, decode) clobbers the match data.
              (let ((tags-string (match-string 1 line))
                    (id (helheim-gnus--decode-tag (match-string 2 line))))
                (puthash id
                         (->> (split-string tags-string " " t)
                              (-map (lambda (token)
                                      (helheim-gnus--decode-tag
                                       (string-remove-prefix "+" token)))))
                         table))))
          (forward-line 1))))))

(defun helheim-gnus--article-tags (header)
  "Return the notmuch tags of the article described by HEADER, or nil."
  (when (and helheim-gnus--tags-table header)
    (when-let* ((id (mail-header-id header)))
      (gethash (string-trim id "<" ">") helheim-gnus--tags-table))))

(defun gnus-user-format-function-notmuch-tags (header)
  "Render the notmuch tags of the article HEADER for `%u&notmuch-tags;'.
Each tag (minus `helheim-gnus-summary-hidden-tags') is shown via
`helheim-gnus-tag-icons' in a dim face, `flagged' getting a standout
one. Builds the tag cache lazily if a redisplay has not populated it."
  (unless helheim-gnus--tags-table
    (helheim-gnus--build-tags-cache))
  (let ((shown (-difference (helheim-gnus--article-tags header)
                            helheim-gnus-summary-hidden-tags)))
    (mapconcat
     (lambda (tag)
       ;; Protect our face from `gnus-summary-highlight-line', which
       ;; otherwise overwrites the whole line's `face'.  It only skips
       ;; characters carrying a `gnus-face' property, and expects `face'
       ;; to be a freshly-consed list whose second element it replaces
       ;; in place with the line-highlight face (see
       ;; `gnus-face-face-function' in gnus-spec.el) -- so we keep
       ;; `default' in that slot.  A `:box' element goes last, where it
       ;; survives both that replacement and the `hl-line' overlay (see
       ;; `helheim-gnus--tag-box').
       (let* ((face (helheim-gnus--tag-face tag))
              (box  (helheim-gnus--tag-box face)))
         (propertize (helheim-gnus--tag-icon tag)
                     'face (if box
                               (list face 'default box)
                             (list face 'default))
                     'gnus-face t)))
     shown " ")))

;;; .
(provide 'helheim-gnus-lib)
;;; helheim-gnus-lib.el ends here
