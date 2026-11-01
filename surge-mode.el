;;; surge-mode.el --- Edit Surge configuration files -*- lexical-binding: t; -*-

;; Copyright (C) 2026 surge-mode contributors
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages, comm

;;; Commentary:

;; Independent editing modes for Surge profiles, modules and rule sets.
;; Language server integration is optional; see examples/lsp-bridge/.
;; This file is not derived from the Surge VS Code extension.

;;; Code:

(require 'imenu)

(defvar font-lock-end)

(defgroup surge nil
  "Edit Surge configuration files."
  :group 'languages)

(defcustom surge-project-roots nil
  "Directories that contain Surge configuration projects.
Each directory must represent one coherent Surge workspace.  Files with
ambiguous `.conf' and `.dconf' suffixes use Surge mode only inside these
directories.  Optional language-server clients can also use the matching
root to share one server and limit recursive file watching."
  :type '(repeat directory)
  :group 'surge)

;;;###autoload
(defun surge-project-root (file)
  "Return the most specific configured Surge project root containing FILE."
  (when (and file (not (file-remote-p file)))
    (let ((path (file-truename (expand-file-name file)))
          best)
      (dolist (root surge-project-roots best)
        (let ((candidate
               (directory-file-name
                (file-truename (expand-file-name root)))))
          (when (and (file-in-directory-p path candidate)
                     (or (null best)
                         (> (length candidate) (length best))))
            (setq best candidate)))))))

(defconst surge--section-regexp "^[ \t]*\\[\\([^]\n]+\\)\\][ \t]*\\(?:[#;/]\\|$\\)"
  "Regexp matching a section header, with its name in group one.")

(defvar surge-conf-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; Delimiters are context dependent: URLs and regex quotes stay ordinary.
    (modify-syntax-entry ?\" "." table)
    (modify-syntax-entry ?\\ "\\" table)
    (modify-syntax-entry ?\n ">" table)
    (dolist (char '(?# ?\; ?/ ?\[ ?\] ?\( ?\) ?{ ?} ?'))
      (modify-syntax-entry char "." table))
    table)
  "Syntax table shared by Surge modes.")

(defun surge--syntax-propertize (start end)
  "Mark line-bounded strings and comments between START and END."
  (goto-char start)
  (while (re-search-forward "\"\\|[#;]\\|//\\|\n" end t)
    (let* ((pos (match-beginning 0))
           (quote-p (eq (char-after pos) ?\"))
           (state (save-excursion (syntax-ppss pos))))
      (cond
       ((eq (char-after pos) ?\n)
        (when (nth 3 state)
          ;; The official profile parser treats these fields as physical lines.
          (when (nth 5 state)
            (put-text-property (1- pos) pos 'syntax-table (string-to-syntax ".")))
          (put-text-property pos (1+ pos) 'syntax-table (string-to-syntax "|"))))
       ((or (nth 4 state) (nth 5 state)))
       (quote-p
        (when (or (nth 3 state)
                  (save-excursion
                    (goto-char pos)
                    (skip-chars-backward " \t" (line-beginning-position))
                    (or (bolp) (memq (char-before) '(?= ?,)))))
          (put-text-property pos (1+ pos) 'syntax-table
                             (string-to-syntax "|"))))
       ((and (not (nth 3 state))
             (or (= pos (line-beginning-position))
                 (memq (char-before pos) '(?\s ?\t))))
        (put-text-property pos (1+ pos) 'syntax-table
                           (string-to-syntax "<")))))))

(defun surge--section-at (pos)
  "Return the section name at POS, or nil before the first section."
  (save-excursion
    (goto-char pos)
    (let ((case-fold-search t))
      (when (re-search-backward surge--section-regexp nil t)
        (downcase (match-string-no-properties 1))))))

(defun surge--match-key (limit)
  "Find an assignment key before LIMIT outside rule sections and comments."
  (catch 'found
    (while (re-search-forward "^[ \t]*\\([^#;/[ \t\n=][^=\n]*?\\)[ \t]*=" limit t)
      (let ((begin (match-beginning 1)))
        (when (and (not (derived-mode-p 'surge-ruleset-mode))
                   (not (member (save-match-data (surge--section-at begin))
                                '("rule")))
                   (not (nth 8 (save-excursion (syntax-ppss begin)))))
          (throw 'found t))))))

(defun surge--match-rule (limit)
  "Find a rule type before LIMIT in a Rule section or rule set."
  (catch 'found
    (while (re-search-forward "^[ \t]*\\([A-Z][A-Z0-9-]*\\)[ \t]*\\(?:,\\|$\\)" limit t)
      (let ((begin (match-beginning 1)))
        (when (and (or (derived-mode-p 'surge-ruleset-mode)
                       (equal (save-match-data (surge--section-at begin)) "rule"))
                   (not (nth 8 (save-excursion (syntax-ppss begin)))))
          (throw 'found t))))))

(defconst surge--font-lock-keywords
  `((,surge--section-regexp (1 font-lock-type-face))
    (surge--match-key (1 font-lock-variable-name-face))
    (surge--match-rule (1 font-lock-keyword-face)))
  "Section-aware highlighting without validating Surge syntax.")

;;;###autoload
(define-derived-mode surge-conf-mode prog-mode "Surge"
  "Major mode for Surge configuration profiles.
Highlight sections, assignment keys and rule types.  Comment syntax is
recognized at line start or after whitespace, outside double-quoted strings.
Validation is provided separately by the optional official language server."
  :syntax-table surge-conf-mode-syntax-table
  (setq-local font-lock-defaults '(surge--font-lock-keywords nil nil))
  (setq-local syntax-propertize-function #'surge--syntax-propertize)
  (add-hook 'syntax-propertize-extend-region-functions
            #'syntax-propertize-wholelines nil t)
  (setq-local comment-start "# ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "\\(?:#+\\|;+\\|//+\\)[ \t]*")
  (setq-local parse-sexp-ignore-comments t)
  (setq-local indent-line-function #'indent-relative)
  (setq-local imenu-generic-expression `((nil ,surge--section-regexp 1)))
  ;; A section change can alter the meaning of every following line.
  (setq-local font-lock-extend-region-functions '(surge--font-lock-extend)))

(defun surge--font-lock-extend ()
  "Extend fontification to the buffer end after a section may have changed."
  (when (< font-lock-end (point-max))
    (setq font-lock-end (point-max))
    t))

;;;###autoload
(define-derived-mode surge-module-mode surge-conf-mode "Surge Module"
  "Major mode for Surge modules.")

;;;###autoload
(define-derived-mode surge-ruleset-mode surge-conf-mode "Surge Ruleset"
  "Major mode for Surge RULE-SET files, not DOMAIN-SET files.")

;;;###autoload
(defun surge--project-conf-p ()
  "Return non-nil when the current ambiguous config belongs to Surge."
  (and buffer-file-name
       (string-match-p "\\.\\(?:conf\\|dconf\\)\\'" buffer-file-name)
       (surge-project-root buffer-file-name)))

;;;###autoload
(add-to-list 'magic-mode-alist '(surge--project-conf-p . surge-conf-mode))
;; Remove the former global `.dconf' association when reloading this file.
(setq auto-mode-alist
      (delete '("\\.\\(?:sgconf\\|dconf\\)\\'" . surge-conf-mode)
              auto-mode-alist))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.sgconf\\'" . surge-conf-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.sgmodule\\'" . surge-module-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\(?:\\`\\|/\\)Surge\\.conf\\'" . surge-conf-mode))

(provide 'surge-mode)
;;; surge-mode.el ends here
