;;; ccemacs-lockfile.el --- Lock file under ~/.claude/ide -*- lexical-binding: t; -*-

;;; Code:

(require 'json)

(defvar ccemacs-lockfile-dir (expand-file-name "~/.claude/ide")
  "Directory where Claude Code looks up IDE lock files.")

(defun ccemacs-lockfile--path (port)
  (expand-file-name (format "%d.lock" port) ccemacs-lockfile-dir))

(defun ccemacs-lockfile--ensure-dir ()
  (make-directory ccemacs-lockfile-dir t)
  (set-file-modes ccemacs-lockfile-dir #o700))

(defun ccemacs-lockfile--payload (token workspace)
  (json-serialize
   `(:pid ,(emacs-pid)
     :workspaceFolders [,workspace]
     :ideName "Emacs"
     :transport "ws"
     :authToken ,token)))

(defun ccemacs-lockfile-write (port token workspace)
  "Write the lock file for PORT with TOKEN and WORKSPACE root path."
  (ccemacs-lockfile--ensure-dir)
  (let ((path (ccemacs-lockfile--path port)))
    (with-temp-file path (insert (ccemacs-lockfile--payload token workspace)))
    (set-file-modes path #o600)))

(defun ccemacs-lockfile-delete (port)
  "Delete the lock file for PORT if it exists."
  (let ((path (ccemacs-lockfile--path port)))
    (when (file-exists-p path) (delete-file path))))

(defun ccemacs-lockfile--pid-alive-p (pid)
  "Return non-nil iff PID names a live OS process."
  (and (integerp pid) (> pid 0)
       (process-attributes pid) t))

(defun ccemacs-lockfile-cleanup-stale ()
  "Remove lock files whose recorded pid is no longer alive.
Malformed files are left untouched so we never destroy state we
don't understand."
  (when (file-directory-p ccemacs-lockfile-dir)
    (dolist (path (directory-files ccemacs-lockfile-dir t "\\.lock\\'"))
      (let ((pid (condition-case _err
                     (plist-get
                      (json-parse-string
                       (with-temp-buffer
                         (insert-file-contents path)
                         (buffer-string))
                       :object-type 'plist)
                      :pid)
                   (error :ccemacs-malformed))))
        (cond
         ((eq pid :ccemacs-malformed) nil)
         ((ccemacs-lockfile--pid-alive-p pid) nil)
         (t (ignore-errors (delete-file path))))))))

(provide 'ccemacs-lockfile)
;;; ccemacs-lockfile.el ends here
