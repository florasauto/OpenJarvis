#!/usr/bin/env bash
# Floras Auto — start the Jarvis interface.
#
# What it does:
#   1. Builds the browser frontend once if it is missing (needs Node 22 and npm 11),
#      and refreshes the Floras Auto page if it changed since that build
#   2. Starts the OpenJarvis API server in the background
#   3. Prints the address of the Floras Auto page and opens it if a browser is available
#
# Usage:
#   scripts/floras-auto/start-interface.sh [PORT]
#
#   PORT  Port for the API server. Default: 8000, or [server] port from the active config.
#
# Stop it later with:
#   uv run jarvis stop
#
# The page at /floras.html lists the ten Floras Auto agents with their setup
# commands and chats with whichever agent the active config selects. The
# full OpenJarvis GUI stays available at / on the same server.
#
# Requires: a working source checkout (see TEAM_README.md) and Ollama
# running with the configured model pulled. The server refuses to start
# without a reachable engine.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${1:-}"
STATIC_DIR="$REPO_ROOT/src/openjarvis/server/static"

cd "$REPO_ROOT"

if [ ! -f "$STATIC_DIR/floras.html" ]; then
  echo "==> Building the browser frontend (first run only)"
  ( cd frontend && npx -y npm@11 ci --no-audit --no-fund && npx -y npm@11 run build )
elif [ frontend/public/floras.html -nt "$STATIC_DIR/floras.html" ]; then
  # The build copies this page as-is, so an updated page needs no rebuild.
  echo "==> Refreshing the Floras Auto page (it changed since the last build)"
  cp frontend/public/floras.html "$STATIC_DIR/floras.html"
fi

if [ -z "$PORT" ]; then
  PORT="$(uv run python -c 'from openjarvis.core.config import load_config; print(load_config().server.port)' 2>/dev/null || echo 8000)"
fi
URL="http://127.0.0.1:$PORT/floras.html"

echo "==> Starting the API server on port $PORT"
uv run jarvis start --port "$PORT" >/dev/null 2>&1 || true   # background daemon
for i in $(seq 1 40); do
  sleep 1
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then break; fi
  if [ "$i" -eq 40 ]; then
    echo "    server did not come up. Is Ollama running? Try: uv run jarvis doctor" >&2
    exit 1
  fi
done

echo
echo "Floras Auto Jarvis is ready:  $URL"
echo "Full OpenJarvis GUI:          http://127.0.0.1:$PORT/"
echo "Stop with:                    uv run jarvis stop"

if command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL" >/dev/null 2>&1 || true
elif command -v open >/dev/null 2>&1; then open "$URL" >/dev/null 2>&1 || true
fi
