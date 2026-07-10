;;; helheim-gnus.el -*- lexical-binding: t; no-byte-compile: t -*-
;;; Commentary:
;;
;; Gnus as the mail client, with notmuch as indexer and search engine.
;;
;; Mail is a lieer (`gmi') mirror of Gmail: one flat maildir, no folders,
;; Gmail labels represented as notmuch tags.  So a single `nnmaildir' group
;; holds every message, and the groups actually read are `nnselect' groups
;; whose contents are live notmuch queries.  See `helheim-gnus-lib.el'.
;;
;; Marks are not local to Gnus. `nnmaildir' maps them onto maildir flags,
;; which notmuch turns into tags, which lieer pushes to Gmail:
;;
;;     read  <-> S <-> "unread" tag  <-> Gmail read state
;;     tick  <-> F <-> "flagged" tag <-> Gmail star
;;     reply <-> R <-> "replied" tag
;;
;; So a Gnus command that clears an article's tick (rather than adding the read
;; mark alongside it) unstars that message in Gmail. That is the intended
;; meaning of the coupling, but it surprises: the mark is not a local note.
;;
;;; Code:
;;; Customization

(defgroup helheim-gnus nil
  "Gnus with notmuch as indexer and search engine."
  :group 'gnus)

(defcustom helheim-gnus-account-directory "~/.mail/account.gmail"
  "Directory holding the lieer-managed maildir.
Its subdirectories are the `nnmaildir' groups. A lieer repository
contains exactly one, named \"mail\"."
  :type 'directory
  :group 'helheim-gnus)

(defcustom helheim-gnus-notmuch-config
  (or (getenv "NOTMUCH_CONFIG")
      (if-let* ((xdg (expand-file-name
                      (format "notmuch/%s/config" (or (getenv "NOTMUCH_PROFILE")
                                                      "default"))
                      (getenv "XDG_CONFIG_HOME")))
                ((file-exists-p xdg)))
          xdg)
      (expand-file-name "~/.notmuch-config"))
  "Path to the notmuch configuration file.
Resolved the way notmuch itself resolves it. Gnus passes this to every
`notmuch search' invocation as --config, and notmuch aborts with
\"cannot load config file\" when it does not exist, so a wrong value
makes every search silently return no articles."
  :type 'file
  :group 'helheim-gnus)

(defcustom helheim-gnus-server "nnmaildir:gmail"
  "The Gnus server searched by the notmuch engine."
  :type 'string
  :group 'helheim-gnus)

(defcustom helheim-gnus-saved-searches
  '(("Inbox"       "tag:inbox and not tag:sent and not tag:spam" 1)
    ("Unread"      "tag:inbox and tag:unread"                    2)
    ("Flagged"     "tag:flagged"                                 2)
    ("Important"   "tag:important"                               2)
    ("Sent"        "tag:sent"                                    3)
    ("Attachments" "tag:attachment"                              3)
    ("Archive"     "not tag:inbox and not tag:trash"             4)
    ("Trash"       "tag:trash"                                   5)
    ("Spam"        "tag:spam"                                    5))
  "Notmuch queries exposed as Gnus groups.

Each entry is (NAME QUERY LEVEL).

QUERY is raw notmuch syntax, handed to notmuch as a single argument
without passing through a shell, so tags containing spaces need only
notmuch's own quoting, as in tag:\"Some Label\".

LEVEL is the Gnus subscription level. Groups above `gnus-activate-level'
are not checked for new messages."
  :type '(repeat (list (string :tag "Group name")
                       (string :tag "Notmuch query")
                       (integer :tag "Level")))
  :group 'helheim-gnus)

