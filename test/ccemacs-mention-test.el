;;; ccemacs-mention-test.el --- Tests for ccemacs-mention -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'json)
(require 'ccemacs-mention)
(require 'ccemacs-server)
(require 'ccemacs-test-helper)

(defun ccemacs-mention-test--parse (s)
  (json-parse-string s :object-type 'plist :array-type 'array))

(ert-deftest ccemacs-mention-broadcasts-with-region ()
  (let* ((ws (file-name-as-directory (make-temp-file "ccemacs-mention-ws-" t)))
         (file (expand-file-name "x.txt" ws))
         (tx (ccemacs-test-make-transport))
         (session (make-ccemacs-session
                   :workspace ws :token "t" :clients (list tx))))
    (puthash ws session ccemacs-server--registry)
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (insert "line1\nline2\nline3\nline4\n")
          (goto-char (point-min))
          (set-mark (point))
          (forward-line 2)
          (activate-mark)
          (ccemacs-send-at-mention)
          (let* ((msg (ccemacs-mention-test--parse
                       (car (ccemacs-test-transport-sent-list tx)))))
            (should (equal (plist-get msg :method) "at_mentioned"))
            (let ((params (plist-get msg :params)))
              (should (equal (plist-get params :filePath) file))
              (should (equal (plist-get params :lineStart) 0))
              (should (equal (plist-get params :lineEnd) 2))))
          (set-buffer-modified-p nil)
          (kill-buffer))
      (clrhash ccemacs-server--registry)
      (when (file-exists-p ws) (delete-directory ws t)))))

(ert-deftest ccemacs-mention-without-file-buffer-errors ()
  (with-temp-buffer
    (should-error (ccemacs-send-at-mention) :type 'user-error)))

(ert-deftest ccemacs-mention-routes-only-to-session-owning-file ()
  (let* ((ws-a (file-name-as-directory (make-temp-file "ccemacs-mention-a-" t)))
         (ws-b (file-name-as-directory (make-temp-file "ccemacs-mention-b-" t)))
         (tx-a (ccemacs-test-make-transport))
         (tx-b (ccemacs-test-make-transport))
         (session-a (make-ccemacs-session
                     :workspace ws-a :token "ta" :clients (list tx-a)))
         (session-b (make-ccemacs-session
                     :workspace ws-b :token "tb" :clients (list tx-b))))
    (puthash ws-a session-a ccemacs-server--registry)
    (puthash ws-b session-b ccemacs-server--registry)
    (unwind-protect
        (let ((file-in-a (concat ws-a "y.txt")))
          (ccemacs-mention-broadcast file-in-a 0 5)
          (should (= 1 (length (ccemacs-test-transport-sent-list tx-a))))
          (should (= 0 (length (ccemacs-test-transport-sent-list tx-b)))))
      (clrhash ccemacs-server--registry)
      (when (file-exists-p ws-a) (delete-directory ws-a t))
      (when (file-exists-p ws-b) (delete-directory ws-b t)))))

(provide 'ccemacs-mention-test)
;;; ccemacs-mention-test.el ends here
