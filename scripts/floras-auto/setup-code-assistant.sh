#!/usr/bin/env bash
# Floras Auto — set up the local code assistant.
#
# What it does:
#   1. Installs configs/floras-auto/code-assistant.toml as ~/.openjarvis/config.toml
#   2. Points security.allowed_dirs at the workspace folder you choose
#   3. Creates the workspace folder
#
# Usage:
#   scripts/floras-auto/setup-code-assistant.sh [WORKSPACE_DIR]
#
#   WORKSPACE_DIR  The only folder the assistant may read and write.
#                  Default: ~/FlorasAuto/scripts
#
# Afterwards, work with it through chat so sensitive tool calls are confirmed:
#   cd WORKSPACE_DIR && uv run jarvis chat
#
# Do not use `jarvis ask` with this agent: it auto-approves every tool call.
#
# Requires: a working source checkout (see TEAM_README.md) and Ollama
# running with the configured model pulled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE="${1:-$HOME/FlorasAuto/scripts}"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/code-assistant.toml"
CONFIG_DST="$HOME/.openjarvis/config.toml"

cd "$REPO_ROOT"

mkdir -p "$WORKSPACE"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

echo "==> Installing config to $CONFIG_DST"
mkdir -p "$(dirname "$CONFIG_DST")"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
# Install the config with allowed_dirs set to the chosen workspace.
WORKSPACE="$WORKSPACE" uv run python - "$CONFIG_SRC" "$CONFIG_DST" <<'PY'
import os, sys, tomlkit
src, dst = sys.argv[1], sys.argv[2]
doc = tomlkit.parse(open(src, encoding="utf-8").read())
doc["security"]["allowed_dirs"] = [os.environ["WORKSPACE"]]
open(dst, "w", encoding="utf-8").write(tomlkit.dumps(doc))
print(f"    allowed_dirs = ['{os.environ['WORKSPACE']}']")
PY

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor                 # confirm Ollama and the model are reachable"
echo "  cd $WORKSPACE && uv run jarvis chat  # start a coding session; confirm tool calls with y"
echo
echo "Try: 'Write a Python script called top_sellers.py that reads sales.csv and prints the five best-selling models.'"
