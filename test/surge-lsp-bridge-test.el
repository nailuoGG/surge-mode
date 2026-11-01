;;; surge-lsp-bridge-test.el --- Optional client regression tests -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Requires lsp-bridge and its Emacs dependencies on `load-path'.
(require 'ert)
(require 'surge-lsp-bridge)

(ert-deftest surge-example-fallback-without-previous-callback ()
  (let ((surge-lsp-bridge--previous-language-id nil))
    (should (equal (lsp-bridge--get-language-id-func
                    "/p" "/p/a.jsx" "tailwindcss" "jsx")
                   "javascriptreact"))
    (should (equal (lsp-bridge--get-language-id-func
                    "/p" "/p/a.tsx" "tailwindcss" "tsx")
                   "tsx"))
    (should-not (lsp-bridge--get-language-id-func
                 "/p" "/p/a.py" "basedpyright" "py"))))

(ert-deftest surge-example-delegates-all-callback-arguments ()
  (let ((surge-lsp-bridge--previous-language-id #'list))
    (should (equal (lsp-bridge--get-language-id-func "p" "f" "other" "x")
                   '("p" "f" "other" "x")))))

(ert-deftest surge-example-prefers-configured-project-root ()
  (let* ((root (make-temp-file "surge-project-" t))
         (file (expand-file-name "profile.conf" root))
         (surge-project-roots (list root))
         (delegated nil)
         (surge-lsp-bridge--previous-project-root
          (lambda (_file) (setq delegated t))))
    (unwind-protect
        (progn
          (write-region "" nil file nil 'silent)
          (should (equal (surge-lsp-bridge-project-root file)
                         (directory-file-name (file-truename root))))
          (should-not delegated))
      (delete-directory root t))))

(ert-deftest surge-example-delegates-project-root-resolution ()
  (let ((surge-project-roots nil)
        (surge-lsp-bridge--previous-project-root
         (lambda (file) (concat "delegated:" file))))
    (should (equal (surge-lsp-bridge-project-root "/p/file.py")
                   "delegated:/p/file.py"))))

(ert-deftest surge-example-preserves-default-dir-locals-root ()
  (let* ((root (make-temp-file "surge-project-" t))
         (file (expand-file-name "profile.conf" root))
         (dir-locals (expand-file-name ".dir-locals.el" root))
         (surge-project-roots nil)
         (surge-lsp-bridge--previous-project-root nil))
    (unwind-protect
        (progn
          (write-region "" nil file nil 'silent)
          (write-region "()\n" nil dir-locals nil 'silent)
          (should (equal (surge-lsp-bridge-project-root file)
                         (directory-file-name root))))
      (delete-directory root t))))

(ert-deftest surge-example-selects-language-id-by-buffer-mode ()
  (dolist (pair '((surge-conf-mode . "surge")
                  (surge-module-mode . "surge-module")
                  (surge-ruleset-mode . "surge-ruleset")))
    (with-temp-buffer
      ;; Test resolution without starting a Python or language-server process.
      (let ((surge-conf-mode-hook nil)) (funcall (car pair)))
      (setq buffer-file-name (expand-file-name "surge-test.virtual"
                                               temporary-file-directory))
      (should (equal (lsp-bridge--get-language-id-func
                      temporary-file-directory buffer-file-name "surge" "virtual")
                     (cdr pair))))))

(provide 'surge-lsp-bridge-test)
;;; surge-lsp-bridge-test.el ends here