(defcustom helheim-gnus-archive-tags '("-inbox")
  "Notmuch tags applied to archive a message."
  :type '(repeat string)
  :group 'helheim-gnus)

(defcustom helheim-gnus-trash-tags '("+trash" "-inbox")
  "Notmuch tags applied to mark a message for deletion.
Must match lieer's `local_trash_tag'. Deleting the file instead would
only make lieer download the message again on the next pull."
  :type '(repeat string)
  :group 'helheim-gnus)

(defcustom helheim-gnus-spam-tags '("+spam" "-inbox")
  "Notmuch tags applied to mark a message as spam."
  :type '(repeat string)
  :group 'helheim-gnus)

(defcustom helheim-gnus-archived-mark ?A
  "Character shown display-only in the mark cell of a just-archived row.
Feedback only: it does not touch the article's read/unread state."
  :type 'character
  :group 'helheim-gnus)

(defcustom helheim-gnus-trashed-mark ?D
  "Character shown display-only in the mark cell of a row marked for deletion.
Feedback only: it does not touch the article's read/unread state."
  :type 'character
  :group 'helheim-gnus)

(defcustom helheim-gnus-spam-mark ?S
  "Character shown display-only in the mark cell of a row marked as spam.
Feedback only: it does not touch the article's read/unread state."
  :type 'character
  :group 'helheim-gnus)

(defcustom helheim-gnus-summary-hidden-tags '("inbox" "unread")
  "Notmuch tags never shown in the summary buffer tag column."
  :type '(repeat string)
  :group 'helheim-gnus)

(defcustom helheim-gnus-tag-icons
  '(("flagged"     "" diff-removed)
    ("yellow_star" "" diff-changed)
    ("green_star"  "" diff-added)
    ("important"   "󱈸")
    ("attachment"  "󰏢")
    ("replied"     "")
    ("sent"        "")
    ("draft"       "")
    ("spam"        "")
    ("trash"       ""))
  "Alist mapping a notmuch tag to how it appears in the summary tag column.
Each entry is (TAG ICON [FACE]).

ICON is the glyph shown for the tag. Nil means use tag's own name
instead. While an empty string renders nothing.

The optional FACE styles it, defaulting to `helheim-gnus-tag'. FACE is
any valid value of the `face' special text property, see Info node
`(elisp) Special Properties'."
  :type '(alist :key-type (string :tag "Tag")
                :value-type
                (cons :tag "Display"
                      (choice :tag "Icon"
                              (string :tag "Glyph")
                              (const :tag "Tag's own name" nil))
                      (choice :tag "Face"
                              (const :tag "Default (helheim-gnus-tag)" nil)
                              (list (choice (face :tag "Face name")
                                            (sexp :tag "Face attributes"))))))
  :group 'helheim-gnus)

(defface helheim-gnus-tag
  '((t :inherit diff-changed))
  "Face for notmuch tags shown in the summary tag column."
  :group 'helheim-gnus)

(defface helheim-gnus-archived-face
  '((((background light)) :background "#e8f0e0" :extend t)
    (((background dark))  :background "#28331f" :extend t))
  "Face laid over a summary row just archived, until the next redisplay."
  :group 'helheim-gnus)

(defface helheim-gnus-trashed-face
  '((t :strike-through t :inherit shadow :extend t))
  "Face laid over a summary row marked for deletion, until redisplay."
  :group 'helheim-gnus)

(defface helheim-gnus-spam-face
  '((((background light)) :background "#f6e0d2" :extend t)
    (((background dark))  :background "#3a271b" :extend t))
  "Face laid over a summary row marked as spam, until the next redisplay."
  :group 'helheim-gnus)

;;; Gnus

(setup gnus
  ;; Must be setup before Gnus is loaded.
  (:setopt gnus-home-directory (expand-file-name "gnus/" user-emacs-directory)
           gnus-directory (expand-file-name "gnus/News/" user-emacs-directory)
           message-directory (expand-file-name "gnus/mail/" user-emacs-directory)
           ;; Only use the Lisp ".newsrc.eld". Never read or write the plain
           ;; ".newsrc" meant only for sharing state with other newsreaders.
           gnus-read-newsrc-file nil
           gnus-save-newsrc-file nil
           ;; No dribble (crash-recovery journal). The real state lives in
           ;; the maildir/notmuch/Gmail, and ".newsrc.eld" is still saved on
           ;; a clean exit.
           gnus-use-dribble-file nil
           gnus-agent nil
           gnus-gcc-mark-as-read t
           gnus-interactive-exit nil
           gnus-large-newsgroup nil
           gnus-search-use-parsed-queries nil ;; standardize searches
           gnus-goto-next-group-when-activating nil
           gnus-summary-next-group-on-exit nil
           gnus-summary-stop-at-end-of-message t
           gnus-mime-display-multipart-related-as-mixed t
           gnus-auto-select-first nil
           gnus-auto-select-next nil
           gnus-paging-select-next nil
           gnus-summary-display-arrow t
           ;; Show all articles (read and unread) when entering any group.
           gnus-parameters '((".*" (display . all)))
           ;; ;; The "Sent" folder
           ;; gnus-message-archive-group "nnimap+ec25gnus:INBOX"
           )
  ;;
  ;; Group buffer
  ;; (:setopt gnus-group-line-format "%M%S%p%P%5y:%B%(%g%)\n")
  ;; ;; Highlighting groups in the group buffer.
  ;; (:setopt gnus-group-highlight ...)
  (:setopt gnus-group-goto-unread t)
  ;;
  ;; Summary buffer
  (:setopt gnus-show-threads t
           gnus-unseen-mark    ?\s ; space
           gnus-unread-mark    ?●  ;
           gnus-read-mark      ?◌  ; ◌ ○
           gnus-ancient-mark   ?·  ; •
           gnus-ticked-mark    ?!
           ;; Despite the name this is not about deletion, this means "mark as
           ;; read and dismiss"
           gnus-del-mark       ?A
           gnus-dormant-mark   ??
           gnus-expirable-mark ?D
           ;;
           gnus-sum-thread-tree-indent          " "
           gnus-sum-thread-tree-single-indent   "" ;; ◎ • ◦ ‣
           gnus-sum-thread-tree-false-root      "─► "
           gnus-sum-thread-tree-root            "● " ;; ┭
           gnus-sum-thread-tree-vertical        "│"
           gnus-sum-thread-tree-leaf-with-other "├► " ;; ├─‣
           gnus-sum-thread-tree-single-leaf     "╰► " ;; ╰─‣
           ;; |2025-03-06 (Thu)| Sender Name | Email Subject |
           gnus-summary-line-format (concat
                                     "%0{%U%R%z%}"
                                     "%3{│%}%1{%&user-date;%}%3{│%}" ;; date
                                     ;; "%ub:" ;; indicate (+) if known (bbdb)
                                     "%4{%-20,20f%}" ;; name
                                     " "
                                     "%3{│%}"
                                     " "
                                     "%1{%B%}"
                                     "%s"
                                     " %u&notmuch-tags;\n") ;; see -lib.el
           gnus-user-date-format-alist '((t . "%Y-%m-%d (%a)"))
           ;; gnus-thread-sort-functions '(gnus-thread-sort-by-date)
           gnus-thread-sort-functions '(gnus-thread-sort-by-most-recent-date
                                        (not gnus-thread-sort-by-number)
                                        ;; gnus-thread-sort-by-score
                                        ;; gnus-thread-sort-by-total-score
                                        )
           )
  (require 'helheim-gnus-lib)
  (:setopt gnus-select-method '(nnnil "") ; no NNTP server
           ;; The one real group, plus the notmuch search engine that indexes it.
           ;; `remove-prefix' is stripped from every file path notmuch returns,
           ;; what remains ("mail/cur/") becomes the group name. Get it wrong
           ;; and every article is silently dropped.
           gnus-secondary-select-methods
           `((nnmaildir
              "gmail"
              (directory ,helheim-gnus-account-directory)
              ;; lieer delivers the mail; Gnus must not try to.
              (get-new-mail nil)
              (gnus-search-engine
               gnus-search-notmuch
               (remove-prefix ,(file-name-as-directory
                                (expand-file-name helheim-gnus-account-directory)))
               (config-file ,helheim-gnus-notmuch-config)
               ;; Pass queries to notmuch verbatim instead of parsing them
               ;; into Gnus' own query language first.
               (raw-queries-p t)))))
  (:setopt gnus-search-notmuch-config-file helheim-gnus-notmuch-config
           ;; Search all groups on the server to reconstructs the whole thread across
           ;; every group using the server's search capability (notmuch in our case)
           ;; when run `gnus-summary-refer-thread'.
           gnus-refer-thread-use-search t)
  (with-eval-after-load 'gnus-search
    (add-to-list 'gnus-search-default-engines '(nnmaildir . notmuch)))
  ;; Build the notmuch-backed groups once Gnus is up.
  (:hook gnus-started-hook helheim-gnus-build-groups)
  (:hook kill-emacs-hook helheim-gnus-save-newsrc-on-exit-h)
  ;; Fill the Message-ID -> notmuch tags cache before each summary is drawn,
  ;; so the `%u&notmuch-tags;' tag column is populated on first render.
  (:hook gnus-summary-generate-hook helheim-gnus--build-tags-cache)
  ;;
  ;; Send email settings.  msmtp reads the 'From' header to pick the account.
  (:setopt mail-user-agent 'gnus-user-agent
           message-kill-buffer-on-exit t
           message-send-mail-function 'message-send-mail-with-sendmail
           send-mail-function 'sendmail-send-it
           sendmail-program (executable-find "msmtp")
           message-sendmail-f-is-evil nil
           mail-specify-envelope-from t
           mail-envelope-from 'header
           message-sendmail-envelope-from 'header
           ;; Gmail files sent mail itself and lieer syncs it back, so do not
           ;; Gcc a copy into a local "sent.YYYY-MM" group.
           gnus-message-archive-group nil))

;; BUG: `gnus-dribble-delete-file' guards `gnus-dribble-buffer' with
;;   a bare non-nil check, unlike its siblings `gnus-dribble-save' and
;;   `gnus-dribble-clear', which test `buffer-live-p'.
;;   With `gnus-use-dribble-file' nil the variable is never reset after
;;   `gnus-clear-system' kills the buffer, so it lingers as a dead buffer
;;   across a Gnus restart. Exiting then reaches `with-current-buffer'
;;   on that killed buffer and signals "Selecting deleted buffer", so
;;   `q' (gnus-group-exit) errors out and never quits.
(define-advice gnus-dribble-delete-file ( :before (&rest _)
                                          helheim-gnus-drop-dead-dribble-buffer)
  (unless (buffer-live-p gnus-dribble-buffer)
    (setq gnus-dribble-buffer nil)))

;; Gnus forwards read/unread marks to a backend only when the group's method has
;; `server-marks' ability, and by default "nnselect" does not. Without this,
;; a message read in a search group never gets its maildir "S" flag, so notmuch
;; keeps the "unread" tag and Gmail still shows it as unread.
(setup nnselect
  (:after-load
    ;; See `gnus-declare-backend'
    (-when-let* (((_ . abilities) (assoc "nnselect" gnus-valid-select-methods))
                ((not (memq 'server-marks abilities))))
      (setq abilities (-snoc abilities 'server-marks)))
    (gnus-redefine-select-method-widget)))

(setup mm-decode
  (:setopt mm-html-inhibit-images nil
           mm-inline-text-html-with-w3m-keymap t
           gnus-inhibit-images nil)
  (:after-load
    (when (executable-find "w3m")
      (:setopt mm-text-html-renderer 'gnus-w3m))
    ;; Clean up file names, removing spaces, so that the operating system
    ;; does not get confused.
    (add-to-list 'mm-file-name-rewrite-functions #'mm-file-name-replace-whitespace)))

;;; Keybindings

;; The bindings below adopt the vim-flavoured layout from evil-collection's
;; `evil-collection-gnus.el'. Evil-motion and `g'-prefix keys
;; (gj/gk/]]/[[/J/gx/g?/gr, gu/gc/ge/gl, ...) are deliberately left out: Hel
;; owns motion and the `g' prefix. As a result a few commands whose evil home
;; was a `g'-prefix key are no longer bound (group: catchup on `c'/`gc',
;; un/subscribe on `gu'/`gU', expire on `ge'/`gE', set-level on `gl'); reach
;; them via `M-x' or add your own keys.

(setup gnus
  (:global-bind "C-c o g" 'gnus))

;;;; Group buffer

(setup gnus-group
  (:after-load
    (:keymap gnus-group-mode-map
      (:unbind
        "M-u"                           ; Make `universal-argument' available
        "#" "M-#" "." "," "j" "o" "L" "T" "c" "d" "z"
        ;; Compose a news article, injecting it straight into the local
        ;; backend without SMTP. On the lieer-managed maildir that writes
        ;; an orphan file Gmail never sees; there is no NNTP server either.
        ;; Compose via `c'/`C' instead.
        "i"        ; `gnus-group-news'
        "a"        ; `gnus-group-post-news'
        ;; File-destroying group operations: remove forever, no undo.
        "G DEL" "G <delete>"            ; `gnus-group-delete-group'
        ;; Delete maildir files that lieer re-downloads. Deletion should goes
        ;; through the `+trash' tag (`helheim-gnus-trash') instead.
        "G x"                           ; `gnus-group-expunge-group'
        "C-c C-x"                       ; `gnus-group-expire-articles'
        "C-c C-M-x"                     ; `gnus-group-expire-all-groups'
        ;; Our config lives in this module, not in `gnus-init-file' (~/.gnus).
        "r"   ;`gnus-group-read-init-file'
        ;; Our group list is code-managed via `helheim-gnus-build-groups'.
        "b"                             ; `gnus-group-check-bogus-groups'
        ;; There is no foreign server: `gnus-select-method' is `nnnil' with one
        ;; `nnmaildir' secondary.
        "B"                             ; `gnus-group-browse-foreign-server'
        "D")                            ; `gnus-summary-mark-as-read-backward'
      (:bind
        "RET"   'gnus-group-select-group
        "M-RET" 'gnus-group-quick-select-group
        ;; Motion (Hel-native, kept from before).
        "C-j"  'gnus-group-next-group
        "C-k"  'gnus-group-prev-group
        "J"    'gnus-group-next-unread-group
        "K"    'gnus-group-prev-unread-group
        "/"    'gnus-group-jump-to-group
        ">"    'gnus-group-best-unread-group
        "<"    'gnus-group-first-unread-group
        ;; Composing, after evil-collection mu4e
        "c"    'gnus-group-mail         ; `gnus-group-catchup-current'
        "C"    'gnus-group-mail         ; `gnus-group-catchup-current-all'
        ", c"  '("compose mail" . gnus-group-mail)
        ;; Actions
        ", a"  'gnus-activate-all-groups
        "A"    'gnus-activate-all-groups ; shadows the `A' list prefix (see L)
        ;; Deleting & pasting
        "d"    'gnus-group-kill-group
        "p"    'gnus-group-yank-group
        ;; Marking (shadows `m' = mail, `u'/`U' = un/subscribe)
        "m"    'gnus-group-mark-group ;; `gnus-group-mail' moved to "c"
        "u"    'gnus-group-unmark-group
        "M"    'gnus-group-mark-buffer
        "U"    'gnus-group-unmark-all-groups
        "%"    'gnus-group-universal-argument
        ;; Searching (shadows `s' = save-newsrc)
        "s"    '("search" . gnus-group-read-ephemeral-search-group)
        ;; Sorting
        "o"    'gnus-group-sort-map
        ", o"  '("sort" . gnus-group-sort-map)
        ;; Listing
        "l"    'gnus-group-list-groups
        "L"    'gnus-group-list-all-groups
        ;; "L l"  'gnus-group-list-level
        ;; "L s"  'gnus-group-list-groups
        ;; "L a"  'gnus-group-list-all-groups
        ;; Topics
        "t"    'gnus-topic-mode
        ;; "G" prefix
        ", g" (cons "group"
                    (:keymap gnus-group-group-map
                      (:unbind
                        "d"        ; `gnus-group-make-directory-group'
                        "V"        ; `gnus-group-make-empty-virtual'
                        "w"        ; `gnus-group-make-web-group'
                        "z"))))))) ; `gnus-group-compact-group'

;;;;; Topic mode

;; Lay down in a layer on top of `gnus-group-mode-map' when `gnus-topic-mode'
;; is active so should track the original group layout it overrides.
(setup gnus-topic
  (:after-load
    (:keymap gnus-topic-mode-map
      (:unbind
        "#" "M-#" ; mark / unmark
        "C-k"     ; `gnus-topic-kill-group'      -> moved to `d'
        "C-y"     ; `gnus-topic-yank-group'      -> moved to `p'
        "c"       ; `gnus-topic-catchup-articles' (our `c' composes mail)
        "C-c C-x" ; `gnus-topic-expire-articles'  (no expiry)
        "A T")    ; `gnus-topic-list-active'      -> moved to `T A' (frees `A')
      (:bind
        "C-j"   'gnus-topic-goto-next-topic
        "C-k"   'gnus-topic-goto-previous-topic
        "z c"   'gnus-topic-hide-topic
        "z o"   'gnus-topic-show-topic
        "d"     'gnus-topic-kill-group ; was `C-k'
        "p"     'gnus-topic-yank-group ; was `C-y'
        ", g p" 'gnus-topic-edit-parameters
        ", t"    (cons "topic"
                       (:keymap gnus-group-topic-map
                         (:unbind "#" "M-#" "C" "M-n" "M-p" "h" "s")
                         (:bind
                           "m"     'gnus-topic-mark-topic
                           "u"     'gnus-topic-unmark-topic
                           "n"     'gnus-topic-create-topic
                           "M"     'gnus-topic-move-group
                           "d"     'gnus-topic-delete
                           "D"     'gnus-topic-remove-group
                           "c"     'gnus-topic-copy-group
                           "/"     'gnus-topic-jump-to-topic
                           "TAB"   'gnus-topic-indent
                           "<tab>" 'gnus-topic-indent
                           "r"     'gnus-topic-rename
                           "A"     'gnus-topic-list-active ; was top-level "A T"
                           "o"     '("sort" . gnus-topic-sort-map))))))))

;;;; Summary buffer

(setup gnus-sum
  (:after-load
    ;; Flagged messages stand out via the `★' glyph in the tag column. We drive
    ;; it from the notmuch `flagged' tag, not the Gnus tick mark: a message
    ;; flagged elsewhere often is not ticked here, so tick is not a reliable
    ;; proxy for the tag.
    (:keymap gnus-summary-mode-map
      (:unbind
        "M-u"   ; `gnus-summary-clear-mark-forward' -> moves to "-"
        ","     ; `gnus-summary-best-unread-article'
        "j"     ; `gnus-summary-goto-article' -> moved to "g/"
        "k"     ; `gnus-summary-kill-same-subject-and-select' -> moved to
        "x"     ; `gnus-summary-limit-to-unread', also on "/u"
        ;; Converted to prefixes
        "o"     ; `gnus-summary-save-article'
        "c"     ; `gnus-summary-catchup-and-exit'
        "g"     ; `gnus-summary-show-article' -> moved to "gr"
        ;; No expiry and no file-touching.
        ;;
        ;; Expiry is the Gnus analoug of Gmail trash: you mark file for expiry
        ;; and Gnus delete it in 7 days.
        ;;
        ;; `B' (backend) prefix -- delete/move/copy/import/respool/edit-article/
        ;; crosspost -- rewrite or delete the maildir file, which lieer simply
        ;; re-downloads on the next sync. Deletion should goes through the
        ;; `+trash' tag (`helheim-gnus-trash') instead.
        "E"     ; `gnus-summary-mark-as-expirable'
        "T E"   ; `gnus-summary-expire-thread'
        "B"     ; backend prefix: delete/move/copy/import/respool/edit/crosspost
        "e"     ; `gnus-summary-edit-article' (rewrites the maildir file)
        "K d")  ; delete-part (rewrites the article)
      ;;
      (:bind
        "q"     'helheim-gnus-summary-quit-dwim
        "RET"   'helheim-gnus-open-article
        ;; ", RET" 'gnus-summary-make-group-from-search
        ;; Motions
        "n"     'gnus-summary-next-article
        "p"     'gnus-summary-prev-article
        "N"     'gnus-summary-next-unread-article
        "P"     'gnus-summary-prev-unread-article
        "C-n"   'gnus-summary-next-same-subject
        "C-p"   'gnus-summary-prev-same-subject
        "M-n"   'gnus-summary-next-unread-subject
        "M-p"   'gnus-summary-prev-unread-subject
        "{"     'gnus-summary-prev-thread
        "}"     'gnus-summary-next-thread
        ;; Marking
        "m"     '("toggle mark" . helheim-gnus-toggle-process-mark)
        "%"     '("mark all" . gnus-uu-mark-buffer)
        "U"     '("unmark all" . gnus-summary-unmark-all-processable)
        ;;
        "a"     '("archive" . helheim-gnus-archive)
        "d"     '("trash" . helheim-gnus-trash)
        "s"     '("spam" . helheim-gnus-spam) ; `gnus-summary-isearch-article'
        "x"     '("redisplay group" . helheim-gnus-redisplay)
        "g r"   '("revert" . gnus-summary-show-article)
        "g /"   'gnus-summary-goto-article
        ;; Commit-and-redisplay workflow (see helheim-gnus-lib.el): a
        ;; tag change commits to notmuch at once but the row stays, so it is
        ;; reversible; `u' reverts the last, `g R' rebuilds the group from
        ;; notmuch (parallel to `g r' reverting the article) so handled rows
        ;; finally leave.
        "u"     '("undo" . helheim-gnus-undo)
        ;; Actions (shadows `!' = tick, `=' = expand-window, `-' = neg-argument)
        "!"     'gnus-summary-mark-as-read-forward
        "="     'gnus-summary-tick-article-forward
        "-"     'gnus-summary-clear-mark-forward ; reset article to unread
        ;; Threads
        "T m"   'gnus-uu-mark-thread    ; was "T #"
        "T u"   'gnus-uu-unmark-thread  ; was "T M-#"
        "z u"   'gnus-summary-up-thread ; was "T u"
        "z o"   '("show thread" . gnus-summary-show-thread)
        "z c"   '("hide-thread" . gnus-summary-hide-thread)
        "z a"   '("archive thread" . helheim-gnus-archive-thread)
        "z d"   '("trash thread" . helheim-gnus-trash-thread)
        "z s"   '("spam thread" . helheim-gnus-spam-thread)
        "A T"   'gnus-summary-refer-thread
        ;; Sorting
        "o a"   'gnus-summary-sort-by-author
        "o c"   'gnus-summary-sort-by-chars
        "o d"   'gnus-summary-sort-by-date
        "o i"   'gnus-summary-sort-by-score
        "o l"   'gnus-summary-sort-by-lines
        "o m d" 'gnus-summary-sort-by-most-recent-date
        "o m m" 'gnus-summary-sort-by-marks
        "o m n" 'gnus-summary-sort-by-most-recent-number
        "o n"   'gnus-summary-sort-by-number
        "o o"   'gnus-summary-sort-by-original
        "o r"   'gnus-summary-sort-by-random
        "o s"   'gnus-summary-sort-by-subject
        "o t"   'gnus-summary-sort-by-recipient
        ;; Searching
        "M-s"   'gnus-summary-search-article-forward
        ;; Composing (shadows `c' = catchup, `C' = cancel-article)
        "C"     '("new mail" . gnus-summary-mail-other-window)
        "c c"   '("new mail" . gnus-summary-mail-other-window)
        "c f"   '("followup to list" . gnus-summary-followup)
        "c F"   '("followup to list + original" . gnus-summary-followup-with-original)
        "c r"   '("reply" . gnus-summary-reply)
        "c R"   '("reply + original" . gnus-summary-reply-with-original)
        "c a"   '("reply all" . gnus-summary-very-wide-reply)
        "c A"   '("reply all + original" . gnus-summary-very-wide-reply-with-original)
        ))
    ;; "A" prefix
    (:keymap gnus-summary-article-map
      (:bind
        "T"  'gnus-summary-refer-thread))
    ;; "S" prefix
    (with-eval-after-load 'gnus-msg
      (:keymap gnus-summary-send-map
        (:unbind
          ;; NNTP posting, but we turned off server (`gnus-select-method' is `nnnil')
          "i"                          ; `gnus-summary-news-other-window'
          "M-c"                        ; `gnus-summary-mail-crosspost-complaint'
          "p"                          ; `gnus-summary-post-news'
          "u"                          ; `gnus-uu-post-news'
          "c"                          ; `gnus-summary-cancel-article'
          "s")                         ; `gnus-summary-supersede-article'
        (:bind
          "o"  'gnus-summary-mail-forward
          "O"  'gnus-uu-digest-mail-forward
          )))
    ;; "M" prefix
    (:keymap gnus-summary-mark-map
      (:unbind
        ;; Expiry deletes the maildir file, which lieer re-downloads.
        "e"                             ; `gnus-summary-mark-as-expirable'
        "x"))                           ; `gnus-summary-mark-as-expirable'
    ;; "Z" prefix
    (:keymap gnus-summary-exit-map
      (:unbind
        ;; Catchup-and-move: mark every unread article read, then jump to the
        ;; next/prev group.
        "n" ; `gnus-summary-catchup-and-goto-next-group'
        "p" ; `gnus-summary-catchup-and-goto-prev-group'
        ;; Mark ALL articles in this newsgroup as read and silently unstars
        ;; them in Gmail, reach the same via "C-u Z c" when actually wanted.
        "C"                             ; `gnus-summary-catchup-all-and-exit'
        "s"))                           ; `gnus-summary-save-newsrc'
    ;; "/" prefix
    (:keymap gnus-summary-limit-map
      (:unbind
        "*"                             ; `gnus-summary-limit-include-cached'
        ".")                            ; `gnus-summary-limit-to-unseen'
      (:bind
        ;; Pop the last limit off the stack (undo a limit). "w" is the default.
        "DEL"         'gnus-summary-pop-limit
        "<backspace>" 'gnus-summary-pop-limit))))

;;;; Article buffer

(setup gnus-art
  (:after-load
    (:keymap gnus-article-mode-map
      ;; `z' becomes the washing prefix, `c' the composing prefix. Free `s'
      ;; (was `gnus-article-show-summary') so it forwards to the summary's
      ;; `s' = spam; `a' = archive and `d' = trash already forward there.
      (:unbind "z" "c" "s")
      (:bind
        "q"       'helheim-gnus-article-quit
        "j"       'next-line
        "k"       'previous-line
        ;; Reply / followup (reclaim `W' from the old washing prefix)
        "r"       '("reply" . gnus-summary-reply)
        "F"       '("followup to list + original" . gnus-article-followup-with-original)
        "W"       '("reply all + original" . gnus-article-wide-reply-with-original)
        ;; Composing
        "C"       '("new mail" . gnus-article-mail)
        "c c"     '("new mail" . gnus-article-mail)
        "c r"     '("reply" . gnus-summary-reply)
        "c R"     '("reply + original" . gnus-summary-reply-with-original)
        "c f"     '("followup to list" . gnus-summary-followup)
        "c F"     '("followup to list + original" . gnus-summary-followup-with-original)
        "c w"     '("reply all" . gnus-summary-very-wide-reply)
        "c W"     '("reply all + original" . gnus-article-wide-reply-with-original)
        ;; Washing (evil-collection moves the standard `W' prefix onto `z w')
        "z w l"   'gnus-summary-stop-page-breaking
        "z w r"   'gnus-summary-caesar-message
        "z w m"   'gnus-summary-morse-message
        "z w i"   'gnus-summary-idna-message
        "z w t"   'gnus-summary-toggle-header
        "z w v"   'gnus-summary-verbose-headers
        "z w o"   'gnus-article-treat-overstrike
        "z w d"   'gnus-article-treat-smartquotes
        "z w u"   'gnus-article-treat-non-ascii ; was W U
        "z w y f" 'gnus-article-outlook-deuglify-article
        "z w y u" 'gnus-article-outlook-unwrap-lines
        "z w y a" 'gnus-article-outlook-repair-attribution
        "z w y c" 'gnus-article-outlook-rearrange-citation
        "z w w"   'gnus-article-fill-cited-article
        "z w q"   'gnus-article-fill-long-lines    ; was W Q
        "z w c"   'gnus-article-capitalize-sentences ; was W C
        "z w 6"   'gnus-article-de-base64-unreadable
        "z w z"   'gnus-article-decode-HZ          ; was W Z
        "z w a"   'gnus-article-treat-ansi-sequences ; was W A
        "z w b"   'gnus-article-add-buttons
        "z w B"   'gnus-article-add-buttons-to-head
        "z w p"   'gnus-article-verify-x-pgp-sig
        "z w s"   'gnus-summary-force-verify-and-decrypt
        ;; Actions
        "C-]"     'gnus-article-refer-article
        ))))

;;;; Server buffer

(setup gnus-srvr
  (:after-load
    (:keymap gnus-server-mode-map
      (:bind
        "Q" 'gnus-server-exit
        "y" 'gnus-server-copy-server      ; was `c'
        "p" 'gnus-server-yank-server
        "d" 'gnus-server-kill-server
        "c" 'gnus-server-compact-server)) ; was `z'
    ;; Browse-server buffer
    (:keymap gnus-browse-mode-map
      (:bind
        "u" 'gnus-browse-unsubscribe-current-group))))

;;;; Bookmark list

(setup gnus-bookmark
  (:after-load
    (:keymap gnus-bookmark-bmenu-mode-map
      (:bind
        "Q" 'quit-window
        "L" 'gnus-bookmark-bmenu-load))))

;;; BBDB (Insidious Big Brother Database)

;; (setup bbdb
;;   (:install t)
;;   ;; initialization for both Gnus and Notmuch
;;   (bbdb-initialize 'gnus 'message 'notmuch)
;;   (bbdb-mua-auto-update-init 'gnus 'message 'notmuch)
;;
;;   ;; When invoking bbdb interactively
;;   (setq bbdb-mua-update-interactive-p '(query . create))
;;
;;   ;; Check every address in a message and not only the first
;;   (setq bbdb-message-all-addresses t)
;;
;;   ;; use ; on a message to invoke bbdb
;;   (:hook gnus-summary-mode-hook
;;       (lambda ()
;;         (keymap-set gnus-summary-mode-map ";" 'bbdb-mua-edit-field)))
;;   (:hook gnus-startup-hook bbdb-insinuate-gnus)
;;   (:hook gnus-startup-hook bbdb-insinuate-notmuch)
;;   (setq bbdb-complete-name-allow-cycling t))

;;; .
(provide 'helheim-gnus)
;;; helheim-gnus.el ends here
