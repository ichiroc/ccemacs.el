;;; ccemacs-selection-test.el --- Tests for ccemacs-selection -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'json)
(require 'ccemacs-selection)
(require 'ccemacs-server)
(require 'ccemacs-test-helper)

(ert-deftest ccemacs-selection-debounce-coalesces ()
  (let* ((tx (ccemacs-test-make-transport))
         (ccemacs-selection-transport tx)
         (ccemacs-selection-debounce 0.05))
    (ccemacs-selection-on-change '(:text "a"))
    (ccemacs-selection-on-change '(:text "b"))
    (ccemacs-selection-on-change '(:text "c"))
    (sleep-for 0.1)
    (let ((sent (ccemacs-test-transport-sent-list tx)))
      (should (= 1 (length sent)))
      (should (string-match-p "\"text\":\"c\"" (car sent))))))

(ert-deftest ccemacs-selection-emits-notification-shape ()
  (let* ((tx (ccemacs-test-make-transport))
         (ccemacs-selection-transport tx)
         (ccemacs-selection-debounce 0.02))
    (ccemacs-selection-on-change
     '(:text "hello" :filePath "/tmp/x" :fileUrl "file:///tmp/x"))
    (sleep-for 0.05)
    (let* ((msg (json-parse-string
                 (car (ccemacs-test-transport-sent-list tx))
                 :object-type 'plist :array-type 'array)))
      (should (equal (plist-get msg :method) "selection_changed"))
      (should-not (plist-member msg :id))
      (let ((params (plist-get msg :params)))
        (should (equal (plist-get params :text) "hello"))
        (should (equal (plist-get params :filePath) "/tmp/x"))))))

(ert-deftest ccemacs-selection-without-transport-does-not-error ()
  (let ((ccemacs-selection-transport nil)
        (ccemacs-selection-debounce 0.02))
    (ccemacs-selection-on-change '(:text "x"))
    (sleep-for 0.05)))

(ert-deftest ccemacs-selection-make-payload-skips-non-file-buffers ()
  (with-temp-buffer
    (rename-buffer "*Messages-test*" t)
    (should-not (ccemacs-selection--make-payload))))

(ert-deftest ccemacs-selection-make-payload-builds-full-shape-for-region ()
  (let ((file (make-temp-file "ccemacs-sel-payload-" nil ".txt")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (insert "hello\nworld\n")
          (goto-char (point-min))
          (set-mark (point))
          (forward-char 5)
          (activate-mark)
          (let* ((p (ccemacs-selection--make-payload))
                 (sel (plist-get p :selection)))
            (should (equal (plist-get p :text) "hello"))
            (should (equal (plist-get p :filePath) file))
            (should (equal (plist-get p :fileUrl) (concat "file://" file)))
            (should (equal (plist-get sel :isEmpty) :false))
            (should (equal (plist-get (plist-get sel :start) :line) 0))
            (should (equal (plist-get (plist-get sel :end) :character) 5)))
          (set-buffer-modified-p nil)
          (kill-buffer))
      (delete-file file))))

(ert-deftest ccemacs-selection-routes-only-to-session-matching-file ()
  (let* ((ws-a (file-name-as-directory (make-temp-file "ccemacs-sel-a-" t)))
         (ws-b (file-name-as-directory (make-temp-file "ccemacs-sel-b-" t)))
         (tx-a (ccemacs-test-make-transport))
         (tx-b (ccemacs-test-make-transport))
         (session-a (make-ccemacs-session
                     :workspace ws-a :token "ta" :clients (list tx-a)))
         (session-b (make-ccemacs-session
                     :workspace ws-b :token "tb" :clients (list tx-b)))
         (ccemacs-selection-transport nil)
         (ccemacs-selection-debounce 0.02))
    (unwind-protect
        (progn
          (puthash ws-a session-a ccemacs-server--registry)
          (puthash ws-b session-b ccemacs-server--registry)
          (let ((file (concat ws-a "x.txt")))
            (ccemacs-selection-on-change
             `(:text "hi" :filePath ,file
               :fileUrl ,(concat "file://" file))))
          (sleep-for 0.05)
          (should (= 1 (length (ccemacs-test-transport-sent-list tx-a))))
          (should (= 0 (length (ccemacs-test-transport-sent-list tx-b)))))
      (clrhash ccemacs-server--registry)
      (when (file-exists-p ws-a) (delete-directory ws-a t))
      (when (file-exists-p ws-b) (delete-directory ws-b t)))))

(ert-deftest ccemacs-selection-skips-when-no-session-matches-file ()
  (let* ((ws (file-name-as-directory (make-temp-file "ccemacs-sel-no-" t)))
         (tx (ccemacs-test-make-transport))
         (session (make-ccemacs-session
                   :workspace ws :token "t" :clients (list tx)))
         (ccemacs-selection-transport nil)
         (ccemacs-selection-debounce 0.02))
    (unwind-protect
        (progn
          (puthash ws session ccemacs-server--registry)
          (ccemacs-selection-on-change
           '(:text "hi" :filePath "/elsewhere/x.txt"))
          (sleep-for 0.05)
          (should (= 0 (length (ccemacs-test-transport-sent-list tx)))))
      (clrhash ccemacs-server--registry)
      (when (file-exists-p ws) (delete-directory ws t)))))

(provide 'ccemacs-selection-test)
;;; ccemacs-selection-test.el ends here
