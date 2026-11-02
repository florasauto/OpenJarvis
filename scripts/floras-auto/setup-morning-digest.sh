#!/usr/bin/env bash
# Floras Auto — set up the spoken morning digest.
#
# What it does:
#   1. Installs the voice extra (Kokoro local text-to-speech)
#   2. Installs configs/floras-auto/morning-digest.toml as ~/.openjarvis/config.toml
#   3. Installs the Floras Auto persona
#   4. Optionally connects the team mailbox over IMAP (prompts for an app password)
#   5. Optionally writes the weather and news feed connector files
#
# Usage:
#   scripts/floras-auto/setup-morning-digest.sh
#
# Afterwards:
#   uv run jarvis digest --fresh --text-only   # first run, text only
#   uv run jarvis digest --fresh               # with audio
#   uv run jarvis digest --schedule            # show the schedule
#
# Requires: a working source checkout (see TEAM_README.md), Ollama running
# with the configured model pulled, and espeak-ng on PATH for Kokoro
# (apt install espeak-ng / brew install espeak-ng).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="$HOME/.openjarvis"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/morning-digest.toml"
CONFIG_DST="$CONFIG_DIR/config.toml"
PERSONA_SRC="$REPO_ROOT/configs/floras-auto/personas/floras-auto.md"
PERSONA_DST="$CONFIG_DIR/prompts/personas/floras-auto.md"

cd "$REPO_ROOT"

echo "==> Installing voice extra (Kokoro)"
uv sync --extra dev --extra server --extra voice

echo "==> Installing config to $CONFIG_DST"
mkdir -p "$CONFIG_DIR/connectors" "$(dirname "$PERSONA_DST")"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
cp "$CONFIG_SRC" "$CONFIG_DST"
cp "$PERSONA_SRC" "$PERSONA_DST"
echo "    persona installed to $PERSONA_DST"

# ── Team mailbox over IMAP ─────────────────────────────────────────────
echo
read -r -p "Connect the team mailbox over IMAP now? [y/N] " yn
if [[ "${yn:-n}" =~ ^[Yy]$ ]]; then
  read -r -p "  Email address: " IMAP_EMAIL
  read -r -s -p "  App password (not your login password): " IMAP_PASSWORD; echo
  read -r -p "  IMAP host (leave blank to detect from the address): " IMAP_HOST
  IMAP_EMAIL="$IMAP_EMAIL" IMAP_PASSWORD="$IMAP_PASSWORD" IMAP_HOST="${IMAP_HOST:-}" \
  uv run python - <<'PY'
import os
import openjarvis.connectors  # noqa: F401  (registers connectors)
from openjarvis.core.registry import ConnectorRegistry

c = ConnectorRegistry.get("imap")()
c.connect_with_credentials(
    os.environ["IMAP_EMAIL"],
    os.environ["IMAP_PASSWORD"],
    imap_host=os.environ.get("IMAP_HOST", ""),
)
print("    mailbox connected and validated")
PY
else
  echo "    skipped. Connect later from the GUI (Data Sources page) or rerun this script."
fi

# ── Weather ───────────────────────────────────────────────────────────
echo
read -r -p "Set up weather (needs a free OpenWeatherMap API key)? [y/N] " yn
if [[ "${yn:-n}" =~ ^[Yy]$ ]]; then
  read -r -p "  API key: " OWM_KEY
  read -r -p "  Location (e.g. Columbus,OH,US): " OWM_LOC
  printf '{"api_key": "%s", "location": "%s"}\n' "$OWM_KEY" "$OWM_LOC" > "$CONFIG_DIR/connectors/weather.json"
  echo "    written to $CONFIG_DIR/connectors/weather.json"
fi

# ── News feeds ────────────────────────────────────────────────────────
if [ ! -f "$CONFIG_DIR/connectors/news_rss.json" ]; then
  cat > "$CONFIG_DIR/connectors/news_rss.json" <<'EOF'
{"feeds": [
  {"name": "Automotive News", "url": "https://www.autonews.com/rss"},
  {"name": "NHTSA Recalls", "url": "https://www.nhtsa.gov/rss/recalls.xml"}
]}
EOF
  echo
  echo "==> Wrote starter news feeds to $CONFIG_DIR/connectors/news_rss.json (edit to taste)"
fi

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor                      # confirm Ollama, model, and speech backend"
echo "  uv run jarvis connect --list              # see which sources are connected"
echo "  uv run jarvis digest --fresh --text-only  # generate the first briefing as text"
echo "  uv run jarvis digest --fresh              # generate and play it"
echo "  uv run jarvis digest --schedule           # show the 6 AM schedule"
