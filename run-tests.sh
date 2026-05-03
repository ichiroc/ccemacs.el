#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

WS_DIR=$(ls -d "$HOME"/.config/emacs/.local/straight/build-*/websocket 2>/dev/null | head -1 || true)
if [[ -z "${WS_DIR}" ]]; then
  WS_DIR="$HOME/.config/emacs/.local/straight/repos/emacs-websocket"
fi
if [[ ! -d "${WS_DIR}" ]]; then
  echo "websocket.el not found under ~/.config/emacs/.local/straight" >&2
  exit 1
fi

LOAD_FLAGS=()
for f in test/*-test.el; do
  LOAD_FLAGS+=(-l "$f")
done

exec emacs -Q -batch -L . -L test -L "${WS_DIR}" \
  "${LOAD_FLAGS[@]}" \
  -f ert-run-tests-batch-and-exit
