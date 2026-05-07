;;; ccemacs.el --- Claude Code IDE integration for Emacs -*- lexical-binding: t; -*-

;; Author: ichiroc
;; Version: 0.0.1
;; Package-Requires: ((emacs "27.1") (websocket "1.15"))
;; Keywords: tools, ai
;; URL: https://github.com/ichiroc/ccemacs.el

;;; Commentary:
;; Make Emacs act as the IDE side of Claude Code's IDE integration
;; protocol (lock file + WebSocket + JSON-RPC 2.0 / MCP).

;;; Code:

(require 'ccemacs-lockfile)
(require 'ccemacs-rpc)
(require 'ccemacs-mcp)
(require 'ccemacs-server)
(require 'ccemacs-selection)
(require 'ccemacs-diff)
(require 'ccemacs-diagnostics)
(require 'ccemacs-tools)
(require 'ccemacs-mention)
(require 'ccemacs-tmux)

;;;###autoload
(defun ccemacs-shutdown-all ()
  "Stop every ccemacs session, used as `kill-emacs-hook'."
  (ignore-errors (ccemacs-server-stop-all)))

(add-hook 'kill-emacs-hook #'ccemacs-shutdown-all)

;;;###autoload
(defun ccemacs-menu ()
  "Pick a ccemacs command from a single entry point."
  (interactive)
  (let* ((entries
          `(("Start server (current workspace)" . ccemacs-server-start)
            ("Stop server (current workspace)"  . ccemacs-server-stop)
            ("Stop all servers"                 . ccemacs-server-stop-all)
            ("Send @-mention"                   . ccemacs-send-at-mention)
            ("Launch claude in tmux"            . ccemacs-tmux-launch-claude)))
         (label (completing-read "ccemacs: " (mapcar #'car entries) nil t))
         (cmd (cdr (assoc label entries))))
    (when cmd (call-interactively cmd))))

(provide 'ccemacs)
;;; ccemacs.el ends here
