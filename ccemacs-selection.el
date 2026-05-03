;;; ccemacs-selection.el --- Selection tracker -*- lexical-binding: t; -*-

;;; Code:

(require 'ccemacs-rpc)

(declare-function ccemacs-server-session-for-file "ccemacs-server" (file))
(declare-function ccemacs-session-clients "ccemacs-server" (session))

(defgroup ccemacs nil
  "Claude Code IDE integration for Emacs."
  :group 'tools
  :prefix "ccemacs-")

(defvar ccemacs-selection-debounce 0.05
  "Seconds to wait before sending selection_changed.")

(defvar ccemacs-selection-transport nil
  "Transport that selection notifications are sent over.")

(defvar ccemacs-selection--timer nil)
(defvar ccemacs-selection--pending nil
  "Pending payload (plist) waiting to be flushed.")

(defvar ccemacs-selection-last-payload nil
  "Most recently sent `selection_changed' payload (plist).")

(defun ccemacs-selection--pos-plist (pos)
  (save-excursion
    (goto-char pos)
    `(:line ,(1- (line-number-at-pos))
      :character ,(- pos (line-beginning-position)))))

(defun ccemacs-selection--make-payload ()
  "Build a `selection_changed' payload for the current buffer.
Return nil for non-file buffers so that *Messages* and similar do not leak."
  (let ((file (buffer-file-name)))
    (when file
      (cond
       ((use-region-p)
        (let* ((begin (region-beginning))
               (end (region-end)))
          `(:text ,(buffer-substring-no-properties begin end)
            :filePath ,file
            :fileUrl ,(concat "file://" file)
            :selection (:start ,(ccemacs-selection--pos-plist begin)
                        :end ,(ccemacs-selection--pos-plist end)
                        :isEmpty :false))))
       (t
        (let* ((pos (point))
               (zero `(:line ,(1- (line-number-at-pos pos))
                       :character ,(- pos (line-beginning-position)))))
          `(:text ""
            :filePath ,file
            :fileUrl ,(concat "file://" file)
            :selection (:start ,zero :end ,zero :isEmpty t))))))))

(defun ccemacs-selection--clients-for-payload (payload)
  "Return the list of clients that should receive PAYLOAD.
Routes by `:filePath' to the session whose workspace owns it."
  (let ((file (plist-get payload :filePath)))
    (when (and file (fboundp 'ccemacs-server-session-for-file))
      (let ((session (ccemacs-server-session-for-file file)))
        (when session (ccemacs-session-clients session))))))

(defun ccemacs-selection--flush ()
  (setq ccemacs-selection--timer nil)
  (let ((payload ccemacs-selection--pending))
    (when payload
      (setq ccemacs-selection-last-payload payload)
      (cond
       (ccemacs-selection-transport
        (ccemacs-rpc-send-notification
         ccemacs-selection-transport "selection_changed" payload))
       (t
        (dolist (client (ccemacs-selection--clients-for-payload payload))
          (ccemacs-rpc-send-notification
           client "selection_changed" payload)))))))

(defun ccemacs-selection-on-change (payload)
  "Schedule a debounced `selection_changed' notification carrying PAYLOAD."
  (setq ccemacs-selection--pending payload)
  (when (timerp ccemacs-selection--timer)
    (cancel-timer ccemacs-selection--timer))
  (setq ccemacs-selection--timer
        (run-at-time ccemacs-selection-debounce nil
                     #'ccemacs-selection--flush)))

(defvar ccemacs-selection--last-text nil)

(defun ccemacs-selection--maybe-emit ()
  (let ((payload (ccemacs-selection--make-payload)))
    (when payload
      (let ((text (plist-get payload :text)))
        (unless (equal text ccemacs-selection--last-text)
          (setq ccemacs-selection--last-text text)
          (ccemacs-selection-on-change payload))))))

;;;###autoload
(define-minor-mode ccemacs-selection-mode
  "Watch the active region and broadcast `selection_changed' notifications."
  :global t
  :group 'ccemacs
  (cond
   (ccemacs-selection-mode
    (add-hook 'post-command-hook #'ccemacs-selection--maybe-emit))
   (t
    (remove-hook 'post-command-hook #'ccemacs-selection--maybe-emit))))

(provide 'ccemacs-selection)
;;; ccemacs-selection.el ends here
