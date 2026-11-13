#!/usr/bin/env bash
# Floras Auto — set up the Unit Intake Checker (native ReAct agent).
#
# What it does:
#   1. Installs configs/floras-auto/intake-checker.toml as ~/.openjarvis/config.toml,
#      with security.allowed_dirs set to the intake and notes folders you choose
#   2. Installs the ReAct system prompt override to ~/.openjarvis/agents/native_react/,
#      with the intake folder and the team's roles written in
#   3. Indexes the notes folder into memory so memory_search can find it
#
# Roles: the checker names an owner for each open item only from
# configs/floras-auto/roles.md. That file ships empty, so until the office
# fills it in every item reads "owner: unassigned". Edit it, then rerun this
# script. Set ROLES_FILE to use a different file.
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
# Or keep the index fresh automatically:
#   uv run python scripts/floras-auto/refresh-notes.py NOTES_DIR --every 600
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
ROLES_FILE="${ROLES_FILE:-$REPO_ROOT/configs/floras-auto/roles.md}"

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
# Intake folder first: a file saved without a full path lands in the first one.
doc["security"]["allowed_dirs"] = [os.environ["INTAKE_DIR"], os.environ["NOTES_DIR"]]
open(dst, "w", encoding="utf-8").write(tomlkit.dumps(doc))
print(f"    allowed_dirs = ['{os.environ['INTAKE_DIR']}', '{os.environ['NOTES_DIR']}']")
PY

echo "==> Installing ReAct prompt override to $PROMPT_DST"
if [ -f "$PROMPT_DST" ]; then
  cp "$PROMPT_DST" "$PROMPT_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing override backed up"
fi
# Write the intake folder and the team's roles into the prompt.
INTAKE_DIR="$INTAKE_DIR" python3 - "$PROMPT_SRC" "$PROMPT_DST" "$ROLES_FILE" <<'PY'
import os, sys

src, dst, roles_file = sys.argv[1:4]
prompt = open(src, encoding="utf-8").read()

def esc(text):  # the agent runs str.format() on this prompt
    return text.replace("{", "{{").replace("}", "}}")

roles = []
if os.path.isfile(roles_file):
    for line in open(roles_file, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            roles.append(line.lstrip("-* ").strip())
if roles:
    block = "Use only these roles as owners:\n" + "\n".join(f"- {esc(r)}" for r in roles)
else:
    block = 'No roles are listed yet. Write "owner: unassigned" after every open item.'

for token, value in (
    ("__INTAKE_DIR__", esc(os.environ["INTAKE_DIR"])),
    ("__ROLES__", block),
):
    if token not in prompt:
        sys.exit(f"error: {token} not found in the prompt")
    prompt = prompt.replace(token, value)
open(dst, "w", encoding="utf-8").write(prompt)
print(f"    roles written into the prompt: {len(roles)}" + ("" if roles else " (owners will read 'unassigned')"))
PY

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
echo "Owners come from $ROLES_FILE. Edit it and rerun this script to change them."
echo "Note: this override replaces the ReAct prompt for every native_react use on this machine."
