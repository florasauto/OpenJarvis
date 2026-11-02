#!/usr/bin/env python3
"""Floras Auto — ingest a folder of documents into the deep research knowledge store.

The deep_research agent answers from ~/.openjarvis/knowledge.db. Note that
`jarvis memory index` writes to a different database (memory.db) and does not
feed deep research. This script fills the right store, using the same text
extraction and chunking as the GUI's upload page.

Supported: .md .markdown .txt .csv .pdf .docx
Skipped:   anything else, hidden files, and folders named in SKIP_DIRS.

Usage:
    uv run python scripts/floras-auto/ingest-documents.py DOCS_DIR [--source NAME]

Re-running replaces everything previously ingested under the same source name
(default "floras-docs"), so edits and deletions in the folder are reflected
without duplicates.

Ask questions afterwards with the --research flag:
    uv run jarvis ask --research "What is our policy on pending titles?"

.pdf needs the `pdf` extra (uv sync --extra pdf); .docx needs python-docx
(uv pip install python-docx). The setup script installs both.
"""

from __future__ import annotations

import argparse
import sys
import uuid
from pathlib import Path

SUPPORTED = {".md", ".markdown", ".txt", ".csv", ".pdf", ".docx"}
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".obsidian"}


def _iter_files(root: Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.name.startswith("."):
            continue
        if any(part in SKIP_DIRS or part.startswith(".") for part in path.relative_to(root).parts[:-1]):
            continue
        if path.suffix.lower() in SUPPORTED:
            yield path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("docs_dir", type=Path)
    parser.add_argument("--source", default="floras-docs", help="Source label stored with every chunk.")
    parser.add_argument("--dry-run", action="store_true", help="List files without ingesting.")
    args = parser.parse_args()

    root = args.docs_dir.expanduser().resolve()
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 2

    files = list(_iter_files(root))
    if not files:
        print(f"no supported documents found under {root}")
        return 0

    if args.dry_run:
        for f in files:
            print(f.relative_to(root))
        print(f"{len(files)} file(s) would be ingested")
        return 0

    # Reuse the server's upload helpers so CLI and GUI ingestion behave the same.
    from openjarvis.server.upload_router import (
        _chunk_text,
        _extract_text_from_docx,
        _extract_text_from_pdf,
        _get_store,
    )

    store = _get_store()
    try:
        removed = store.delete_by_source(args.source)
        if removed:
            print(f"removed {removed} previously ingested chunk(s) under source '{args.source}'")

        total_chunks = 0
        failed: list[str] = []
        for path in files:
            ext = path.suffix.lower()
            try:
                data = path.read_bytes()
                if ext == ".pdf":
                    text = _extract_text_from_pdf(data)
                elif ext == ".docx":
                    text = _extract_text_from_docx(data)
                else:
                    text = data.decode("utf-8", errors="replace")
            except Exception as exc:  # noqa: BLE001
                failed.append(f"{path.relative_to(root)}: {exc}")
                continue

            if not text.strip():
                failed.append(f"{path.relative_to(root)}: no text extracted")
                continue

            doc_id = str(uuid.uuid4())
            title = str(path.relative_to(root))
            chunks = _chunk_text(text)
            for idx, chunk in enumerate(chunks):
                store.store(
                    chunk,
                    source=args.source,
                    doc_type=ext.lstrip("."),
                    doc_id=doc_id,
                    title=title,
                    chunk_index=idx,
                )
            total_chunks += len(chunks)
            print(f"  {title}: {len(chunks)} chunk(s)")

        print(f"ingested {total_chunks} chunk(s) from {len(files) - len(failed)} file(s) into {store.db_path if hasattr(store, 'db_path') else 'knowledge.db'}")
        if failed:
            print(f"{len(failed)} file(s) skipped:")
            for line in failed:
                print(f"  {line}")
        return 0
    finally:
        store.close()


if __name__ == "__main__":
    sys.exit(main())
