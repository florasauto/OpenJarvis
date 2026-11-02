#!/usr/bin/env bash
# Floras Auto — set up the Weekly Auction Recap operator (operative agent).
#
# What it does:
#   1. Installs configs/floras-auto/weekly-recap.toml as ~/.openjarvis/config.toml,
#      with security.allowed_dirs set to the notes and recaps folders you choose
#   2. Installs the operator manifest with the folder paths written into its prompt
#
# Usage:
#   scripts/floras-auto/setup-weekly-recap.sh [NOTES_DIR] [RECAPS_DIR]
#
#   NOTES_DIR   Folder of overnight notes the operator reads. Default: ~/FlorasAuto/overnight-notes
#   RECAPS_DIR  Folder where it writes weekly-recap.md.       Default: ~/FlorasAuto/recaps
#
# Afterwards:
#   uv run jarvis operators run floras_weekly_recap       # one tick now, to test
#   uv run jarvis operators activate floras_weekly_recap  # schedule it (Fridays 5 PM)
#   uv run jarvis scheduler start                          # keep running so the schedule fires
#   uv run jarvis operators logs floras_weekly_recap      # what it did
#
# Requires: a working source checkout (see TEAM_README.md) and Ollama
# running with the configured model pulled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NOTES_DIR="${1:-$HOME/FlorasAuto/overnight-notes}"
RECAPS_DIR="${2:-$HOME/FlorasAuto/recaps}"
CONFIG_DIR="$HOME/.openjarvis"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/weekly-recap.toml"
CONFIG_DST="$CONFIG_DIR/config.toml"
MANIFEST_SRC="$REPO_ROOT/configs/floras-auto/operators/floras_weekly_recap.toml"
MANIFEST_TMP="$(mktemp -t floras_weekly_recap.XXXXXX.toml)"

cd "$REPO_ROOT"

mkdir -p "$NOTES_DIR" "$RECAPS_DIR"
NOTES_DIR="$(cd "$NOTES_DIR" && pwd)"
RECAPS_DIR="$(cd "$RECAPS_DIR" && pwd)"
RECAP_FILE="$RECAPS_DIR/weekly-recap.md"

echo "==> Installing config to $CONFIG_DST"
mkdir -p "$CONFIG_DIR"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
NOTES_DIR="$NOTES_DIR" RECAPS_DIR="$RECAPS_DIR" RECAP_FILE="$RECAP_FILE" \
uv run python - "$CONFIG_SRC" "$CONFIG_DST" "$MANIFEST_SRC" "$MANIFEST_TMP" <<'PY'
import os, sys, tomlkit
cfg_src, cfg_dst, man_src, man_tmp = sys.argv[1:5]
notes, recaps, recap_file = os.environ["NOTES_DIR"], os.environ["RECAPS_DIR"], os.environ["RECAP_FILE"]

cfg = tomlkit.parse(open(cfg_src, encoding="utf-8").read())
cfg["security"]["allowed_dirs"] = [notes, recaps]
open(cfg_dst, "w", encoding="utf-8").write(tomlkit.dumps(cfg))
print(f"    allowed_dirs = ['{notes}', '{recaps}']")

man = tomlkit.parse(open(man_src, encoding="utf-8").read())
prompt = str(man["operator"]["agent"]["system_prompt"])
prompt = prompt.replace(
    "The path is given in your instructions below.",
    f"NOTES_DIR is {notes}.",
).replace(
    "RECAP_FILE: the recap you own.",
    f"RECAP_FILE is {recap_file}: the recap you own.",
)
man["operator"]["agent"]["system_prompt"] = prompt
open(man_tmp, "w", encoding="utf-8").write(tomlkit.dumps(man))
PY

echo "==> Installing operator manifest"
# The manifests directory is named after the file, so keep the id in the name.
MANIFEST_INSTALL="$(dirname "$MANIFEST_TMP")/floras_weekly_recap.toml"
cp "$MANIFEST_TMP" "$MANIFEST_INSTALL"
uv run jarvis operators install "$MANIFEST_INSTALL"
rm -f "$MANIFEST_TMP" "$MANIFEST_INSTALL"

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor                                   # confirm Ollama and the model are reachable"
echo "  uv run jarvis operators list                           # see the operator"
echo "  uv run jarvis operators run floras_weekly_recap        # one tick now, to test"
echo "  uv run jarvis operators activate floras_weekly_recap   # schedule it for Fridays 5 PM"
echo "  uv run jarvis scheduler list                           # activate leaves a DUPLICATE task: cancel the"
echo "                                                         # one whose id is not operator:floras_weekly_recap"
echo "  uv run jarvis scheduler start                           # keep running so the schedule fires"
echo "  cat $RECAP_FILE                                        # the recap it maintains"
echo
echo "Note: 'jarvis operators logs' is broken in this version; use 'jarvis scheduler logs operator:floras_weekly_recap'."
