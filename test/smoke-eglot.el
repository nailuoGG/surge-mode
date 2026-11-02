;;; smoke-eglot.el --- Synthetic official-server smoke test -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later
(require 'surge-eglot)

(let* ((directory (make-temp-file "surge-mode-smoke-" t))
       (file (expand-file-name "Surge.conf" directory))
       (surge-project-roots (list directory))
       ;; Isolate the smoke buffer from user hooks that may start another
       ;; language client.  This script starts Eglot explicitly below.
       (prog-mode-hook nil)
       (surge-conf-mode-hook nil)
       (eglot-sync-connect 10)
       (eglot-connect-timeout 10)
       (eglot-autoshutdown t)
       buffer
       server)
  (unwind-protect
      (with-current-buffer (setq buffer (find-file-noselect file))
        (insert "[General]\nunknown-general-key = true\n[Rule]\nFINAL,DIRECT\n")
        (save-buffer)
        (call-interactively #'eglot)
        (setq server (eglot-current-server))
        (flymake-start)
        ;; Trigger one post-connection change after Eglot has registered the
        ;; buffer and Flymake backend.  The server can publish diagnostics for
        ;; didOpen before that setup is complete in a fast local session.
        (goto-char (point-max))
        (insert "# smoke refresh\n")
        (save-buffer)
        (let ((deadline (+ (float-time) 15))
              diagnostics
              found)
          (while (and (< (float-time) deadline) (not found))
            (setq diagnostics (flymake-diagnostics)
                  found (seq-some
                         (lambda (diagnostic)
                           (string-match-p
                            "unknown-general-key"
                            (flymake-diagnostic-text diagnostic)))
                         diagnostics))
            (unless found
              (accept-process-output nil 0.1)))
          (unless (and (eglot-managed-p) found)
            (error "Expected official unknown-key diagnostic: %S" diagnostics))
          (princ (format "MANAGED=%S MODE=%S DIAGNOSTICS=%S\n"
                         (eglot-managed-p) major-mode
                         (mapcar #'flymake-diagnostic-text diagnostics)))))
    (unless server
      (setq server (and (buffer-live-p buffer)
                        (with-current-buffer buffer
                          (ignore-errors (eglot-current-server))))))
    (when server
      (ignore-errors (eglot-shutdown server)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (set-buffer-modified-p nil))
      (kill-buffer buffer))
    (delete-directory directory t)))
