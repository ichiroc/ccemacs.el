;;; ccemacs-diff-test.el --- Tests for ccemacs-diff -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'ccemacs-diff)
(require 'ccemacs-tools)
(require 'ccemacs-test-helper)

(defun ccemacs-diff-test--parse (s)
  (json-parse-string s :object-type 'plist :array-type 'array
                     :false-object :false :null-object :null))

(ert-deftest ccemacs-diff-register-then-resolve-saved-sends-response ()
  (let* ((tx (ccemacs-test-make-transport)))
    (clrhash ccemacs-diff--pending)
    (ccemacs-diff--register "tab-1" tx 99)
    (ccemacs-diff-resolve-saved "tab-1")
    (let* ((sent (ccemacs-test-transport-sent-list tx))
           (resp (ccemacs-diff-test--parse (car sent))))
      (should (equal (plist-get resp :id) 99))
      (let* ((result (plist-get resp :result))
             (text (plist-get (aref (plist-get result :content) 0) :text)))
        (should (equal text "FILE_SAVED"))))
    (should-not (gethash "tab-1" ccemacs-diff--pending))))

(ert-deftest ccemacs-diff-resolve-rejected-sends-response ()
  (let* ((tx (ccemacs-test-make-transport)))
    (clrhash ccemacs-diff--pending)
    (ccemacs-diff--register "tab-2" tx 100)
    (ccemacs-diff-resolve-rejected "tab-2")
    (let* ((resp (ccemacs-diff-test--parse
                  (car (ccemacs-test-transport-sent-list tx))))
           (text (plist-get
                  (aref (plist-get (plist-get resp :result) :content) 0)
                  :text)))
      (should (equal text "DIFF_REJECTED")))))

(ert-deftest ccemacs-diff-resolve-unknown-tab-is-noop ()
  (clrhash ccemacs-diff--pending)
  (ccemacs-diff-resolve-saved "nope"))

(ert-deftest ccemacs-tools-openDiff-returns-async-and-registers-pending ()
  (let ((tx (ccemacs-test-make-transport))
        (launched nil))
    (clrhash ccemacs-diff--pending)
    (cl-letf (((symbol-function 'ccemacs-diff--launch)
               (lambda (&rest args) (setq launched args))))
      (let* ((ccemacs-rpc-current-transport tx)
             (ccemacs-rpc-current-id 7)
             (result (ccemacs-tools--open-diff
                      '(:old_file_path "/tmp/a"
                        :new_file_path "/tmp/a"
                        :new_file_contents "X\n"
                        :tab_name "diff:1"))))
        (should (eq result ccemacs-rpc-async))
        (should (gethash "diff:1" ccemacs-diff--pending))
        (should launched)))))

(ert-deftest ccemacs-rpc-async-handler-suppresses-immediate-response ()
  (let ((tx (ccemacs-test-make-transport)))
    (ccemacs-rpc-register-method
     "test.async" (lambda (_p) ccemacs-rpc-async))
    (unwind-protect
        (progn
          (ccemacs-rpc-handle-frame
           tx "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"test.async\",\"params\":{}}")
          (should (= 0 (length (ccemacs-test-transport-sent-list tx))))
          (ccemacs-rpc-send-response tx 11 '(:ok t))
          (let ((resp (ccemacs-diff-test--parse
                       (car (ccemacs-test-transport-sent-list tx)))))
            (should (equal (plist-get resp :id) 11))
            (should (equal (plist-get (plist-get resp :result) :ok) t))))
      (remhash "test.async" ccemacs-rpc--methods))))

(provide 'ccemacs-diff-test)
;;; ccemacs-diff-test.el ends here
