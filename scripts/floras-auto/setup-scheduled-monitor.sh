#!/usr/bin/env bash
# Floras Auto — set up the morning auction-review scheduled monitor.
#
# What it does:
#   1. Installs configs/floras-auto/scheduled-monitor.toml as ~/.openjarvis/config.toml,
#      with read access to the notes-bundle folder only
#   2. Writes the first notes bundle with refresh-notes.py
#   3. Registers a cron task that runs the operative agent every morning
#
# Usage:
#   scripts/floras-auto/setup-scheduled-monitor.sh [NOTES_DIR] [CRON] [BUNDLE_DIR]
#
#   NOTES_DIR   Folder of overnight notes. Default: ~/FlorasAuto/overnight-notes
#   CRON        Schedule in cron syntax. Default: "0 7 * * 1-6" (7 AM, Monday to Saturday)
#   BUNDLE_DIR  Where refresh-notes.py writes the notes bundle the monitor reads.
#               Default: a "jarvis" folder beside NOTES_DIR
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
CONFIG_DIR="$HOME/.openjarvis"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/scheduled-monitor.toml"
CONFIG_DST="$CONFIG_DIR/config.toml"
REFRESH="$REPO_ROOT/scripts/floras-auto/refresh-notes.py"

cd "$REPO_ROOT"

mkdir -p "$NOTES_DIR"
NOTES_DIR="$(cd "$NOTES_DIR" && pwd)"
BUNDLE_DIR="${3:-$(dirname "$NOTES_DIR")/jarvis}"
mkdir -p "$BUNDLE_DIR"
BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd)"
NOTES_BUNDLE="$BUNDLE_DIR/recent-notes.md"

# Why the task reads this way (found in the real-model runs):
# - It reads the notes bundle, one file with every recent note in date order.
#   Memory search handed it the five best-matching pieces in no order, and it
#   dropped a unit and missed a rebooked pickup.
# - Units are numbered one by one, oldest note first, and counted after the
#   list. Asked to list units "from Edge Pipeline, IAA, and Salvato", the
#   model gave each source exactly one unit and dropped the fourth. Asked for
#   the count before the list, it wrote 3 and then listed three.
# - Title and transport are reported separately. Asked for "pickup or title
#   status", the model gave one of the two. Transport uses the title watch's
#   two lists, Done and Waiting: given one free line per unit, the model
#   wrote "done" for a pickup that had only been moved.
# - "Due today" and "late" are read off the [TODAY] and [PAST] marks the
#   refresh script puts after every date. The model mislabels dates it has to
#   compare with today itself.
# - A title is received, pending, or not mentioned. The model often says
#   "pending" where "not mentioned" is right, which is harmless. Given only
#   two states, the weekly recap once called an unmentioned title "received".
# - Nothing is stored in memory. A stored summary was fed back in on the next
#   morning and the review repeated the old statuses.
PROMPT="$(cat <<EOF
First call file_read on $NOTES_BUNDLE. It starts with the date of today, then holds every recent overnight note, oldest first. Every date in the notes is followed by a mark: [TODAY], [PAST], or [FUTURE].

Then write the morning review in four parts.

Part 1, the units. Go through the notes from the oldest to the newest. Every time a note says a unit was bought, write the next numbered line: the year, make and model of the unit, the last four of its VIN, the source, the date of the note that says it was bought, the price, and then "Title:" with one of three answers. Edge Pipeline, IAA, and Salvato can each have several units, and a unit bought in the newest note counts too.
- Title: received, only when a note says, in these words, that the title was received. A unit that was picked up or delivered has not had its title received.
- Title: pending, when a note says the title is pending and no later note says it was received.
- Title: not mentioned, when no note says anything about this unit's title.

Part 2, one line: "Units bought: " and the number of lines in part 1.

Part 3, transport. Every unit that has a pickup or delivery booked goes on exactly one of two lists.
Done: only the units a note says, in words, were picked up, arrived, or were delivered. Names only, on one line.
Waiting: one line for every other booked unit: the unit, the vendor, the transport cost if a note gives one, and the booked date with the mark the notes put after it. If a pickup was moved, it is still waiting: give the new date and its mark. A booking that is "not confirmed" is still waiting. The purchase price is not a transport cost. When no note gives a transport cost, leave the cost out and never write a zero. A unit on the Done list does not also go on the Waiting list.

Part 4, "Needs a call today": every unit whose line in part 1 says Title: pending or Title: not mentioned, every Waiting line marked [TODAY] or [PAST], and every parts promise that is still open. A Waiting line marked [FUTURE] does not go here. Give each item its reason in two or three words, such as "title pending", "title not mentioned", "pickup due today", or "delivery late". Write "- Nothing" if there is none.

Report only what the notes say. Nobody is at the keyboard, so do not ask questions.
EOF
)"
# file_read is the only tool. The upstream preset's knowledge tools have no
# store on the scheduler path, think once used up the whole output allowance,
# and the memory tools are left out for the reason above.
TOOLS="file_read"

echo "==> Installing config to $CONFIG_DST"
mkdir -p "$CONFIG_DIR"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
BUNDLE_DIR="$BUNDLE_DIR" uv run python - "$CONFIG_SRC" "$CONFIG_DST" <<'PY'
import os, sys, tomlkit
cfg_src, cfg_dst = sys.argv[1:3]
bundle_dir = os.environ["BUNDLE_DIR"]
cfg = tomlkit.parse(open(cfg_src, encoding="utf-8").read())
cfg["security"]["allowed_dirs"] = [bundle_dir]
open(cfg_dst, "w", encoding="utf-8").write(tomlkit.dumps(cfg))
print(f"    allowed_dirs = ['{bundle_dir}']")
PY

echo "==> Writing the first notes bundle to $BUNDLE_DIR"
if [ -z "$(ls -A "$NOTES_DIR")" ]; then
  echo "    $NOTES_DIR is empty; drop .md or .txt notes in it. The bundle will say there are no notes."
fi
uv run python "$REFRESH" "$NOTES_DIR" "$BUNDLE_DIR" --no-index

echo "==> Registering scheduled task ($CRON)"
uv run jarvis scheduler create "$PROMPT" --type cron --value "$CRON" --agent operative --tools "$TOOLS"

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor                       # confirm Ollama and the model are reachable"
echo "  uv run jarvis scheduler run-task operative # run the task once to test"
echo "  uv run jarvis scheduler start              # keep running to honour the schedule"
echo "  uv run jarvis scheduler list               # see the task and its next run time"
echo
echo "The monitor reads the notes bundle. Keep it fresh, or it works from old notes:"
echo "  uv run python $REFRESH $NOTES_DIR $BUNDLE_DIR --no-index --every 600"
