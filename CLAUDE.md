## Code Modification Workflow

Modify code using TDD in the t-wada style: write a failing test first, make it pass with the smallest change, then refactor. Strip any leftover comments that begin with `AI` — they are not needed.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`ccemacs.el` makes Emacs act as the **IDE side** of Claude Code's IDE-integration protocol. The Claude Code CLI discovers a running Emacs through a lock file under `~/.claude/ide/<port>.lock`, opens a WebSocket to the advertised port, and speaks JSON-RPC 2.0 / MCP — the same protocol used by the official VS Code extension.

## Running tests

```sh
./run-tests.sh
```

The script invokes `emacs -Q -batch` with `ert-run-tests-batch-and-exit`, loading every `test/*-test.el`. It locates `websocket.el` under `~/.config/emacs/.local/straight/build-*/websocket` (falling back to the straight repos directory). If neither exists the script aborts — the test harness depends on a straight.el-managed `websocket.el` checkout, not on `package.el`.

To run a single test, invoke ERT directly with a selector:

```sh
emacs -Q -batch -L . -L test \
  -L ~/.config/emacs/.local/straight/build-*/websocket \
  -l test/ccemacs-server-test.el \
  --eval '(ert-run-tests-batch-and-exit "ccemacs-server-start-binds-port-and-writes-lockfile")'
```

Tests tagged `:tags '(integration)` (e.g. `ccemacs-server-roundtrip-initialize`) open real WebSocket connections to a freshly bound port; they need the `websocket` package to actually start a server.

## High-level architecture

The protocol has five moving parts. They are split across files so each layer can be tested in isolation through the `ccemacs-rpc-transport-send` generic.

### 1. Lock file handshake (`ccemacs-lockfile.el`)

When a session starts, a JSON file `~/.claude/ide/<port>.lock` is written with the Emacs `pid`, the workspace path, and a freshly generated `authToken`. This is how the Claude Code CLI finds the IDE. Stale lock files (whose recorded PID is no longer alive) are pruned on session start and on Emacs exit. Malformed lock files are deliberately **not** deleted — they may belong to another tool.

### 2. WebSocket server + session registry (`ccemacs-server.el`)

Each call to `ccemacs-server-start` binds a random port in `[ccemacs-server-port-min, ccemacs-server-port-max]` and creates a `ccemacs-session` struct keyed by **workspace path** in `ccemacs-server--registry`. **Multi-workspace is first-class**: starting from a different `default-directory` produces an independent session with its own port, lock file, token, and connected clients. Calling `ccemacs-server-start` twice for the same workspace is a `user-error`.

Session lookup helpers exist for three different angles:
- by workspace path (`ccemacs-server-session-for-workspace`)
- by connected websocket client (`ccemacs-server-session-for-client`) — used by tools that need to know "who asked me?"
- by file path (`ccemacs-server-session-for-file`) — picks the session whose workspace is the longest prefix of the file; used to route `selection_changed` and `at_mentioned` to the right Claude instance when several are connected.

### 3. JSON-RPC 2.0 dispatcher (`ccemacs-rpc.el`)

`ccemacs-rpc-handle-frame` parses an incoming frame, looks up the method in `ccemacs-rpc--methods`, and calls the handler with `params`. The handler returns a plist that becomes the `:result`, **except** when it returns the sentinel `ccemacs-rpc-async` — that defers the response so the handler can resolve it later (used by `openDiff`). During a request, `ccemacs-rpc-current-transport` and `ccemacs-rpc-current-id` are dynamically bound so handlers can identify the caller and capture the id for deferred replies.

The transport is abstracted via the `ccemacs-rpc-transport-send` generic. The production implementation specializes on `websocket`; tests register their own `ccemacs-test-transport` (see `test/ccemacs-test-helper.el`).

### 4. MCP surface (`ccemacs-mcp.el`, `ccemacs-tools.el`)

