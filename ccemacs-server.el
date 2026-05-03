;;; ccemacs-server.el --- WebSocket server lifecycle and auth -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'websocket)
(require 'project)
(require 'ccemacs-rpc)
(require 'ccemacs-mcp)
(require 'ccemacs-lockfile)
(require 'ccemacs-selection)

(defvar ccemacs-server-port-min 10000)
(defvar ccemacs-server-port-max 65535)
(defvar ccemacs-server-bind-attempts 50)

(cl-defstruct ccemacs-session
  workspace
  port
  token
  instance
  (clients nil))

(defvar ccemacs-server--registry (make-hash-table :test 'equal)
  "Workspace path (string) → `ccemacs-session' struct.")

(defun ccemacs-server-sessions ()
  "Return a list of all active sessions."
  (let (sessions)
    (maphash (lambda (_w s) (push s sessions)) ccemacs-server--registry)
    sessions))

(defun ccemacs-server-session-for-workspace (workspace)
  "Return the session registered for WORKSPACE, or nil."
  (gethash (file-name-as-directory (expand-file-name workspace))
           ccemacs-server--registry))

(defun ccemacs-server-session-for-client (client)
  "Return the session that owns websocket CLIENT, or nil."
  (cl-loop for s in (ccemacs-server-sessions)
           when (memq client (ccemacs-session-clients s))
           return s))

(defun ccemacs-server-session-for-file (file)
  "Return the session whose workspace is the longest prefix of FILE, or nil."
  (when (and file (stringp file))
    (let ((path (expand-file-name file))
          best best-len)
      (dolist (s (ccemacs-server-sessions))
        (let* ((ws (ccemacs-session-workspace s))
               (len (length ws)))
          (when (and (string-prefix-p ws path)
                     (or (null best-len) (> len best-len)))
            (setq best s best-len len))))
      best)))

(defun ccemacs-server-clients ()
  "Return a fresh list of all currently connected clients across sessions."
  (cl-loop for s in (ccemacs-server-sessions)
           append (copy-sequence (ccemacs-session-clients s))))

(defun ccemacs-server-check-auth-header (header expected-token)
  "Return non-nil iff HEADER matches EXPECTED-TOKEN."
  (and header expected-token
       (stringp header) (stringp expected-token)
       (not (string-empty-p header))
       (string-equal header expected-token)))

(defun ccemacs-server--make-token ()
  (format "%04x%04x-%04x-4%03x-%04x-%04x%04x%04x"
          (random 65536) (random 65536)
          (random 65536) (random 4096)
          (logior #x8000 (logand #x3fff (random 65536)))
          (random 65536) (random 65536) (random 65536)))

(defun ccemacs-server--workspace-root ()
  (file-name-as-directory
   (or (when (fboundp 'project-current)
         (let ((proj (project-current)))
           (and proj (expand-file-name (project-root proj)))))
       (expand-file-name default-directory))))

(defun ccemacs-server--session-from-ws (ws)
  "Return the session WS belongs to by matching its auth token."
  (let ((token (process-get (websocket-conn ws) :ccemacs-token)))
    (cl-loop for s in (ccemacs-server-sessions)
             when (equal (ccemacs-session-token s) token)
             return s)))

(defun ccemacs-server--on-open (session)
  (lambda (ws)
    (process-put (websocket-conn ws) :ccemacs-token
                 (ccemacs-session-token session))
    (push ws (ccemacs-session-clients session))))

(defun ccemacs-server--on-message (ws frame)
  (let ((text (websocket-frame-text frame)))
    (when text
      (ccemacs-rpc-handle-frame ws text))))

(defun ccemacs-server--on-close (ws)
  (let ((session (ccemacs-server--session-from-ws ws)))
    (when session
      (setf (ccemacs-session-clients session)
            (delq ws (ccemacs-session-clients session))))))

(cl-defmethod ccemacs-rpc-transport-send ((ws websocket) message)
  (websocket-send-text ws message))

(defun ccemacs-server--try-bind (session)
  "Bind a random port in the configured range. Return (PORT . SERVER)."
  (let ((attempts 0) result)
    (while (and (< attempts ccemacs-server-bind-attempts) (not result))
      (let* ((port (+ ccemacs-server-port-min
                      (random (- ccemacs-server-port-max
                                 ccemacs-server-port-min))))
             (server (condition-case _err
                         (websocket-server
                          port
                          :host "127.0.0.1"
                          :on-open (ccemacs-server--on-open session)
                          :on-message #'ccemacs-server--on-message
                          :on-close #'ccemacs-server--on-close)
                       (error nil))))
        (if server
            (setq result (cons port server))
          (cl-incf attempts))))
    (or result
        (error "ccemacs: could not bind a port after %d attempts"
               ccemacs-server-bind-attempts))))

(defun ccemacs-server-running-p (&optional workspace)
  "Return non-nil if a session is running for WORKSPACE (or any session)."
  (cond
   (workspace (and (ccemacs-server-session-for-workspace workspace) t))
   (t (> (hash-table-count ccemacs-server--registry) 0))))

;;;###autoload
(defun ccemacs-server-start ()
  "Start a ccemacs WebSocket server for the current workspace.
Return the bound port. Multiple sessions may run concurrently for
different workspaces; calling twice for the same workspace is an error."
  (interactive)
  (let* ((workspace (ccemacs-server--workspace-root))
         (existing (gethash workspace ccemacs-server--registry)))
    (when existing
      (user-error "ccemacs server already running for %s on port %s"
                  workspace (ccemacs-session-port existing)))
    (let* ((token (ccemacs-server--make-token))
           (session (make-ccemacs-session
                     :workspace workspace
                     :token token))
           (pair (ccemacs-server--try-bind session))
           (port (car pair))
           (server (cdr pair)))
      (setf (ccemacs-session-port session) port
            (ccemacs-session-instance session) server)
      (puthash workspace session ccemacs-server--registry)
      (ccemacs-lockfile-write port token workspace)
      (ccemacs-selection-mode 1)
      port)))

;;;###autoload
(defun ccemacs-server-stop (&optional workspace)
  "Stop the ccemacs session for WORKSPACE (default: current workspace)."
  (interactive)
  (let* ((ws (file-name-as-directory
              (expand-file-name
               (or workspace (ccemacs-server--workspace-root)))))
         (session (gethash ws ccemacs-server--registry)))
    (when session
      (ignore-errors (websocket-server-close (ccemacs-session-instance session)))
      (ignore-errors (ccemacs-lockfile-delete (ccemacs-session-port session)))
      (remhash ws ccemacs-server--registry))
    (when (zerop (hash-table-count ccemacs-server--registry))
      (ccemacs-selection-mode -1))))

;;;###autoload
(defun ccemacs-server-stop-all ()
  "Stop every active ccemacs session."
  (interactive)
  (dolist (s (ccemacs-server-sessions))
    (ccemacs-server-stop (ccemacs-session-workspace s))))

(provide 'ccemacs-server)
;;; ccemacs-server.el ends here
