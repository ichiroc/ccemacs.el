;;; ccemacs-mcp.el --- MCP method handlers -*- lexical-binding: t; -*-

;;; Code:

(require 'ccemacs-rpc)

(defconst ccemacs-mcp-protocol-version "2025-03-26")
(defconst ccemacs-mcp-server-name "ccemacs")
(defconst ccemacs-mcp-server-version "0.0.1")

(defun ccemacs-mcp--empty-object ()
  (make-hash-table :test 'equal))

(defun ccemacs-mcp-handle-initialize (_params)
  `(:protocolVersion ,ccemacs-mcp-protocol-version
    :capabilities (:tools ,(ccemacs-mcp--empty-object))
    :serverInfo (:name ,ccemacs-mcp-server-name
                 :version ,ccemacs-mcp-server-version)))

(ccemacs-rpc-register-method "initialize" #'ccemacs-mcp-handle-initialize)

(provide 'ccemacs-mcp)
;;; ccemacs-mcp.el ends here
