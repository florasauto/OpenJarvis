#!/usr/bin/env python3
"""Floras Auto — print the scheduled monitor's latest morning review in full.

The scheduled monitor's review is the result of a scheduler task. It is kept
in the scheduler's database, and `jarvis scheduler logs` shows only its first
few words. This script prints the whole review, and can save it to a file the
team can open.

Usage:
    uv run python scripts/floras-auto/show-morning-review.py [--save FILE]
        [--task ID]

    --save FILE  Also write the review to FILE, for example
                 ~/FlorasAuto/status/morning-review.md
    --task ID    Show this task's latest run. Default: the latest run of any
                 task that uses the operative agent, which is how the
                 scheduled monitor is registered.

It reads ~/.openjarvis/scheduler.db, or the folder in OPENJARVIS_HOME, and
changes nothing there.

Exit status: 0 when a review was printed, 1 when there is no run to show or
the latest run failed, 2 when there is no scheduler database.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sqlite3
import sys
from pathlib import Path


def jarvis_home() -> Path:
    return Path(os.environ.get("OPENJARVIS_HOME", "~/.openjarvis")).expanduser()


def latest_run(db_path: Path, task_id: str | None) -> sqlite3.Row | None:
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        if task_id:
            query = (
                "SELECT l.* FROM task_run_logs l"
                " WHERE l.task_id LIKE ? ORDER BY l.id DESC LIMIT 1"
            )
            return connection.execute(query, (task_id + "%",)).fetchone()
        query = (
            "SELECT l.* FROM task_run_logs l"
            " JOIN scheduled_tasks t ON t.id = l.task_id"
            " WHERE t.agent = 'operative' ORDER BY l.id DESC LIMIT 1"
        )
        return connection.execute(query).fetchone()
    finally:
        connection.close()


def review_text(result: str | None) -> str:
    """The review itself, taken out of the JSON the scheduler stores."""
    if not result:
        return ""
    try:
        parsed = json.loads(result)
    except ValueError:
        return result.strip()
    if isinstance(parsed, dict):
        return str(parsed.get("content") or "").strip()
    return result.strip()


def local_time(stamp: str | None) -> str:
    """A stored run time as local clock time, for example 2026-11-16 07:00."""
    if not stamp:
        return "at an unknown time"
    try:
        moment = dt.datetime.fromisoformat(stamp)
    except ValueError:
        return stamp[:16].replace("T", " ")
    if moment.tzinfo is not None:
        moment = moment.astimezone()
    return moment.strftime("%Y-%m-%d %H:%M")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--save", default=None, metavar="FILE")
    parser.add_argument("--task", default=None, metavar="ID")
    args = parser.parse_args()

    db_path = jarvis_home() / "scheduler.db"
    if not db_path.is_file():
        print(f"error: no scheduler database at {db_path}", file=sys.stderr)
        return 2
    try:
        run = latest_run(db_path, args.task)
    except sqlite3.Error as exc:
        print(f"error: could not read {db_path}: {exc}", file=sys.stderr)
        return 2
    if run is None:
        print("No run found. Has the scheduled monitor run yet?", file=sys.stderr)
        return 1

    started = local_time(run["started_at"])
    if not run["success"]:
        problem = str(run["error"] or "no error text was recorded")
        print(f"The latest run, started {started}, failed: {problem}")
        return 1
    text = review_text(run["result"])
    if not text:
        print(f"The latest run, started {started}, returned an empty review.")
        return 1

    page = f"{text}\n\nReview written by the run that started {started}.\n"
    print(page, end="")
    if args.save:
        target = Path(args.save).expanduser()
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(target.name + ".tmp")
        temporary.write_text(page, encoding="utf-8")
        os.replace(temporary, target)
        print(f"\nSaved to {target}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
