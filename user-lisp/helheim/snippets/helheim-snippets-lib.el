;;; helheim-snippets-lib.el -*- lexical-binding: t -*-
;;; Code:

(require 'yasnippet-capf)
(declare-function cape-wrap-trigger "cape")

;;;###autoload
(defun helheim-yas-capf ()
  "Complete a snippet key before point, or list every snippet.
`yasnippet-capf' answers only when a word character stands before
point.  An empty prefix gets the same table over a zero-width region,
so the popup that opens right after the \"/\" trigger shows the whole
snippet list of the current major mode."
  (or (yasnippet-capf)
      `(,(point) ,(point)
        ,(completion-table-with-cache
          (lambda (input) (yasnippet-capf-candidates input)))
        ,@yasnippet-capf--properties)))

;;;###autoload
(defun helheim-yas-trigger-capf ()
  "Complete a snippet key typed after a \"/\".
The slash has to open a word: i.e. stands at the beginning of the line
or after a space or a tab. A slash inside a path like \"src/main\",
a division like \"a/b\" and the \"//\" of a comment do not trigger."
  (when-let* ((slash (save-excursion (search-backward "/" (pos-bol) t)))
              ((or (= slash (pos-bol))
                   (memq (char-before slash) '(?\s ?\t)))))
    (cape-wrap-trigger #'helheim-yas-capf ?/)))

;;; .
(provide 'helheim-snippets '(lib))
;;; helheim-snippets-lib.el ends here
