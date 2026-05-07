;;; ccemacs-tmux.el --- Launch claude CLI in a tmux pane -*- lexical-binding: t; -*-

;;; Code:

(require 'ccemacs-server)

(defgroup ccemacs-tmux nil
  "Launch the Claude Code CLI in tmux from Emacs."
  :group 'ccemacs)

(defcustom ccemacs-tmux-claude-command "claude"
  "Shell command (or program path) executed inside the new tmux pane."
  :type 'string
  :group 'ccemacs-tmux)

(defcustom ccemacs-tmux-window-name "claude"
  "Window name used when `ccemacs-tmux-split' is `window'."
  :type 'string
  :group 'ccemacs-tmux)

(defcustom ccemacs-tmux-split 'window
  "How to allocate tmux real estate for the claude pane.

- `window'      open a new tmux window (`tmux new-window').
- `horizontal'  split the current window left/right (`tmux split-window -h').
- `vertical'    split the current window top/bottom (`tmux split-window -v')."
  :type '(choice (const :tag "New window" window)
                 (const :tag "Split horizontal" horizontal)
                 (const :tag "Split vertical" vertical))
  :group 'ccemacs-tmux)

(defcustom ccemacs-tmux-auto-start-server t
  "When non-nil, start the ccemacs server for the workspace before launching."
  :type 'boolean
  :group 'ccemacs-tmux)

(defun ccemacs-tmux--inside-tmux-p ()
  "Return non-nil iff the current Emacs is inside a tmux session."
  (let ((v (getenv "TMUX")))
    (and v (not (string-empty-p v)))))

(defun ccemacs-tmux--build-args (workspace)
  "Return the tmux argv (without the leading program) for WORKSPACE."
  (pcase ccemacs-tmux-split
    ('window
     (list "new-window"
           "-n" ccemacs-tmux-window-name
           "-c" workspace
           ccemacs-tmux-claude-command))
    ('horizontal
     (list "split-window" "-h"
           "-c" workspace
           ccemacs-tmux-claude-command))
    ('vertical
     (list "split-window" "-v"
           "-c" workspace
           ccemacs-tmux-claude-command))
    (other
     (error "ccemacs-tmux-split has unknown value: %S" other))))

;;;###autoload
(defun ccemacs-tmux-launch-claude ()
  "Launch the claude CLI in a tmux pane for the current workspace.

Requires Emacs to be running inside a tmux session (i.e. `$TMUX' set).
When `ccemacs-tmux-auto-start-server' is non-nil and no ccemacs server
is running for the workspace yet, one is started first so claude can
connect via the lock file."
  (interactive)
  (unless (ccemacs-tmux--inside-tmux-p)
    (user-error "ccemacs: Emacs is not running inside a tmux session"))
  (let ((workspace (ccemacs-server--workspace-root)))
    (when (and ccemacs-tmux-auto-start-server
               (not (ccemacs-server-running-p workspace)))
      (ccemacs-server-start))
    (let* ((args (ccemacs-tmux--build-args workspace))
           (status (apply #'call-process "tmux" nil nil nil args)))
      (unless (eq status 0)
        (error "ccemacs: tmux exited with status %S" status))
      (message "ccemacs: launched claude in tmux for %s" workspace))))

(provide 'ccemacs-tmux)
;;; ccemacs-tmux.el ends here
