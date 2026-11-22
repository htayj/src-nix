;; Run from the repository root: nyxt --script scripts/test-nyxt-keymaps.lisp
(in-package :nyxt-user)
(handler-case
    (progn
      ;; Load repository config while resolving its companion file locally.
      (let ((original-load (symbol-function 'load)))
        (unwind-protect
             (sb-ext:without-package-locks
               (setf (symbol-function 'load)
                     (lambda (path &rest args)
                       (apply original-load
                              (if (equal (pathname-name path) "karakeep")
                                  #p"home/nyxt-karakeep.lisp" path) args)))
               (load #p"home/nyxt.lisp"))
          (sb-ext:without-package-locks (setf (symbol-function 'load) original-load))))
      ;; Match the navigation callback's warning-to-error behavior. Previously,
      ;; constructing BASE-MODE here crashed on C-x C-b's intentional override.
      (handler-bind ((warning (lambda (condition) (error condition))))
        (dotimes (i 3)
          (declare (ignorable i))
          (let ((base (keymaps:get-keymap nyxt/keyscheme:emacs
                                         (keyscheme-map (make-instance 'base-mode))))
                (page (keymaps:get-keymap nyxt/keyscheme:emacs
                                         (keyscheme-map (make-instance 'nyxt/mode/document:document-mode)))))
            (assert (eq (keymaps:lookup-key "C-x C-b" base) 'switch-buffer-most-recent))
            (assert (eq (keymaps:lookup-key "C-x k" base) 'delete-current-buffer))
            (assert (eq (keymaps:lookup-key "C-c k s" base) 'karakeep-save))
            (assert (eq (keymaps:lookup-key "f" page) 'page-follow-hint))
            (assert (eq (keymaps:lookup-key "F" page) 'page-follow-hint-new-buffer)))))
      (format t "PASS: repeated mode creation is safe in navigation callbacks; personal bindings preserved.~%"))
  (error (condition)
    (format t "FAIL: ~a~%" condition)
    (uiop:quit 1)))
