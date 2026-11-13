#!/usr/bin/env bash
# Floras Auto — set up the Weekly Auction Recap operator (operative agent).
#
# What it does:
#   1. Installs configs/floras-auto/weekly-recap.toml as ~/.openjarvis/config.toml,
#      with security.allowed_dirs set to the recaps and notes-bundle folders
#   2. Writes the first notes bundle with refresh-notes.py
#   3. Installs the operator manifest with the real file paths written into its prompt
#
# Usage:
#   scripts/floras-auto/setup-weekly-recap.sh [NOTES_DIR] [RECAPS_DIR] [BUNDLE_DIR]
#
#   NOTES_DIR   Folder of overnight notes.                 Default: ~/FlorasAuto/overnight-notes
#   RECAPS_DIR  Folder where it writes weekly-recap.md.    Default: ~/FlorasAuto/recaps
#   BUNDLE_DIR  Folder for the notes bundle it reads.      Default: a "jarvis" folder beside NOTES_DIR
#
# The agent cannot list a folder, so it never reads NOTES_DIR itself. It reads
# the bundle that refresh-notes.py writes. Refresh the bundle before the recap
# fires, or it recaps old notes.
#
# Afterwards (the setup prints these with the real paths):
#   uv run python scripts/floras-auto/refresh-notes.py NOTES_DIR BUNDLE_DIR --no-index --every 600
#   uv run jarvis operators run floras_weekly_recap       # one tick now, to test
#   uv run jarvis operators activate floras_weekly_recap  # schedule it (Fridays 5 PM)
#   uv run jarvis scheduler start                          # keep running so the schedule fires
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
REFRESH="$REPO_ROOT/scripts/floras-auto/refresh-notes.py"

cd "$REPO_ROOT"

mkdir -p "$NOTES_DIR" "$RECAPS_DIR"
NOTES_DIR="$(cd "$NOTES_DIR" && pwd)"
RECAPS_DIR="$(cd "$RECAPS_DIR" && pwd)"
BUNDLE_DIR="${3:-$(dirname "$NOTES_DIR")/jarvis}"
mkdir -p "$BUNDLE_DIR"
BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd)"
RECAP_FILE="$RECAPS_DIR/weekly-recap.md"
NOTES_BUNDLE="$BUNDLE_DIR/recent-notes.md"

echo "==> Installing config to $CONFIG_DST"
mkdir -p "$CONFIG_DIR"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
RECAPS_DIR="$RECAPS_DIR" BUNDLE_DIR="$BUNDLE_DIR" RECAP_FILE="$RECAP_FILE" NOTES_BUNDLE="$NOTES_BUNDLE" \
uv run python - "$CONFIG_SRC" "$CONFIG_DST" "$MANIFEST_SRC" "$MANIFEST_TMP" <<'PY'
import os, sys, tomlkit
cfg_src, cfg_dst, man_src, man_tmp = sys.argv[1:5]
recaps, bundle_dir = os.environ["RECAPS_DIR"], os.environ["BUNDLE_DIR"]

cfg = tomlkit.parse(open(cfg_src, encoding="utf-8").read())
# Recaps folder first: a file saved without a full path lands in the first one.
cfg["security"]["allowed_dirs"] = [recaps, bundle_dir]
open(cfg_dst, "w", encoding="utf-8").write(tomlkit.dumps(cfg))
print(f"    allowed_dirs = ['{recaps}', '{bundle_dir}']")

man = tomlkit.parse(open(man_src, encoding="utf-8").read())
prompt = str(man["operator"]["agent"]["system_prompt"])
for token, value in (
    ("__RECAP_FILE__", os.environ["RECAP_FILE"]),
    ("__NOTES_BUNDLE__", os.environ["NOTES_BUNDLE"]),
):
    if token not in prompt:
        sys.exit(f"error: {token} not found in the manifest prompt")
    prompt = prompt.replace(token, value)
man["operator"]["agent"]["system_prompt"] = prompt
open(man_tmp, "w", encoding="utf-8").write(tomlkit.dumps(man))
PY

echo "==> Writing the first notes bundle to $BUNDLE_DIR"
uv run python "$REFRESH" "$NOTES_DIR" "$BUNDLE_DIR" --no-index

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
echo "  cat $RECAP_FILE"
echo "  uv run jarvis operators activate floras_weekly_recap   # schedule it for Fridays 5 PM"
echo "  uv run jarvis scheduler list                           # activate leaves a DUPLICATE task: cancel the"
echo "                                                         # one whose id is not operator:floras_weekly_recap"
echo "  uv run jarvis scheduler start                           # keep running so the schedule fires"
echo
echo "Keep the notes bundle fresh, or the recap works from old notes:"
echo "  uv run python $REFRESH $NOTES_DIR $BUNDLE_DIR --no-index --every 600"
echo
echo "Note: 'jarvis operators logs' is broken in this version; use 'jarvis scheduler logs operator:floras_weekly_recap'."
