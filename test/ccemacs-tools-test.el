;;; ccemacs-tools-test.el --- Tests for ccemacs-tools -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'json)
(require 'ccemacs-tools)
(require 'ccemacs-selection)
(require 'ccemacs-server)
(require 'ccemacs-test-helper)

(defun ccemacs-tools-test--call (name &optional args)
  "Invoke `tools/call' on NAME with ARGS plist. Return parsed result plist."
  (ccemacs-tools-handle-call `(:name ,name :arguments ,args)))

(defun ccemacs-tools-test--text-payload (result)
  "Extract the JSON-decoded text payload from MCP RESULT plist."
  (let* ((content (plist-get result :content))
         (first (and (vectorp content) (> (length content) 0) (aref content 0))))
    (when first
      (json-parse-string (plist-get first :text)
                         :object-type 'plist :array-type 'array
                         :false-object :false :null-object :null))))

(ert-deftest ccemacs-tools-list-includes-known-tools ()
  (let* ((res (ccemacs-tools-handle-list nil))
         (tools (plist-get res :tools))
         (names (mapcar (lambda (t-) (plist-get t- :name))
                        (append tools nil))))
    (should (member "getCurrentSelection" names))
    (should (member "getLatestSelection" names))
    (should (member "getOpenEditors" names))
    (should (member "getWorkspaceFolders" names))
    (should (member "checkDocumentDirty" names))))

(ert-deftest ccemacs-tools-call-unknown-tool-returns-mcp-error ()
  (let ((res (ccemacs-tools-test--call "no.such.tool")))
    (should (equal (plist-get res :isError) t))))

(ert-deftest ccemacs-tools-getCurrentSelection-without-region ()
  (with-temp-buffer
    (let* ((res (ccemacs-tools-test--call "getCurrentSelection"))
           (payload (ccemacs-tools-test--text-payload res))
           (sel (plist-get payload :selection)))
      (should (equal (plist-get payload :text) ""))
      (should (equal (plist-get sel :isEmpty) t)))))

(ert-deftest ccemacs-tools-getCurrentSelection-with-region ()
  (let ((file (make-temp-file "ccemacs-sel-" nil ".txt")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (insert "hello\nworld\n")
          (goto-char (point-min))
          (set-mark (point))
          (forward-char 5) ;; "hello"
          (activate-mark)
          (let* ((res (ccemacs-tools-test--call "getCurrentSelection"))
                 (payload (ccemacs-tools-test--text-payload res))
                 (sel (plist-get payload :selection))
                 (start (plist-get sel :start))
                 (end (plist-get sel :end)))
            (should (equal (plist-get payload :text) "hello"))
            (should (equal (plist-get payload :filePath) file))
            (should (equal (plist-get sel :isEmpty) :false))
            (should (equal (plist-get start :line) 0))
            (should (equal (plist-get start :character) 0))
            (should (equal (plist-get end :line) 0))
            (should (equal (plist-get end :character) 5)))
          (set-buffer-modified-p nil)
          (kill-buffer))
      (delete-file file))))

(ert-deftest ccemacs-tools-getLatestSelection-returns-last-payload ()
  (let ((ccemacs-selection-last-payload '(:text "remembered")))
    (let* ((res (ccemacs-tools-test--call "getLatestSelection"))
           (payload (ccemacs-tools-test--text-payload res)))
      (should (equal (plist-get payload :text) "remembered")))))

(ert-deftest ccemacs-tools-getOpenEditors-lists-file-buffers ()
  (let ((file (make-temp-file "ccemacs-ed-" nil ".txt")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (let* ((res (ccemacs-tools-test--call "getOpenEditors"))
                 (payload (ccemacs-tools-test--text-payload res))
                 (tabs (plist-get payload :tabs))
                 (paths (mapcar (lambda (t-) (plist-get t- :filePath))
                                (append tabs nil))))
            (should (member file paths)))
          (kill-buffer))
      (delete-file file))))

(ert-deftest ccemacs-tools-checkDocumentDirty-tracks-modified-p ()
  (let ((file (make-temp-file "ccemacs-dirty-" nil ".txt")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (let* ((res-clean (ccemacs-tools-test--call
                             "checkDocumentDirty"
                             `(:filePath ,file)))
                 (clean (ccemacs-tools-test--text-payload res-clean)))
            (should (equal (plist-get clean :exists) t))
            (should (equal (plist-get clean :isDirty) :false)))
          (insert "X")
          (let* ((res-dirty (ccemacs-tools-test--call
                             "checkDocumentDirty"
                             `(:filePath ,file)))
                 (dirty (ccemacs-tools-test--text-payload res-dirty)))
            (should (equal (plist-get dirty :isDirty) t)))
          (set-buffer-modified-p nil)
          (kill-buffer))
      (delete-file file))))

(ert-deftest ccemacs-tools-openFile-opens-buffer ()
  (let ((file (make-temp-file "ccemacs-open-" nil ".txt")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "line1\nline2\nline3\n"))
          (let ((res (ccemacs-tools-test--call
                      "openFile" `(:filePath ,file))))
            (should-not (plist-get res :isError))
            (should (find-buffer-visiting file))))
      (let ((buf (find-buffer-visiting file)))
        (when buf (kill-buffer buf)))
      (delete-file file))))

