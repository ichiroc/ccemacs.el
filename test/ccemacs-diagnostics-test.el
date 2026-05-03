;;; ccemacs-diagnostics-test.el --- Tests for ccemacs-diagnostics -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'flymake)
(require 'ccemacs-diagnostics)

(ert-deftest ccemacs-diagnostics-empty-buffer-returns-no-diagnostics ()
  (with-temp-buffer
    (should-not (ccemacs-diagnostics--from-buffer (current-buffer)))))

(ert-deftest ccemacs-diagnostics-from-flymake-normalizes-fields ()
  (let ((file (make-temp-file "ccemacs-diag-" nil ".el")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (insert "abc\ndef\n")
          (cl-letf
              (((symbol-function 'ccemacs-diagnostics--flymake-active-p)
                (lambda (_) t))
               ((symbol-function 'flymake-diagnostics)
                (lambda (&rest _)
                  (list (flymake-make-diagnostic
                         (current-buffer) 1 4 :error "bad")
                        (flymake-make-diagnostic
                         (current-buffer) 5 7 :warning "meh")))))
            (let* ((diags (ccemacs-diagnostics--from-flymake (current-buffer)))
                   (first (nth 0 diags))
                   (second (nth 1 diags)))
              (should (= 2 (length diags)))
              (should (equal (plist-get first :severity) 1))
              (should (equal (plist-get first :message) "bad"))
              (should (equal (plist-get first :source) "flymake"))
              (should (equal (plist-get
                              (plist-get (plist-get first :range) :start)
                              :line)
                             0))
              (should (equal (plist-get second :severity) 2))))
          (set-buffer-modified-p nil)
          (kill-buffer))
      (delete-file file))))

(ert-deftest ccemacs-diagnostics-collect-by-uri-filters-buffers ()
  (let ((file (make-temp-file "ccemacs-diag-" nil ".el")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (insert "abc\n")
          (cl-letf
              (((symbol-function 'ccemacs-diagnostics--flymake-active-p)
                (lambda (b) (eq b (current-buffer))))
               ((symbol-function 'flymake-diagnostics)
                (lambda (&rest _)
                  (list (flymake-make-diagnostic
                         (current-buffer) 1 2 :error "x")))))
            (let* ((res (ccemacs-diagnostics-collect
                         (concat "file://" file)))
                   (diags (plist-get res :diagnostics)))
              (should (vectorp diags))
              (should (= 1 (length diags)))))
          (set-buffer-modified-p nil)
          (kill-buffer))
      (delete-file file))))

(provide 'ccemacs-diagnostics-test)
;;; ccemacs-diagnostics-test.el ends here
