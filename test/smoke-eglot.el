;;; smoke-eglot.el --- Synthetic official-server smoke test -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later
(require 'surge-mode)
(require 'eglot)

(let* ((directory (make-temp-file "surge-mode-smoke-" t))
       (file (expand-file-name "Surge.conf" directory))
       (eglot-server-programs
        '(((surge-conf-mode :language-id "surge") . ("/Applications/Surge.app/Contents/Applications/surge-cli"
                              "lsp" "--stdio"))))
       (eglot-sync-connect 10)
       (eglot-connect-timeout 10)
       (eglot-autoshutdown t))
  (unwind-protect
      (with-current-buffer (find-file-noselect file)
        (insert "[General]\nunknown-general-key = true\n[Rule]\nFINAL,DIRECT\n")
        (save-buffer)
        (surge-conf-mode)
        (call-interactively #'eglot)
        (flymake-start)
        (let ((deadline (+ (float-time) 15)))
          (while (and (< (float-time) deadline)
                      (not (flymake-diagnostics)))
            (accept-process-output nil 0.1)))
        (let ((diagnostics (flymake-diagnostics)))
          (unless (and (eglot-managed-p)
                       (seq-some (lambda (diagnostic)
                                   (string-match-p "unknown-general-key"
                                                   (flymake-diagnostic-text diagnostic)))
                                 diagnostics))
            (error "Expected official unknown-key diagnostic: %S" diagnostics))
          (princ (format "MANAGED=%S MODE=%S DIAGNOSTICS=%S\n"
                         (eglot-managed-p) major-mode
                         (mapcar #'flymake-diagnostic-text diagnostics))))
        (eglot-shutdown (eglot-current-server))
        (kill-buffer))
    (delete-directory directory t)))
