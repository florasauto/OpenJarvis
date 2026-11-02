#!/usr/bin/env bash
# Floras Auto — set up the office assistant (orchestrator agent).
#
# What it does:
#   1. Installs configs/floras-auto/office-assistant.toml as ~/.openjarvis/config.toml,
#      with security.allowed_dirs set to the notes and drafts folders you choose
#   2. Installs the office persona (SOUL.md)
#   3. Indexes the notes folder into memory so memory_search can find it
#
# Usage:
#   scripts/floras-auto/setup-office-assistant.sh [NOTES_DIR] [DRAFTS_DIR]
#
#   NOTES_DIR   Folder of notes the assistant may read and search. Default: ~/FlorasAuto/overnight-notes
#   DRAFTS_DIR  Folder where it writes drafts and checklists.       Default: ~/FlorasAuto/drafts
#
# Afterwards:
#   uv run jarvis chat
#   Try: "What is pending on the IAA SUV, and what is the total with a $350 fee and 7.25% tax on $4,200?"
#
# Re-index whenever notes change:
#   uv run jarvis memory index NOTES_DIR
#
# Requires: a working source checkout (see TEAM_README.md) and Ollama
# running with the configured model pulled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NOTES_DIR="${1:-$HOME/FlorasAuto/overnight-notes}"
DRAFTS_DIR="${2:-$HOME/FlorasAuto/drafts}"
CONFIG_DIR="$HOME/.openjarvis"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/office-assistant.toml"
CONFIG_DST="$CONFIG_DIR/config.toml"
PERSONA_SRC="$REPO_ROOT/configs/floras-auto/personas/office/SOUL.md"
PERSONA_DST="$CONFIG_DIR/personas/floras-office/SOUL.md"

cd "$REPO_ROOT"

mkdir -p "$NOTES_DIR" "$DRAFTS_DIR" "$(dirname "$PERSONA_DST")"
NOTES_DIR="$(cd "$NOTES_DIR" && pwd)"
DRAFTS_DIR="$(cd "$DRAFTS_DIR" && pwd)"

echo "==> Installing config to $CONFIG_DST"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
NOTES_DIR="$NOTES_DIR" DRAFTS_DIR="$DRAFTS_DIR" uv run python - "$CONFIG_SRC" "$CONFIG_DST" <<'PY'
import os, sys, tomlkit
src, dst = sys.argv[1], sys.argv[2]
doc = tomlkit.parse(open(src, encoding="utf-8").read())
doc["security"]["allowed_dirs"] = [os.environ["NOTES_DIR"], os.environ["DRAFTS_DIR"]]
open(dst, "w", encoding="utf-8").write(tomlkit.dumps(doc))
print(f"    allowed_dirs = ['{os.environ['NOTES_DIR']}', '{os.environ['DRAFTS_DIR']}']")
PY

echo "==> Installing persona to $PERSONA_DST"
cp "$PERSONA_SRC" "$PERSONA_DST"

echo "==> Indexing notes from $NOTES_DIR"
if [ -z "$(ls -A "$NOTES_DIR")" ]; then
  echo "    folder is empty; add notes and run: uv run jarvis memory index $NOTES_DIR"
else
  uv run jarvis memory index "$NOTES_DIR"
fi

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor                     # confirm Ollama and the model are reachable"
echo "  uv run jarvis chat                       # start a session"
echo "  uv run jarvis memory index $NOTES_DIR    # re-index after notes change"
echo "  ls $DRAFTS_DIR                           # drafts it writes land here"