`ccemacs-mcp.el` only owns `initialize` and advertises protocol version `2025-03-26`. Everything user-facing lives in `ccemacs-tools.el`, which:

- Registers `tools/list` and `tools/call` with the RPC dispatcher.
- Maintains its own `ccemacs-tools--registry` so individual tools can be added with `ccemacs-tools-register NAME DESCRIPTION INPUT-SCHEMA HANDLER`.
- Wraps successful results in `:content [{type:"text", text:...}]` and errors in `{isError: t, content: [...]}` to match the MCP shape.

Currently registered tools: `getCurrentSelection`, `getLatestSelection`, `getOpenEditors`, `getWorkspaceFolders`, `checkDocumentDirty`, `openDiff`, `closeAllDiffTabs`, `getDiagnostics`, `saveDocument`, `close_tab`, `executeCode` (intentionally returns an error — not supported), `openFile`.

When a tool needs a workspace path it calls `ccemacs-tools--caller-workspace`, which looks up the in-flight transport in the session registry. This is what scopes `getOpenEditors` so a workspace only sees its own buffers.

### 5. Notifications pushed from Emacs

These flow IDE → Claude (server-to-client):

- **`selection_changed`** (`ccemacs-selection.el`) — global minor mode `ccemacs-selection-mode` hooks `post-command-hook`, builds a payload (skipping non-file buffers so `*Messages*` etc. don't leak), and **debounces** by `ccemacs-selection-debounce`. Notifications are routed per-file: only clients of the session whose workspace owns the file receive them.
- **`at_mentioned`** (`ccemacs-mention.el`) — user-triggered via `M-x ccemacs-send-at-mention`. Sends the current region (or point's line) and is again routed to the session that owns the file.

### Deferred-response pattern (`ccemacs-diff.el`)

`openDiff` is the canonical async tool. The handler:
1. Captures the in-flight transport + id into `ccemacs-diff--pending` keyed by `tab_name`.
2. Launches `ediff-buffers` against a scratch buffer holding the proposed contents.
3. Returns the `ccemacs-rpc-async` sentinel so no immediate response is sent.

The ediff session installs a buffer-local `ediff-quit-hook`. On quit it asks the user whether to save; the answer is reported back to Claude as either `FILE_SAVED` or `DIFF_REJECTED` via `ccemacs-diff--resolve`. `closeAllDiffTabs` and `close_tab` reuse the same resolver to cancel pending diffs cleanly.

### Diagnostics adapter (`ccemacs-diagnostics.el`)

Pure adapter: maps either Flycheck (`flycheck-current-errors`) or Flymake (`flymake-diagnostics`) to LSP-style `{uri, range, severity, message, source}`. Flycheck wins when both are active. Severity numbers follow LSP (`1=error, 2=warning, 3=info`). Both backends are loaded with `nil t` / `declare-function` so neither is a hard dependency.

## Conventions to keep

- **Position encoding**: every position payload uses LSP-style zero-based `{:line, :character}` (line `0` = first line). Look at `ccemacs-tools--pos-plist` / `ccemacs-selection--pos-plist` before adding new ones.
- **Empty JSON objects**: use `(make-hash-table :test 'equal)` (see `ccemacs-mcp--empty-object`, `ccemacs-tools--empty-object`). A plain `nil` would serialize as `null`, not `{}`.
- **Booleans for JSON**: explicitly use `t` / `:false` (not `nil`) so `json-serialize` produces `true`/`false` instead of dropping the key.
- **Arrays**: convert lists with `(apply #'vector ...)` before serializing — `json-serialize` writes lists as objects.
- **Adding a new MCP tool**: define the handler, then `ccemacs-tools-register NAME DOC SCHEMA HANDLER`. The schema is the JSON-Schema object Claude shows the model; pass `nil` if there are no arguments.
- **Adding a new RPC method outside MCP tools**: call `ccemacs-rpc-register-method "name" #'handler` (this is what `ccemacs-mcp.el` does for `initialize`).
