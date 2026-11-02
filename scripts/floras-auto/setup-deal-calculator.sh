#!/usr/bin/env bash
# Floras Auto — set up the Deal Calculator (native OpenHands / CodeAct agent).
#
# What it does:
#   1. Installs configs/floras-auto/deal-calculator.toml as ~/.openjarvis/config.toml,
#      with security.allowed_dirs set to the notes and deals folders you choose
#   2. Installs the system prompt override, which holds the fee schedule, to
#      ~/.openjarvis/agents/native_openhands/system_prompt.md
#
# Usage:
#   scripts/floras-auto/setup-deal-calculator.sh [NOTES_DIR] [DEALS_DIR]
#
#   NOTES_DIR  Folder of notes the calculator may read for inputs. Default: ~/FlorasAuto/overnight-notes
#   DEALS_DIR  Folder where it saves deal sheets.                   Default: ~/FlorasAuto/deals
#
# Afterwards:
#   uv run jarvis ask "Landed cost on the IAA SUV at a 4200 bid with 180 transport, and save a deal sheet"
#
# To change fee rates, edit ~/.openjarvis/agents/native_openhands/system_prompt.md
# (or the copy in the repo and rerun this script).
#
# Requires: a working source checkout (see TEAM_README.md) and Ollama
# running with the configured model pulled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NOTES_DIR="${1:-$HOME/FlorasAuto/overnight-notes}"
DEALS_DIR="${2:-$HOME/FlorasAuto/deals}"
CONFIG_DIR="$HOME/.openjarvis"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/deal-calculator.toml"
CONFIG_DST="$CONFIG_DIR/config.toml"
PROMPT_SRC="$REPO_ROOT/configs/floras-auto/prompts/native_openhands_system_prompt.md"
PROMPT_DST="$CONFIG_DIR/agents/native_openhands/system_prompt.md"

cd "$REPO_ROOT"

mkdir -p "$NOTES_DIR" "$DEALS_DIR" "$(dirname "$PROMPT_DST")"
NOTES_DIR="$(cd "$NOTES_DIR" && pwd)"
DEALS_DIR="$(cd "$DEALS_DIR" && pwd)"

echo "==> Installing config to $CONFIG_DST"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
NOTES_DIR="$NOTES_DIR" DEALS_DIR="$DEALS_DIR" uv run python - "$CONFIG_SRC" "$CONFIG_DST" <<'PY'
import os, sys, tomlkit
src, dst = sys.argv[1], sys.argv[2]
doc = tomlkit.parse(open(src, encoding="utf-8").read())
doc["security"]["allowed_dirs"] = [os.environ["NOTES_DIR"], os.environ["DEALS_DIR"]]
open(dst, "w", encoding="utf-8").write(tomlkit.dumps(doc))
print(f"    allowed_dirs = ['{os.environ['NOTES_DIR']}', '{os.environ['DEALS_DIR']}']")
PY

echo "==> Installing CodeAct prompt override to $PROMPT_DST"
if [ -f "$PROMPT_DST" ]; then
  cp "$PROMPT_DST" "$PROMPT_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing override backed up"
fi
# Write the folders into the prompt so the agent knows where to read and save.
sed -e "s|the deals folder|the deals folder ($DEALS_DIR)|" \
    -e "s|Read inputs with file_read|Read inputs with file_read from the notes folder ($NOTES_DIR)|" \
    "$PROMPT_SRC" > "$PROMPT_DST"

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor                                                   # confirm Ollama and the model are reachable"
echo "  uv run jarvis ask \"Landed cost on the IAA SUV at a 4200 bid with 180 transport\""
echo "  ls $DEALS_DIR                                                          # deal sheets land here"
echo
echo "Fee rates live in $PROMPT_DST. Edit that file when they change."
echo "Note: this override replaces the prompt for every native_openhands use on this machine."