(ert-deftest ccemacs-tools-openFile-positions-region ()
  (let ((file (make-temp-file "ccemacs-open-" nil ".txt")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "line1\nline2\nline3\nline4\n"))
          (ccemacs-tools-test--call
           "openFile" `(:filePath ,file :startLine 2 :endLine 3))
          (with-current-buffer (find-buffer-visiting file)
            (should (= (line-number-at-pos (point)) 3))
            (should (use-region-p))))
      (let ((buf (find-buffer-visiting file)))
        (when buf (kill-buffer buf)))
      (delete-file file))))

(ert-deftest ccemacs-tools-openFile-missing-path-returns-error ()
  (let ((res (ccemacs-tools-test--call
              "openFile" '(:filePath "/this/does/not/exist.txt"))))
    (should (plist-get res :isError))))

(ert-deftest ccemacs-tools-saveDocument-saves-buffer ()
  (let ((file (make-temp-file "ccemacs-save-" nil ".txt")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (insert "data")
          (let* ((res (ccemacs-tools-test--call
                       "saveDocument" `(:filePath ,file)))
                 (payload (ccemacs-tools-test--text-payload res)))
            (should-not (plist-get res :isError))
            (should (equal (plist-get payload :saved) t))
            (should-not (buffer-modified-p)))
          (kill-buffer))
      (delete-file file))))

(ert-deftest ccemacs-tools-saveDocument-without-buffer-returns-error ()
  (let ((res (ccemacs-tools-test--call
              "saveDocument" '(:filePath "/no/such/file.txt"))))
    (should (plist-get res :isError))))

(ert-deftest ccemacs-tools-close-tab-rejects-pending-diff ()
  (let ((tx (ccemacs-test-make-transport)))
    (clrhash ccemacs-diff--pending)
    (ccemacs-diff--register "diff:close" tx 5)
    (let* ((res (ccemacs-tools-test--call
                 "close_tab" '(:tab_name "diff:close")))
           (payload (ccemacs-tools-test--text-payload res)))
      (should (equal (plist-get payload :closed) t))
      (should-not (gethash "diff:close" ccemacs-diff--pending)))))

(ert-deftest ccemacs-tools-close-tab-kills-buffer-by-path ()
  (let ((file (make-temp-file "ccemacs-close-" nil ".txt")))
    (unwind-protect
        (progn
          (find-file-noselect file)
          (let* ((res (ccemacs-tools-test--call
                       "close_tab" `(:filePath ,file)))
                 (payload (ccemacs-tools-test--text-payload res)))
            (should (equal (plist-get payload :closed) t))
            (should-not (find-buffer-visiting file))))
      (delete-file file))))

(ert-deftest ccemacs-tools-executeCode-returns-error ()
  (let ((res (ccemacs-tools-test--call "executeCode" '(:code "x"))))
    (should (plist-get res :isError))))

(ert-deftest ccemacs-tools-getWorkspaceFolders-returns-non-empty-folders ()
  (let* ((res (ccemacs-tools-test--call "getWorkspaceFolders"))
         (payload (ccemacs-tools-test--text-payload res))
         (folders (plist-get payload :folders)))
    (should (vectorp folders))
    (should (> (length folders) 0))
    (let* ((first (aref folders 0)))
      (should (stringp (plist-get first :path))))))

(ert-deftest ccemacs-tools-getWorkspaceFolders-returns-callers-workspace ()
  (let* ((ws (file-name-as-directory (make-temp-file "ccemacs-tools-ws-" t)))
         (client (ccemacs-test-make-transport))
         (session (make-ccemacs-session
                   :workspace ws :token "t" :clients (list client))))
    (puthash ws session ccemacs-server--registry)
    (unwind-protect
        (let* ((ccemacs-rpc-current-transport client)
               (res (ccemacs-tools-test--call "getWorkspaceFolders"))
               (payload (ccemacs-tools-test--text-payload res))
               (folders (plist-get payload :folders)))
          (should (= 1 (length folders)))
          (should (equal (plist-get (aref folders 0) :path) ws)))
      (clrhash ccemacs-server--registry)
      (when (file-exists-p ws) (delete-directory ws t)))))

(ert-deftest ccemacs-tools-getOpenEditors-filters-by-callers-workspace ()
  (let* ((ws-a (file-name-as-directory (make-temp-file "ccemacs-ed-a-" t)))
         (ws-b (file-name-as-directory (make-temp-file "ccemacs-ed-b-" t)))
         (file-a (expand-file-name "a.txt" ws-a))
         (file-b (expand-file-name "b.txt" ws-b))
         (client (ccemacs-test-make-transport))
         (session-a (make-ccemacs-session
                     :workspace ws-a :token "ta" :clients (list client)))
         (session-b (make-ccemacs-session
                     :workspace ws-b :token "tb")))
    (puthash ws-a session-a ccemacs-server--registry)
    (puthash ws-b session-b ccemacs-server--registry)
    (unwind-protect
        (progn
          (find-file-noselect file-a)
          (find-file-noselect file-b)
          (let* ((ccemacs-rpc-current-transport client)
                 (res (ccemacs-tools-test--call "getOpenEditors"))
                 (payload (ccemacs-tools-test--text-payload res))
                 (paths (mapcar (lambda (t-) (plist-get t- :filePath))
                                (append (plist-get payload :tabs) nil))))
            (should (member file-a paths))
            (should-not (member file-b paths))))
      (clrhash ccemacs-server--registry)
      (dolist (f (list file-a file-b))
        (let ((b (find-buffer-visiting f)))
          (when b (with-current-buffer b (set-buffer-modified-p nil))
                (kill-buffer b))))
      (when (file-exists-p ws-a) (delete-directory ws-a t))
      (when (file-exists-p ws-b) (delete-directory ws-b t)))))

(provide 'ccemacs-tools-test)
;;; ccemacs-tools-test.el ends here
