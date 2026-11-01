;;; surge-mode-test.el --- Editing boundary tests -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later
(require 'ert)
(require 'surge-mode)

(defmacro surge-test--with (mode text &rest body)
  "Run BODY after enabling MODE and fontifying TEXT."
  (declare (indent 2))
  `(with-temp-buffer
     (insert ,text)
     (,mode)
     (font-lock-ensure)
     (goto-char (point-min))
     ,@body))

(defun surge-test--state (text)
  "Return syntax state immediately after TEXT in the current buffer."
  (goto-char (point-min))
  (search-forward text)
  (syntax-ppss))

(defun surge-test--auto-mode-for-file (file)
  "Return the automatically selected major mode for FILE without user hooks."
  (with-temp-buffer
    (setq buffer-file-name file)
    (let ((after-change-major-mode-hook nil)
          (change-major-mode-hook nil)
          (conf-mode-hook nil)
          (prog-mode-hook nil)
          (surge-conf-mode-hook nil))
      (set-auto-mode)
      major-mode)))

(ert-deftest surge-comments-strings-and-urls ()
  (surge-test--with surge-conf-mode
      "[General]\nurl = https://example.invalid/a#b\nname = \"a # b // c\" # comment\n// line\n# line\n"
    (should-not (nth 8 (surge-test--state "https://example.invalid/a#b")))
    (should (nth 3 (surge-test--state "a # b //")))
    (should (nth 4 (surge-test--state "# comment")))
    (should (nth 4 (surge-test--state "// line")))
    (should (nth 4 (surge-test--state "# line")))))

(ert-deftest surge-escaped-quote-and-comment-edit ()
  (surge-test--with surge-conf-mode "x = \"a \\\" # b\"\n# comment\n"
    (should (nth 3 (surge-test--state "# b")))
    (should (nth 4 (surge-test--state "# comment")))
    (goto-char (point-min))
    (forward-line 1)
    (delete-char 1)
    (syntax-propertize (point-max))
    (should-not (nth 4 (surge-test--state "comment")))))

(ert-deftest surge-section-aware-highlighting ()
  (surge-test--with surge-conf-mode
      "[General]\nloglevel = notify\nDOMAIN,not-a-rule\n[Rule]\nURL-REGEX,^https://example.invalid/(a|b),DIRECT\nAND,((DOMAIN,a),(DOMAIN,b)),DIRECT\n[Script]\njob = type=http-request,pattern=^https://example.invalid/(a),script-path=x.js\n"
    (search-forward "loglevel")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-variable-name-face))
    (search-forward "DOMAIN")
    (should-not (get-text-property (1- (point)) 'face))
    (search-forward "URL-REGEX")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-keyword-face))
    (search-forward "AND")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-keyword-face))
    (search-forward "job")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-variable-name-face))
    (should-not (nth 4 (surge-test--state "script-path")))))

(ert-deftest surge-ruleset-without-sections ()
  (surge-test--with surge-ruleset-mode "DOMAIN,example.invalid\nDOMAIN-SUFFIX,example.invalid\n"
    (search-forward "DOMAIN")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-keyword-face))))

(ert-deftest surge-module-metadata-and-imenu ()
  (surge-test--with surge-module-mode "#!name=Demo\n[General]\nloglevel = notify\n[Rule]\nFINAL,DIRECT\n"
    (should (nth 4 (surge-test--state "#!name")))
    (should (equal (mapcar #'car (imenu--generic-function imenu-generic-expression)) '("General" "Rule")))))

(ert-deftest surge-conservative-file-associations ()
  (dolist (case '(("a.sgconf" surge-conf-mode)
                  ("a.sgmodule" surge-module-mode)
                  ("Surge.conf" surge-conf-mode)
                  ("ordinary.conf" nil)
                  ("a.dconf" nil)
                  ("rules.list" nil)
                  ("rules.txt" nil)))
    (let ((mode (assoc-default (car case) auto-mode-alist #'string-match)))
      (if (cadr case)
          (should (eq mode (cadr case)))
        (should-not (memq mode '(surge-conf-mode surge-module-mode surge-ruleset-mode)))))))

(ert-deftest surge-project-root-prefers-the-most-specific-match ()
  (let* ((outer (make-temp-file "surge-project-" t))
         (inner (expand-file-name "nested" outer))
         (file (expand-file-name "profile.conf" inner)))
    (unwind-protect
        (progn
          (make-directory inner)
          (write-region "" nil file nil 'silent)
          (let ((surge-project-roots (list outer inner)))
            (should (equal (surge-project-root file)
                           (directory-file-name (file-truename inner))))))
      (delete-directory outer t))))

(ert-deftest surge-project-roots-limit-ambiguous-config-associations ()
  (let ((root (make-temp-file "surge-project-" t))
        (other (make-temp-file "surge-other-" t)))
    (unwind-protect
        (let ((surge-project-roots (list root)))
          (dolist (name '("profile.conf" "fragment.dconf"))
            (let ((inside (expand-file-name name root))
                  (outside (expand-file-name name other)))
              (write-region "" nil inside nil 'silent)
              (write-region "" nil outside nil 'silent)
              (should (eq (surge-test--auto-mode-for-file inside)
                          'surge-conf-mode))
              (should-not (memq (surge-test--auto-mode-for-file outside)
                                '(surge-conf-mode surge-module-mode
                                  surge-ruleset-mode))))))
      (delete-directory root t)
      (delete-directory other t))))

(ert-deftest surge-project-root-rejects-symlink-escape ()
  (let ((root (make-temp-file "surge-project-" t))
        (other (make-temp-file "surge-other-" t)))
    (unwind-protect
        (let* ((target (expand-file-name "external.conf" other))
               (link (expand-file-name "linked.conf" root))
               (surge-project-roots (list root)))
          (write-region "" nil target nil 'silent)
          (condition-case nil
              (make-symbolic-link target link)
            (file-error (ert-skip "Symbolic links are unavailable")))
          (should-not (surge-project-root link))
          (with-temp-buffer
            (setq buffer-file-name link)
            (should-not (surge--project-conf-p))))
      (delete-directory root t)
      (delete-directory other t))))

(ert-deftest surge-comment-region-round-trip ()
  (surge-test--with surge-conf-mode "[Rule]\nFINAL,DIRECT\n"
    (let ((before (buffer-string)))
      (comment-region (point-min) (point-max))
      (should (nth 4 (surge-test--state "[Rule]")))
      (uncomment-region (point-min) (point-max))
      (should (equal (buffer-string) before)))))

(ert-deftest surge-section-edit-refontifies-rules ()
  (surge-test--with surge-conf-mode "[Rule]\nDOMAIN,example.invalid,DIRECT\n"
    (search-forward "DOMAIN")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-keyword-face))
    (goto-char (point-min))
    (search-forward "Rule")
    (replace-match "Host")
    (font-lock-flush (point-min) (line-end-position))
    (font-lock-ensure (point-min) (line-end-position))
    (search-forward "DOMAIN")
    (should-not (get-text-property (1- (point)) 'face))))

(ert-deftest surge-regex-literal-quotes-do-not-open-strings ()
  (surge-test--with surge-conf-mode
      "[Rule]\nURL-REGEX,^https://example.invalid/[\"],DIRECT\n# after regex\n[Script]\njob = type=http-request,pattern=[\"],script-path=x.js\n# after script\n"
    (should-not (nth 3 (surge-test--state "DIRECT")))
    (should (nth 4 (surge-test--state "# after regex")))
    (should-not (nth 3 (surge-test--state "script-path")))
    (should (nth 4 (surge-test--state "# after script")))))

(ert-deftest surge-semicolon-comments-sections-and-values ()
  (surge-test--with surge-conf-mode
      "; leading\n[General] ; section comment\nurl = https://example.invalid/a;b\nname = \"a ; b\" ; trailing\n[Rule] ; rules\nDOMAIN,example.invalid,DIRECT\n"
    (should (nth 4 (surge-test--state "; leading")))
    (should-not (nth 8 (surge-test--state "a;b")))
    (should (nth 3 (surge-test--state "a ; b")))
    (should (nth 4 (surge-test--state "; trailing")))
    (should (equal (mapcar #'car (imenu--generic-function imenu-generic-expression))
                   '("General" "Rule")))
    (goto-char (point-min))
    (search-forward "DOMAIN")
    (should (equal (surge--section-at (point)) "rule"))
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-keyword-face))
    (goto-char (point-min))
    (uncomment-region (line-beginning-position) (line-end-position))
    (should (looking-at "leading"))))

(ert-deftest surge-unclosed-field-string-recovers-at-newline ()
  (dolist (ending '("" "\\"))
    (surge-test--with surge-conf-mode
        (concat "[General]\nname = \"unfinished" ending
                "\n[Rule]\nDOMAIN,example.invalid,DIRECT\n# after field\n")
      (should (nth 3 (surge-test--state "unfinished")))
      (goto-char (point-min))
      (search-forward "DOMAIN")
      (should-not (nth 3 (syntax-ppss)))
      (should (eq (get-text-property (1- (point)) 'face) 'font-lock-keyword-face))
      (should (nth 4 (surge-test--state "# after field"))))))

(provide 'surge-mode-test)
;;; surge-mode-test.el ends here
