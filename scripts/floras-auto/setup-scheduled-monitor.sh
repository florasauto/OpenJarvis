#!/usr/bin/env bash
# Floras Auto — set up the morning auction-review scheduled monitor.
#
# What it does:
#   1. Installs configs/floras-auto/scheduled-monitor.toml as ~/.openjarvis/config.toml
#   2. Indexes the notes folder into local memory
#   3. Registers a cron task that runs the operative agent every morning
#
# Usage:
#   scripts/floras-auto/setup-scheduled-monitor.sh [NOTES_DIR] [CRON]
#
#   NOTES_DIR  Folder of overnight notes to index. Default: ~/FlorasAuto/overnight-notes
#   CRON       Schedule in cron syntax. Default: "0 7 * * 1-6" (7 AM, Monday to Saturday)
#
# Afterwards, start the scheduler in a terminal or a service:
#   uv run jarvis scheduler start
# Or run the task once to test it:
#   uv run jarvis scheduler run-task operative
#
# Requires: a working source checkout (see TEAM_README.md) and Ollama
# running with the configured model pulled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NOTES_DIR="${1:-$HOME/FlorasAuto/overnight-notes}"
CRON="${2:-0 7 * * 1-6}"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/scheduled-monitor.toml"
CONFIG_DST="$HOME/.openjarvis/config.toml"

PROMPT='Review the overnight auction and purchase notes that were indexed since your last run. List every unit purchased from Edge Pipeline, IAA, and Salvato with its pickup or title status. Flag anything that needs a follow-up call today, such as pending titles or unsourced parts. Store a short dated summary in memory so tomorrow'"'"'s run can compare against it.'
TOOLS="knowledge_search,knowledge_sql,memory_search,memory_store,think"

cd "$REPO_ROOT"

echo "==> Installing config to $CONFIG_DST"
mkdir -p "$(dirname "$CONFIG_DST")"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
cp "$CONFIG_SRC" "$CONFIG_DST"

echo "==> Indexing notes from $NOTES_DIR"
mkdir -p "$NOTES_DIR"
if [ -z "$(ls -A "$NOTES_DIR")" ]; then
  echo "    folder is empty; drop .md or .txt notes in it and rerun 'uv run jarvis memory index $NOTES_DIR'"
else
  uv run jarvis memory index "$NOTES_DIR"
fi

echo "==> Registering scheduled task ($CRON)"
uv run jarvis scheduler create "$PROMPT" --type cron --value "$CRON" --agent operative --tools "$TOOLS"

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor                       # confirm Ollama and the model are reachable"
echo "  uv run jarvis scheduler run-task operative # run the task once to test"
echo "  uv run jarvis scheduler start              # keep running to honour the schedule"
echo "  uv run jarvis scheduler list               # see the task and its next run time"
