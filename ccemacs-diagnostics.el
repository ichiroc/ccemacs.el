;;; ccemacs-diagnostics.el --- Flycheck/Flymake diagnostics adapter -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'flymake nil t)

(defvar flycheck-current-errors)
(declare-function flycheck-error-line "flycheck")
(declare-function flycheck-error-column "flycheck")
(declare-function flycheck-error-level "flycheck")
(declare-function flycheck-error-message "flycheck")

(defun ccemacs-diagnostics--pos-plist-at (pos)
  (save-excursion
    (goto-char pos)
    `(:line ,(1- (line-number-at-pos))
      :character ,(- pos (line-beginning-position)))))

(defun ccemacs-diagnostics--severity-from-flymake-type (type)
  (pcase type
    (:error 1) (:warning 2) (:note 3) (_ 3)))

(defun ccemacs-diagnostics--flymake-active-p (buffer)
  (with-current-buffer buffer
    (and (fboundp 'flymake-mode)
         (bound-and-true-p flymake-mode))))

(defun ccemacs-diagnostics--from-flymake (buffer)
  (when (ccemacs-diagnostics--flymake-active-p buffer)
    (with-current-buffer buffer
      (let ((file (buffer-file-name)))
        (mapcar
         (lambda (d)
           `(:uri ,(if file (concat "file://" file) :null)
             :range (:start ,(ccemacs-diagnostics--pos-plist-at
                              (flymake-diagnostic-beg d))
                     :end ,(ccemacs-diagnostics--pos-plist-at
                            (flymake-diagnostic-end d)))
             :severity ,(ccemacs-diagnostics--severity-from-flymake-type
                         (flymake-diagnostic-type d))
             :message ,(flymake-diagnostic-text d)
             :source "flymake"))
         (flymake-diagnostics))))))

(defun ccemacs-diagnostics--flycheck-active-p (buffer)
  (with-current-buffer buffer
    (and (fboundp 'flycheck-current-errors)
         (bound-and-true-p flycheck-mode))))

(defun ccemacs-diagnostics--severity-from-flycheck-level (level)
  (pcase level
    ('error 1) ('warning 2) ('info 3) (_ 3)))

(defun ccemacs-diagnostics--from-flycheck (buffer)
  (when (ccemacs-diagnostics--flycheck-active-p buffer)
    (with-current-buffer buffer
      (let ((file (buffer-file-name)))
        (mapcar
         (lambda (err)
           (let* ((line (or (flycheck-error-line err) 1))
                  (col (or (flycheck-error-column err) 0))
                  (level (flycheck-error-level err))
                  (msg (or (flycheck-error-message err) "")))
             `(:uri ,(if file (concat "file://" file) :null)
               :range (:start (:line ,(1- line) :character ,col)
                       :end (:line ,(1- line) :character ,(1+ col)))
               :severity ,(ccemacs-diagnostics--severity-from-flycheck-level level)
               :message ,msg
               :source "flycheck")))
         flycheck-current-errors)))))

(defun ccemacs-diagnostics--from-buffer (buffer)
  (or (ccemacs-diagnostics--from-flycheck buffer)
      (ccemacs-diagnostics--from-flymake buffer)))

(defun ccemacs-diagnostics-collect (&optional uri)
  (let ((buffers
         (cond
          (uri
           (let ((path (replace-regexp-in-string "\\`file://" "" uri)))
             (delq nil (list (find-buffer-visiting path)))))
          (t (buffer-list))))
        result)
    (dolist (buf buffers)
      (when (buffer-live-p buf)
        (setq result
              (append result (ccemacs-diagnostics--from-buffer buf)))))
    `(:diagnostics ,(apply #'vector result))))

(provide 'ccemacs-diagnostics)
;;; ccemacs-diagnostics.el ends here
