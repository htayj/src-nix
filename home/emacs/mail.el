;;; mail.el --- Gnus mail and Usenet -*- lexical-binding: t; -*-

(require 'auth-source)
(require 'cl-lib)
(require 'subr-x)

(defun tay/gnus-rbw-secret (&optional entry)
  "Read Vaultwarden ENTRY without saving it; default to the mail account."
  (unless (executable-find "rbw")
    (user-error "Gnus needs rbw from the Home Manager profile"))
  (with-temp-buffer
    ;; Capture stdout in this temporary buffer and discard stderr. The password
    ;; never appears in arguments, config files, the kill ring or the echo area.
    (unless (eq 0 (call-process
                   "rbw" nil (list (current-buffer) nil) nil
                   "get" "--" (or entry "c399a1ca-8592-4718-af8d-83ee4b01ef04")))
      (user-error "Cannot read Gnus credential; run rbw unlock and rbw sync"))
    (let ((secret (string-remove-suffix "\n" (buffer-string))))
      (when (string-empty-p secret)
        (user-error "The Gnus credential in Vaultwarden is empty"))
      secret)))

(cl-defun tay/gnus-rbw-search (&rest _spec &key host user port require delete
                                   &allow-other-keys)
  "Supply the mail credential only for this account's encrypted endpoints."
  (let ((matching-port
         (cl-find-if (lambda (value) (member value '(993 "993" "imaps"
                                                   465 "465" "smtps")))
                     (ensure-list port))))
    (when (and (not delete)
               (member "mail.nogroup.group" (ensure-list host))
               (or (null user)
                   (member "tay@nogroup.group" (ensure-list user)))
               matching-port
               ;; TLS client-certificate lookups must not receive a password.
               (cl-subsetp require '(:host :port :user :secret)))
      (list (list :host "mail.nogroup.group"
                  :port (format "%s" matching-port)
                  :user "tay@nogroup.group"
                  :secret #'tay/gnus-rbw-secret)))))

(cl-defun tay/gnus-eternal-rbw-search (&rest _spec &key host user port require delete
                                           &allow-other-keys)
  "Supply the Eternal September credential for its TLS endpoint."
  (when (and (not delete)
             (member "news.eternal-september.org" (ensure-list host))
             (or (null user) (member "htayj" (ensure-list user)))
             (cl-intersection (ensure-list port) '(563 "563" "nntps" "snews")
                              :test #'equal)
             (cl-subsetp require '(:host :port :user :secret :force)))
    (list (list :host "news.eternal-september.org" :port "563" :user "htayj"
                :force t
                :secret (lambda ()
                          (tay/gnus-rbw-secret
                           "a5f736ba-36a9-4658-9462-2f51a461aa0e"))))))

(defun tay/gnus-rbw-backend (entry)
  "Recognize account-specific auth-source ENTRY."
  (pcase entry
    ('tay-nogroup-rbw
     (auth-source-backend :source "Vaultwarden (nogroup mail)"
                          :type 'tay-nogroup-rbw
                          :host "mail.nogroup.group"
                          :search-function #'tay/gnus-rbw-search))
    ('tay-eternal-rbw
     (auth-source-backend :source "Vaultwarden (Eternal September)"
                          :type 'tay-eternal-rbw
                          :host "news.eternal-september.org"
                          :search-function #'tay/gnus-eternal-rbw-search))))

(add-hook 'auth-source-backend-parser-functions #'tay/gnus-rbw-backend)
(add-to-list 'auth-sources 'tay-nogroup-rbw)
(add-to-list 'auth-sources 'tay-eternal-rbw)

(setq user-full-name "Taylor Hardy"
      user-mail-address "tay@nogroup.group"
      mail-user-agent 'gnus-user-agent
      read-mail-command 'gnus
      send-mail-function 'smtpmail-send-it
      message-send-mail-function 'smtpmail-send-it
      smtpmail-smtp-server "mail.nogroup.group"
      smtpmail-default-smtp-server "mail.nogroup.group"
      smtpmail-smtp-service 465
      smtpmail-stream-type 'tls
      smtpmail-smtp-user "tay@nogroup.group"
      message-sendmail-envelope-from 'header
      ;; This account uses implicit TLS, with certificate verification.
      gnutls-verify-error t
      ;; EasyPG uses the existing GnuPG keyring and graphical gpg-agent prompt.
      mm-verify-option 'known
      mm-decrypt-option 'known
      mml-secure-openpgp-sign-with-sender t
      ;; Include the From identity's key so encrypted sent copies stay readable.
      mml-secure-openpgp-encrypt-to-self t
      gnus-select-method '(nnnil "")
      gnus-secondary-select-methods
      '((nnimap "nogroup"
                (nnimap-address "mail.nogroup.group")
                (nnimap-server-port 993)
                (nnimap-stream tls)
                (nnimap-user "tay@nogroup.group")))
      gnus-auto-subscribed-groups "\\`nnimap\\+nogroup:"
      gnus-message-archive-method (car gnus-secondary-select-methods)
      gnus-message-archive-group "Sent Items"
      gnus-gcc-mark-as-read t
      ;; Use the normal completion UI (including Corfu) for address headers.
      message-mail-alias-type 'ecomplete
      message-expand-name-standard-ui t
      message-self-insert-commands nil
      gnus-thread-sort-functions
      '(gnus-thread-sort-by-number gnus-thread-sort-by-most-recent-date)
      gnus-article-sort-functions
      '(gnus-article-sort-by-number (not gnus-article-sort-by-date))
      gnus-directory
      (expand-file-name "gnus/" (or (getenv "XDG_DATA_HOME")
                                    (expand-file-name "~/.local/share/")))
      gnus-startup-file (expand-file-name "newsrc" gnus-directory)
      message-directory (expand-file-name "Mail/" gnus-directory))

(add-to-list 'gnus-secondary-select-methods
             '(nntp "eternal-september"
                    (nntp-address "news.eternal-september.org")
                    (nntp-port-number 563)
                    (nntp-open-connection-function nntp-open-tls-stream)
                    (nntp-authinfo-user "htayj")
                    (nntp-authinfo-force t))
             t)

;; Include read messages when entering mail folders and Usenet groups normally.
(with-eval-after-load 'gnus
  (add-to-list 'gnus-parameters '(".*" (display . all)) t))

;; Keep the signature/decryption status visible when rendering message bodies.
(with-eval-after-load 'gnus-art
  (dolist (type '("multipart/signed" "multipart/encrypted"))
    (add-to-list 'gnus-buttonized-mime-types type)))

(defun tay/message-sign-internal-mail ()
  "Require signing when any To, Cc or Bcc recipient is at nogroup.group."
  (when (let ((case-fold-search t))
          (cl-some
           (lambda (header)
             (when-let* ((value (message-field-value header)))
               (cl-some
                (lambda (address)
                  (string-match-p "@nogroup\\.group\\'" (car address)))
                (mail-header-parse-addresses value))))
           '("To" "Cc" "Bcc")))
    (require 'mml)
    (save-excursion
      (message-goto-body)
      (skip-chars-forward " \t\n")
      (if (not (looking-at "<#secure\\_>"))
          (mml-secure-message-sign-pgpmime)
        (let* ((start (point))
               (tag (with-syntax-table mml-syntax-table (mml-read-tag)))
               (mode (assq 'mode (cdr tag))))
          (cond
           ((member (cdr mode) '("sign" "signencrypt")))
           ((equal (cdr mode) "encrypt")
            ;; Retain the encryption method and any explicit key selections.
            (setcdr mode "signencrypt")
            (let ((attributes
                   (cl-loop for (key . value) in (cdr tag)
                            unless (eq key 'tag-location)
                            append (list key value))))
              (delete-region start (point))
              (apply #'mml-insert-tag 'secure attributes)))
           (t (user-error "Internal mail needs a valid signing mode"))))))))

(with-eval-after-load 'message
  (add-hook 'message-send-hook #'tay/message-sign-internal-mail t)
  ;; Partial completion can mistake a short name for a domain component.
  (setf (alist-get 'email completion-category-overrides)
        '((styles basic substring)))
  (add-hook 'message-mode-hook
            (lambda () (setq-local completion-ignore-case t))))

;; Subscriptions, drafts and Gnus state are mutable and stay outside Nix.
(make-directory gnus-directory t)
(set-file-modes gnus-directory #o700)

;; Seed the built-in address history; successful sends teach it new contacts.
;; Keep learned contacts and usage counts when reloading the configuration.
(require 'ecomplete)
(setq ecomplete-database-file (expand-file-name "addresses.eld" gnus-directory))
(ecomplete-setup)
(let ((added nil))
  (dolist (address '("bubu@nogroup.group" "chryso@nogroup.group"
                     "donk@nogroup.group" "gronk@nogroup.group"))
    (unless (assoc address (cdr (assq 'mail ecomplete-database)))
      (ecomplete-add-item 'mail address address)
      (setq added t)))
  (when added (ecomplete-save)))

(global-set-key (kbd "C-c g") #'gnus)

(provide 'tay-gnus-mail)
;;; mail.el ends here
