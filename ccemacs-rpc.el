;;; ccemacs-rpc.el --- JSON-RPC 2.0 framing -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'json)

(cl-defgeneric ccemacs-rpc-transport-send (transport message)
  "Send MESSAGE (a JSON string) over TRANSPORT.")

(defconst ccemacs-rpc-async 'ccemacs-rpc-async
  "Sentinel value: a handler returning this defers its response.")

(defvar ccemacs-rpc-current-transport nil
  "Bound during a request to the transport that delivered it.")

(defvar ccemacs-rpc-current-id nil
  "Bound during a request to the JSON-RPC id of the in-flight call.")

(defvar ccemacs-rpc--methods (make-hash-table :test 'equal)
  "Method name (string) → handler function (params -> result plist).")

(defun ccemacs-rpc-register-method (name handler)
  (puthash name handler ccemacs-rpc--methods))

(defun ccemacs-rpc--build-response (id result)
  (json-serialize `(:jsonrpc "2.0" :id ,id :result ,result)))

(defun ccemacs-rpc--build-error (id code message)
  (json-serialize
   `(:jsonrpc "2.0" :id ,id
     :error (:code ,code :message ,message))))

(defun ccemacs-rpc-send-response (transport id result)
  "Send a JSON-RPC response with ID and RESULT over TRANSPORT."
  (ccemacs-rpc-transport-send
   transport (ccemacs-rpc--build-response id result)))

(defun ccemacs-rpc-handle-frame (transport frame)
  "Parse FRAME (JSON string) as a JSON-RPC 2.0 message and dispatch."
  (let* ((req (json-parse-string frame :object-type 'plist :array-type 'array))
         (method (plist-get req :method))
         (id-present (plist-member req :id))
         (id (plist-get req :id))
         (params (plist-get req :params))
         (handler (and method (gethash method ccemacs-rpc--methods))))
    (cond
     ((null method) nil)
     ((null handler)
      (when id-present
        (ccemacs-rpc-transport-send
         transport
         (ccemacs-rpc--build-error
          id -32601 (format "Method not found: %s" method)))))
     (t
      (let* ((ccemacs-rpc-current-transport transport)
             (ccemacs-rpc-current-id id)
             (result (funcall handler params)))
        (when (and id-present (not (eq result ccemacs-rpc-async)))
          (ccemacs-rpc-send-response transport id result)))))))

(defun ccemacs-rpc-send-notification (transport method params)
  (ccemacs-rpc-transport-send
   transport
   (json-serialize `(:jsonrpc "2.0" :method ,method :params ,params))))

(provide 'ccemacs-rpc)
;;; ccemacs-rpc.el ends here
