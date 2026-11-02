;;; surge-eglot-test.el --- Optional Eglot integration tests -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'surge-eglot)

(defun surge-eglot-test--language-id (mode)
  "Return the Eglot language identifier configured for MODE."
  (alist-get mode (car (eglot--lookup-mode mode))))

(ert-deftest surge-eglot-language-ids ()
  (should (equal (surge-eglot-test--language-id 'surge-conf-mode)
                 "surge"))
  (should (equal (surge-eglot-test--language-id 'surge-module-mode)
                 "surge-module"))
  (should (equal (surge-eglot-test--language-id 'surge-ruleset-mode)
                 "surge-ruleset")))

(ert-deftest surge-eglot-project-is-eglot-specific ()
  (let ((root (make-temp-file "surge-eglot-root-" t))
        (outside (make-temp-file "surge-eglot-outside-" t)))
    (unwind-protect
        (let ((surge-project-roots (list root)))
          (should-not (let ((eglot-lsp-context nil))
                        (surge-eglot-project root)))
          (let ((project (let ((eglot-lsp-context t))
                           (surge-eglot-project root))))
            (should (eq (car project) 'surge-eglot))
            (should (equal (project-root project)
                           (file-name-as-directory
                            (file-truename root)))))
          (should-not (let ((eglot-lsp-context t))
                        (surge-eglot-project outside))))
      (delete-directory root t)
      (delete-directory outside t))))

(ert-deftest surge-eglot-server-contact-is-deterministic ()
  (cl-letf (((symbol-function 'executable-find)
             (lambda (_program) "/tmp/surge-cli"))
            ((symbol-function 'file-executable-p)
             (lambda (_file) t)))
    (should (equal (surge-eglot-server-contact nil nil)
                   '("/tmp/surge-cli" "lsp" "--stdio"))))
  (cl-letf (((symbol-function 'executable-find) #'ignore)
            ((symbol-function 'file-executable-p) (lambda (_file) t)))
    (should (equal (surge-eglot-server-contact nil nil)
                   (list surge-eglot--bundled-cli "lsp" "--stdio"))))
  (cl-letf (((symbol-function 'executable-find) #'ignore)
            ((symbol-function 'file-executable-p) #'ignore))
    (should-error (surge-eglot-server-contact nil nil)
                  :type 'user-error)))

(ert-deftest surge-eglot-setup-is-idempotent ()
  (let ((example (locate-library "surge-eglot")))
    (should example)
    (load example nil t)
    (should (= (cl-count surge-eglot--languages eglot-server-programs
                         :key #'car :test #'equal)
               1))
    (should (= (cl-count #'surge-eglot-project project-find-functions)
               1))
    (should (= (cl-count #'eglot-ensure surge-conf-mode-hook)
               1))))

(provide 'surge-eglot-test)
;;; surge-eglot-test.el ends here
