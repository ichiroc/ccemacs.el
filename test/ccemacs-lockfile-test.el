;;; ccemacs-lockfile-test.el --- Tests for ccemacs-lockfile -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'json)
(require 'ccemacs-lockfile)

(ert-deftest ccemacs-lockfile-write-and-cleanup ()
  (let* ((tmp-dir (make-temp-file "ccemacs-test-" t))
         (ccemacs-lockfile-dir tmp-dir)
         (port 54321)
         (token "abc-123")
         (workspace "/tmp/proj"))
    (unwind-protect
        (progn
          (ccemacs-lockfile-write port token workspace)
          (let ((path (expand-file-name "54321.lock" ccemacs-lockfile-dir)))
            (should (file-exists-p path))
            (should (= #o600 (file-modes path)))
            (let ((j (json-parse-string
                      (with-temp-buffer
                        (insert-file-contents path)
                        (buffer-string))
                      :object-type 'plist)))
              (should (equal (plist-get j :authToken) token))
              (should (equal (plist-get j :transport) "ws"))
              (should (equal (plist-get j :ideName) "Emacs"))
              (should (equal (aref (plist-get j :workspaceFolders) 0)
                             workspace))
              (should (integerp (plist-get j :pid))))
            (ccemacs-lockfile-delete port)
            (should-not (file-exists-p path))))
      (when (file-exists-p tmp-dir)
        (delete-directory tmp-dir t)))))

(ert-deftest ccemacs-lockfile-dir-permissions ()
  "Parent directory should be created with 0700 if it does not exist."
  (let* ((parent (make-temp-file "ccemacs-test-parent-" t))
         (ccemacs-lockfile-dir (expand-file-name "ide" parent))
         (port 12345))
    (unwind-protect
        (progn
          (ccemacs-lockfile-write port "tok" "/tmp/x")
          (should (file-directory-p ccemacs-lockfile-dir))
          (should (= #o700 (file-modes ccemacs-lockfile-dir))))
      (when (file-exists-p parent)
        (delete-directory parent t)))))

(provide 'ccemacs-lockfile-test)
;;; ccemacs-lockfile-test.el ends here
