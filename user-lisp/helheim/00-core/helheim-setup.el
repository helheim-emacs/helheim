;;; helheim-setup.el -*- lexical-binding: t -*-
;;; Commentary:
;;
;; `helheim-setup' does not rearrange blocks of code — it is not declarative,
;; just syntactic sugar.
;;
;; It allows create local macros that are exist only withing the scope
;; of `helheim-setup'. A form in the body whose car is a keyword from
;; `helheim-setup-macros' and expanded in place by `macroexpand-all',
;; while all other forms passed through untouched.
;;
;; Use `helheim-setup-define' to define new keywords.
;;
;;; Code:

(eval-when-compile (require 'cl-macs))
(require 'dash)
(require 'helheim-lib)

;;; Utils

(defsubst helheim-setup-unprogn (body)
  "`macroexp-unprogn' BODY and delete all nil items from it."
  (->> (macroexp-unprogn body)
       (delete (list nil))
       (delq nil)))

(defsubst helheim-setup--unquote (form)
  "Strip a leading `\\='' (`quote') or `#\\='' (`function') from FORM."
  (if (memq (car-safe form) '(quote function))
      (cadr form)
    form))

(defun helheim-setup--split-keyword-args (args)
  "Split ARGS list into keyword-value pairs and remaining arguments.
Returns a cons cell (PLIST . REST) where:
PLIST is a list with keyword-value pairs from the beginning of ARGS list;
REST contains all other elements."
  (let (plist)
    (while (keywordp (car-safe args))
      (cl-callf plist-put plist (car args) (cadr args))
      (cl-callf cddr args)) ; advance by 2
    (cons plist args)))

;;; The expander

(defvar helheim-setup-macros nil
  "Alist of (KEYWORD . EXPANDER) used as a `macroexpand-all' environment.")

(defvar helheim-setup--context nil
  "Alist holding the context of the `helheim-setup' form being expanded.
Keyword macros can extend it with `helheim-setup--expand', and read from
it with `helheim-setup-context'. Bound only during macro expansion.")

(defvar helheim-setup--wrappers nil
  "Alist of (KIND . VALUE) requests to wrap the body of a `helheim-setup' form.
A keyword whose job is to enclose the whole body (like `:when',
`:after', `:elpaca') cannot expand in place, so the process is
two-phase:
  1. The macro pushes a request here and expands to nil.
  2. The counterpart `helheim-setup--wrap-KIND' function, once the body is
     expanded, looks up its own KIND here and wraps the body if it finds
     a request.

Bound only during macro expansion.")

(defmacro helheim-setup--expand (body context)
  "Expand BODY with CONTEXT prepended to the expansion context.
CONTEXT is an alist of (KEY . VALUE) pairs."
  (declare (indent 1))
  `(let ((helheim-setup--context (append ,context helheim-setup--context)))
     (helheim-setup--expand-1 ,body)))

(defun helheim-setup--expand-1 (body)
  "Expand keyword macros from `helheim-setup-macros' in BODY."
  (macroexpand-all (macroexp-progn body)
                   (append helheim-setup-macros
                           macroexpand-all-environment)))

(defun helheim-setup-context (key)
  "Return the value of KEY in the context of the `helheim-setup' form."
  (or (alist-get key helheim-setup--context)
      (error "helheim-setup: cannot deduce %S from context" key)))

;;; Defining keywords

(defmacro helheim-setup-define (name args &rest body)
  "Define NAME as a `helheim-setup'-local macro.

This is a `cl-defmacro' for macros that exist only within the scope of
a `helheim-setup' form, and takes the same arguments `cl-defmacro' does.

The `declare' form, besides the standard `indent' and `debug' keys, accepts:

  (repeatable t)  Apply the expander to each successive group of arguments,
                  the group size being the number of arguments in ARGS.
                  ARGS must therefore be fixed-arity: neither `&optional'
                  nor `&rest' can appear in it.

\(fn NAME (ARGS...) [DOCSTRING] [DECL] BODY...)"
  (declare (indent defun)
           (doc-string 3)
           (debug ( &define sexp lambda-list
                    [&optional stringp]
                    [&optional ("declare" &rest sexp)]
                    def-body)))
  (let ((docstring (if (stringp (car body))
                       (pop body)))
        repeatable
        properties)
    (pcase (car body)
      (`(declare . ,declarations)
       (pop body)
       (dolist (declaration declarations)
         (pcase declaration
           (`(indent ,value)
            (push `(put ,name 'lisp-indent-function ',value) properties))
           (`(debug ,value)
            (push `(put ,name 'edebug-form-spec ',value) properties))
           (`(repeatable ,value)
            (setq repeatable value))
           (_
            (error "helheim-setup-define: unknown declaration %S in %S" declaration name))))))
    (let ((expander `(lambda ,args ,@body)))
      (if repeatable
          (-let [(arity . max-arity) (func-arity expander)]
            (when (zerop arity)
              (error "helheim-setup-define: %S is `repeatable' but takes no arguments" name))
            (unless (eql arity max-arity) ;; max-arity can be symbol 'many
              (error "helheim-setup-define: %S is `repeatable' but its arglist is not fixed-arity: %S" name args))
            (setq expander `(helheim-setup--make-repeatable ,expander ,arity)))
        ;; Else allow expander supports full Common Lisp arguments conventions
        (setq expander `(cl-function ,expander)))
      `(progn
         (setf (alist-get ,name helheim-setup-macros) ,expander)
         ;; Record where the keyword was defined, so "gd" (native "M-.")
         ;; on it inside a `helheim-setup' form jumps here.
         (put ,name 'helheim-setup-definition-file
              (or load-file-name buffer-file-name))
         ,@(when docstring
             `((put ,name 'helheim-setup-documentation ,docstring)))
         ,@(nreverse properties)
         ,name))))

(defun helheim-setup--make-repeatable (expander n)
  "Return an expander applying EXPANDER to each successive group of N arguments."
  (lambda (&rest args)
    (unless (zerop (mod (length args) n))
      (error "helheim-setup: number of arguments is not a multiple of %d" n))
    (macroexp-progn
     (->> args
          (-partition n)
          (-map (lambda (group)
                  (apply expander group)))))))

(defun helheim-setup--xref-def-function (symbol)
  "Return an elisp xref location for SYMBOL if it is a `helheim-setup' keyword.
Registered on `elisp-xref-find-def-functions' so that \\[xref-find-definitions]
on a keyword inside a `helheim-setup' form jumps to its `helheim-setup-define'."
  (require 'elisp-mode)
  (if-let* (((assq symbol helheim-setup-macros))
            (file (get symbol 'helheim-setup-definition-file)))
       (list (elisp--xref-make-xref nil symbol file))))

(add-to-list 'elisp-xref-find-def-functions
             #'helheim-setup--xref-def-function)

;;; The macro

(defmacro helheim-setup (name &rest body)
  "Configure the feature or package NAME.

A form in BODY whose car is a keyword from `helheim-setup-macros' is
expanded in place, at any depth: BODY is walked by `macroexpand-all', so
a keyword nested inside a `when', a `let' or a `with-eval-after-load'
expands just as one written at the top of BODY does. Data behind `quote'
is left alone. Any other form is passed through untouched.

NAME is a feature symbol. The default context is derived from it: the
mode is NAME, or NAME-mode unless NAME already ends in `-mode', the
keymap is MODE-map and the hook is MODE-hook.

\(fn NAME &rest BODY)"
  (declare (indent 1)
           (debug (sexp &rest sexp)))
  (unless (symbolp name)
    (error "helheim-setup: NAME must be a symbol, got %S" name))
  (let* ((mode (if (string-suffix-p "-mode" (symbol-name name))
                   name
                 (intern (format "%s-mode" name))))
         (helheim-setup--context
          `((feature . ,name)
            (mode . ,mode)
            (hook . ,(intern (format "%s-hook" mode)))
            (keymap . ,(intern (format "%s-map" mode)))))
         (helheim-setup--wrappers nil)
         ;; Bind the two dynamic variables above *before* the body is
         ;; expanded — `let*' sequencing is doing real work here, the
         ;; expanders run inside their dynamic extent.
         (body (helheim-setup--expand-1 body)))
    ;; Innermost first: `:after' sits closest to the body, `:when' outermost.
    (->> body
         (helheim-setup--wrap-after)
         (helheim-setup--wrap-elpaca)
         (helheim-setup--wrap-when))))

(put 'helheim-setup 'function-documentation '(helheim-setup--make-docstring))

(defun helheim-setup--make-docstring ()
  "Return the docstring for `helheim-setup'."
  (with-temp-buffer
    ;; Read the docstring from the function object, not the symbol, because
    ;; the symbol's `function-documentation' is this very function, so
    ;; `(documentation 'helheim-setup)' is a recursion.
    (insert (documentation (symbol-function 'helheim-setup) 'raw)
            "\n\n")
    (when helheim-setup-macros
      (insert "Within BODY, the following context-local keyword macros are defined:")
      (fill-paragraph)
      (dolist (keyword (->> helheim-setup-macros
                            (reverse)
                            (-map #'-first-item)))
        (insert "\n" (make-separator-line) "\n"
                (or (get keyword 'helheim-setup-documentation)
                    "No documentation."))))
    (buffer-string)))

(defalias 'setup 'helheim-setup
  "Compatibility alias for `helheim-setup'.
Helheim used to build on the `setup.el' package and its `setup' macro;
the expander is now our own. The name is kept so existing configurations
keep working.")

;; Indentation and edebug specs live on the symbol and do not follow an alias.
(put 'setup 'lisp-indent-function 1)
(put 'setup 'edebug-form-spec '(sexp &rest sexp))

;;; :install
;;;; :install

(helheim-setup-define :install (package &rest recipe)
  "\(:install PACKAGE &rest RECIPE)

Install PACKAGE using package manager specified in `helheim-package-manager'.
RECIPE should be written in Elpaca's recipe dialect."
  (pcase helheim-package-manager
    ('elpaca   `(:elpaca ,package ,@recipe))
    ('straight `(:straight ,package
                 ,@(helheim-setup--elpaca-recipe-to-straight recipe)))))

(defun helheim-setup--elpaca-recipe-to-straight (recipe)
  "Translate the Elpaca RECIPE plist into its Straight equivalent.
Currently only `:repo' translates to `:local-repo' when PATH is a local
filesystem path. Straight reserves `:repo' for the remote."
  (unless (zerop (mod (length recipe) 2))
    (error "helheim-setup: recipe is not a property list: %S" recipe))
  (->> recipe
       (-partition 2)
       (-mapcat (-lambda ((key value))
                  (if (and (eq key :repo)
                           (helheim-setup--local-repo-p value))
                      (list :local-repo value)
                    (list key value))))))

(defun helheim-setup--local-repo-p (repo)
  "Return non-nil if REPO is a local filesystem path."
  (and (stringp repo)
       (string-match-p "\\`[/~]" repo)))

;;;; :straight

(helheim-setup-define :straight (package &rest recipe)
  "\(:straight PACKAGE &rest RECIPE)

Install PACKAGE with `straight-use-package'."
  (if (eq helheim-package-manager 'straight)
      `(straight-use-package ',(pcase package
                                 ('nil `(,(helheim-setup-context 'feature)
                                         :type built-in))
                                 ('t (helheim-setup-context 'feature))
                                 (_ (cons package recipe))))
    nil))

;;;; :elpaca

(helheim-setup-define :elpaca (package &rest recipe)
  "\(:elpaca PACKAGE &rest RECIPE)

Install PACKAGE with `elpaca'."
  (when (eq helheim-package-manager 'elpaca)
    (push (cons 'elpaca (cond ((eq package 't)
                               (helheim-setup-context 'feature))
                              (recipe
                               (cons package recipe))
                              (t package)))
          helheim-setup--wrappers))
  nil)

(defun helheim-setup--wrap-elpaca (body)
  "Wrap BODY in an `elpaca' form if `:elpaca' recorded a recipe."
  (if-let* ((recipe (alist-get 'elpaca helheim-setup--wrappers)))
      `(elpaca ',recipe ,@(helheim-setup-unprogn body))
    body))

;;; :require

(helheim-setup-define :require (feature)
  "\(:require &rest FEATURES)

Require FEATURE."
  (declare (repeatable t))
  `(require ',(if (eq feature t)
                  (helheim-setup-context 'feature)
                feature)))

;;; :when

(helheim-setup-define :when (condition)
  "\(:when CONDITION)

Eval `helheim-setup' macro body only if CONDITION evaluates to non-nil."
  (declare (debug (form)))
  (push (cons 'when condition)
        helheim-setup--wrappers)
  nil)

(defun helheim-setup--wrap-when (body)
  "Wrap BODY in a `when' form if `:when' recorded a condition."
  (if-let* ((condition (alist-get 'when helheim-setup--wrappers)))
      `(when ,condition
         ,@(helheim-setup-unprogn body))
    body))

;;; :after

(helheim-setup-define :after (&rest features)
  "\(:after &rest FEATURES)

Evaluate current `helheim-setup' macro body after all the FEATURES will been
loaded."
  (push `(after . ,features) helheim-setup--wrappers)
  nil)

(defun helheim-setup--wrap-after (body)
  "Wrap BODY in a `with-eval-after-load' for each feature `:after' recorded."
  (dolist (feature (reverse (alist-get 'after helheim-setup--wrappers)))
    (setq body `(with-eval-after-load ',feature
                  ,@(helheim-setup-unprogn body))))
  body)

;;; :after-init

(helheim-setup-define :after-init (&rest body)
  "\(:after-init &rest BODY)

Eval BODY in `after-init-hook'. If Elpaca package manager is used — eval in
`elpaca-after-init-hook' instead. BODY can be a symbol, a lambda, or any number
or forms that will be wrapped in lambda in this case."
  (declare (indent 0))
  (let ((hook (pcase helheim-package-manager
                ('straight 'after-init-hook)
                ('elpaca   'elpaca-after-init-hook)))
        (func (pcase (car body)
                ((pred symbolp) `#',(car body))
                (`(lambda . ,_) (car body))
                (_  `(lambda () ,@body)))))
    `(add-hook ',hook ,func)))

;;; :after-load

(helheim-setup-define :after-load (&rest body)
  "\(:after-load &rest BODY)

Evaluate BODY after the current feature has been loaded."
  (declare (indent 0)
           (debug (setup)))
  `(with-eval-after-load ',(helheim-setup-context 'feature)
     ,@body))

;;; :defer

(defvar helheim-initial-deferred-task-timeout (if (daemonp) 0 2.0)
  "Number of seconds Emacs will wait until starts executing deferred tasks.
Set this to nil to disable delayed loading at startup.
Set this to 0 to load all deferred packages immediately at `after-init-hook'.")

(defvar helheim-deferred-task-timeout 0.75
  "Number of seconds Emacs should idle untill eval next delayed function.")

(defvar helheim-deferred-tasks nil)

(defsubst helheim-defer (task)
  (declare (indent 0))
  (push task helheim-deferred-tasks))

(helheim-setup-define :defer (&rest body)
  "\(:defer &rest BODY)

Evaluate BODY when Emacs is idle for DELAY seconds after startup."
  (declare (indent 0)
           (debug (setup)))
  `(helheim-defer (lambda () ,@body)))

(add-hook 'emacs-startup-hook 'helheim-schedule-deferred-tasks 99)

(defun helheim-schedule-deferred-tasks ()
  (when helheim-deferred-tasks
    (run-with-idle-timer helheim-initial-deferred-task-timeout nil
                         'helheim--eval-deferred-tasks
                         (reverse helheim-deferred-tasks))
    (unless debug-on-error
      (setq helheim-deferred-tasks nil))))

(defun helheim--eval-deferred-tasks (tasks)
  (when tasks
    (condition-case-unless-debug e
        (let ((gc-cons-threshold most-positive-fixnum))
          (funcall (car tasks)))
      (error
       (message "Error in deferred task: %s" e)))
    (when (cdr tasks)
      (run-with-idle-timer helheim-deferred-task-timeout nil
                           'helheim--eval-deferred-tasks (cdr tasks)))))

;;; :setopt

(helheim-setup-define :setopt (variable value)
  "\(:setopt &rest [VARIABLE VALUE]...)

Set VARIABLE to VALUE only if it hasn’t already been changed. This macro is
for internal use in Helheim to prevent user settings from being overwritten
by Helheim defaults. Use `setopt' for your custom settings."
  (declare (indent 0)
           (debug (setq))
           (repeatable t))
  (cl-assert (symbolp variable) nil "Attempting to set a non-symbol: %s" value)
  `(helheim-setopt ',variable ,value))

(defun helheim-setopt (variable value)
  "Set VARIABLE to VALUE only if it hasn’t been already changed."
  (cond ((get variable 'custom-check-value) ; set by the user's `setopt'
         nil)
        ((not (boundp variable))
         (set-default variable value))
        ((equal (symbol-value variable)
                (ignore-errors (custom--standard-value variable)))
         (funcall (or (get variable 'custom-set)
                      #'set-default)
                  variable value))))

;;; :hook

(helheim-setup-define :hook (hooks &optional functions)
  "\(:hook HOOKS &optional FUNCTIONS)

Add FUNCTIONS to HOOKS.
This macro can map many. Also it accepts lambda form."
  (unless functions
    (setq functions (helheim-setup-context 'mode)))
  (cond ((memq (car-safe functions) '(lambda defun))
         (cond ((symbolp hooks)
                `(add-hook ',hooks ,functions))
               ((proper-list-p hooks)
                (cl-with-gensyms (fun)
                  `(let ((,fun ,functions))
                     ,@(cl-loop for hook in hooks
                                collect `(add-hook ',hook ,fun)))))))
        ((or (proper-list-p hooks)
             (proper-list-p functions))
         `(progn
            ,@(->> (-table-flat #'list (ensure-list hooks) (ensure-list functions))
                   (-map (-lambda ((hook func))
                           `(add-hook ',hook ',func))))))
        (t
         `(add-hook ',hooks ',functions))))

;;; :treesit

(helheim-setup-define :treesit (language &rest recipe)
  "\(:treesit LANG RECIPE)

Install tree-sitter grammar for LANGUAGE. The RECIPE follows
`treesit-language-source-alist' keywords syntax introduced in Emacs 31:

    (URL [KEYWORD VALUE]...)

RECIPE keywords:

  `:revision'       The Git tag or branch of the desired version, defaulting
                  to the latest default branch.

  `:commit'         If non-nil, checkout this commit hash after cloning the repo.
                  COMMIT has precedence over REVISION if both are non-nil.

  `:source-dir'     Relative subdirectory in the repository in which the
                  grammar's parser.c file resides, defaulting to \"src\".

  `:copy-queries'   When non-nil specifies whether to copy the files in the
                  \"queries\" directory from the source directory to the
                  installation directory.

  `:cc'             C compiler, default is \"cc\"

  `:c++'            C++ compiler, default is \"c++\""
  (declare (indent defun))
  (let ((recipe (if (< emacs-major-version 31)
                    (-let [(url . (&plist :revision :source-dir :cc :c++)) recipe]
                      (list url revision source-dir cc c++))
                  recipe)))
    `(with-eval-after-load 'treesit
       (cl-symbol-macrolet ((val (alist-get ',language treesit-language-source-alist)))
         (unless val
           (setf val (list ,@recipe)))))))

;;; :keymap

(helheim-setup-define :keymap (keymap &rest body)
  "\(:keymap KEYMAP &rest BODY)

Use KEYMAP for all nested `:bind' and `:unbind' forms. KEYMAP is an
unquoted keymap symbol, or an unquoted list of them. When a list is
given, every nested `:bind' / `:unbind' binds into every map named.

BODY is expanded once, not once per map: the fan-out over the maps lives
in `:bind' / `:unbind' themselves. Imperative Lisp in BODY is therefore
emitted once, whatever KEYMAP names."
  (declare (indent 1)
           (debug (sexp setup)))
  (let ((maps (ensure-list keymap)))
    (unless (-all-p #'symbolp maps)
      (error "helheim-setup: `:keymap' takes a symbol or a list of them, got %S" keymap))
    (helheim-setup--expand body `((keymap . ,maps)))))

;;; :bind

(helheim-setup-define :bind (&rest args)
  "\(:bind [:state STATE] &rest [KEY DEFINITION]...)

Bind KEYs to DEFINITIONs in current keymap.
See `hel-keymap-set'for arguments.

When the enclosing `:keymap' named several maps, this is where the
fan-out happens: one `hel-keymap-set' call per map."
  (declare (indent defun))
  (-let [((&plist :state) . bindings) (helheim-setup--split-keyword-args args)]
    (cl-loop for key in-ref bindings by #'cddr
             when (vectorp key)
             do (setf key (key-description key)))
    (macroexp-progn
     (-map (lambda (map)
             `(hel-keymap-set ,map
                ,@(if state `(:state ',(helheim-setup--unquote state)))
                ,@bindings))
           (ensure-list (helheim-setup-context 'keymap))))))

(helheim-setup-define :unbind (&rest args)
  "\(:unbind [:state STATE] &rest KEYS)

Remove KEYS bindings from current keymap.

STATE is an optional keyword argument that specifies the Hel state.
Can be a symbol or list of symbols."
  (declare (indent defun))
  (-let [((&plist :state) . keys) (helheim-setup--split-keyword-args args)]
    (macroexp-progn
     (-map (lambda (map)
             `(hel-keymap-set ,map
                ,@(if state `(:state ',(helheim-setup--unquote state)))
                ,@(-mapcat (lambda (key)
                             (when (vectorp key)
                               (setq key (key-description key)))
                             (list key nil))
                           keys)))
           (ensure-list (helheim-setup-context 'keymap))))))

;;; :global-bind

(helheim-setup-define :global-bind (&rest args)
  "\(:global-bind [:state STATE] &rest [KEY DEFINITION]...)

STATE is an optional keyword argument that specifies the Hel state in which the
keybindings will be active. Can be a symbol or list of symbols."
  (declare (indent defun))
  (-let [((&plist :state) . bindings) (helheim-setup--split-keyword-args args)]
    (cl-loop for key in-ref bindings by #'cddr
             when (vectorp key)
             do (setf key (key-description key)))
    `(hel-keymap-global-set
       ,@(if state `(:state ',(helheim-setup--unquote state)))
       ,@bindings)))

(helheim-setup-define :global-unbind (&rest args)
  "\(:global-unbind [:state STATE] &rest KEYS)

Remove KEYS bindings from current keymap.

STATE is an optional keyword argument that specifies the Hel state.
Can be a symbol or list of symbols."
  (declare (indent defun))
  (-let [((&plist :state) . keys) (helheim-setup--split-keyword-args args)]
    `(hel-keymap-global-set
       ,@(if state `(:state ',(helheim-setup--unquote state)))
       ,@(-mapcat (lambda (key)
                    (when (vectorp key)
                      (setq key (key-description key)))
                    (list key nil))
                  keys))))

;;; :initial-state

(helheim-setup-define :initial-state (mode state)
  "\(:initial-state MODE STATE)

Start major MODE in the Hel STATE.

Spelled and behaving exactly as in `hel-collection-setup', so a form
can be moved between hel-collection and Helheim unchanged."
  (declare (indent defun)
           (debug (sexp sexp)))
  `(hel-set-initial-state ',(helheim-setup--unquote mode)
                          ',(helheim-setup--unquote state)))

;;; :blackout

(helheim-setup-define :blackout (&rest args)
  "\(:blackout &rest ARGS)

Do not display MODE in the mode line.

    \(helheim-setup foo
      (:blackout t))                   =>  \(blackout 'foo-mode nil)

    \(helheim-setup foo
      (:blackout \" Foo\"))              =>  \(blackout 'foo-mode \" Foo\")

    \(helheim-setup foo
      \(:blackout \(foo-mode . \" Foo\"))  =>  \(blackout 'foo-mode \" Foo\")"
  (or args (setq args '(t)))
  `(with-eval-after-load ',(helheim-setup-context 'feature)
     ,@(cl-loop for arg in args
                collect (pcase arg
                          ('t
                           `(blackout ',(helheim-setup-context 'mode)))
                          ((and (pred symbolp) mode)
                           `(blackout ',mode))
                          ((and (pred stringp) replacement)
                           `(blackout ',(helheim-setup-context 'mode) ,replacement))
                          (`(,mode . ,replacement)
                           `(blackout ',mode ,replacement))))))

;;; :command

(helheim-setup-define :command (command)
  "\(:command &rest COMMANDS)

Autoload COMMAND from the current feature."
  (declare (repeatable t))
  `(autoload ',(helheim-setup--unquote command)
     ,(format "%s" (helheim-setup-context 'feature))
     nil t))

;;; :mode

(helheim-setup-define :mode (cons-cell)
  "\(:mode &rest CONS-CELLS)

Add CONS-CELL to `auto-mode-alist'."
  (declare (debug (form))
           (repeatable t))
  `(add-to-list 'auto-mode-alist ',cons-cell))

;;; .
(provide 'helheim-setup)
;;; helheim-setup.el ends here
