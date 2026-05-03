;;; ccemacs-test-helper.el --- ERT test helpers -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'ccemacs-rpc)

(cl-defstruct ccemacs-test-transport
  (sent nil))

(defun ccemacs-test-make-transport ()
  (make-ccemacs-test-transport))

(cl-defmethod ccemacs-rpc-transport-send ((tx ccemacs-test-transport) message)
  (setf (ccemacs-test-transport-sent tx)
        (append (ccemacs-test-transport-sent tx) (list message))))

(defun ccemacs-test-transport-sent-list (tx)
  (ccemacs-test-transport-sent tx))

(provide 'ccemacs-test-helper)
;;; ccemacs-test-helper.el ends here
