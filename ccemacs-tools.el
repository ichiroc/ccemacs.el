;;; ccemacs-tools.el --- MCP tools/* dispatcher and handlers -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'project)
(require 'ccemacs-rpc)
(require 'ccemacs-selection)
(require 'ccemacs-diff)
(require 'ccemacs-diagnostics)

(declare-function ccemacs-server-session-for-client "ccemacs-server" (client))
(declare-function ccemacs-session-workspace "ccemacs-server" (session))

(cl-defstruct ccemacs-tool name description input-schema handler)

(defvar ccemacs-tools--registry (make-hash-table :test 'equal))

(defun ccemacs-tools-register (name description input-schema handler)
  (puthash name
           (make-ccemacs-tool :name name
                              :description description
                              :input-schema input-schema
                              :handler handler)
           ccemacs-tools--registry))

(defun ccemacs-tools--empty-object ()
  (make-hash-table :test 'equal))

(defun ccemacs-tools--ensure-vector (lst)
  (apply #'vector lst))

(defun ccemacs-tools--list-payload ()
  (let (entries)
    (maphash
     (lambda (_k tool)
       (push `(:name ,(ccemacs-tool-name tool)
               :description ,(ccemacs-tool-description tool)
               :inputSchema ,(or (ccemacs-tool-input-schema tool)
                                 (ccemacs-tools--empty-object)))
             entries))
     ccemacs-tools--registry)
    (ccemacs-tools--ensure-vector (nreverse entries))))

(defun ccemacs-tools-handle-list (_params)
  `(:tools ,(ccemacs-tools--list-payload)))

(defun ccemacs-tools--text-result (payload)
  (let ((text (if (stringp payload) payload (json-serialize payload))))
    `(:content ,(vector `(:type "text" :text ,text)))))

(defun ccemacs-tools--error-result (message)
  `(:isError t
    :content ,(vector `(:type "text" :text ,message))))

(defun ccemacs-tools-handle-call (params)
  (let* ((name (plist-get params :name))
         (args (plist-get params :arguments))
         (tool (and name (gethash name ccemacs-tools--registry))))
    (if (not tool)
        (ccemacs-tools--error-result (format "Unknown tool: %s" name))
      (condition-case err
          (ccemacs-tools--text-result
           (funcall (ccemacs-tool-handler tool) args))
        (error
         (ccemacs-tools--error-result (error-message-string err)))))))

(ccemacs-rpc-register-method "tools/list" #'ccemacs-tools-handle-list)
(ccemacs-rpc-register-method "tools/call" #'ccemacs-tools-handle-call)


;; ---- handlers ---------------------------------------------------------

(defun ccemacs-tools--pos-plist (pos)
  (save-excursion
    (goto-char pos)
    `(:line ,(1- (line-number-at-pos))
      :character ,(- pos (line-beginning-position)))))

(defun ccemacs-tools--get-current-selection (_args)
  (let ((file (buffer-file-name)))
    (cond
     ((and (use-region-p) file)
      (let* ((begin (region-beginning))
             (end (region-end))
             (text (buffer-substring-no-properties begin end)))
        `(:text ,text
          :filePath ,file
          :fileUrl ,(concat "file://" file)
          :selection (:start ,(ccemacs-tools--pos-plist begin)
                      :end ,(ccemacs-tools--pos-plist end)
                      :isEmpty ,(if (= begin end) t :false)))))
     (t
      (let* ((pos (point))
             (zero `(:line ,(1- (line-number-at-pos pos))
                     :character ,(- pos (line-beginning-position)))))
        `(:text ""
          :filePath ,(or file :null)
          :fileUrl ,(if file (concat "file://" file) :null)
          :selection (:start ,zero :end ,zero :isEmpty t)))))))

(defun ccemacs-tools--get-latest-selection (_args)
  (or ccemacs-selection-last-payload '(:text "")))

(defun ccemacs-tools--language-id (buffer)
  (with-current-buffer buffer
    (replace-regexp-in-string "-mode\\'" ""
                              (symbol-name major-mode))))

(defun ccemacs-tools--get-open-editors (_args)
  (let ((scope (ccemacs-tools--caller-workspace))
        entries)
    (dolist (buf (buffer-list))
      (let ((file (buffer-local-value 'buffer-file-name buf)))
        (when (and file
                   (or (null scope)
                       (string-prefix-p scope (expand-file-name file))))
          (push `(:filePath ,file
                  :languageId ,(ccemacs-tools--language-id buf)
                  :isDirty ,(if (buffer-modified-p buf) t :false)
                  :isActive ,(if (eq buf (current-buffer)) t :false))
                entries))))
    `(:tabs ,(ccemacs-tools--ensure-vector (nreverse entries)))))

(defun ccemacs-tools--caller-workspace ()
  "Return the workspace path of the in-flight request's session, or nil."
  (when (and ccemacs-rpc-current-transport
             (fboundp 'ccemacs-server-session-for-client))
    (let ((s (ccemacs-server-session-for-client
              ccemacs-rpc-current-transport)))
      (when s (ccemacs-session-workspace s)))))

(defun ccemacs-tools--workspace-root ()
  (or (ccemacs-tools--caller-workspace)
      (when (fboundp 'project-current)
        (let ((p (project-current)))
          (and p (expand-file-name (project-root p)))))
      (expand-file-name default-directory)))

(defun ccemacs-tools--get-workspace-folders (_args)
  (let* ((root (ccemacs-tools--workspace-root))
         (entry `(:name ,(file-name-nondirectory (directory-file-name root))
                  :uri ,(concat "file://" root)
                  :path ,root)))
    `(:folders ,(vector entry))))

(defun ccemacs-tools--check-document-dirty (args)
  (let* ((file (plist-get args :filePath))
         (buf (and file (find-buffer-visiting file))))
    (if (null buf)
        '(:isDirty :false :exists :false)
      `(:isDirty ,(if (buffer-modified-p buf) t :false)
        :exists t))))

(ccemacs-tools-register
 "getCurrentSelection"
 "Return the currently selected text in the active buffer."
 nil #'ccemacs-tools--get-current-selection)

(ccemacs-tools-register
 "getLatestSelection"
 "Return the most recent selection that was sent."
 nil #'ccemacs-tools--get-latest-selection)

(ccemacs-tools-register
 "getOpenEditors"
 "List buffers visiting files."
 nil #'ccemacs-tools--get-open-editors)

(ccemacs-tools-register
 "getWorkspaceFolders"
 "Return the project root(s)."
 nil #'ccemacs-tools--get-workspace-folders)

(ccemacs-tools-register
 "checkDocumentDirty"
 "Return whether a file's buffer is modified."
 '(:type "object" :properties (:filePath (:type "string")) :required ["filePath"])
 #'ccemacs-tools--check-document-dirty)

(defun ccemacs-tools--open-file (args)
  (let* ((path (plist-get args :filePath))
         (start-line (plist-get args :startLine))
         (end-line (plist-get args :endLine)))
    (unless (and path (stringp path) (file-exists-p path))
      (error "File not found: %s" path))
    (let ((buf (find-file-noselect path)))
      (with-current-buffer buf
        (cond
         ((and start-line end-line)
          (goto-char (point-min))
          (forward-line (1- start-line))
          (let ((begin (line-beginning-position)))
            (goto-char (point-min))
            (forward-line (1- end-line))
            (set-mark begin)
            (goto-char (line-end-position))
            (activate-mark)))
         (start-line
          (goto-char (point-min))
          (forward-line (1- start-line)))))
      (display-buffer buf)
      `(:opened t :filePath ,path))))

(defun ccemacs-tools--open-diff (args)
  (let ((old (plist-get args :old_file_path))
        (new (plist-get args :new_file_path))
        (contents (plist-get args :new_file_contents))
        (tab (plist-get args :tab_name)))
    (unless (and tab old new (stringp contents))
      (error "openDiff: missing required parameter"))
    (ccemacs-diff--register tab
                            ccemacs-rpc-current-transport
                            ccemacs-rpc-current-id)
    (ccemacs-diff--launch old new contents tab)
    ccemacs-rpc-async))

(ccemacs-tools-register
 "openDiff"
 "Open an ediff session comparing the on-disk file with proposed contents."
 '(:type "object"
   :properties (:old_file_path (:type "string")
                :new_file_path (:type "string")
                :new_file_contents (:type "string")
                :tab_name (:type "string"))
   :required ["old_file_path" "new_file_path" "new_file_contents" "tab_name"])
 #'ccemacs-tools--open-diff)

(defun ccemacs-tools--close-all-diff-tabs (_args)
  (let (closed)
    (maphash
     (lambda (tab _v)
       (push tab closed))
     ccemacs-diff--pending)
    (dolist (tab closed)
      (ccemacs-diff-resolve-rejected tab))
    `(:closed ,(length closed))))

(ccemacs-tools-register
 "closeAllDiffTabs"
 "Reject every pending openDiff tab."
 nil #'ccemacs-tools--close-all-diff-tabs)

(defun ccemacs-tools--get-diagnostics (args)
  (ccemacs-diagnostics-collect (plist-get args :uri)))

(ccemacs-tools-register
 "getDiagnostics"
 "Return Flycheck/Flymake diagnostics, optionally filtered by URI."
 '(:type "object" :properties (:uri (:type "string")))
 #'ccemacs-tools--get-diagnostics)

(defun ccemacs-tools--save-document (args)
  (let* ((path (plist-get args :filePath))
         (buf (and path (find-buffer-visiting path))))
    (unless buf
      (error "No buffer visiting %s" path))
    (with-current-buffer buf (save-buffer))
    `(:saved t :filePath ,path)))

(ccemacs-tools-register
 "saveDocument"
 "Save the buffer visiting filePath."
 '(:type "object"
   :properties (:filePath (:type "string"))
   :required ["filePath"])
 #'ccemacs-tools--save-document)

(defun ccemacs-tools--close-tab (args)
  (let* ((tab (plist-get args :tab_name))
         (path (plist-get args :filePath))
         (closed nil))
    (when (and tab (gethash tab ccemacs-diff--pending))
      (ccemacs-diff-resolve-rejected tab)
      (setq closed t))
    (when path
      (let ((buf (find-buffer-visiting path)))
        (when buf
          (kill-buffer buf)
          (setq closed t))))
    `(:closed ,(if closed t :false))))

(ccemacs-tools-register
 "close_tab"
 "Close a tab: reject a pending diff or kill a file buffer."
 '(:type "object"
   :properties (:tab_name (:type "string") :filePath (:type "string")))
 #'ccemacs-tools--close-tab)

(defun ccemacs-tools--execute-code (_args)
  (error "executeCode is not supported by ccemacs"))

(ccemacs-tools-register
 "executeCode"
 "Not supported by ccemacs (returns error)."
 nil #'ccemacs-tools--execute-code)

(ccemacs-tools-register
 "openFile"
 "Open a file in the editor, optionally selecting a line range."
 '(:type "object"
   :properties (:filePath (:type "string")
                :startLine (:type "integer")
                :endLine (:type "integer")
                :preview (:type "boolean")
                :makeFrontmost (:type "boolean"))
   :required ["filePath"])
 #'ccemacs-tools--open-file)

(provide 'ccemacs-tools)
;;; ccemacs-tools.el ends here
