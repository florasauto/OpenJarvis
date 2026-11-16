# Floras Auto – OpenJarvis Team Notes

This fork tracks the upstream [OpenJarvis](https://github.com/open-jarvis/OpenJarvis)
project, a local-first personal AI agent framework from Stanford. These notes
cover what the team needs to get a working checkout, run the tests, and keep
our branch in good shape. The upstream `README.md` and `CONTRIBUTING.md` remain
the source of truth for the project itself.

Evaluation baseline: upstream `main` at commit `ef8d459`, verified 2026-11-02.

## Branch workflow

| Branch | Purpose |
|---|---|
| `main` | Upstream plus these team notes. Receives merges from `floras-auto-dev` only. |
| `floras-auto-dev` | Our working line. Feature branches merge into this. |
| `feature/<short-name>` | One branch per task, opened as a PR into `floras-auto-dev`. |

To pull in upstream changes:

```bash
git remote add upstream https://github.com/open-jarvis/OpenJarvis.git
git fetch upstream main
git checkout main && git merge --ff-only upstream/main && git push origin main
git checkout floras-auto-dev && git merge main
```

## Requirements

| Component | Version | Notes |
|---|---|---|
| Python | 3.10 – 3.13 | 3.14 is excluded upstream because numpy has no wheel for it. |
| uv | latest | Manages the venv and dependencies. |
| Rust toolchain | stable | Needed to build the PyO3 extension. |
| Node.js | 22.22 or newer | Only for the browser GUI. |
| npm | 11.x | The frontend refuses npm 10. See the workaround below. |
| Ollama | latest | Default local inference engine. The CLI and server refuse to start without a reachable engine. See "Ollama: the local model engine" below. |

## Ollama: the local model engine

Every Floras agent runs on Ollama, and none of them has yet been checked
against a real model. This section is how to get Ollama running and the
models pulled, which is the step that closes that gap.

### Install it

On a shop machine, the official installer or desktop app from
https://ollama.com/download is the simplest route. Building from source
is the fallback when an installer is not an option, and it is the route
verified here.

### Build from source (verified 2026-11-02)

Needs Go, CMake 3.24 or newer, a C/C++ compiler, and Ninja. Go downloads
the exact toolchain version the module asks for on its own, so an older
Go on the machine is fine.

```bash
git clone --depth 1 https://github.com/ollama/ollama && cd ollama
```

```bash
cmake -B build . && cmake --build build --parallel 4
```

This builds the `ollama` binary in the repository root and the CPU
inference libraries under `build/lib/ollama`, one per CPU generation from
Sandy Bridge to Zen 4. On a four-core machine the native compile takes
roughly twenty minutes. GPU backends are opt-in at configure time, for
example `-DOLLAMA_LLAMA_BACKENDS=cuda_v13`; see `docs/development.md` in
the Ollama repository.

A source build reports its version as `0.0.0`. That is expected and
harmless.

### Start it and pull the models

```bash
./ollama serve
```

It listens on `127.0.0.1:11434`, the address every Floras config expects.
To keep models off the system disk, set `OLLAMA_MODELS` to a folder first.
In a second terminal, pull what the configs use:

```bash
./ollama pull qwen3.5:4b
```

```bash
./ollama pull qwen3.5:9b
```

```bash
./ollama pull nomic-embed-text
```

| Model | Used by | Size on disk (measured 2026-11-11) |
|---|---|---|
| `qwen3.5:4b` | simple chat, morning digest minimum, the recommended default from `jarvis init` | 3.3 GB |
| `qwen3.5:9b` | every other Floras agent; the ReAct and CodeAct agents need at least this size | 6.6 GB |
| `nomic-embed-text` | optional, improves ranking in deep research | 0.3 GB |

Loaded for use, the 9B model takes about 7 GB of RAM with the 16k context
OpenJarvis asks for.

Then confirm OpenJarvis sees the engine:

```bash
uv run jarvis doctor
```

### Claude Code on the local model

Ollama can start the Claude Code CLI pointed at the local server, so
Claude Code's agent loop runs on a model on our own hardware:

```bash
./ollama launch claude --model qwen3.5:9b
```

It sets Claude Code's API address to the local Ollama server and uses a
placeholder key, so nothing goes to a cloud API. If the model is not
pulled yet it stops and says so; add `--yes` to let it pull automatically.
Claude Code itself must be installed; the launcher offers to install it if
it is missing.

### Cloud sessions and the model registry

In a Claude Code cloud session, model pulls go to `registry.ollama.ai`,
and the session's network policy must allow it. Add `registry.ollama.ai`
and `ollama.com` under Allowed domains in the environment's network
settings, with the package managers box left ticked. The policy is fixed
when a session starts, so start a new session after changing it. In the
session of 2026-11-02 the build, `ollama serve`, and `ollama launch claude`
all worked, and the pull stopped with "Forbidden" for exactly this reason.
On 2026-11-11, in an environment named "openjarvis" that allows both hosts,
all three models pulled without trouble.

## Setup from source

```bash
uv sync --extra dev --extra framework-comparison --extra server
```

```bash
uv run maturin develop --manifest-path rust/crates/openjarvis-python/Cargo.toml
```

```bash
uv run jarvis init --force --engine ollama --no-scan
```

These are the same extras CI installs. The plain `uv sync --extra dev` from the
upstream README is not enough to collect the test suite, because the server
tests import FastAPI.

If Ollama lives on another machine on the shop network, pass its address:

```bash
uv run jarvis init --force --engine ollama --host http://<host>:11434
```

### GUI (optional)

The frontend pins npm 11. On a machine with npm 10, run npm 11 through npx:

```bash
cd frontend && npx -y npm@11 ci && npx -y npm@11 run build
```

The build writes into `src/openjarvis/server/static/`, and `jarvis serve`
hosts the GUI from there. `jarvis gui` starts the Vite dev server instead.

On first launch the GUI shows a "Win a Mac mini" leaderboard and analytics
opt-in dialog. Choose **Continue without sharing** unless the team has decided
otherwise. Analytics are also off in the generated config
(`analytics.enabled = false`).

## Running the tests

Python, the same lane CI runs:

```bash
uv run pytest tests/ -n auto -q --tb=short -m "not live and not cloud and not hub"
```

Rust:

```bash
cd rust && cargo test --workspace
```

Frontend:

```bash
cd frontend && npx -y npm@11 test
```

Lint and format:

```bash
uv run ruff check src/ tests/ && uv run ruff format --check src/ tests/
```

### Status at the baseline commit

| Suite | Result |
|---|---|
| Python | 9383 passed, 4 failed, 106 skipped |
| Rust | all passed, 29 crates |
| Frontend | 117 passed |
| Ruff | clean |

The four Python failures (`tests/server/test_connectors_router.py` and
`tests/tools/test_web_search.py`) make live network calls to Granola,
DuckDuckGo, and example.com. They pass with open internet access and fail
behind a restrictive proxy. Treat them as environment failures, not
regressions, unless the error text changes.

A fifth failure appears on a machine where the deep research setup script
has run: `tests/memory/test_ingest.py::test_read_document_pdf_missing_dep`.
That script installs the PDF reader, and the test hands the reader a fake
PDF while only allowing for the reader being absent. It is an environment
difference too. The skipped count also moves with the extras installed. On
2026-11-12, with the PDF extra in place, the suite gave 9382 passed, 5
failed, 92 skipped.

## Quick smoke test

With Ollama running and a model pulled:

```bash
uv run jarvis doctor
```

```bash
uv run jarvis ask "Hello"
```

```bash
uv run jarvis serve --host 127.0.0.1 --port 8000
```

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.5:4b","messages":[{"role":"user","content":"hello"}]}'
```

The server is OpenAI-compatible, exposes 97 routes, and supports streaming.
Stop it with `uv run jarvis stop`.

## The Floras Auto Jarvis interface

A single branded page, served by the local API server at `/floras.html`,
that acts as the team's front door: cards for all ten agents with their
setup and run commands ready to copy, live status chips for the server,
engine, model, and active agent, and a chat panel that streams from
whichever agent the active config selects. The full OpenJarvis GUI stays
available at `/` on the same server.

Files:

| Path | Purpose |
|---|---|
| `frontend/public/floras.html` | The page. Vite copies it into `src/openjarvis/server/static/` at build time, and the server serves it at `/floras.html`. |
| `scripts/floras-auto/start-interface.sh` | Builds the frontend once if needed, refreshes the page copy when the page has changed since that build, starts the server in the background, and prints or opens the address. |

Start it:

```bash
scripts/floras-auto/start-interface.sh
```

Then open http://127.0.0.1:8000/floras.html on that machine. Stop with
`uv run jarvis stop`.

### How it works, and its limits

- The page is plain HTML and JavaScript with no build step of its own. It
  reads `/health`, `/v1/info`, and `/v1/models` for the status chips and
  posts to the OpenAI-compatible `/v1/chat/completions` endpoint with
  streaming for the chat.
- **The chat talks to the active agent only.** The chat endpoint has no
  per-request agent switch, so the server answers with the agent from the
  config that was active when it started. To use a different agent, run its
  setup script and restart the server. The cards exist so the team does not
  have to remember those commands.
- The server binds to the local machine. Do not open it to the shop network
  without putting authentication in front of it.
- Any `uv run jarvis` or GUI first launch may still show the upstream
  leaderboard dialog at `/`. The Floras page does not.

Verified in the sandbox on 2026-11-02: the start script found the built
page, started the server, and reported the address; in a headless browser
the page showed all ten cards, the status chips read server online with the
engine, model, and agent, a message sent from the chat panel streamed back
a reply from the stand-in engine, and the console showed no errors.

## Real-model check: how the agents did on qwen3.5:9b

Until 2026-11-11 every agent here had only run against a stand-in engine
with canned replies. On 2026-11-11 and 2026-11-12 each one ran against the
real `qwen3.5:9b` model on Ollama, through its own setup script, on a
four-core machine with no GPU. The inputs were three fictional overnight
notes and two fictional policy documents with known facts, so every answer
could be checked.

The first run passed three agents, half-passed five, and failed one. The
first round of fixes came out of that run, and the changed agents were
rerun until they passed or the cause was understood. The table shows where
that round ended. The follow-up below it shows what a harder test found.

| Agent | First run | After the fixes | Time of latest run |
|---|---|---|---|
| Deep research | Pass: both answers correct, with citations | not changed | 1.5 min |
| Code assistant | Pass: its script printed the right top five | output limit raised only | 2 min |
| Morning digest | Pass with no sources connected | not changed | under 1 min |
| Scheduled monitor | Partial: no per-unit list, stale saved summary | Pass: full list, latest statuses, summary really stored | 3 min |
| Title watch | Fail: could not find the notes, wrote nothing | Pass: correct page, and the next run tracked a change | 4 min |
| Office assistant | Partial: draft landed in the notes folder with a wrong date | Pass: calculator used, correct total, draft in the drafts folder | 4 min |
| Intake checker | Partial: invented owner roles, misfiled a parts promise | Pass: owners unassigned, parts "none noted", checklist saved | 5 min |
| Deal calculator | Partial: right figures, but never saved the deal sheet | Pass: same figures, deal sheet saved, surcharge rule explicit | 6 min |
| Weekly recap | Partial: counted a title as resolved that no note mentions | Pass: every count and the totals correct | 11 min |

What held up from the start: tool calling, the ReAct text format, running
Python, and file fencing all work on the real model. No agent invented a
VIN or a price, and every figure computed with a tool was correct.

### Follow-up on 2026-11-13 and 2026-11-16: the small misses

The passes above still had small misses. Each was worked on and rerun, on
four test units across four notes, with a fifth note added before a second
run. Three of them turned out not to be small.

| Miss | What was done | Result in the reruns |
|---|---|---|
| Simple chat named the wrong weekday and added a requirement | Persona rules: no dates of its own, only the details given | Clean on 2 runs of 2 |
| Office assistant replied with only the saved path | Persona fixes the order: answer, steps, path | Answer and every figure in the reply, 1 run of 1 |
| Deal calculator replied with only the saved path | Reply repeats the sheet, then the path | Right on 1 run of 1 with the final wording |
| Intake checker left out title type and days pending | Checklist items name their parts; a later note wins; a source on every item | Both present on 3 runs of 3; everything right on 2 |
| Title watch did not flag a pickup due today | The refresh script marks every date `[TODAY]`, `[PAST]`, or `[FUTURE]` | On the call list on 6 first runs of 6 |
| Title watch counted business days its own way | The script prints the count on each note | Right on 6 runs of 6 |
| Scheduled monitor left out a transport booking | Rebuilt: reads the notes bundle, numbers every unit, lists transport as Done and Waiting, stores nothing | All four units on 5 runs of 6; transport right on both first mornings |
| Weekly recap dropped its "past 10 business days" line | Line removed: a one-week recap cannot hold such a title. The title watch carries old titles forward | The watch carried and flagged a 14-day title, 1 run of 1 |

Larger problems found on the way, and fixed:

- **The weekly recap wrote nothing** when its think step ran past the
  output limit, two runs out of two, on a four-unit week. The think step
  is gone.
- **The weekly recap copied last week's figures** when it read last week's
  recap. It no longer reads it, and no longer compares weeks.
- **The scheduled monitor repeated yesterday's review** when its stored
  summary was fed back in. It stores nothing now.
- **The title watch once put its page in the reply** without saving it. It
  has saved the page on every run since the instruction was reworded.

What to keep in mind when using them:

- **Each result is a handful of runs.** The model is not consistent. At
  temperature 0.3 the office assistant used the calculator and saved its
  draft on one run and, on the next, added in its head, got the total wrong
  by $10, and reported a saved file that did not exist. Low temperature and
  explicit rules reduced this in testing. They do not remove it. Check
  anything that matters.
- **The three monitors still make a mistake on some runs.** Tracking four
  units across four notes is the hardest thing asked of this model here.
  Dates, day counts, and the 10-day limit are now worked out by the refresh
  script, and those came out right. What the model still has to judge, it
  sometimes gets wrong: a late delivery that was "not confirmed" was
  flagged by the title watch on two first runs of five, and the scheduled
  monitor once called a title "received" that no note mentions. Treat the
  status page, the morning review, and the recap as prompts to look, not as
  the record.
- **A larger model has not been tried.** It is the obvious next thing to
  try for the three monitors if a machine with a GPU is available.
- **Not tested:** the morning digest with a real mailbox, calendar, and
  voice; the agents firing on their own schedules through the daemons; real
  dealership notes and documents; a week of notes longer than a few pages;
  notes that write dates in a form the refresh script does not recognise.
- **Speed is for a machine with no GPU.** The model reads about 35 tokens a
  second and writes about 3 there, so every model turn costs half a minute
  or more.

## Keeping the notes fresh: refresh-notes.py

Five agents work from the overnight notes folder, and none of them can look
in it directly: no tool lets an agent list a folder. One script does that
work for all of them. Run it whenever notes change, or leave it running.

```bash
uv run python scripts/floras-auto/refresh-notes.py ~/FlorasAuto/overnight-notes --every 600
```

Each pass does three things:

1. **Writes a bundle of the recent notes** into a `jarvis` folder beside the
   notes folder. The bundle starts with today's date, written both in full
   and the way notes write it (`11/13`), and a table of business days
   elapsed since each recent date. Then comes the full text of every note
   from the last seven days, oldest first. The weekly recap and the
   scheduled monitor read it as one file, `recent-notes.md`. The title
   watch reads the same text as pages, `recent-notes-page-1.md` onward, each
   under 2,000 characters.
2. **Re-indexes the notes folder into memory**, so the agents that search
   (office assistant, intake checker) see new notes.
3. **Re-counts the pending titles on the title watch's status page.** A line
   such as "pending since 2026-10-27, 8 business days (not over 10)" is
   rewritten with today's count. The watch carries an old pending title
   forward by copying its line, count and all, so without this pass the
   count would never grow and the 10-day limit would never be reached.

| Option | Meaning |
|---|---|
| `--every SECONDS` | Keep running and refresh on that interval. Without it, one pass. |
| `--days N` | How many days of notes go in the bundle. Default 7. |
| `--no-index` | Skip the memory index. Use it on a machine whose active config is the title watch, weekly recap, or scheduled monitor, which run without memory. |
| `--status-page FILE` | The title watch's status page. Default: `status/title-watch.md` beside the notes folder, which is where the standard setup puts it. Skipped when the file does not exist. |

The script also does the date work the model gets wrong:

- **Every date in a note is followed by a mark**: `[TODAY]`, `[PAST]`, or
  `[FUTURE]`. Asked to flag a pickup booked for today, the model first
  wrote no flag and then, on the next try, wrote "upcoming". With the marks
  it reads the answer off the page. A note line then looks like this:
  `Pickup moved to Friday 11/13 [TODAY], same $340 quote.`
- **Every note's heading carries its age**: `Business days since this note:
  4 (not over 10).` A title that went pending in that note has been pending
  that long.
- **Every count says which side of the 10-day limit it is on**: `(not over
  10)` or `(OVER 10)`, in the note headings and in the table. Left to
  compare the number with 10 itself, the model listed a title at 4 business
  days as "over 10". The limit is `TITLE_LIMIT_DAYS` at the top of the
  script.
- Dates are recognised as `2026-11-09`, `November 9`, `Nov 9, 2026`,
  `11/09/2026`, and `11/09`. A bare month and day counts as a date only when
  both parts have two digits or a weekday comes first (`Fri 11/9`), so
  "3/4 ton" and "1/2 tank" are left alone. Write dates one of these ways.
  A date written another way gets no mark, and the agent has to judge it.
- The marks are only in the bundle. The note files are never changed.

How notes are picked up:

- `.md`, `.markdown`, and `.txt` files directly in the notes folder. Files in
  subfolders, and names starting with `.` or `_`, are ignored.
- A note's date comes from a `YYYY-MM-DD` in its file name, for example
  `overnight-2026-11-09.md`. Name notes this way. Without a date in the
  name, the file's last-modified date is used, which changes when a file is
  copied or edited.
- Holidays are not skipped in the business-day table.
- The table counts days elapsed, so a title that went pending on Monday
  shows 1 on Tuesday. A note that counts Monday as day one will read one
  higher. The agents are told to use the table and ignore counts in notes.
- A deleted note stays in the memory index until the index is rebuilt.

On a shop machine, three things must stay running for the scheduled agents:
`ollama serve`, this refresh loop, and the agent's own daemon
(`jarvis scheduler start` or `jarvis agents daemon`).

## Scheduled monitor: morning auction review

Our first configured agent. Every morning it reads the notes bundle and
writes a morning review: every unit bought from Edge Pipeline, IAA, and
Salvato, numbered, each with its title status and its pickup or transport
status, then what needs a call today. It reads one local file, so nothing
leaves the machine. Its only tool is `file_read`, fenced to the bundle
folder. The review is the task's result and is kept in the scheduler's run
log; `show-morning-review.py` prints it.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/scheduled-monitor.toml` | Config installed to `~/.openjarvis/config.toml`. |
| `scripts/floras-auto/setup-scheduled-monitor.sh` | One-shot setup: installs the config with the bundle folder, writes the first notes bundle, registers the task. |
| `scripts/floras-auto/show-morning-review.py` | Prints the latest review in full, and can save it to a file. |

Set it up. The third argument, the bundle folder, is optional and defaults
to a `jarvis` folder beside the notes folder:

```bash
scripts/floras-auto/setup-scheduled-monitor.sh ~/FlorasAuto/overnight-notes "0 7 * * 1-6"
```

Then run it once to test, and start the scheduler to honour the schedule:

```bash
uv run jarvis scheduler run-task operative
```

```bash
uv run jarvis scheduler start
```

Read the latest review in full, or save it where the team can open it:

```bash
uv run python scripts/floras-auto/show-morning-review.py
```

```bash
uv run python scripts/floras-auto/show-morning-review.py --save ~/FlorasAuto/status/morning-review.md
```

`jarvis scheduler logs <task-id>` lists the runs but shows only the first
few words of each review, which is why this script exists. It reads the
scheduler's database and changes nothing in it.

The scheduler runs in the foreground. On a shop machine, run it under a
service manager or a scheduled task so it survives reboots. The monitor
works from the notes bundle, so keep `refresh-notes.py` running too, or it
reviews old notes. The setup script prints the command.

### How it works, and why

The first version searched memory for the notes and stored a summary there
for the next run. Both went wrong on the real model.

- **It reads the notes bundle, not memory.** Memory search hands the agent
  the five best-matching pieces of the notes, in no particular order. On
  four short test notes the review dropped a unit and missed a pickup that a
  later note had moved. A real week of notes does not fit in five pieces.
  See "Keeping the notes fresh".
- **It stores nothing.** The summary one run stored was fed back into the
  next morning's run, and that review repeated the old statuses instead of
  reading the new note. Memory is switched off for this config, as for the
  title watch and the weekly recap.
- **Units are numbered one by one and counted afterwards.** Asked to list
  units "from Edge Pipeline, IAA, and Salvato", the model gave each source
  exactly one unit. Asked for the count first, it wrote 3 and then listed
  three of four.
- **Title and transport are reported separately.** Asked for "pickup or
  title status", it gave one of the two. Each unit's line ends with its
  title status: received, pending, or not mentioned.
- **Transport is two lists, Done and Waiting**, as on the title watch's
  page. Given one free line per unit, the model wrote "done" for a pickup
  that had only been moved to another day.
- **"Due today" and "late" come from the date marks** the refresh script
  puts in the bundle, not from the model comparing dates.

The upstream guide for this preset is out of date. The real command syntax is:

| Documented | Actual |
|---|---|
| `scheduler create --prompt X --schedule Y` | `scheduler create "X" --type cron --value "Y"` |
| `scheduler run <id>` | `scheduler run-task <agent-name>` |
| `scheduler status <id>` | `scheduler logs <id>` |
| `scheduler delete <id>` | `scheduler cancel <id>` |

Real-model result (2026-11-16, `qwen3.5:9b`), on four test units across
four notes, two mornings in a row. On its best first morning the review
listed all four units, got every title and every transport line right, and
put the pickup due today, the late delivery, and a pending title on the
call list, in about three and a half minutes. Over the last three first
mornings the unit count was right every time and the transport lists were
right twice. Second mornings, after a new note, were weaker each time: a
unit left out of the numbered list, a unit on both transport lists, and
once a title called "received" that no note mentions. Read the review as a
prompt to look, not as the record. Earlier versions did worse; see
"Real-model check".

## Morning digest: spoken team briefing

A spoken briefing for the start of the business day: new purchases and
arrivals, emails that need a reply, today's calendar, and weather where it
affects transport. The model runs on Ollama and the voice on Kokoro, so no
cloud API key is needed. Sources are collected from connectors the team
chooses to connect; anything not connected is simply skipped.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/morning-digest.toml` | Config installed to `~/.openjarvis/config.toml`. |
| `configs/floras-auto/personas/floras-auto.md` | Briefing style: professional, addresses the team, closes with action items. |
| `scripts/floras-auto/setup-morning-digest.sh` | Installs the voice extra, config, and persona; offers to connect the mailbox, weather, and news feeds. |

Set it up:

```bash
scripts/floras-auto/setup-morning-digest.sh
```

Then generate the first briefing as text, and with audio once it reads well:

```bash
uv run jarvis digest --fresh --text-only
```

```bash
uv run jarvis digest --fresh
```

Before the first run, edit `timezone` in the config. It ships as
`America/New_York` as a placeholder.

### Sources

| Section | Source | How to connect |
|---|---|---|
| messages | `imap` | Generic IMAP. Works with the Yahoo team mailbox and detects the server from the address. Needs an app password, not the login password. The setup script prompts for it, or use the GUI's Data Sources page. |
| calendar | `gcalendar` | `uv run jarvis connect gdrive`, one Google OAuth flow. Optional. |
| world | `weather` | Free OpenWeatherMap key in `~/.openjarvis/connectors/weather.json`. The script prompts for it. |
| world | `news_rss` | Feed list in `~/.openjarvis/connectors/news_rss.json`. The script writes a starter list. |

The scheduled monitor and the morning digest use different configs. The
monitor's config is the one with `default_agent = "operative"` and the
scheduler task; the digest's has the `[digest]` section. Installing one
backs up and replaces the other in `~/.openjarvis/config.toml`. To run both
on one machine, merge the two files by hand: keep the monitor's `[agent]`
and `[tools]` lists and add the digest's `[digest]` sections plus
`digest_collect` and `text_to_speech` to `tools.enabled`.

### Quirks found in the digest CLI

- `jarvis digest --schedule` with no value errors. Pass an empty string to
  show status: `jarvis digest --schedule ""`.
- `jarvis digest --text-only` still prints "Playing audio..." lines. Harmless
  when no speech backend is installed.
- `jarvis connect imap` runs the OAuth flow and fails, because the CLI treats
  the IMAP connectors as OAuth sources. Use the setup script or the GUI.

Real-model result (2026-11-11, `qwen3.5:9b`): with no sources connected it
addressed the team, gave the correct date, said plainly that the mailbox,
calendar, weather, and news were not connected, and invented nothing. A
briefing built from a real mailbox, and the Kokoro voice, are still
untested.

## Deep research: questions over our own documents

Ask questions about dealership documents such as title procedures, vendor
lists, auction notes, and parts references, and get answers that cite the
source files. Documents are ingested into a local knowledge store and
answered by the local model, so nothing leaves the machine. Web search is
left out of the config on purpose.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/deep-research.toml` | Config installed to `~/.openjarvis/config.toml`. |
| `scripts/floras-auto/ingest-documents.py` | Ingests a folder (.md .txt .csv .pdf .docx) into the knowledge store. Re-running replaces, never duplicates. |
| `scripts/floras-auto/setup-deep-research.sh` | Installs PDF and Word support, the config, and runs the ingest. |

Set it up and ask a question:

```bash
scripts/floras-auto/setup-deep-research.sh ~/FlorasAuto/documents
```

```bash
uv run jarvis ask --research "What is our policy on pending titles?"
```

Re-ingest whenever documents change:

```bash
uv run python scripts/floras-auto/ingest-documents.py ~/FlorasAuto/documents
```

Optional, for better ranking once Ollama is installed:

```bash
ollama pull nomic-embed-text
```

### Two things the upstream guide gets wrong

- **Use the ingest script, not `jarvis memory index`.** The memory index
  command writes to `memory.db`. The deep research tools read `knowledge.db`.
  Following the upstream guide leaves the agent with nothing to search.
- **Always pass `--research` to `jarvis ask`.** From the CLI, the
  `deep_research` agent is built without a knowledge store even when
  `knowledge.db` exists, so every search returns "No knowledge store
  configured". The `--research` flag uses a separate research loop that is
  wired correctly. The GUI's Deep Research mode is wired correctly too.

Export Excel sheets to CSV or PDF before ingesting. Unsupported files are
skipped and listed at the end of the ingest run.

Real-model result (2026-11-11, `qwen3.5:9b`): asked a two-part question
over two test policy documents, it answered both parts correctly with
citations in about ninety seconds, and ranking used the `nomic-embed-text`
model. The output shows citation numbers but does not list which file each
number refers to.

## Code assistant: local help with our own scripts

A coding helper for the team's scripts: CSV clean-ups, report generators,
import helpers. It reads and writes files inside one workspace folder, runs
Python in a hardened subprocess, and reasons step by step. The model runs on
Ollama, so code and data never leave the machine.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/code-assistant.toml` | Config installed to `~/.openjarvis/config.toml`, with file access fenced to one folder. |
| `scripts/floras-auto/setup-code-assistant.sh` | Installs the config and points the fence at the workspace you choose. |

Set it up and start a session:

```bash
scripts/floras-auto/setup-code-assistant.sh ~/FlorasAuto/scripts
```

```bash
cd ~/FlorasAuto/scripts && uv run jarvis chat
```

### Safety decisions, and why

- **Use `jarvis chat`, never `jarvis ask`, with this agent.** The ask command
  auto-approves every tool call (`src/openjarvis/cli/ask.py`, the
  `confirm_callback` that always returns true). Chat prompts y/N before any
  tool marked sensitive. Verified in the sandbox: with `shell_exec` enabled,
  `jarvis ask` ran a shell command with no prompt at all.
- **`shell_exec` is left out of the config.** The Python interpreter tool
  covers most script work and runs in a subprocess that blocks `os`, `sys`,
  `subprocess`, and network imports, with a timeout. If a task truly needs
  the shell, add `shell_exec` to `tools.enabled` for that session and stay
  in chat.
- **File access is fenced.** `security.allowed_dirs` limits `file_read` and
  `file_write` to the workspace. Verified: a read inside the fence succeeded,
  a read of `/etc/hostname` was refused, a write landed inside the folder.
- **No web search**, so questions and code stay local.
- The upstream guide mentions a `sandboxed` agent for Docker isolation. It is
  not registered in this version, so do not rely on it.

Real-model result (2026-11-11, `qwen3.5:9b`): asked for a script that
prints the five best-selling models from a CSV, it wrote one in two turns,
and the script printed exactly the right five when run from its folder. It
opens the CSV relative to the current folder, so it fails when run from
elsewhere. The output limit is raised to 4,096 tokens, because a script is
written in one tool call and a call that is cut off writes nothing.

## Simple chat: a general assistant for the team

A plain assistant with no tools, no file access, and no web: drafting
customer and vendor messages, explaining auction and title terms, cleaning up
notes, quick arithmetic. It carries a Floras Auto identity through a persona
file, and memory injection is off so one person's chat never leaks into
another's on a shared machine.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/chat-simple.toml` | Config installed to `~/.openjarvis/config.toml`. |
| `configs/floras-auto/personas/chat/SOUL.md` | The assistant's identity and rules. Installed to `~/.openjarvis/personas/floras-auto/`. |
| `configs/floras-auto/personas/chat/USER.md` | Describes the team. Installed once and then kept local, so edit the installed copy. |
| `scripts/floras-auto/setup-chat-simple.sh` | Installs the config and the persona. |

Set it up and use it:

```bash
scripts/floras-auto/setup-chat-simple.sh
```

```bash
uv run jarvis chat
```

```bash
uv run jarvis serve
```

The server binds to the local machine only. Do not open it to the shop
network without putting authentication in front of it.

### How the identity works

The `[memory_files] persona_name` setting makes the prompt builder read
`SOUL.md`, `MEMORY.md`, and `USER.md` from `~/.openjarvis/personas/<name>/`
and append them to the system prompt. The `[agent] system_prompt` setting
that the config schema advertises is not read by the CLI, so use the persona
mechanism instead. Verified in the sandbox: the persona text reached the
engine's system prompt through `jarvis ask`, the API server, and `jarvis chat`.

Real-model result (`qwen3.5:4b`): on 2026-11-11, asked for a pickup-ready
text, it wrote a professional draft but named the wrong weekday and told the
customer to bring a document nobody had mentioned. The persona now says that
it is not told the date, that a draft uses only the details the user gave,
and that a missing detail gets a blank in square brackets. On 2026-11-13 two
reruns of the same request kept "tomorrow after 10 AM" as given and added
nothing. Both drafts opened with a "Subject:" line, which a text message
does not have. Read its drafts before sending them.

The upstream guide mentions an `OPENJARVIS_MODEL` environment variable. It
does not exist in this version; use `jarvis ask -m <model>` or edit the config.

## Title and transport watch: a continuous managed agent

The monitor operative is a long-running agent managed by the agents
subsystem, with checkpoints, pause and resume, and a status page it owns.
Every 30 minutes ours reads its own previous status page and the recent
notes, then rewrites a one-page status file: titles pending and for how
long, transport due, parts promises, what changed since the last run, and
what needs a call today.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/title-watch.toml` | Global config: engine, model, output and turn limits, memory off, and file access fenced to the status and notes-bundle folders. |
| `configs/floras-auto/templates/floras_title_watch.toml` | The managed-agent template: schedule, tools, and the step-by-step prompt. |
| `scripts/floras-auto/setup-title-watch.sh` | Installs the config and template with the real file paths written in, writes the first notes bundle, and creates the agent. |

Set it up, test one run, then schedule it. The setup prints these commands
with the real agent id and paths:

```bash
scripts/floras-auto/setup-title-watch.sh ~/FlorasAuto/overnight-notes ~/FlorasAuto/status
```

```bash
uv run jarvis agents run <agent-id>
```

```bash
uv run jarvis agents start <agent-id>
```

```bash
uv run jarvis agents daemon
```

```bash
uv run python scripts/floras-auto/refresh-notes.py ~/FlorasAuto/overnight-notes --no-index --every 600
```

With the standard folders the refresh loop finds the status page by itself.
If your status folder is somewhere else, add `--status-page` with the full
path of `title-watch.md`. The setup script prints the exact command.

The daemon and the refresh loop both run in the foreground and must stay
up. The status page lands at `~/FlorasAuto/status/title-watch.md` and shows
when the notes bundle was written, so stale notes are visible on the page.

### Reading the status page

- **Titles pending** lists each title a note says is pending, the day it
  went pending, the business days since, and `(not over 10)` or `(OVER 10)`.
- **Transport** has a Done line and a Waiting list. A waiting pickup ends
  with the mark from the notes bundle: `[TODAY]` is due today, `[PAST]` is
  late, `[FUTURE]` is still to come.
- **Needs a call today** should hold titles marked `(OVER 10)`, waiting
  transport marked `[TODAY]` or `[PAST]`, and open parts promises, and
  nothing else. When there is nothing, it says so in one line.

A title that stays pending for weeks drops out of the notes bundle after
seven days. The watch keeps it by copying its line from its previous page,
and `refresh-notes.py` keeps the count on that line current. In the one
test of this, a title pending since 2026-10-27 was carried to a new page,
shown at 14 business days, marked `(OVER 10)`, and put on the call list.
This only works while the refresh loop runs with the status page in reach:
use the command the setup script prints.

### How it works, and why

The first version told the agent to read every file in the notes folder and
keep its state in memory. On the real model it wrote nothing. Each choice
below answers something found in those runs.

- **It reads the notes bundle, not the folder.** No tool can list a folder,
  so the agent could not find the note files and ran out of turns guessing
  names. See "Keeping the notes fresh".
- **The notes come in pages under 2,000 characters.** This agent type
  replaces any longer tool output with a model-written summary before the
  agent sees it. The status page is kept under that size for the same reason.
- **One page costs one model turn.** The turn limit of 12 leaves room for
  about nine pages, roughly 12,000 characters of notes in the seven-day
  window. Past that, expect the run to end before the page is written,
  leaving the old page in place with its old "Updated" line. This has not
  been tested with notes that long. If yours run longer, raise
  `[agent] max_turns` in `title-watch.toml` and rerun the setup. The
  refresh script prints the page count on every pass.
- **Its state is its own status page.** Each run starts by reading the
  previous page. Memory is switched off for this config
  (`[tools.storage] default_backend = "none"`, a name no backend is
  registered under). With memory on, this agent type makes an extra model
  call after every tool call to extract "causal relationships" into the
  store all agents share, and pulls other agents' leftovers into its prompt.
- **No think step.** With one, the model spent its whole output allowance
  on a single think call, was cut off, and the run ended with nothing
  written. It now writes the page straight after the last notes page.
- **Output limit raised to 2,048 tokens**, turn limit set to 12, temperature
  0.1. All three come from the global config. The template's own
  `max_turns`, `temperature`, and four strategy fields are stored with the
  agent but never applied.
- **Dates are judged by the refresh script, not the model.** The page
  carries the bundle's marks as they are: a waiting pickup ends in
  `[TODAY]`, `[PAST]`, or `[FUTURE]`. `[TODAY]` means due today and `[PAST]`
  means late. Asked to compare dates itself, the model left a pickup booked
  for today unflagged on one run and called it "upcoming" on the next.
- **Day counts and the 10-day limit are copied too.** Each note's heading
  in the bundle says how many business days have passed since it and
  whether that is over 10, and a pending title's line repeats both. Left to
  count, the model continued a note's own "now 3 business days". Left to
  compare with 10, it listed a title at 4 days as "over 10".
- **Transport is split into Done and Waiting**, and every booked unit goes
  on one of them. Done needs a note that says so in words. One run called a
  delivery done that a note said was "not confirmed yet", because its date
  had passed.
- **The page must be saved, not spoken.** One run put the whole new page in
  its reply and never called `file_write`, so the old page stayed in place.
  The standing instruction now says that only a `file_write` call saves it.
- **An old pending title is carried by copying its line.** The notes that
  mention it age out of the bundle, so the previous page is the only place
  it lives. The model copies the old count with the line, so the refresh
  script re-counts the pending lines on the status page before each run.
  Everything else on the page is written fresh from the notes.

### Things to know about managed agents

- **`jarvis agents run` needs the agent id, not its name.** `agents list`
  shows it, and prints to stderr, so a script must capture `2>&1`.
- **`jarvis agents create` takes no instruction.** The setup script writes
  the real file paths into the template's prompt before installing it.
- **Rerunning the setup creates a second agent with the same name.** Delete
  the old one first with `jarvis agents delete <agent-id>`.
- **`jarvis agents logs` reports no history after `agents run`.** The run
  count and findings do show in `agents info` and `agents list`.
- **Managed agents auto-approve sensitive tools** when run from the CLI,
  the same as `jarvis ask`. This template has only `file_read` and
  `file_write`, fenced to two folders.

Real-model result (2026-11-13 and 2026-11-16, `qwen3.5:9b`), on four test
units across four notes. Since the date marks went in, the page has been
saved on every run, the pickup due today has been on the call list on six
first runs out of six, and the day counts have been right on six runs out
of six. On the last run a title carried over from an older page was shown
as 14 business days, over 10, and put on the call list. A run takes five to
ten minutes on a machine with no GPU.

What it still gets wrong on some runs: a delivery that is late and "not
confirmed yet" was put on the call list on two first runs out of five. On
the others it was listed as late but left off the call list, or treated as
arrived. Smaller slips move around from run to run: "$0" for a cost no
note gives, a unit missing from the Done line. Read the page as a prompt to
look, not as the record. See "Real-model check".

## Office assistant: multi-step help with tools

The orchestrator is the agent that picks tools itself, turn by turn. Ours is
set up as an office assistant: it looks things up in the indexed notes with
a cited search, does fee and margin arithmetic with a calculator, stores
reminders, and drafts emails or checklists as files in a shared folder. No
shell, no code execution, no web. The model runs on Ollama.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/office-assistant.toml` | Config with the orchestrator agent, six tools, and file access fenced to the drafts and notes folders. |
| `configs/floras-auto/personas/office/SOUL.md` | Tells the assistant when to use each tool and how to report. Installed to `~/.openjarvis/personas/floras-office/` with the drafts folder path written in. |
| `scripts/floras-auto/setup-office-assistant.sh` | Installs the config and persona and indexes the notes folder. |

Set it up and start a session:

```bash
scripts/floras-auto/setup-office-assistant.sh ~/FlorasAuto/overnight-notes ~/FlorasAuto/drafts
```

```bash
uv run jarvis chat
```

Re-index whenever notes change. For this agent `jarvis memory index` is the
right command, because the `memory_search` tool reads `memory.db`:

```bash
uv run jarvis memory index ~/FlorasAuto/overnight-notes
```

The refresh loop in "Keeping the notes fresh" does the same on a timer.

### What the real-model runs changed

- **The drafts folder is listed first in `allowed_dirs`.** A file saved
  without a full path lands in the first folder listed. With the notes
  folder first, a draft landed among the notes and was indexed as one, and
  another agent then cited it as a source.
- **The persona carries the full drafts path**, written in by the setup.
- **Three rules are spelled out in the persona**: every number comes from a
  calculator call, a file is saved only by `file_write` and never claimed
  otherwise, and nothing is invented. On one run the model added in its head,
  got the total wrong by $10, and reported a saved file that did not exist.
- **Temperature is 0.1.** At 0.3 the same request behaved correctly on one
  run and badly on the next.
- **It writes no dates of its own.** `jarvis ask` does not tell the model
  the date, and it had dated a draft a day late.
- **The reply states the answer, then the path.** After saving a draft the
  model used to reply with only "Note saved to" and the path. The persona
  now fixes the order: the findings and every figure, the steps taken, and
  the saved path on the last line.

### How it differs from the other agents

- The **code assistant** is the same orchestrator agent with the Python
  interpreter instead of memory search. Use that one for scripts, this one
  for office work.
- The **deep research** agent gives longer, cited answers over the full
  document set in `knowledge.db`. This one gives quick lookups over notes in
  `memory.db` and can act on them.
- Memory is shared across the Floras agents on one machine, so the title
  watch's stored summaries also show up in this assistant's searches. That
  is useful, but keep it in mind when reading results.
- Context injection is off; the agent reaches the notes only through the
  search tool, so every fact it uses is visible as a tool call.

Real-model result (2026-11-13, `qwen3.5:9b`): it found the pending items in
the notes, including a pickup that a later note had moved, reported the
correct total with every line, and saved the draft in the drafts folder.
The reply stated all of that and gave the path last. On this run it made one
calculator call for the total and worked the tax line out itself; the
figure was right. Two runs on 2026-11-12 each failed in a different way.
See "Real-model check".

## Unit intake checker: an auditable ReAct agent

The native ReAct agent reasons in a visible Thought, Action, Observation
loop, which makes it the right choice when a colleague needs to see how a
conclusion was reached. Ours works one unit at a time: it searches the
notes, walks a fixed intake checklist (title, odometer, keys, transport,
yard location, parts promises, photos, damage), writes the checklist to the
intake folder, and reports only the open items and who should own them.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/intake-checker.toml` | Config with the `native_react` agent, five tools, and file access fenced to the intake and notes folders. |
| `configs/floras-auto/prompts/native_react_system_prompt.md` | The agent's system prompt: the checklist, the rules, and the ReAct format block. |
| `configs/floras-auto/roles.md` | The team's roles. The checker names owners only from this list. Ships empty. |
| `scripts/floras-auto/setup-intake-checker.sh` | Installs the config, installs the prompt with the intake path and the roles written in, and indexes the notes. |

Set it up and run one unit:

```bash
scripts/floras-auto/setup-intake-checker.sh ~/FlorasAuto/overnight-notes ~/FlorasAuto/intake
```

```bash
uv run jarvis ask "Intake checklist for the IAA SUV"
```

### Owners come from roles.md

The checker ends each open item with an owner. On its first real run it had
no list to draw on and invented roles such as "Title Clerk" and "Yard
Coordinator". It now names an owner only from `configs/floras-auto/roles.md`.
That file ships empty, so until the office fills it in, every item reads
"owner: unassigned". Add one line per role, written as
`Role: what that role owns`, then rerun the setup script.

### What the checklist carries

Three additions came out of the real-model runs:

- **The title and transport items name their parts.** Title: status, type
  (clean, salvage, rebuilt), whether it is in the binder, and how long a
  note says it has been pending. Transport: status, vendor, date, cost.
  When the prompt only said "title: received, logged, and type", the
  checklist said "pending" and left the rest out.
- **Every item ends with "Source:"** and the note it came from, or "none".
- **A later note wins.** Without that rule one run kept a pickup date that
  a later note had moved.

The checker is not told today's date and does not read the notes bundle. It
reports how long a note says a title has been pending, as of that note. It
cannot tell you a pickup is due today; the title watch does that.

### How this agent is customised, and a caution

- **It ignores the persona files.** The ReAct agent builds its own system
  prompt and does not use the `[memory_files]` persona. Customisation goes
  through an override file at `~/.openjarvis/agents/native_react/system_prompt.md`,
  which the setup script installs. The override must keep the format block
  and end with the `{skill_examples}{tool_descriptions}` placeholders, or
  the agent loses its tool list.
- **The override is machine-wide.** Every use of `native_react` on that
  machine gets the intake prompt. Keep this agent on its own machine or
  accept that `jarvis ask --agent native_react` always means intake.
- **Use a 9B model or larger.** The text format depends on the model
  following instructions exactly; smaller models drift and the loop stalls.
- Few-shot examples can be added at
  `~/.openjarvis/agents/native_react/few_shot.json` if the model needs
  nudging on the format.

Real-model result (2026-11-13, `qwen3.5:9b`): the 9B model held the ReAct
format in every run. The final run saved the checklist with the title as
pending, type salvage, "3 business days as of the note dated 2026-11-11",
the pickup on its moved date with the $340 quote, parts "none noted" with
the reason, and a source on every item. Every owner read "unassigned". Of
three runs that day, two were right on all of this. The middle one put the
title type in the status slot and kept the old pickup date, which is what
the later-note rule was added for. See "Real-model check".

## Deal calculator: a CodeAct agent that computes every figure

The native OpenHands agent writes small Python programs and runs them, so
numbers are computed rather than guessed and the code is visible in the
trace. Ours is a deal calculator: landed cost with buyer-fee tiers,
transport, tax, and title fee; break-even and target resale; what-if tables
for different bids. It can read a notes file for inputs and save a deal
sheet. The fee schedule lives in its prompt, where the office can edit it
when the auction houses change their rates.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/deal-calculator.toml` | Config with the `native_openhands` agent, five tools, and file access fenced to the deals and notes folders. |
| `configs/floras-auto/prompts/native_openhands_system_prompt.md` | The agent's prompt: tool format, the fee schedule, what to produce, and the rules. |
| `scripts/floras-auto/setup-deal-calculator.sh` | Installs the config and the prompt with the folder paths written in. |

Set it up and ask:

```bash
scripts/floras-auto/setup-deal-calculator.sh ~/FlorasAuto/overnight-notes ~/FlorasAuto/deals
```

```bash
uv run jarvis ask "Landed cost on the IAA SUV at a 4200 bid with 180 transport, and save a deal sheet"
```

### Things to know

- **The fee schedule shipped is a placeholder.** The rates in the prompt are
  illustrative. The office must replace them with the real IAA, Edge
  Pipeline, and Salvato schedules before anyone relies on a figure. Edit
  `~/.openjarvis/agents/native_openhands/system_prompt.md` or the repo copy
  and rerun the script.
- **The interpreter is locked down on purpose.** Python may import only
  `json`, `math`, and `time`; `open`, `exec`, `eval`, and `input` are
  blocked, and it runs in a subprocess with a timeout. Inputs come in
  through `file_read` and outputs go out through `file_write`, both fenced.
  That means the agent cannot crunch a large CSV directly; for that, the
  office assistant or a proper script is the better tool.
- **The default turn limit is 3**, which is too few to compute, save, and
  answer. The config raises it to 6.
- **Same override caution as the intake checker.** This agent ignores the
  persona files and builds its prompt from a machine-wide override at
  `~/.openjarvis/agents/native_openhands/system_prompt.md`, which must keep
  the `{tool_descriptions}` placeholder.
- **Write every fee rule so it has one reading.** "Where it applies" was
  enough for the model to add a fee on one run and leave it out on the
  next. When the office replaces the placeholder schedule, say exactly when
  each fee applies and what to do when the user does not say.
- **`file_read` and `file_write` are tools, not Python functions.** The
  model once called `file_write` inside its Python and got an error. The
  prompt now says so.

Real-model result (2026-11-13, `qwen3.5:9b`): it wrote and ran the Python,
reported the landed cost on the test unit correctly against the placeholder
schedule, and saved a deal sheet with every line and assumption. The reply
repeated the sheet and gave the saved path last. That took two tries at the
wording: told to reply in a fixed shape ending in a "Saved:" line, the
model replied with that line alone. Told to repeat the text of the sheet,
it did. Its first run on 2026-11-11 skipped the save without
saying so, and one run added the internet surcharge when the other runs
left it out, which gave two totals for the same question. The schedule now
says to add that surcharge only when the user says the bid was placed
online. See "Real-model check".

## Weekly auction recap: a scheduled operator

The operative agent is the persistent, scheduled agent, and the operators
subsystem runs it from a TOML manifest. Ours is a weekly recap: every
Friday at 5 PM it reads the recent-notes bundle and writes a one-page
recap of the week: every unit bought, numbered and counted by source,
titles received and pending, transport, parts promises, and a line of JSON
totals. Each run overwrites `weekly-recap.md`, so copy a recap elsewhere if
you want to keep it.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/operators/floras_weekly_recap.toml` | The operator manifest: cron schedule, tools, and the step-by-step prompt. |
| `configs/floras-auto/weekly-recap.toml` | Global config with the scheduler and operators enabled, output and turn limits, memory off, and file access fenced to the recaps and notes-bundle folders. |
| `scripts/floras-auto/setup-weekly-recap.sh` | Installs the config and the manifest with the real file paths written in, and writes the first notes bundle. |

Set it up, test one run, then schedule it:

```bash
scripts/floras-auto/setup-weekly-recap.sh ~/FlorasAuto/overnight-notes ~/FlorasAuto/recaps
```

```bash
uv run jarvis operators run floras_weekly_recap
```

```bash
uv run jarvis operators activate floras_weekly_recap
```

```bash
uv run jarvis scheduler start
```

```bash
uv run python scripts/floras-auto/refresh-notes.py ~/FlorasAuto/overnight-notes --no-index --every 600
```

The bundle must be fresh when the recap fires, so keep the refresh loop
running alongside the scheduler.

### How it works, and why

- **It reads the notes bundle in one call.** The first version had to find
  the note files itself, which only worked because another agent's setup had
  indexed them, and took 13 model turns. It now takes three or four.
- **Today's date and the business-day counts come from the bundle.**
  Operator ticks are not told the date.
- **It does not read last week's recap.** When it did, it copied last
  week's figures into this week's: a transport cost that belonged to a
  different unit, and "First recap" under changes. The recap is built from
  this week's notes only and makes no week-over-week comparison. The JSON
  totals line is there for anyone who wants to compare two weeks by hand.
  Memory is switched off for this config, as for the title watch.
- **No think step.** With one, the model spent its whole output allowance
  on the think call in two runs out of two, was cut off, and wrote nothing.
  A four-unit test week was enough to do it. It now writes the recap
  straight after reading the bundle.
- **Units are numbered one per line, then counted by source.** Asked for
  "each source, then its units", the model gave every source exactly one
  unit and dropped a second purchase from the same auction.
- **Each numbered unit carries its own title status**: received, pending,
  or not mentioned. Received means a note says the title was received; the
  first version read "picked up" as "title resolved". The model often
  writes "pending" where "not mentioned" is right. That mistake is harmless.
  A version with only two states was tried, and in two runs out of two it
  called an unmentioned title "received" because the truck had been picked
  up. That mistake hides a missing title, so the third state stays.
- **There is no "past 10 business days" line.** The bundle holds seven days
  of notes, so no title in it can be more than five business days old.
  Titles that have been pending for weeks are the title watch's job.
- **Output limit raised to 4,096 tokens.** Writing the recap took about 650
  for a three-unit test week, and a call that is cut off writes nothing.

### Things to know about operators

- **Activate creates a duplicate task.** The manager creates the scheduler
  task once under a random id and again under `operator:floras_weekly_recap`,
  so the recap would run twice every Friday. After activating, run
  `jarvis scheduler list` and cancel the task whose id is not the
  `operator:` one. The setup script prints this reminder.
- **`jarvis operators logs` crashes** in this version. Use
  `jarvis scheduler logs operator:floras_weekly_recap` instead. Runs started
  with `operators run` bypass the scheduler and do not appear there.
- **The manifest's `max_turns` is ignored.** Operators take the turn limit
  from `[agent] max_turns` in the global config, which this config sets to 14.
- **The memory tools are not wired on this path.** `memory_store` and
  `memory_retrieve` are built without a backend for operator ticks. The
  manifest does not use them.

Real-model result (2026-11-16, `qwen3.5:9b`): the last run was right on
every line. Four numbered units, two of them for Edge Pipeline, the title
no note mentions listed as "not mentioned", both pending titles with their
dates and counts, all four transport bookings with the moved pickup on its
new date, and the totals line. It took about seven and a half minutes on a
machine with no GPU. That is one run. Each version before it got something
wrong, and the points above say what. See "Real-model check".

## Known quirks

Found in the real-model runs of 2026-11-11 to 2026-11-16:

- **No tool can list a folder.** `file_read` reads one file at a known path.
  An agent told to "read every file in the folder" cannot find them. This
  is why `refresh-notes.py` exists.
- **Most agents are not told today's date.** Managed agents, the morning
  digest, and the deep research agent get it. Agents run through
  `jarvis ask`, `jarvis chat`, the scheduler, and operators do not, and the
  model will guess. The monitors read the date from the notes bundle.
- **The default output limit of 1,024 tokens ends runs silently.** When a
  tool call is cut off at the limit, the model returns nothing, and the run
  finishes with an empty answer and no error. The `think` tool makes this
  likely, because the model can pour the whole allowance into one thought.
  Every tool-using Floras config sets `max_tokens` to 2,048 or more.
- **Raising the limit does not make `think` safe.** At 2,048 tokens the
  weekly recap's think step still ran out, twice in a row, on a four-unit
  week. None of the three monitors has a think step now. The deal
  calculator keeps one: its questions are about one unit, and its thoughts
  have stayed short.
- **The model does not compare dates or count days reliably.** It called a
  pickup booked for today "upcoming", extended a note's own day count, and
  listed a title at 4 business days as "over 10". Anything of that kind is
  now worked out by `refresh-notes.py` and printed in the bundle, so the
  agent copies it.
- **The model's own earlier output misleads it.** Shown last week's recap,
  it copied last week's figures. Given the summary it had stored the day
  before, it repeated yesterday's statuses. The title watch still reads its
  previous page, because that is how it carries a long-pending title
  forward, and it is told to write from the notes and not to copy the page.
- **Asked for units "by source", the model gives each source one unit.**
  It dropped a second purchase from the same auction in four runs out of
  four. Ask for a numbered list, one unit per line, and count afterwards.
  Asked for the count first, it wrote 3 and then listed three of four.
- **After saving a file, the model tends to answer with only the path.**
  Tell it that the reply repeats what the file says.
- **A file saved without a full path lands in the first `allowed_dirs`
  folder.** List the output folder first, and give agents full paths.
- **The monitor operative rewrites long tool output.** Any tool result over
  2,000 characters is replaced with a model-written summary, and with memory
  on it makes an extra model call after every tool call. The template
  fields that would turn this off are not applied to managed agents.
- **Memory is shared by every agent on a machine.** One agent's stored
  summary ranks alongside the real notes in another agent's search, stale
  or wrong figures included.
- **The 9B model is not consistent from run to run.** The same request
  used the right tools on one run and skipped them on the next. Low
  temperature and short, explicit rules help. Check its work.

Found earlier:

- **`uv sync` removes the Rust extension.** Any `uv sync` rebuilds the venv
  without the locally built `openjarvis_rust` package, and the memory backend
  and rate limiter then fall back with warnings. Rebuild after every sync:

  ```bash
  uv run maturin develop --manifest-path rust/crates/openjarvis-python/Cargo.toml
  ```

  The Floras Auto setup scripts that run `uv sync` now do this themselves.

- `jarvis config show` reports `Tools: none` even when the config enables
  tools. The tools still register (`jarvis tool list` shows them). Display
  issue only, not yet investigated.
- The frontend build rewrites `frontend/tsconfig.tsbuildinfo`. Discard that
  change rather than committing it.
- `jarvis serve` and `jarvis ask` exit immediately with "No inference engine
  available" when nothing answers on the Ollama port. Start Ollama first.

## Candidate uses for the dealership

These are starting points for discussion, not commitments.

- **Scheduled monitor agent** to summarize overnight auction and purchase
  emails into a morning brief.
- **Deep research agent** over indexed internal documents such as parts
  catalogs and policy binders.
- **Code assistant agent** for internal scripts, with data staying on our own
  hardware rather than a cloud API.
