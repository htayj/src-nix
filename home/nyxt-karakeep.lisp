(in-package :nyxt-user)

(defun karakeep-object (&rest pairs)
  (let ((object (make-hash-table :test #'equal)))
    (loop for (key value) on pairs by #'cddr do (setf (gethash key object) value))
    object))

(defun karakeep-request (&rest pairs)
  (with-input-from-string (input (njson:encode (apply #'karakeep-object pairs)))
    (multiple-value-bind (output errors status)
        (uiop:run-program '("nyxt-karakeep") :input input :output :string
                          :error-output :string :ignore-error-status t)
      (declare (ignore errors status))
      (let ((response (njson:decode output)))
        (unless (eq t (gethash "ok" response))
          (error "~a" (gethash "error" response)))
        (gethash "result" response)))))

(defmacro with-karakeep-errors (&body body)
  `(handler-case (progn ,@body)
     (error (condition) (echo-warning "Karakeep: ~a" condition))))

(defun karakeep-prompt-text (label)
  (prompt1 :prompt label :sources (make-instance 'prompter:raw-source)))

(defclass karakeep-list-choice ()
  ((id :initarg :id :reader karakeep-list-id)
   (label :initarg :label :reader karakeep-list-label)))

(defmethod prompter:object-attributes ((choice karakeep-list-choice) (source prompter:source))
  (declare (ignore source))
  `(("List" ,(karakeep-list-label choice))
    ("ID" ,(or (karakeep-list-id choice) ""))))

(defun karakeep-prompt-list ()
  (let* ((result (karakeep-request "action" "lists"))
         (choices (cons (make-instance 'karakeep-list-choice :id nil :label "No list (save only)")
                        (map 'list (lambda (item)
                                     (make-instance 'karakeep-list-choice
                                                    :id (gethash "id" item)
                                                    :label (gethash "path" item)))
                             (gethash "lists" result)))))
    (karakeep-list-id
     (prompt1 :prompt "Karakeep list (type to filter, or RET for no list)"
              :sources (make-instance 'prompter:source :name "Writable lists"
                                      :constructor choices :active-attributes-keys '("List"))))))

(defun karakeep-save-url (url title)
  (let* ((tags (karakeep-prompt-text "Karakeep tags (comma-separated, or blank)"))
         (list-id (karakeep-prompt-list))
         (result (karakeep-request "action" "save" "url" (render-url url)
                                   "listId" (or list-id :null)
                                   "title" title "tags"
                                   (coerce (uiop:split-string (or tags "") :separator '(#\,)) 'vector))))
    (if (gethash "warning" result)
        (echo-warning "~a" (gethash "warning" result))
        (if (gethash "list" result)
            (echo "Saved to Karakeep list: ~a." (gethash "list" result))
            (echo "Saved to Karakeep. Article extraction runs on the server.")))))

(define-command karakeep-save ()
  "Save this page to Karakeep, with optional tags and a list."
  (with-karakeep-errors
    (karakeep-save-url (url (current-buffer)) (title (current-buffer)))))

(define-command karakeep-save-hint ()
  "Save hinted links to Karakeep without opening them."
  (nyxt/mode/hint:query-hints
   "Save link(s) to Karakeep"
   (lambda (hints)
     (with-karakeep-errors
       (dolist (hint hints) (karakeep-save-url (url hint) ""))))
   :selector "a"))

(defclass karakeep-entry ()
  ((data :initarg :data :reader karakeep-entry-data)))

(defmethod prompter:object-attributes ((entry karakeep-entry) (source prompter:source))
  (declare (ignore source))
  (let ((data (karakeep-entry-data entry)))
    `(("Title" ,(gethash "title" data))
      ("URL" ,(gethash "url" data))
      ("Tags" ,(format nil "~{~a~^, ~}" (coerce (gethash "tags" data) 'list))))))

(defun karakeep-open-entry (entry reader-p)
  (let* ((data (karakeep-entry-data entry))
         (original (gethash "url" data))
         (target (if (or reader-p (str:emptyp original)) (gethash "reader" data) original)))
    (make-buffer-focus :url (quri:uri target))))

(defun karakeep-search-prompt (reader-p)
  (with-karakeep-errors
    (let* ((query (karakeep-prompt-text "Search Karakeep (blank for recent bookmarks)"))
           (result (karakeep-request "action" "search" "query" (or query "")))
           (entries (map 'list (lambda (data) (make-instance 'karakeep-entry :data data))
                         (gethash "bookmarks" result))))
      (if (null entries)
          (echo "No matching Karakeep bookmarks.")
          (prompt
           :prompt (if (gethash "more" result)
                       "Karakeep (first 100; narrow search for more)" "Karakeep")
           :sources (make-instance
                     'prompter:source :name "Karakeep" :constructor entries
                     :active-attributes-keys '("Title" "URL" "Tags")
                     :enable-marks-p t
                     :actions-on-return
                     (list
                      (lambda-command karakeep-open-selection (selections)
                        "Open selected bookmarks."
                        (dolist (entry selections) (karakeep-open-entry entry reader-p)))
                      (lambda-command karakeep-open-alternate (selections)
                        "Open using the alternate view (original or saved reader)."
                        (dolist (entry selections) (karakeep-open-entry entry (not reader-p)))))))))))

(define-command karakeep-search ()
  "Search Karakeep's full text, select results, and open their original URLs."
  (karakeep-search-prompt nil))

(define-command karakeep-read ()
  "Search Karakeep and open saved Reader Views. Sign in to its web UI once."
  (karakeep-search-prompt t))

(define-command karakeep-library ()
  "Open the Karakeep web library."
  (make-buffer-focus :url (quri:uri "https://horde.nogroup.group")))

(define-configuration base-mode
  ((keyscheme-map
    (with-personal-key-overrides
      (define-keyscheme-map "personal-karakeep" (list :import %slot-value%)
        nyxt/keyscheme:emacs
        (list "C-c k s" 'karakeep-save
              "C-c k o" 'karakeep-search
              "C-c k r" 'karakeep-read
              "C-c k h" 'karakeep-save-hint
              "C-c k b" 'karakeep-library))))))
