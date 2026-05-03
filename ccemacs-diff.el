;;; ccemacs-diff.el --- openDiff with deferred response -*- lexical-binding: t; -*-

;;; Code:

(require 'ediff)
(require 'ccemacs-rpc)

(defvar ccemacs-diff--pending (make-hash-table :test 'equal)
  "tab-name (string) -> (TRANSPORT . ID) for in-flight openDiff calls.")

(defun ccemacs-diff--text-result (text)
  `(:content ,(vector `(:type "text" :text ,text))))

(defun ccemacs-diff--register (tab-name transport id)
  (puthash tab-name (cons transport id) ccemacs-diff--pending))

(defun ccemacs-diff--resolve (tab-name result)
  (let ((pair (gethash tab-name ccemacs-diff--pending)))
    (when pair
      (remhash tab-name ccemacs-diff--pending)
      (ccemacs-rpc-send-response (car pair) (cdr pair) result))))

(defun ccemacs-diff-resolve-saved (tab-name)
  (ccemacs-diff--resolve tab-name (ccemacs-diff--text-result "FILE_SAVED")))

(defun ccemacs-diff-resolve-rejected (tab-name)
  (ccemacs-diff--resolve tab-name (ccemacs-diff--text-result "DIFF_REJECTED")))

(defun ccemacs-diff--scratch-buffer (tab-name new-contents)
  (let ((buf (generate-new-buffer (format "*ccemacs-diff:%s*" tab-name))))
    (with-current-buffer buf
      (insert new-contents))
    buf))

(defun ccemacs-diff--launch (old-path _new-path new-contents tab-name)
  "Launch an ediff session for OLD-PATH against NEW-CONTENTS, keyed by TAB-NAME."
  (let* ((proposed (ccemacs-diff--scratch-buffer tab-name new-contents))
         (original (find-file-noselect old-path))
         (control (ediff-buffers original proposed)))
    (with-current-buffer control
      (setq-local ccemacs-diff--tab-name tab-name)
      (setq-local ccemacs-diff--proposed-buffer proposed)
      (setq-local ccemacs-diff--original-buffer original)
      (add-hook 'ediff-quit-hook #'ccemacs-diff--on-ediff-quit nil t))
    control))

(defvar-local ccemacs-diff--tab-name nil)
(defvar-local ccemacs-diff--proposed-buffer nil)
(defvar-local ccemacs-diff--original-buffer nil)

(defun ccemacs-diff--on-ediff-quit ()
  (let ((tab-name ccemacs-diff--tab-name)
        (proposed ccemacs-diff--proposed-buffer)
        (original ccemacs-diff--original-buffer))
    (when (and tab-name original proposed)
      (let ((accepted
             (with-current-buffer original
               (and (buffer-modified-p)
                    (yes-or-no-p
                     (format "ccemacs: save %s? "
                             (buffer-file-name original)))))))
        (cond
         (accepted
          (with-current-buffer original (save-buffer))
          (ccemacs-diff-resolve-saved tab-name))
         (t
          (with-current-buffer original
            (when (buffer-modified-p)
              (revert-buffer t t)))
          (ccemacs-diff-resolve-rejected tab-name)))
        (when (buffer-live-p proposed) (kill-buffer proposed))))))

(provide 'ccemacs-diff)
;;; ccemacs-diff.el ends here
