;;; surge-lsp-bridge.el --- Optional Surge client setup -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Load after installing surge-mode and lsp-bridge.  Recent lsp-bridge versions
;; can provide the Surge server config; otherwise copy surge.json to
;; `lsp-bridge-user-langserver-dir'.  This example configures the client in
;; memory; it does not edit your init file.

;;; Code:

(require 'surge-mode)
(require 'lsp-bridge)

(defvar surge-lsp-bridge--previous-language-id lsp-bridge-get-language-id
  "Language ID callback used before the Surge example was loaded.")

(defvar surge-lsp-bridge--previous-project-root
  lsp-bridge-get-project-path-by-filepath
  "Project-root callback used before the Surge example was loaded.")

(defun surge-lsp-bridge-project-root (file-path)
  "Return the configured Surge root for FILE-PATH, otherwise delegate."
  (or (surge-project-root file-path)
      (let ((lsp-bridge-get-project-path-by-filepath
             surge-lsp-bridge--previous-project-root))
        (lsp-bridge--get-project-path-func file-path))))

(defun surge-lsp-bridge-language-id
    (project-path file-path lsp-server-name extension-name)
  "Resolve Surge IDs from FILE-PATH's mode, otherwise delegate.
Pass PROJECT-PATH, LSP-SERVER-NAME and EXTENSION-NAME to the original resolver
when this is not a Surge document, retaining its built-in fallback."
  (or (when (equal lsp-server-name "surge")
        (let ((buffer (lsp-bridge-get-match-buffer-by-filepath file-path)))
          (when (buffer-live-p buffer)
            (with-current-buffer buffer
              (pcase major-mode
                ('surge-conf-mode "surge")
                ('surge-module-mode "surge-module")
                ('surge-ruleset-mode "surge-ruleset"))))))
      (let ((lsp-bridge-get-language-id surge-lsp-bridge--previous-language-id))
        (lsp-bridge--get-language-id-func
         project-path file-path lsp-server-name extension-name))))

(dolist (mode '(surge-conf-mode surge-module-mode surge-ruleset-mode))
  (setf (alist-get mode lsp-bridge-single-lang-server-mode-list) "surge"))
(setq lsp-bridge-get-project-path-by-filepath
      #'surge-lsp-bridge-project-root)
(setq lsp-bridge-get-language-id #'surge-lsp-bridge-language-id)
(add-hook 'surge-conf-mode-hook #'lsp-bridge-mode)

(provide 'surge-lsp-bridge)
;;; surge-lsp-bridge.el ends here
