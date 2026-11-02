#!/usr/bin/env bash
# Floras Auto — set up the Unit Intake Checker (native ReAct agent).
#
# What it does:
#   1. Installs configs/floras-auto/intake-checker.toml as ~/.openjarvis/config.toml,
#      with security.allowed_dirs set to the notes and intake folders you choose
#   2. Installs the ReAct system prompt override to ~/.openjarvis/agents/native_react/
#   3. Indexes the notes folder into memory so memory_search can find it
#
# Usage:
#   scripts/floras-auto/setup-intake-checker.sh [NOTES_DIR] [INTAKE_DIR]
#
#   NOTES_DIR   Folder of notes the checker may read and search. Default: ~/FlorasAuto/overnight-notes
#   INTAKE_DIR  Folder where it writes intake checklists.          Default: ~/FlorasAuto/intake
#
# Afterwards:
#   uv run jarvis ask "Intake checklist for the IAA SUV"
#   uv run jarvis chat
#
# Re-index whenever notes change:
#   uv run jarvis memory index NOTES_DIR
#
# Requires: a working source checkout (see TEAM_README.md) and Ollama
# running with the configured model pulled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NOTES_DIR="${1:-$HOME/FlorasAuto/overnight-notes}"
INTAKE_DIR="${2:-$HOME/FlorasAuto/intake}"
CONFIG_DIR="$HOME/.openjarvis"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/intake-checker.toml"
CONFIG_DST="$CONFIG_DIR/config.toml"
PROMPT_SRC="$REPO_ROOT/configs/floras-auto/prompts/native_react_system_prompt.md"
PROMPT_DST="$CONFIG_DIR/agents/native_react/system_prompt.md"

cd "$REPO_ROOT"

mkdir -p "$NOTES_DIR" "$INTAKE_DIR" "$(dirname "$PROMPT_DST")"
NOTES_DIR="$(cd "$NOTES_DIR" && pwd)"
INTAKE_DIR="$(cd "$INTAKE_DIR" && pwd)"

echo "==> Installing config to $CONFIG_DST"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
NOTES_DIR="$NOTES_DIR" INTAKE_DIR="$INTAKE_DIR" uv run python - "$CONFIG_SRC" "$CONFIG_DST" <<'PY'
import os, sys, tomlkit
src, dst = sys.argv[1], sys.argv[2]
doc = tomlkit.parse(open(src, encoding="utf-8").read())
doc["security"]["allowed_dirs"] = [os.environ["NOTES_DIR"], os.environ["INTAKE_DIR"]]
open(dst, "w", encoding="utf-8").write(tomlkit.dumps(doc))
print(f"    allowed_dirs = ['{os.environ['NOTES_DIR']}', '{os.environ['INTAKE_DIR']}']")
PY

echo "==> Installing ReAct prompt override to $PROMPT_DST"
if [ -f "$PROMPT_DST" ]; then
  cp "$PROMPT_DST" "$PROMPT_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing override backed up"
fi
# Write the intake folder into the prompt so the agent knows where to save.
sed "s|the intake folder|the intake folder ($INTAKE_DIR)|" "$PROMPT_SRC" > "$PROMPT_DST"

echo "==> Indexing notes from $NOTES_DIR"
if [ -z "$(ls -A "$NOTES_DIR")" ]; then
  echo "    folder is empty; add notes and run: uv run jarvis memory index $NOTES_DIR"
else
  uv run jarvis memory index "$NOTES_DIR"
fi

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor                                   # confirm Ollama and the model are reachable"
echo "  uv run jarvis ask \"Intake checklist for the IAA SUV\"    # one unit"
echo "  uv run jarvis memory index $NOTES_DIR                  # re-index after notes change"
echo "  ls $INTAKE_DIR                                         # checklists land here"
echo
echo "Note: this override replaces the ReAct prompt for every native_react use on this machine."
