#!/usr/bin/env python3
"""Floras Auto — refresh what the agents know about the notes folder.

The agents cannot list a folder, most of them are not told today's date, and
small models are poor at counting business days. This script does that
deterministic work for them. Run it whenever notes change, or leave it running
with --every.

It does two things:

1. Writes a bundle of the recent notes into BUNDLE_DIR:
     recent-notes.md            everything in one file (weekly recap, people)
     recent-notes-page-N.md     the same text in pages under 2,000 characters
                                (title watch: its agent type replaces any
                                longer tool output with a model-written summary)
   The bundle starts with today's date and a table of business days elapsed,
   then the full text of every note in the window, oldest first.
2. Re-indexes NOTES_DIR into memory with `jarvis memory index`, so the agents
   that search (scheduled monitor, office assistant, intake checker) see new
   notes. Skipped with --no-index, and skipped with a warning when the active
   config has no memory backend (the title watch and weekly recap configs).

Usage:
    uv run python scripts/floras-auto/refresh-notes.py [NOTES_DIR] [BUNDLE_DIR]
        [--days 7] [--every SECONDS] [--no-index]

    NOTES_DIR    Folder of notes. Default: ~/FlorasAuto/overnight-notes
    BUNDLE_DIR   Where the bundle is written. Default: ~/FlorasAuto/jarvis
                 Must not be inside NOTES_DIR, or the bundle would be indexed.
    --days N     Include notes dated within the last N days. Default 7.
    --every S    Keep running and refresh every S seconds (minimum 60).
    --no-index   Write the bundle only.

Which files count as notes: .md, .markdown and .txt files directly inside
NOTES_DIR (not in subfolders), except names starting with "." or "_".

A note's date comes from a YYYY-MM-DD in its file name, for example
overnight-2026-11-09.md. Without one, the file's last-modified date is used.
Naming notes with the date is recommended: it survives copying and editing.

Known limits: holidays are not skipped in the business-day table, and notes
that are deleted stay in the memory index until it is rebuilt.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

NOTE_SUFFIXES = {".md", ".markdown", ".txt"}
DATE_IN_NAME = re.compile(r"(20\d{2})-(\d{2})-(\d{2})")
BUNDLE_NAME = "recent-notes.md"
PAGE_STEM = "recent-notes-page-"
PAGE_CHARS = 1800  # stay under the 2,000-character summarisation threshold
MAX_NOTE_CHARS = 6000  # one very long note must not crowd out the others
MAX_BUNDLE_CHARS = 24000  # about 6,000 tokens; fits the 16k context with room
CALENDAR_ROWS = 15  # must reach past the 10-business-day escalation rule


@dataclass
class Note:
    path: Path
    date: dt.date
    date_source: str
    text: str


def _note_date(path: Path) -> tuple[dt.date, str]:
    match = DATE_IN_NAME.search(path.name)
    if match:
        try:
            year, month, day = (int(g) for g in match.groups())
            return dt.date(year, month, day), "the file name"
        except ValueError:
            pass
    modified = dt.datetime.fromtimestamp(path.stat().st_mtime).date()
    return modified, "the file's last-modified date"


def collect_notes(notes_dir: Path, today: dt.date, days: int) -> list[Note]:
    cutoff = today - dt.timedelta(days=days - 1)
    notes: list[Note] = []
    for path in sorted(notes_dir.iterdir()):
        if not path.is_file() or path.name.startswith((".", "_")):
            continue
        if path.suffix.lower() not in NOTE_SUFFIXES:
            continue
        date, source = _note_date(path)
        if date < cutoff:
            continue
        text = path.read_text(encoding="utf-8", errors="replace").strip()
        if len(text) > MAX_NOTE_CHARS:
            text = (
                text[:MAX_NOTE_CHARS].rstrip()
                + f"\n[note cut at {MAX_NOTE_CHARS:,} characters; the file is longer]"
            )
        notes.append(Note(path=path, date=date, date_source=source, text=text))
    notes.sort(key=lambda n: (n.date, n.path.name))
    return notes


def business_days_elapsed(since: dt.date, today: dt.date) -> int:
    """Weekdays after *since*, up to and including *today*."""
    count = 0
    day = since
    while day < today:
        day += dt.timedelta(days=1)
        if day.weekday() < 5:
            count += 1
    return count


def calendar_lines(today: dt.date) -> list[str]:
    lines = []
    day = today
    while len(lines) < CALENDAR_ROWS:
        if day.weekday() < 5 or day == today:
            elapsed = business_days_elapsed(day, today)
            suffix = " (today)" if day == today else ""
            lines.append(f"{day.isoformat()} {day.strftime('%a')} = {elapsed}{suffix}")
        day -= dt.timedelta(days=1)
    return lines


def render_blocks(
    notes: list[Note], notes_dir: Path, now: dt.datetime, days: int
) -> tuple[list[str], int]:
    """Return the bundle as blocks (a header, then one block per note).

    Also returns how many of the oldest notes were left out to save space.
    Blocks let the pager keep a note whole on one page where it fits.
    """
    today = now.date()
    omitted = 0
    kept = list(notes)
    while kept and sum(len(n.text) for n in kept) > MAX_BUNDLE_CHARS:
        kept.pop(0)
        omitted += 1

    window_start = today - dt.timedelta(days=days - 1)
    long_date = f"{today.strftime('%A, %B')} {today.day}, {today.year}"
    header = [
        "RECENT NOTES FOR THE FLORAS AUTO AGENTS",
        "Written by scripts/floras-auto/refresh-notes.py. Edit the notes, not this.",
        "",
        f"TODAY IS: {long_date} ({today.isoformat()})",
        f"Bundle written: {now.strftime('%Y-%m-%d %H:%M')}",
        f"Notes folder: {notes_dir}",
        f"Window: notes dated {window_start.isoformat()} or later (last {days} days)",
        f"Notes included: {len(kept)}, oldest first. A later note is newer news.",
    ]
    if omitted:
        header.append(f"Older notes left out to save space: {omitted}")
    header += [
        "",
        "BUSINESS DAYS ELAPSED SINCE A DATE (weekends skipped, holidays are not)",
        *calendar_lines(today),
    ]
    if not kept:
        header += ["", "THERE ARE NO NOTES IN THE WINDOW."]

    blocks = ["\n".join(header)]
    for index, note in enumerate(kept, start=1):
        weekday = note.date.strftime("%A")
        blocks.append(
            "\n".join(
                [
                    f"===== NOTE {index} of {len(kept)} | file: {note.path.name} =====",
                    f"Note date: {weekday} {note.date.isoformat()}"
                    f" (from {note.date_source})",
                    note.text if note.text else "(this note file is empty)",
                    f"===== END OF NOTE {index} =====",
                ]
            )
        )
    blocks.append("===== END OF ALL NOTES =====")
    return blocks, omitted


def paginate(blocks: list[str], bundle_dir: Path) -> list[str]:
    """Arrange *blocks* into pages whose full size stays under PAGE_CHARS.

    A block that fits on a page is never split. A block longer than a page is
    split at line ends.
    """
    # Reserve room for the header line and the footer line with a full path.
    footer_room = len(str(bundle_dir / f"{PAGE_STEM}999.md")) + 40
    budget = max(400, PAGE_CHARS - footer_room - 80)

    pieces: list[str] = []
    for block in blocks:
        if len(block) <= budget:
            pieces.append(block)
            continue
        part: list[str] = []
        size = 0
        for line in block.splitlines():
            while len(line) > budget:  # hard-wrap a single very long line
                if part:
                    pieces.append("\n".join(part))
                    part, size = [], 0
                pieces.append(line[:budget])
                line = line[budget:]
            if size + len(line) + 1 > budget and part:
                pieces.append("\n".join(part))
                part, size = [], 0
            part.append(line)
            size += len(line) + 1
        if part:
            pieces.append("\n".join(part))

    chunks: list[list[str]] = [[]]
    size = 0
    for piece in pieces:
        if size + len(piece) + 2 > budget and chunks[-1]:
            chunks.append([])
            size = 0
        chunks[-1].append(piece)
        size += len(piece) + 2

    pages = []
    total = len(chunks)
    for number, chunk in enumerate(chunks, start=1):
        header = f"PAGE {number} of {total} of the recent notes. Read every page."
        if number < total:
            footer = f"NEXT PAGE: {bundle_dir / f'{PAGE_STEM}{number + 1}.md'}"
        else:
            footer = "THIS IS THE LAST PAGE. You have now read all the notes."
        pages.append("\n\n".join([header, *chunk, footer]) + "\n")
    return pages


def _write_atomic(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def write_bundle(notes_dir: Path, bundle_dir: Path, days: int) -> str:
    now = dt.datetime.now()
    notes = collect_notes(notes_dir, now.date(), days)
    blocks, omitted = render_blocks(notes, notes_dir, now, days)
    text = "\n\n".join(blocks) + "\n"
    pages = paginate(blocks, bundle_dir)

    bundle_dir.mkdir(parents=True, exist_ok=True)
    _write_atomic(bundle_dir / BUNDLE_NAME, text)
    for number, page in enumerate(pages, start=1):
        _write_atomic(bundle_dir / f"{PAGE_STEM}{number}.md", page)
    # Remove pages left over from an earlier, longer bundle.
    for stale in bundle_dir.glob(f"{PAGE_STEM}*.md"):
        match = re.fullmatch(rf"{re.escape(PAGE_STEM)}(\d+)\.md", stale.name)
        if match and int(match.group(1)) > len(pages):
            stale.unlink()

    longest = max(len(p) for p in pages)
    summary = (
        f"bundle: {len(notes) - omitted} note(s), {len(text):,} characters, "
        f"{len(pages)} page(s), longest page {longest:,} characters"
    )
    if omitted:
        summary += f", {omitted} older note(s) left out"
    return summary


def reindex(notes_dir: Path) -> str:
    jarvis = shutil.which("jarvis")
    if jarvis is None:
        return "index skipped: the jarvis command is not on PATH (run with `uv run`)"
    try:
        result = subprocess.run(
            [jarvis, "memory", "index", str(notes_dir)],
            capture_output=True,
            text=True,
            timeout=600,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"index skipped: {exc}"
    output = result.stdout + result.stderr
    lines = [ln.strip() for ln in output.splitlines() if ln.strip()]
    last = lines[-1] if lines else ""
    if result.returncode != 0:
        return (
            "index skipped: `jarvis memory index` failed "
            f"({last[:160] or 'no output'}). Expected when the active config has no "
            "memory backend; pass --no-index to silence this."
        )
    return f"index: {last[:160]}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("notes_dir", nargs="?", default="~/FlorasAuto/overnight-notes")
    parser.add_argument("bundle_dir", nargs="?", default="~/FlorasAuto/jarvis")
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--every", type=int, default=0, metavar="SECONDS")
    parser.add_argument("--no-index", action="store_true")
    args = parser.parse_args()

    notes_dir = Path(args.notes_dir).expanduser().resolve()
    bundle_dir = Path(args.bundle_dir).expanduser().resolve()
    if not notes_dir.is_dir():
        print(f"error: notes folder not found: {notes_dir}", file=sys.stderr)
        return 2
    if bundle_dir == notes_dir or notes_dir in bundle_dir.parents:
        print("error: BUNDLE_DIR must not be inside NOTES_DIR", file=sys.stderr)
        return 2
    if args.days < 1:
        print("error: --days must be at least 1", file=sys.stderr)
        return 2
    if args.every and args.every < 60:
        print("error: --every must be at least 60 seconds", file=sys.stderr)
        return 2

    while True:
        stamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        try:
            summary = write_bundle(notes_dir, bundle_dir, args.days)
            print(f"[{stamp}] {summary}", flush=True)
            if not args.no_index:
                print(f"[{stamp}] {reindex(notes_dir)}", flush=True)
        except OSError as exc:
            print(f"[{stamp}] error: {exc}", file=sys.stderr, flush=True)
            if not args.every:
                return 1
        if not args.every:
            return 0
        time.sleep(args.every)


if __name__ == "__main__":
    sys.exit(main())
