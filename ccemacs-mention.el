;;; ccemacs-mention.el --- Push at_mentioned notifications -*- lexical-binding: t; -*-

;;; Code:

(require 'ccemacs-rpc)
(require 'ccemacs-server)

(defun ccemacs-mention--current-range ()
  (let* ((begin (if (use-region-p) (region-beginning) (point)))
         (end (if (use-region-p) (region-end) (point)))
         (line-start (1- (line-number-at-pos begin)))
         (line-end (1- (line-number-at-pos end))))
    (cons line-start line-end)))

(defun ccemacs-mention--clients-for-file (file)
  "Return clients of the session whose workspace owns FILE, or nil."
  (let ((session (ccemacs-server-session-for-file file)))
    (when session (ccemacs-session-clients session))))

(defun ccemacs-mention-broadcast (file line-start line-end)
  "Send `at_mentioned' for FILE between LINE-START and LINE-END.
Delivered only to clients of the session whose workspace owns FILE."
  (let ((params `(:filePath ,file
                  :lineStart ,line-start
                  :lineEnd ,line-end)))
    (dolist (client (ccemacs-mention--clients-for-file file))
      (ccemacs-rpc-send-notification client "at_mentioned" params))))

;;;###autoload
(defun ccemacs-send-at-mention ()
  "Notify connected Claude clients about the current selection or point."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless file
      (user-error "Buffer is not visiting a file"))
    (let* ((range (ccemacs-mention--current-range))
           (line-start (car range))
           (line-end (cdr range))
           (recipients (ccemacs-mention--clients-for-file file)))
      (ccemacs-mention-broadcast file line-start line-end)
      (message "ccemacs: mentioned %s:%d-%d to %d client(s)"
               (file-name-nondirectory file)
               (1+ line-start) (1+ line-end)
               (length recipients)))))

(provide 'ccemacs-mention)
;;; ccemacs-mention.el ends here
