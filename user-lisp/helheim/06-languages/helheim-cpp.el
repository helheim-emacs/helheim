;;; helheim-cpp.el -*- lexical-binding: t; no-byte-compile: t -*-

(setup c-ts-mode
  (add-to-list 'major-mode-remap-defaults '(c-mode . c-ts-mode))
  (add-to-list 'major-mode-remap-defaults '(c++-mode . c++-ts-mode))
  (:hook ( c-mode-hook c++-mode-hook
           c-ts-mode-hook c++-ts-mode-hook)
         helheim-lsp)
  (:hook (c-ts-mode-hook c++-ts-mode-hook)
         helheim-c-ts-use-google-indent-style)
  (:setopt c-ts-indent-offset 4
           c-ts-mode-indent-style 'k&r)
  (:after-load
    ;; Set line comment style.
    (c-ts-mode-toggle-comment-style -1)))

(setup lsp-mode
  (:after-load
    (:setopt lsp-clients-clangd-args '("--header-insertion-decorators=0"))))

;;;; Google C++ indentation style
;;
;; The K&R style of `c-ts-mode' is the closest built-in one, and the rules
;; below are the places where the Google C++ style guide differs from it.
;; They are added in front of the K&R rules once the mode is up, so that they
;; win over them.
;;
;; A function in `c-ts-mode-indent-style' would be the other way in, but the
;; two paths that call such a function disagree about what it has to return:
;; the mode body takes the return value as the whole value of
;; `treesit-simple-indent-rules', an alist keyed by language, while
;; `c-ts-mode-set-style' wraps it in that alist itself.  Whichever shape the
;; function returns, one of the two paths breaks.
;;
;; - How to write custom treesitter-based indentation rules:
;;   - info:elisp#Parser-based Indentation
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Parser_002dbased-Indentation.html
;;
;; - Use `treesit-explore-mode' to see where you're in the tree-sitter tree.
;;
;; - Set `treesit--indent-verbose' to debug which rule is being applied at
;;   a given point.

(defun helheim-c-ts--google-indent-rules ()
  "Return the indent rules where the Google C++ style differs from K&R."
  (let ((offset c-ts-indent-offset))
    `(;; A base class list aligns with the first base class.
      ((parent-is "base_class_clause") (nth-sibling 1) 0)
      ;; Every member of a class sits one level inside it, whatever comes
      ;; before it.  The built-in rules align a member that follows a blank
      ;; line with the first access specifier instead.  The access specifier
      ;; itself and the closing brace keep the column of the class.
      ((node-is "access_specifier") standalone-parent 0)
      ((n-p-gp "}" "field_declaration_list" nil) standalone-parent 0)
      ((parent-is "field_declaration_list") standalone-parent ,offset)
      ;; The body of a namespace keeps the column of the namespace itself.
      ((n-p-gp nil "declaration_list" "namespace_definition") grand-parent 0)
      ;; A constructor initializer list is one level in, and so is an
      ;; argument or parameter list that opens on its own line.  The
      ;; built-in rules align those lists with the open paren instead.
      ((node-is "field_initializer_list") standalone-parent ,offset)
      ((match nil "argument_list" nil 1 1) standalone-parent ,offset)
      ((match nil "parameter_list" nil 1 1) standalone-parent ,offset)
      ;; The body of a lambda is one level in from the code on the line where
      ;; its opening brace is, and the closing brace aligns with that code.
      ;; A leading binary operator does not count as code, so in a `|'
      ;; pipeline the body is indented from `views::filter', not from `|'.
      ;; The built-in rules indent the body from the first line of the whole
      ;; statement instead.
      ((n-p-gp "}" "compound_statement" "lambda_expression")
       helheim-c-ts--code-bol 0)
      ((n-p-gp nil "compound_statement" "lambda_expression")
       helheim-c-ts--code-bol ,offset)
      ;; A line that starts with a binary operator continues the expression
      ;; on the right of `=', and the operator aligns with the `='.
      (helheim-c-ts--assignment-sign helheim-c-ts--assignment-sign 0)
      ;; Elsewhere, for example inside the arguments of a call, the operator
      ;; aligns with the first operator of the chain.  When that operator
      ;; starts a line itself, the operators align with the first operand.
      (helheim-c-ts--first-operator helheim-c-ts--first-operator 0))))

(defun helheim-c-ts--assignment-sign (node parent &rest _)
  "Return the position of the `=' whose right side NODE continues, or nil.
NODE must be the operator of the binary expression PARENT.  The `=' is
the sign of the declaration or the assignment that holds the outermost
binary expression around PARENT."
  (when (and (equal (treesit-node-type parent) "binary_expression")
             (equal (treesit-node-field-name node) "operator"))
    (let ((top parent))
      (while (equal (treesit-node-type (treesit-node-parent top))
                    "binary_expression")
        (setq top (treesit-node-parent top)))
      (when (member (treesit-node-type (treesit-node-parent top))
                    '("init_declarator" "assignment_expression"))
        (when-let* ((sign (treesit-node-prev-sibling top)))
          (treesit-node-start sign))))))

(defun helheim-c-ts--first-operator (node parent &rest _)
  "Return the position that the operator NODE aligns with, or nil.
NODE must be the operator of the binary expression PARENT.  The chain is
PARENT and the binary expressions with the same operator that nest on
its left side.  The position is the first operator of the chain.  When
that operator is the first token on its line, the position is the start
of the first operand instead."
  (when (and (equal (treesit-node-type parent) "binary_expression")
             (equal (treesit-node-field-name node) "operator"))
    (let ((operator (treesit-node-type node))
          (first parent)
          left)
      (while (and (setq left (treesit-node-child-by-field-name first "left"))
                  (equal (treesit-node-type left) "binary_expression")
                  (equal (treesit-node-type
                          (treesit-node-child-by-field-name left "operator"))
                         operator))
        (setq first left))
      (let ((pos (treesit-node-start
                  (treesit-node-child-by-field-name first "operator"))))
        (save-excursion
          (goto-char pos)
          (skip-chars-backward " \t")
          (if (bolp)
              (treesit-node-start
               (treesit-node-child-by-field-name first "left"))
            pos))))))

(defun helheim-c-ts--code-bol (_node parent &rest _)
  "Return the position where the code on the line of PARENT starts.
That is the first non-space character of the line.  When the line starts
with the operator of a binary expression, the position is the start of
the operand after it, because the operator hangs to the left of the code."
  (save-excursion
    (goto-char (treesit-node-start parent))
    (back-to-indentation)
    (let ((token (treesit-node-at (point))))
      (if (and (equal (treesit-node-field-name token) "operator")
               (equal (treesit-node-type (treesit-node-parent token))
                      "binary_expression"))
          (treesit-node-start (treesit-node-next-sibling token))
        (point)))))

(defun helheim-c-ts-use-google-indent-style ()
  "Indent the current C or C++ buffer in the Google style."
  (treesit-simple-indent-add-rules
   (if (derived-mode-p 'c-ts-mode) 'c 'cpp)
   (helheim-c-ts--google-indent-rules)))

;;; .
(provide 'helheim-cpp)
;;; helheim-cpp.el ends here
