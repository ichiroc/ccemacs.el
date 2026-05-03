;;; ccemacs-server-test.el --- Tests for ccemacs-server -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'json)
(require 'websocket)
(require 'ccemacs-server)

(defun ccemacs-server-test--cleanup ()
  (ignore-errors (ccemacs-server-stop-all)))

(ert-deftest ccemacs-server-start-binds-port-and-writes-lockfile ()
  (let ((ccemacs-lockfile-dir (make-temp-file "ccemacs-test-srv-" t)))
    (unwind-protect
        (let ((port (ccemacs-server-start)))
          (should (integerp port))
          (should (>= port ccemacs-server-port-min))
          (should (<= port ccemacs-server-port-max))
          (let ((path (expand-file-name (format "%d.lock" port)
                                        ccemacs-lockfile-dir)))
            (should (file-exists-p path))))
      (ccemacs-server-test--cleanup)
      (when (file-exists-p ccemacs-lockfile-dir)
        (delete-directory ccemacs-lockfile-dir t)))))

(ert-deftest ccemacs-server-stop-closes-and-deletes-lockfile ()
  (let ((ccemacs-lockfile-dir (make-temp-file "ccemacs-test-srv-" t)))
    (unwind-protect
        (let ((port (ccemacs-server-start)))
          (ccemacs-server-stop)
          (should-not (file-exists-p
                       (expand-file-name (format "%d.lock" port)
                                         ccemacs-lockfile-dir))))
      (ccemacs-server-test--cleanup)
      (when (file-exists-p ccemacs-lockfile-dir)
        (delete-directory ccemacs-lockfile-dir t)))))

(ert-deftest ccemacs-server-roundtrip-initialize ()
  :tags '(integration)
  (let ((ccemacs-lockfile-dir (make-temp-file "ccemacs-test-srv-" t))
        (received nil))
    (unwind-protect
        (let* ((port (ccemacs-server-start))
               (client (websocket-open
                        (format "ws://127.0.0.1:%d" port)
                        :on-message
                        (lambda (_ws frame)
                          (setq received (websocket-frame-text frame))))))
          (with-timeout (2 (error "client did not open"))
            (while (not (eq (websocket-ready-state client) 'open))
              (accept-process-output nil 0.05)))
          (websocket-send-text
           client
           "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"initialize\",\"params\":{}}")
          (with-timeout (2 (error "no response"))
            (while (not received)
              (accept-process-output nil 0.05)))
          (websocket-close client)
          (let* ((resp (json-parse-string received :object-type 'plist))
                 (result (plist-get resp :result)))
            (should (equal (plist-get resp :id) 42))
            (should result)
            (should (equal (plist-get result :protocolVersion) "2025-03-26"))))
      (ccemacs-server-test--cleanup)
      (when (file-exists-p ccemacs-lockfile-dir)
        (delete-directory ccemacs-lockfile-dir t)))))

(ert-deftest ccemacs-server-start-supports-multiple-workspaces ()
  (let* ((ccemacs-lockfile-dir (make-temp-file "ccemacs-test-multi-" t))
         (ws-a (file-name-as-directory (make-temp-file "ccemacs-ws-a-" t)))
         (ws-b (file-name-as-directory (make-temp-file "ccemacs-ws-b-" t))))
    (unwind-protect
        (let* ((default-directory ws-a)
               (port-a (ccemacs-server-start))
               (port-b (let ((default-directory ws-b))
                         (ccemacs-server-start))))
          (should (/= port-a port-b))
          (should (file-exists-p (expand-file-name (format "%d.lock" port-a)
                                                   ccemacs-lockfile-dir)))
          (should (file-exists-p (expand-file-name (format "%d.lock" port-b)
                                                   ccemacs-lockfile-dir)))
          (should (= 2 (length (ccemacs-server-sessions))))
          (should (ccemacs-server-session-for-workspace ws-a))
          (should (ccemacs-server-session-for-workspace ws-b)))
      (ccemacs-server-test--cleanup)
      (when (file-exists-p ccemacs-lockfile-dir)
        (delete-directory ccemacs-lockfile-dir t))
      (when (file-exists-p ws-a) (delete-directory ws-a t))
      (when (file-exists-p ws-b) (delete-directory ws-b t)))))

(ert-deftest ccemacs-server-start-rejects-duplicate-workspace ()
  (let* ((ccemacs-lockfile-dir (make-temp-file "ccemacs-test-dup-" t))
         (ws (file-name-as-directory (make-temp-file "ccemacs-ws-dup-" t))))
    (unwind-protect
        (let ((default-directory ws))
          (ccemacs-server-start)
          (should-error (ccemacs-server-start) :type 'user-error))
      (ccemacs-server-test--cleanup)
      (when (file-exists-p ccemacs-lockfile-dir)
        (delete-directory ccemacs-lockfile-dir t))
      (when (file-exists-p ws) (delete-directory ws t)))))

(ert-deftest ccemacs-server-stop-only-stops-current-workspace ()
  (let* ((ccemacs-lockfile-dir (make-temp-file "ccemacs-test-stop-" t))
         (ws-a (file-name-as-directory (make-temp-file "ccemacs-ws-a-" t)))
         (ws-b (file-name-as-directory (make-temp-file "ccemacs-ws-b-" t))))
    (unwind-protect
        (let* ((default-directory ws-a)
               (port-a (ccemacs-server-start))
               (port-b (let ((default-directory ws-b))
                         (ccemacs-server-start))))
          (let ((default-directory ws-a))
            (ccemacs-server-stop))
          (should-not (ccemacs-server-session-for-workspace ws-a))
          (should (ccemacs-server-session-for-workspace ws-b))
          (should-not (file-exists-p
                       (expand-file-name (format "%d.lock" port-a)
                                         ccemacs-lockfile-dir)))
          (should (file-exists-p
                   (expand-file-name (format "%d.lock" port-b)
                                     ccemacs-lockfile-dir))))
      (ccemacs-server-test--cleanup)
      (when (file-exists-p ccemacs-lockfile-dir)
        (delete-directory ccemacs-lockfile-dir t))
      (when (file-exists-p ws-a) (delete-directory ws-a t))
      (when (file-exists-p ws-b) (delete-directory ws-b t)))))

(ert-deftest ccemacs-server-check-auth-header-accepts-matching-token ()
  (should (ccemacs-server-check-auth-header "abc-123" "abc-123")))

(ert-deftest ccemacs-server-check-auth-header-rejects-mismatch ()
  (should-not (ccemacs-server-check-auth-header "abc-123" "xyz-999")))

(ert-deftest ccemacs-server-check-auth-header-rejects-nil ()
  (should-not (ccemacs-server-check-auth-header nil "abc-123"))
  (should-not (ccemacs-server-check-auth-header "" "abc-123")))

(provide 'ccemacs-server-test)
;;; ccemacs-server-test.el ends here
