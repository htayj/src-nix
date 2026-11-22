;;; mail-tests.el --- Mail signing policy checks -*- lexical-binding: t; -*-

;; Run from the repository root:
;; agent-job -- emacs --batch -l home/emacs/mail.el -l home/emacs/mail-tests.el \
;;   -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'message)
(require 'mml)

(defmacro tay-test/with-message (headers body &rest forms)
  "Evaluate FORMS in a temporary message with HEADERS and BODY."
  (declare (indent 2))
  `(with-temp-buffer
     (message-mode)
     (insert "From: Taylor Hardy <tay@nogroup.group>\nSubject: Local policy check\n"
             ,headers "\n" mail-header-separator "\n" ,body)
     (goto-char (point-max))
     ,@forms))

(ert-deftest tay/mail-signs-internal-recipients ()
  (dolist (headers '("To: member@nogroup.group"
                     "To: outside@example.org\nCc: member@nogroup.group"
                     "To: outside@example.org\nBcc: member@nogroup.group"
                     "To: Member <member@NOGROUP.GROUP>"
                     "To: member+tag@nogroup.group"
                     "To: Friends: Outside <outside@example.org>,\n Member <member@nogroup.group>;"
                     "To: outside@example.org\nTo: member@nogroup.group"))
    (ert-info ((format "Recipient headers: %s" headers))
      (tay-test/with-message headers "A local test message.\n"
        (run-hooks 'message-send-hook)
        (message-goto-body)
        (should (looking-at "<#secure method=pgpmime mode=sign>"))
        ;; Retrying a send must not accumulate security directives.
        (let ((once (buffer-string)))
          (run-hooks 'message-send-hook)
          (should (equal once (buffer-string))))))))

(ert-deftest tay/mail-leaves-external-mail-and-news-alone ()
  (dolist (headers '("To: outside@example.org"
                     "To: \"member@nogroup.group\" <outside@example.org>"
                     "To: member@nogroup.group.example.org"
                     "To: member@sub.nogroup.group"
                     "Newsgroups: comp.lang.lisp"))
    (ert-info ((format "Recipient headers: %s" headers))
      (tay-test/with-message headers "To: body-only@nogroup.group\n"
        (let ((before (buffer-string)))
          (run-hooks 'message-send-hook)
          (should (equal before (buffer-string))))))))

(ert-deftest tay/mail-preserves-encryption-and-explicit-key-options ()
  (tay-test/with-message "To: member@nogroup.group"
      (concat "<#secure method=pgpmime mode=\"encrypt\""
              " recipients=\"KEY1 KEY2\" sender=SIGNING-KEY>\nPrivate body.\n")
    (run-hooks 'message-send-hook)
    (message-goto-body)
    (let ((tag (with-syntax-table mml-syntax-table (mml-read-tag))))
      (should (equal (cdr (assq 'mode tag)) "signencrypt"))
      (should (equal (cdr (assq 'method tag)) "pgpmime"))
      (should (equal (cdr (assq 'recipients tag)) "KEY1 KEY2"))
      (should (equal (cdr (assq 'sender tag)) "SIGNING-KEY")))
    (should (search-forward "Private body." nil t))))

(ert-deftest tay/mail-preserves-existing-signatures ()
  (dolist (mode '("sign" "signencrypt"))
    (tay-test/with-message "To: member@nogroup.group"
        (format "<#secure method=pgpmime mode=%s sender=SIGNING-KEY>\nBody.\n" mode)
      (let ((before (buffer-string)))
        (run-hooks 'message-send-hook)
        (should (equal before (buffer-string)))))))

(ert-deftest tay/mail-stops-before-delivery-if-signing-fails ()
  (tay-test/with-message "To: member@nogroup.group" "Local failure check.\n"
    (let ((delivered nil)
          (message-confirm-send nil)
          (message-send-mail-function (lambda () (setq delivered t))))
      (cl-letf (((symbol-function 'mml-secure-epg-sign)
                 (lambda (&rest _) (error "Test signing failure"))))
        (should (equal (error-message-string (should-error (message-send)))
                       "Test signing failure"))
        (should-not delivered)))))

;;; mail-tests.el ends here
