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
| Ollama | latest | Default local inference engine. The CLI and server refuse to start without a reachable engine. |

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

## Scheduled monitor: morning auction review

Our first configured agent. Every morning it reads the overnight notes the
team drops into a folder, lists each unit bought from Edge Pipeline, IAA, and
Salvato with its pickup or title status, flags follow-up calls, and stores a
dated summary so the next run can compare against it. It only reads locally
indexed documents, so nothing leaves the machine.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/scheduled-monitor.toml` | Config installed to `~/.openjarvis/config.toml`. |
| `scripts/floras-auto/setup-scheduled-monitor.sh` | One-shot setup: installs the config, indexes notes, registers the task. |

Set it up:

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

The scheduler runs in the foreground. On a shop machine, run it under a
service manager or a scheduled task so it survives reboots.

The upstream guide for this preset is out of date. The real command syntax is:

| Documented | Actual |
|---|---|
| `scheduler create --prompt X --schedule Y` | `scheduler create "X" --type cron --value "Y"` |
| `scheduler run <id>` | `scheduler run-task <agent-name>` |
| `scheduler status <id>` | `scheduler logs <id>` |
| `scheduler delete <id>` | `scheduler cancel <id>` |

Verified in the sandbox on 2026-11-02 with a stand-in engine: task creation,
an immediate run through the operative agent, and the run log all worked.
The model's actual reasoning still needs checking on a machine with Ollama.

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

Verified in the sandbox on 2026-11-02 with a stand-in engine: config parses,
the four sources are recognised and reported as not connected, the collector
builds the briefing prompt, and the engine is called. Voice output and the
real briefing text still need a machine with Ollama and the voice extra.

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

Verified in the sandbox on 2026-11-02 with a stand-in engine that issues one
search call: ingest wrote two sample documents to the knowledge store, the
research loop searched it, both documents came back as hits, and the answer
was built from them. Real answer quality still needs a machine with Ollama.

## Known quirks

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
