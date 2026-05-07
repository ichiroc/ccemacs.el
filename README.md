# ccemacs.el

**An Emacs extension for people who run [Claude Code](https://www.anthropic.com/claude-code)
in a terminal.** ccemacs does *not* embed Claude Code inside Emacs — you keep
running the `claude` CLI in a separate terminal (iTerm, Alacritty, tmux, …),
and ccemacs makes Emacs act as the **IDE side** of that CLI so the two can
talk to each other.

Concretely, the Claude Code CLI discovers a running Emacs through a lock file
under `~/.claude/ide/<port>.lock`, opens a WebSocket to the advertised port,
and speaks JSON-RPC 2.0 / MCP — the same protocol the official VS Code
extension uses. Once connected, Claude in your terminal can see your current
selection, list open buffers, open ediff sessions for proposed edits, read
Flycheck/Flymake diagnostics, and so on.

> Status: experimental, written by hobby. The protocol surface that VS Code
> uses is mostly covered, but expect rough edges.

## Who is this for?

You already use Claude Code from the command line and want the same kind of
editor integration the VS Code extension offers, but for Emacs. If you are
looking for a Claude *chat UI* embedded in Emacs, this is not that — Claude
keeps living in your terminal; ccemacs only bridges Emacs to it.

## Features

- Lock file + WebSocket + JSON-RPC 2.0 / MCP server, just like the VS Code
  extension.
- **Multi-workspace is first-class.** Each `M-x ccemacs-server-start` invoked
  from a different project root produces an independent session with its own
  port, lock file, token, and connected clients. Notifications are routed per
  file so several Claude instances do not see each other's buffers.
- Push notifications:
  - `selection_changed` — debounced, scoped to the workspace that owns the
    file (non-file buffers like `*Messages*` are skipped).
  - `at_mentioned` — `M-x ccemacs-send-at-mention` sends the current region
    (or the line at point) to Claude.
- MCP tools:
  - `getCurrentSelection`, `getLatestSelection`
  - `getOpenEditors` (scoped to the caller's workspace)
  - `getWorkspaceFolders`
  - `checkDocumentDirty`, `saveDocument`
  - `openFile` (with optional line range selection)
  - `openDiff` — opens an `ediff` session against the proposed contents and
    reports `FILE_SAVED` / `DIFF_REJECTED` back to Claude when you quit.
  - `closeAllDiffTabs`, `close_tab`
  - `getDiagnostics` — Flycheck or Flymake diagnostics, mapped to LSP shape.
- tmux helper: `M-x ccemacs-tmux-launch-claude` starts the server (if needed)
  and launches `claude` in a new tmux window or split.

## Requirements

- Emacs 27.1 or later
- [`websocket.el`](https://github.com/ahyatt/emacs-websocket) 1.15 or later
- The [`claude` CLI](https://docs.claude.com/en/docs/claude-code/overview)
- (Optional) `tmux`, for `ccemacs-tmux-launch-claude`
- (Optional) `flycheck` or `flymake`, for `getDiagnostics`

## Installation

### straight.el + use-package

```elisp
(use-package ccemacs
  :straight (ccemacs :type git :host github :repo "ichiroc/ccemacs.el")
  :commands (ccemacs-menu
             ccemacs-server-start
             ccemacs-server-stop
             ccemacs-send-at-mention
             ccemacs-tmux-launch-claude))
```

### Doom Emacs

In `$DOOMDIR/packages.el`:

```elisp
(package! ccemacs
  :recipe (:host github :repo "ichiroc/ccemacs.el"))
```

Then run `doom sync` and restart Emacs. The user-facing commands
(`ccemacs-menu`, `ccemacs-server-start`, etc.) are autoloaded, so no
`use-package!` block is required unless you want to add extra hooks or
keybindings.

### Manual

Clone the repo and add it to your `load-path`:

```elisp
(add-to-list 'load-path "/path/to/ccemacs.el")
(require 'ccemacs)
```

`websocket.el` must be installed separately (any of `package.el`,
`straight.el`, or your distro's package manager will do).

## Usage

### One-shot menu

```
M-x ccemacs-menu
```

It prompts for one of:

- *Start server (current workspace)*
- *Stop server (current workspace)*
- *Stop all servers*
- *Send @-mention*
- *Launch claude in tmux*

### Typical flow

1. Open a file inside your project and run `M-x ccemacs-server-start`. A
   random port in `[10000, 65535]` is bound, a lock file is written to
   `~/.claude/ide/<port>.lock`, and `ccemacs-selection-mode` is enabled.
2. In a terminal at the same project root, run `claude`. The CLI auto-discovers
   the lock file, connects to the WebSocket, and authenticates with the token
   embedded in the lock file.
3. Edit code in Emacs as usual. The current selection is pushed to Claude as
   you move around. Use `M-x ccemacs-send-at-mention` to explicitly @-mention
   the region/line at point.
4. When Claude proposes an edit, ccemacs opens an `ediff` session. Quit the
   session and answer the prompt — your choice (save / reject) is reported
   back to Claude.

### Multi-workspace

`ccemacs-server-start` keys sessions on the project root, so you can run it
from several projects in the same Emacs:

```
~/code/foo $ emacsclient -e "(progn (find-file \"~/code/foo/main.el\") (ccemacs-server-start))"
~/code/bar $ emacsclient -e "(progn (find-file \"~/code/bar/main.el\") (ccemacs-server-start))"
```

Each project gets its own port, lock file, and token. `getOpenEditors`,
`selection_changed`, and `at_mentioned` are scoped so the Claude instance
attached to `foo` only sees `foo` buffers.

### tmux integration

If you launch Emacs inside tmux, `M-x ccemacs-tmux-launch-claude` opens a new
tmux window (or split) at the current workspace and starts `claude` for you.
Customize:

| Variable                          | Default    | Meaning                                                 |
| --------------------------------- | ---------- | ------------------------------------------------------- |
| `ccemacs-tmux-claude-command`     | `"claude"` | Command run inside the new pane.                        |
| `ccemacs-tmux-window-name`        | `"claude"` | tmux window name when `ccemacs-tmux-split` is `window`. |
| `ccemacs-tmux-split`              | `window`   | `window` / `horizontal` / `vertical`.                   |
| `ccemacs-tmux-auto-start-server`  | `t`        | Start the ccemacs server before launching `claude`.     |

## Configuration

| Variable                          | Default | Meaning                                          |
| --------------------------------- | ------- | ------------------------------------------------ |
| `ccemacs-server-port-min`         | `10000` | Lower bound for random port selection.           |
| `ccemacs-server-port-max`         | `65535` | Upper bound for random port selection.           |
| `ccemacs-server-bind-attempts`    | `50`    | How many ports to try before giving up.          |
| `ccemacs-selection-debounce`      | `0.2`   | Seconds to debounce `selection_changed` pushes.  |

## Architecture

See [CLAUDE.md](./CLAUDE.md) for a detailed walkthrough. In short, the
moving parts are:

- `ccemacs-lockfile.el` — read/write/prune `~/.claude/ide/<port>.lock`.
- `ccemacs-server.el` — WebSocket server lifecycle, per-workspace session
  registry, auth.
- `ccemacs-rpc.el` — JSON-RPC 2.0 dispatcher with a transport-agnostic
  generic (`ccemacs-rpc-transport-send`) so handlers are testable.
- `ccemacs-mcp.el` + `ccemacs-tools.el` — MCP `initialize` and the `tools/*`
  surface.
- `ccemacs-selection.el`, `ccemacs-mention.el` — IDE→Claude push notifications.
- `ccemacs-diff.el` — async `openDiff` resolved on `ediff` quit.
- `ccemacs-diagnostics.el` — Flycheck/Flymake → LSP diagnostics adapter.

## Development

Run the test suite:

```sh
./run-tests.sh
```

The script invokes `emacs -Q -batch` with `ert-run-tests-batch-and-exit`,
loading every `test/*-test.el`. It locates `websocket.el` under
`~/.config/emacs/.local/straight/build-*/websocket` (falling back to the
straight repos directory). If neither exists the script aborts — the test
harness depends on a straight.el-managed `websocket.el` checkout.

To run a single test, invoke ERT directly:

```sh
emacs -Q -batch -L . -L test \
  -L ~/.config/emacs/.local/straight/build-*/websocket \
  -l test/ccemacs-server-test.el \
  --eval '(ert-run-tests-batch-and-exit "ccemacs-server-start-binds-port-and-writes-lockfile")'
```

Tests tagged `:tags '(integration)` open real WebSocket connections and need
the `websocket` package available.

## Acknowledgements

- The Claude Code team for the IDE-integration protocol.
- The official VS Code extension, which is the de-facto reference for the
  protocol surface.
