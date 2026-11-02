#!/usr/bin/env bash
# Floras Auto — set up deep research over the dealership's documents.
#
# What it does:
#   1. Installs the PDF extra so PDFs can be ingested
#   2. Installs configs/floras-auto/deep-research.toml as ~/.openjarvis/config.toml
#   3. Ingests the documents folder into the deep research knowledge store
#
# Usage:
#   scripts/floras-auto/setup-deep-research.sh [DOCS_DIR]
#
#   DOCS_DIR  Folder of documents to ingest. Default: ~/FlorasAuto/documents
#
# Supported formats: .md .txt .csv .pdf .docx. Export Excel sheets to CSV or
# PDF first. Rerun this script, or the ingest command below, whenever the
# documents change; re-ingesting replaces the previous copy, no duplicates.
#
# Note: `jarvis memory index` is NOT the right command for this agent. It
# writes to memory.db, while deep research reads knowledge.db. Use the ingest
# script instead:
#   uv run python scripts/floras-auto/ingest-documents.py DOCS_DIR
#
# Afterwards (always pass --research; a plain `jarvis ask` cannot reach the
# knowledge store from the CLI):
#   uv run jarvis ask --research "What is our policy on pending titles?"
#
# Requires: a working source checkout (see TEAM_README.md) and Ollama
# running with the configured model pulled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCS_DIR="${1:-$HOME/FlorasAuto/documents}"
CONFIG_SRC="$REPO_ROOT/configs/floras-auto/deep-research.toml"
CONFIG_DST="$HOME/.openjarvis/config.toml"
INGEST="$REPO_ROOT/scripts/floras-auto/ingest-documents.py"

cd "$REPO_ROOT"

echo "==> Installing PDF extra and Word support"
uv sync --extra dev --extra server --extra pdf
uv pip install --quiet python-docx     # no upstream extra covers .docx yet
# uv sync drops the locally built Rust extension; rebuild it or the memory
# backend and rate limiter fall back with warnings.
uv run maturin develop --manifest-path rust/crates/openjarvis-python/Cargo.toml

echo "==> Installing config to $CONFIG_DST"
mkdir -p "$(dirname "$CONFIG_DST")"
if [ -f "$CONFIG_DST" ]; then
  cp "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
  echo "    existing config backed up"
fi
cp "$CONFIG_SRC" "$CONFIG_DST"

echo "==> Ingesting documents from $DOCS_DIR"
mkdir -p "$DOCS_DIR"
if [ -z "$(ls -A "$DOCS_DIR")" ]; then
  echo "    folder is empty; add documents and rerun:"
  echo "      uv run python $INGEST $DOCS_DIR"
else
  uv run python "$INGEST" "$DOCS_DIR"
fi

echo
echo "Done. Next steps:"
echo "  uv run jarvis doctor                                                # confirm Ollama and the model are reachable"
echo "  ollama pull nomic-embed-text                                        # optional: better ranking (hybrid search)"
echo "  uv run jarvis ask --research \"What is our policy on pending titles?\"  # ask over the documents, with sources"
echo "  uv run python $INGEST $DOCS_DIR   # re-ingest after documents change"
echo
echo "Always pass --research. A plain 'jarvis ask' cannot reach the knowledge store from the CLI."
