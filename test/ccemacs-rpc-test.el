;;; ccemacs-rpc-test.el --- Tests for ccemacs-rpc -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'json)
(require 'ccemacs-rpc)
(require 'ccemacs-mcp)
(require 'ccemacs-test-helper)

(defun ccemacs-rpc-test--parse (s)
  (json-parse-string s :object-type 'plist :array-type 'array))

(ert-deftest ccemacs-rpc-handle-initialize-returns-mcp-response ()
  (let* ((tx (ccemacs-test-make-transport))
         (req "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\"}}"))
    (ccemacs-rpc-handle-frame tx req)
    (let* ((sent (ccemacs-test-transport-sent-list tx)))
      (should (= 1 (length sent)))
      (let* ((resp (ccemacs-rpc-test--parse (car sent))))
        (should (equal (plist-get resp :jsonrpc) "2.0"))
        (should (equal (plist-get resp :id) 1))
        (let ((result (plist-get resp :result)))
          (should result)
          (should (equal (plist-get result :protocolVersion) "2025-03-26"))
          (let ((info (plist-get result :serverInfo)))
            (should (equal (plist-get info :name) "ccemacs"))
            (should (stringp (plist-get info :version)))))))))

(ert-deftest ccemacs-rpc-unknown-method-returns-error ()
  (let* ((tx (ccemacs-test-make-transport))
         (req "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"no.such.method\",\"params\":{}}"))
    (ccemacs-rpc-handle-frame tx req)
    (let* ((resp (ccemacs-rpc-test--parse
                  (car (ccemacs-test-transport-sent-list tx)))))
      (should (equal (plist-get resp :id) 7))
      (let ((err (plist-get resp :error)))
        (should err)
        (should (equal (plist-get err :code) -32601))))))

(ert-deftest ccemacs-rpc-notification-has-no-id-and-no-response ()
  "Requests without id are notifications and must not get a response."
  (let* ((tx (ccemacs-test-make-transport))
         (req "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"))
    (ccemacs-rpc-handle-frame tx req)
    (should (= 0 (length (ccemacs-test-transport-sent-list tx))))))

(ert-deftest ccemacs-rpc-send-notification-formats-correctly ()
  (let ((tx (ccemacs-test-make-transport)))
    (ccemacs-rpc-send-notification
     tx "selection_changed"
     '(:text "hi" :filePath "/tmp/x"))
    (let ((msg (ccemacs-rpc-test--parse
                (car (ccemacs-test-transport-sent-list tx)))))
      (should (equal (plist-get msg :jsonrpc) "2.0"))
      (should (equal (plist-get msg :method) "selection_changed"))
      (should-not (plist-member msg :id))
      (should (equal (plist-get (plist-get msg :params) :text) "hi")))))

(provide 'ccemacs-rpc-test)
;;; ccemacs-rpc-test.el ends here
