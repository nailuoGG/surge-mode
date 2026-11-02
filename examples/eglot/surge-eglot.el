;;; surge-eglot.el --- Optional Surge Eglot setup -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Load after installing surge-mode.  This example configures Eglot in memory;
;; it does not edit your init file.  `surge-project-roots' controls project
;; sharing without changing project.el behavior outside Eglot.

;;; Code:

(require 'eglot)
(require 'project)
(require 'surge-mode)

(defconst surge-eglot--bundled-cli
  "/Applications/Surge.app/Contents/Applications/surge-cli"
  "Path to the command-line tool bundled with Surge Mac.")

(defun surge-eglot-server-contact (_interactive _project)
  "Return the command that starts the official Surge language server."
  (let ((program (or (executable-find "surge-cli")
                     (and (file-executable-p surge-eglot--bundled-cli)
                          surge-eglot--bundled-cli))))
    (unless program
      (user-error "Cannot find surge-cli in PATH or Surge.app"))
    (list program "lsp" "--stdio")))

(defconst surge-eglot--languages
  '((surge-conf-mode :language-id "surge")
    (surge-module-mode :language-id "surge-module")
    (surge-ruleset-mode :language-id "surge-ruleset"))
  "Surge modes and their official language identifiers.")

(defun surge-eglot-project (directory)
  "Return a Surge Eglot project for DIRECTORY, or nil.
Only participate while Eglot is looking for a language-server project."
  (when (bound-and-true-p eglot-lsp-context)
    (let ((root (surge-project-root directory)))
      (when root
        (cons 'surge-eglot root)))))

(cl-defmethod project-root ((project (head surge-eglot)))
  (file-name-as-directory (cdr project)))

(add-hook 'project-find-functions #'surge-eglot-project -50)
(add-to-list 'eglot-server-programs
             (cons surge-eglot--languages #'surge-eglot-server-contact))
(add-hook 'surge-conf-mode-hook #'eglot-ensure)

(provide 'surge-eglot)
;;; surge-eglot.el ends here
