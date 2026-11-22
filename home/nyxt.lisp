(in-package :nyxt-user)

;; Nyxt's asynchronous navigation handler promotes warnings to errors.  These
;; overrides are intentional: muffle only this warning while constructing maps,
;; including when middle-click creates another buffer.
(defmacro with-personal-key-overrides (&body body)
  `(handler-bind ((nkeymaps/conditions:override-existing-binding #'muffle-warning))
     ,@body))

(define-configuration context-buffer
  ((search-engines
    (append (remove "google" %slot-value% :key #'shortcut :test #'string=)
            (list (make-instance 'search-engine
                                 :name "Google"
                                 :shortcut "google"
                                 :search-url "https://www.google.com/search?q=~a"
                                 :fallback-url (quri:uri "https://www.google.com")))))))

(define-command switch-buffer-most-recent ()
  "Switch buffers with the previously visited buffer selected first."
  (switch-buffer :current-is-last-p t))

(define-configuration base-mode
  ((keyscheme-map
    (with-personal-key-overrides
      (define-keyscheme-map "personal-base" (list :import %slot-value%)
        nyxt/keyscheme:emacs
        (list "C-x C-b" 'switch-buffer-most-recent
              "C-x k" 'delete-current-buffer))))))

(defun page-input-focused-p ()
  (eq t (ps-eval
          (let ((element (ps:@ document active-element)))
            ;; Follow focus inside web components; preserve typing in frames too.
            (loop while (and element (ps:@ element shadow-root)
                             (ps:@ element shadow-root active-element))
                  do (setf element (ps:@ element shadow-root active-element)))
            (and element
                 (or (ps:@ element is-content-editable)
                     (ps:chain (ps:array "INPUT" "TEXTAREA" "SELECT" "IFRAME")
                               (includes (ps:@ element tag-name)))))))))

(defun page-command-or-type (command)
  ;; A different page command cancels the first g of a pending gg sequence.
  (ps-eval (ps:chain document
                    (dispatch-event (ps:new (-event "nyxt-page-key-reset")))))
  (if (page-input-focused-p)
      (forward-to-renderer)
      (funcall command)))

(define-command page-scroll-left ()
  "Scroll left, or type normally in a form field."
  (page-command-or-type #'nyxt/mode/document:scroll-left))

(define-command page-scroll-down ()
  "Scroll down, or type normally in a form field."
  (page-command-or-type #'nyxt/mode/document:scroll-down))

(define-command page-scroll-up ()
  "Scroll up, or type normally in a form field."
  (page-command-or-type #'nyxt/mode/document:scroll-up))

(define-command page-scroll-right ()
  "Scroll right, or type normally in a form field."
  (page-command-or-type #'nyxt/mode/document:scroll-right))

(defvar *page-hint-sessions* (make-hash-table :test #'eq))

(defun page-follow-hints (command)
  ;; Each invocation owns its fallback request.  The Space command runs on a
  ;; different thread, so pass the request through a per-page session.
  (let* ((buffer (current-buffer))
         (mode (find-submode 'nyxt/mode/hint:hint-mode buffer))
         (original-type (nyxt/mode/hint:hinting-type mode))
         (previous-session (gethash buffer *page-hint-sessions*))
         (session (list nil)))
    (unwind-protect
         (progn
           (setf (gethash buffer *page-hint-sessions*) session)
           (handler-case (funcall command)
             (prompt-buffer-canceled (condition)
               (unless (car session) (error condition))))
           (when (car session)
             ;; Rebuild using Nyxt's original whole-page fuzzy hint source.
             (setf (nyxt/mode/hint:hinting-type mode) :emacs)
             (funcall command)))
      (setf (nyxt/mode/hint:hinting-type mode) original-type)
      (if previous-session
          (setf (gethash buffer *page-hint-sessions*) previous-session)
          (remhash buffer *page-hint-sessions*)))))

(define-command page-hint-fuzzy-or-space ()
  "Use the fuzzy hint selector on initial Space; otherwise insert a space."
  (let* ((prompt (current-prompt-buffer))
         (session (gethash (current-buffer) *page-hint-sessions*)))
    (if (and prompt session
             (str:emptyp (prompter:input prompt))
             (prompter:auto-return-p prompt))
        (progn
          (setf (car session) t)
          (nyxt/mode/prompt-buffer:quit-prompt-buffer prompt))
        (forward-to-renderer :buffer (or prompt (current-buffer))))))

(define-configuration nyxt/mode/hint-prompt-buffer:hint-prompt-buffer-mode
  ((keyscheme-map
    (with-personal-key-overrides
      (define-keyscheme-map "personal-hint-prompt" (list :import %slot-value%)
        nyxt/keyscheme:default
        (list "space" 'page-hint-fuzzy-or-space))))))

(define-command page-follow-hint ()
  "Follow a hint, or type normally in a form field."
  (page-command-or-type (lambda () (page-follow-hints #'nyxt/mode/hint:follow-hint))))

(define-command page-follow-hint-new-buffer ()
  "Follow a hint in a new buffer, or type normally in a form field."
  (page-command-or-type (lambda () (page-follow-hints #'nyxt/mode/hint:follow-hint-new-buffer))))

(define-configuration nyxt/mode/hint:hint-mode
  ;; Label-only, viewport hints: follow on a match, without the completion list.
  ((nyxt/mode/hint:hinting-type :vi)))

(define-command page-scroll-bottom ()
  "Scroll to the bottom, or type normally in a form field."
  (page-command-or-type #'nyxt/mode/document:scroll-to-bottom))

(define-command page-open-url ()
  "Set the URL, or type normally in a form field."
  (page-command-or-type #'set-url))

(define-command page-open-url-new-buffer ()
  "Set the URL in a new buffer, or type normally in a form field."
  (page-command-or-type #'set-url-new-buffer))

(define-command page-up-or-type ()
  "Scroll one page up, or type normally in a form field."
  (page-command-or-type #'nyxt/mode/document:scroll-page-up))

(define-configuration web-buffer
  ((default-modes (pushnew 'nyxt/mode/user-script:user-script-mode %slot-value%))))

(define-configuration nyxt/mode/user-script:user-script-mode
  ((nyxt/mode/user-script:user-scripts
    (append %slot-value%
            (list (make-instance 'nyxt/mode/user-script:user-script
                                 :base-path (merge-pathnames "nyxt/page-keys.js" (uiop:xdg-config-home))
                                 :all-frames-p t
                                 :run-at :document-start))))))

(define-configuration nyxt/mode/document:document-mode
  ((keyscheme-map
    (with-personal-key-overrides
      (define-keyscheme-map "personal-page" (list :import %slot-value%)
      nyxt/keyscheme:emacs
      (list "h" 'page-scroll-left
            "j" 'page-scroll-down
            "k" 'page-scroll-up
            "l" 'page-scroll-right
            "f" 'page-follow-hint
            "F" 'page-follow-hint-new-buffer
            "G" 'page-scroll-bottom
            "o" 'page-open-url
            "O" 'page-open-url-new-buffer
            "shift-space" 'page-up-or-type))))))

;; Use the existing Home Manager rbw account; authentication stays in pinentry.
(defclass vaultwarden-interface (password:password-interface)
  ((password:executable :initform "rbw")
   (entries :initform (make-hash-table :test #'equal) :reader vaultwarden-entries)))

(defun vaultwarden-run (interface arguments &key input (output :string))
  ;; Never include command output in an error or send it to Nyxt's log.
  (multiple-value-bind (output errors status)
      (uiop:run-program (cons (password:executable interface) arguments)
                        :input input :output output :error-output :string
                        :ignore-error-status t)
    (declare (ignore errors))
    (unless (zerop status)
      (error "Vaultwarden command failed. Check rbw login/unlock/sync in a terminal."))
    output))

(defmethod password:password-correct-p ((interface vaultwarden-interface))
  (vaultwarden-run interface '("unlock"))
  t)

(defmethod password:list-passwords ((interface vaultwarden-interface))
  (clrhash (vaultwarden-entries interface))
  ;; Request metadata only. UUIDs distinguish entries with identical names.
  (loop for line in (uiop:split-string
                    (vaultwarden-run interface '("list" "--fields" "id,name,user"))
                    :separator '(#\Newline))
        for tab = (position #\Tab line)
        when tab
          collect (let* ((id (subseq line 0 tab))
                         (label (format nil "~a [~a]"
                                        (substitute #\Space #\Tab (subseq line (1+ tab)))
                                        id)))
                    (setf (gethash label (vaultwarden-entries interface)) id)
                    label)))

(defun vaultwarden-copy (interface entry &optional username-p)
  (let ((id (gethash entry (vaultwarden-entries interface))))
    (unless id
      (error "Select a Vaultwarden entry with copy-password or copy-username."))
    (let* ((output (vaultwarden-run
                    interface (append '("get")
                                      (when username-p '("--field" "username"))
                                      (list "--" id))))
           ;; rbw appends a newline; preserve whitespace in the actual value.
           (value (if (and (plusp (length output))
                           (char= #\Newline (char output (1- (length output)))))
                      (subseq output 0 (1- (length output)))
                      output)))
      (unless (plusp (length value))
        (error "The selected Vaultwarden field is empty."))
      ;; Nyxt clears the clipboard after sleep-timer unless it has changed.
      (password::clip-password-string interface value)))
  t)

(defmethod password:clip-password ((interface vaultwarden-interface)
                                  &key password-name service)
  (declare (ignore service))
  (vaultwarden-copy interface password-name))

(defmethod password:clip-username ((interface vaultwarden-interface)
                                  &key password-name service)
  (declare (ignore service))
  (vaultwarden-copy interface password-name t))

(defun vaultwarden-site-uri (url)
  ;; Save the site's origin, excluding URL credentials, query strings and fragments.
  (when url
    (let ((uri (quri:uri url)))
      (when (and (member (quri:uri-scheme uri) '("https" "http") :test #'string-equal)
                 (quri:uri-host uri))
        (quri:render-uri (quri:make-uri :scheme (quri:uri-scheme uri)
                                      :host (quri:uri-host uri)
                                      :port (quri:uri-port uri)))))))

(defmethod password:save-password ((interface vaultwarden-interface)
                                  &key password-name username password service)
  (unless (and password-name
               (plusp (length (string-trim '(#\Space #\Tab #\Newline) password-name))))
    (error "Enter a name for the new Vaultwarden login."))
  ;; rbw treats subsequent lines as notes, so do not silently truncate passwords.
  (when (and password (find-if (lambda (char) (find char '(#\Newline #\Return))) password))
    (error "Saving passwords containing line breaks is not supported by rbw add."))
  (let* ((site (vaultwarden-site-uri
                (or service (when (current-buffer) (url (current-buffer))))))
         (arguments (append (when site (list "--uri" site))
                            (list "--" password-name)
                            (when (and username (plusp (length username)))
                              (list username)))))
    (if (or (null password) (zerop (length password)))
        ;; rbw prints generated passwords; discard stdout instead of logging it.
        (vaultwarden-run interface (append '("generate" "24") arguments) :output nil)
        ;; A pipe avoids exposing the password in argv, environment or a file.
        (with-input-from-string (input (concatenate 'string password (string #\Newline)))
          (vaultwarden-run interface (cons "add" arguments) :input input :output nil))))
  (echo "Saved a new login to Vaultwarden.")
  t)

(define-configuration nyxt/mode/password:password-mode
  ((nyxt/mode/password:password-interface
    (make-instance 'vaultwarden-interface))))

(load (merge-pathnames "nyxt/karakeep.lisp" (uiop:xdg-config-home)))
