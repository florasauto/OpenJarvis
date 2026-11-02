#!/usr/bin/env bash
# Floras Auto — set up the simple team chat assistant.
#
# What it does:
#   1. Installs configs/floras-auto/chat-simple.toml as ~/.openjarvis/config.toml
#   2. Installs the Floras Auto persona (SOUL.md, USER.md) for the system prompt
#
# Usage:
#   scripts/floras-auto/setup-chat-simple.sh
#
# Afterwards:
#   uv run jarvis chat            # interactive session
#   uv run jarvis ask "Draft a text telling a customer their pickup is ready"
#   uv run jarvis serve           # browser GUI at http://127.0.0.1:8000
#
# Requires: a working source checkout (see TEAM_README.md) and Ollama
# running with the configured model pulled (ollama pull qwen3.5:4b).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="$HOME/.openjarvis"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/chat-simple.toml"
CONFIG_DST="$CONFIG_DIR/config.toml"
PERSONA_SRC="$REPO_ROOT/configs/floras-auto/personas/chat"
PERSONA_DST="$CONFIG_DIR/personas/floras-auto"

cd "$REPO_ROOT"

echo "==> Installing config to $CONFIG_DST"
mkdir -p "$CONFIG_DIR"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
cp "$CONFIG_SRC" "$CONFIG_DST"

echo "==> Installing persona to $PERSONA_DST"
mkdir -p "$PERSONA_DST"
cp "$PERSONA_SRC/SOUL.md" "$PERSONA_DST/SOUL.md"
# USER.md is meant to be edited locally; do not overwrite an existing copy.
if [ -f "$PERSONA_DST/USER.md" ]; then
  echo "    USER.md already exists, keeping the local copy"
else
  cp "$PERSONA_SRC/USER.md" "$PERSONA_DST/USER.md"
fi
# MEMORY.md is the assistant's own notes file; start it empty if missing.
[ -f "$PERSONA_DST/MEMORY.md" ] || : > "$PERSONA_DST/MEMORY.md"

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor          # confirm Ollama and the model are reachable"
echo "  uv run jarvis chat            # start chatting"
echo "  uv run jarvis serve           # or use the browser GUI at http://127.0.0.1:8000"
echo
echo "Edit $PERSONA_DST/USER.md to tell the assistant about the team."
