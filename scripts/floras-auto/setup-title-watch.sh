#!/usr/bin/env bash
# Floras Auto — set up the Title and Transport Watch managed agent.
#
# What it does:
#   1. Installs configs/floras-auto/title-watch.toml as ~/.openjarvis/config.toml,
#      with security.allowed_dirs set to the status and notes-bundle folders
#   2. Writes the first notes bundle with refresh-notes.py
#   3. Installs the agent template to ~/.openjarvis/templates/, with the real
#      file paths written into its prompt
#   4. Creates the managed agent from the template
#
# Usage:
#   scripts/floras-auto/setup-title-watch.sh [NOTES_DIR] [STATUS_DIR] [BUNDLE_DIR]
#
#   NOTES_DIR   Folder of overnight notes.                 Default: ~/FlorasAuto/overnight-notes
#   STATUS_DIR  Folder where it writes title-watch.md.     Default: ~/FlorasAuto/status
#   BUNDLE_DIR  Folder for the notes bundle it reads.      Default: a "jarvis" folder beside NOTES_DIR
#
# The agent cannot list a folder, so it never reads NOTES_DIR itself. It reads
# the bundle pages that refresh-notes.py writes. Keep that script running, or
# the agent keeps working from old notes. The status page shows when the
# bundle was written, so stale notes are visible.
#
# Afterwards (the setup prints these with the real paths and agent id):
#   uv run python scripts/floras-auto/refresh-notes.py NOTES_DIR BUNDLE_DIR --no-index --every 600
#   uv run jarvis agents run <agent-id>     # one tick now, to test
#   uv run jarvis agents start <agent-id>   # schedule it (every 30 minutes)
#   uv run jarvis agents daemon             # keep this running so scheduled ticks fire
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
REFRESH="$REPO_ROOT/scripts/floras-auto/refresh-notes.py"
AGENT_NAME="${AGENT_NAME:-Title and Transport Watch}"

cd "$REPO_ROOT"

mkdir -p "$NOTES_DIR" "$STATUS_DIR"
NOTES_DIR="$(cd "$NOTES_DIR" && pwd)"
STATUS_DIR="$(cd "$STATUS_DIR" && pwd)"
BUNDLE_DIR="${3:-$(dirname "$NOTES_DIR")/jarvis}"
mkdir -p "$BUNDLE_DIR"
BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd)"
STATUS_FILE="$STATUS_DIR/title-watch.md"
NOTES_PAGE_1="$BUNDLE_DIR/recent-notes-page-1.md"

echo "==> Installing config to $CONFIG_DST"
mkdir -p "$(dirname "$CONFIG_DST")" "$(dirname "$TEMPLATE_DST")"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
STATUS_DIR="$STATUS_DIR" BUNDLE_DIR="$BUNDLE_DIR" STATUS_FILE="$STATUS_FILE" NOTES_PAGE_1="$NOTES_PAGE_1" \
uv run python - "$CONFIG_SRC" "$CONFIG_DST" "$TEMPLATE_SRC" "$TEMPLATE_DST" <<'PY'
import os, sys, tomlkit
cfg_src, cfg_dst, tpl_src, tpl_dst = sys.argv[1:5]
status_dir, bundle_dir = os.environ["STATUS_DIR"], os.environ["BUNDLE_DIR"]

cfg = tomlkit.parse(open(cfg_src, encoding="utf-8").read())
# Status folder first: a file saved without a full path lands in the first one.
cfg["security"]["allowed_dirs"] = [status_dir, bundle_dir]
open(cfg_dst, "w", encoding="utf-8").write(tomlkit.dumps(cfg))
print(f"    allowed_dirs = ['{status_dir}', '{bundle_dir}']")

tpl = tomlkit.parse(open(tpl_src, encoding="utf-8").read())
prompt = str(tpl["template"]["system_prompt_template"])
for token, value in (
    ("__STATUS_FILE__", os.environ["STATUS_FILE"]),
    ("__NOTES_PAGE_1__", os.environ["NOTES_PAGE_1"]),
):
    if token not in prompt:
        sys.exit(f"error: {token} not found in the template prompt")
    prompt = prompt.replace(token, value)
tpl["template"]["system_prompt_template"] = prompt
open(tpl_dst, "w", encoding="utf-8").write(tomlkit.dumps(tpl))
print(f"    template installed to {tpl_dst}")
PY

echo "==> Writing the first notes bundle to $BUNDLE_DIR"
uv run python "$REFRESH" "$NOTES_DIR" "$BUNDLE_DIR" --no-index

echo "==> Creating managed agent '$AGENT_NAME'"
CREATE_OUT="$(uv run jarvis agents create --name "$AGENT_NAME" --template floras_title_watch 2>&1)"
printf '%s\n' "$CREATE_OUT" | grep -v 'UV_NATIVE_TLS' || true
AGENT_ID="$(printf '%s\n' "$CREATE_OUT" | sed -n 's/^Created agent: \([0-9a-f]*\).*/\1/p' | head -1)"
AGENT_ID="${AGENT_ID:-<agent-id>}"

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor                     # confirm Ollama and the model are reachable"
echo "  uv run jarvis agents run $AGENT_ID      # one tick now, to test"
echo "  cat $STATUS_FILE"
echo "  uv run jarvis agents start $AGENT_ID    # schedule every 30 minutes"
echo "  uv run jarvis agents daemon              # keep running so scheduled ticks fire"
echo
echo "Keep the notes bundle fresh, or the agent works from old notes:"
echo "  uv run python $REFRESH $NOTES_DIR $BUNDLE_DIR --no-index --every 600"
