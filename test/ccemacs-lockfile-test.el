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

(ert-deftest ccemacs-lockfile-cleanup-stale-removes-dead-pid-files ()
  "A lockfile whose pid is no longer alive must be deleted."
  (let* ((tmp-dir (make-temp-file "ccemacs-test-stale-" t))
         (ccemacs-lockfile-dir tmp-dir)
         (alive-port 11111)
         (dead-port 22222)
         (alive-path (expand-file-name "11111.lock" tmp-dir))
         (dead-path (expand-file-name "22222.lock" tmp-dir)))
    (unwind-protect
        (progn
          (with-temp-file alive-path
            (insert (json-serialize
                     `(:pid ,(emacs-pid)
                       :workspaceFolders ["/tmp/a"]
                       :ideName "Emacs" :transport "ws"
                       :authToken "alive"))))
          (with-temp-file dead-path
            (insert (json-serialize
                     `(:pid 1
                       :workspaceFolders ["/tmp/b"]
                       :ideName "Emacs" :transport "ws"
                       :authToken "dead"))))
          ;; Pretend pid 1 is dead. We can't easily fake it, but pid 1
          ;; is launchd on macOS / init on Linux — definitely alive.
          ;; Use a pid that is overwhelmingly unlikely to exist instead.
          (with-temp-file dead-path
            (insert (json-serialize
                     `(:pid 999999
                       :workspaceFolders ["/tmp/b"]
                       :ideName "Emacs" :transport "ws"
                       :authToken "dead"))))
          (ccemacs-lockfile-cleanup-stale)
          (should (file-exists-p alive-path))
          (should-not (file-exists-p dead-path)))
      (when (file-exists-p tmp-dir)
        (delete-directory tmp-dir t)))))

(ert-deftest ccemacs-lockfile-cleanup-stale-skips-malformed-files ()
  "Files that are not valid JSON should be left alone."
  (let* ((tmp-dir (make-temp-file "ccemacs-test-mal-" t))
         (ccemacs-lockfile-dir tmp-dir)
         (path (expand-file-name "33333.lock" tmp-dir)))
    (unwind-protect
        (progn
          (with-temp-file path (insert "not json"))
          (ccemacs-lockfile-cleanup-stale)
          (should (file-exists-p path)))
      (when (file-exists-p tmp-dir)
        (delete-directory tmp-dir t)))))

(provide 'ccemacs-lockfile-test)
;;; ccemacs-lockfile-test.el ends here
