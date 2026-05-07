;;; ccemacs-tmux-test.el --- Tests for ccemacs-tmux -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ccemacs-tmux)

(defmacro ccemacs-tmux-test--with-env (pairs &rest body)
  "Run BODY with PAIRS ((NAME VALUE) ...) applied to `process-environment'.
A VALUE of nil unsets the variable."
  (declare (indent 1))
  `(let ((process-environment (copy-sequence process-environment)))
     ,@(mapcar (lambda (pair)
                 `(setenv ,(car pair) ,(cadr pair)))
               pairs)
     ,@body))

(defmacro ccemacs-tmux-test--capturing-call-process (var &rest body)
  "Run BODY with `call-process' stubbed to push its argv onto VAR.
The stub returns 0 (success). VAR ends up as a list of argv lists,
in invocation order."
  (declare (indent 1))
  `(let ((,var nil))
     (cl-letf (((symbol-function 'call-process)
                (lambda (program &optional _infile _destination _display
                                 &rest args)
                  (setq ,var (append ,var (list (cons program args))))
                  0)))
       ,@body)))

(ert-deftest ccemacs-tmux-inside-tmux-p-detects-env ()
  (ccemacs-tmux-test--with-env (("TMUX" "/tmp/tmux-1000/default,1234,0"))
    (should (ccemacs-tmux--inside-tmux-p)))
  (ccemacs-tmux-test--with-env (("TMUX" nil))
    (should-not (ccemacs-tmux--inside-tmux-p)))
  (ccemacs-tmux-test--with-env (("TMUX" ""))
    (should-not (ccemacs-tmux--inside-tmux-p))))

(ert-deftest ccemacs-tmux-build-args-new-window ()
  (let ((ccemacs-tmux-split 'window)
        (ccemacs-tmux-window-name "claude")
        (ccemacs-tmux-claude-command "claude"))
    (should (equal (ccemacs-tmux--build-args "/tmp/ws/")
                   '("new-window" "-n" "claude"
                     "-c" "/tmp/ws/" "claude")))))

(ert-deftest ccemacs-tmux-build-args-split-horizontal ()
  (let ((ccemacs-tmux-split 'horizontal)
        (ccemacs-tmux-claude-command "claude"))
    (should (equal (ccemacs-tmux--build-args "/tmp/ws/")
                   '("split-window" "-h" "-c" "/tmp/ws/" "claude")))))

(ert-deftest ccemacs-tmux-build-args-split-vertical ()
  (let ((ccemacs-tmux-split 'vertical)
        (ccemacs-tmux-claude-command "claude"))
    (should (equal (ccemacs-tmux--build-args "/tmp/ws/")
                   '("split-window" "-v" "-c" "/tmp/ws/" "claude")))))

(ert-deftest ccemacs-tmux-build-args-rejects-unknown-split ()
  (let ((ccemacs-tmux-split 'diagonal))
    (should-error (ccemacs-tmux--build-args "/tmp/ws/"))))

(ert-deftest ccemacs-tmux-launch-errors-when-not-in-tmux ()
  (ccemacs-tmux-test--with-env (("TMUX" nil))
    (should-error (ccemacs-tmux-launch-claude) :type 'user-error)))

(ert-deftest ccemacs-tmux-launch-invokes-tmux-with-built-args ()
  (ccemacs-tmux-test--with-env (("TMUX" "/tmp/tmux,1,0"))
    (let ((ccemacs-tmux-split 'window)
          (ccemacs-tmux-window-name "claude")
          (ccemacs-tmux-claude-command "claude")
          (default-directory "/tmp/ws/")
          (ccemacs-tmux-auto-start-server nil))
      (ccemacs-tmux-test--capturing-call-process calls
        (ccemacs-tmux-launch-claude)
        (should (= 1 (length calls)))
        (let ((argv (car calls)))
          (should (equal (car argv) "tmux"))
          (should (equal (cdr argv)
                         '("new-window" "-n" "claude"
                           "-c" "/tmp/ws/" "claude"))))))))

(ert-deftest ccemacs-tmux-launch-auto-starts-server-when-enabled ()
  (ccemacs-tmux-test--with-env (("TMUX" "/tmp/tmux,1,0"))
    (let ((ccemacs-tmux-auto-start-server t)
          (default-directory "/tmp/ws/")
          (started nil))
      (cl-letf (((symbol-function 'ccemacs-server-running-p)
                 (lambda (&optional _ws) nil))
                ((symbol-function 'ccemacs-server-start)
                 (lambda () (setq started t) 12345)))
        (ccemacs-tmux-test--capturing-call-process _calls
          (ccemacs-tmux-launch-claude)
          (should started))))))

(ert-deftest ccemacs-tmux-launch-skips-auto-start-when-already-running ()
  (ccemacs-tmux-test--with-env (("TMUX" "/tmp/tmux,1,0"))
    (let ((ccemacs-tmux-auto-start-server t)
          (default-directory "/tmp/ws/")
          (started nil))
      (cl-letf (((symbol-function 'ccemacs-server-running-p)
                 (lambda (&optional _ws) t))
                ((symbol-function 'ccemacs-server-start)
                 (lambda () (setq started t) 12345)))
        (ccemacs-tmux-test--capturing-call-process _calls
          (ccemacs-tmux-launch-claude)
          (should-not started))))))

(provide 'ccemacs-tmux-test)
;;; ccemacs-tmux-test.el ends here
