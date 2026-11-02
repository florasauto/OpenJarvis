#!/usr/bin/env bash
# Floras Auto — set up the Title and Transport Watch managed agent.
#
# What it does:
#   1. Installs configs/floras-auto/title-watch.toml as ~/.openjarvis/config.toml,
#      with security.allowed_dirs set to the notes and status folders you choose
#   2. Installs the agent template to ~/.openjarvis/templates/, with the folder
#      paths written into its standing instruction
#   3. Creates the managed agent from the template
#
# Usage:
#   scripts/floras-auto/setup-title-watch.sh [NOTES_DIR] [STATUS_DIR]
#
#   NOTES_DIR   Folder of overnight notes the agent reads. Default: ~/FlorasAuto/overnight-notes
#   STATUS_DIR  Folder where it writes title-watch.md.   Default: ~/FlorasAuto/status
#
# Afterwards:
#   uv run jarvis agents run <agent-id>     # one tick now, to test
#   uv run jarvis agents start <agent-id>   # schedule it (every 30 minutes)
#   uv run jarvis agents daemon             # keep this running so scheduled ticks fire
#   uv run jarvis agents logs <agent-id>    # what it did
#
# Requires: a working source checkout (see TEAM_README.md) and Ollama
# running with the configured model pulled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NOTES_DIR="${1:-$HOME/FlorasAuto/overnight-notes}"
STATUS_DIR="${2:-$HOME/FlorasAuto/status}"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/title-watch.toml"
CONFIG_DST="$HOME/.openjarvis/config.toml"
TEMPLATE_SRC="$REPO_ROOT/configs/floras-auto/templates/floras_title_watch.toml"
TEMPLATE_DST="$HOME/.openjarvis/templates/floras_title_watch.toml"
AGENT_NAME="${AGENT_NAME:-Title and Transport Watch}"

cd "$REPO_ROOT"

mkdir -p "$NOTES_DIR" "$STATUS_DIR"
NOTES_DIR="$(cd "$NOTES_DIR" && pwd)"
STATUS_DIR="$(cd "$STATUS_DIR" && pwd)"
STATUS_FILE="$STATUS_DIR/title-watch.md"

echo "==> Installing config to $CONFIG_DST"
mkdir -p "$(dirname "$CONFIG_DST")" "$(dirname "$TEMPLATE_DST")"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
NOTES_DIR="$NOTES_DIR" STATUS_DIR="$STATUS_DIR" STATUS_FILE="$STATUS_FILE" \
uv run python - "$CONFIG_SRC" "$CONFIG_DST" "$TEMPLATE_SRC" "$TEMPLATE_DST" <<'PY'
import os, sys, tomlkit
cfg_src, cfg_dst, tpl_src, tpl_dst = sys.argv[1:5]
notes, status_dir, status_file = os.environ["NOTES_DIR"], os.environ["STATUS_DIR"], os.environ["STATUS_FILE"]

cfg = tomlkit.parse(open(cfg_src, encoding="utf-8").read())
cfg["security"]["allowed_dirs"] = [notes, status_dir]
open(cfg_dst, "w", encoding="utf-8").write(tomlkit.dumps(cfg))
print(f"    allowed_dirs = ['{notes}', '{status_dir}']")

tpl = tomlkit.parse(open(tpl_src, encoding="utf-8").read())
original = str(tpl["template"]["instruction"])
tpl["template"]["instruction"] = (
    f"NOTES_DIR is {notes}. STATUS_FILE is {status_file}. " + original
)
open(tpl_dst, "w", encoding="utf-8").write(tomlkit.dumps(tpl))
print(f"    template installed to {tpl_dst}")
PY

echo "==> Creating managed agent '$AGENT_NAME'"
uv run jarvis agents create --name "$AGENT_NAME" --template floras_title_watch

echo
echo "Done. Next steps (find the agent id with 'uv run jarvis agents list'):"
echo "  uv run jarvis doctor                     # confirm Ollama and the model are reachable"
echo "  uv run jarvis agents run <agent-id>      # one tick now, to test"
echo "  uv run jarvis agents start <agent-id>    # schedule every 30 minutes"
echo "  uv run jarvis agents daemon              # keep running so scheduled ticks fire"
echo "  cat $STATUS_FILE                         # the status page it maintains"
