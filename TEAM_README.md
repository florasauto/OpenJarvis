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

| Model | Used by | Approximate size |
|---|---|---|
| `qwen3.5:4b` | simple chat, morning digest minimum, the recommended default from `jarvis init` | 2–3 GB |
| `qwen3.5:9b` | every other Floras agent; the ReAct and CodeAct agents need at least this size | 6 GB |
| `nomic-embed-text` | optional, improves ranking in deep research | under 1 GB |

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
| `scripts/floras-auto/start-interface.sh` | Builds the frontend once if needed, starts the server in the background, and prints or opens the address. |

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

Verified in the sandbox on 2026-11-02 with a stand-in engine that issues one
tool call per request: Python execution returned the right result, reads and
writes respected the fence, and the agent had no shell tool available. Real
code quality still needs a machine with Ollama.

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

The upstream guide mentions an `OPENJARVIS_MODEL` environment variable. It
does not exist in this version; use `jarvis ask -m <model>` or edit the config.

## Title and transport watch: a continuous managed agent

The monitor operative is a long-running agent that keeps state between
runs. Ours re-reads the overnight notes folder every 30 minutes, compares
against what it remembered from the previous run, and rewrites a one-page
status file: titles pending and for how long, transport pickups due, parts
promises not yet sourced, and what changed since last time. It differs from
the scheduled monitor in that it is managed by the agents subsystem, with
checkpoints, pause and resume, and a status page it owns.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/title-watch.toml` | Global config: engine, model, sqlite memory, and file access fenced to the notes and status folders. |
| `configs/floras-auto/templates/floras_title_watch.toml` | The managed-agent template: schedule, tools, standing instruction, and system prompt. |
| `scripts/floras-auto/setup-title-watch.sh` | Installs the config and template with the chosen folder paths written in, then creates the agent. |

Set it up, test one run, then schedule it:

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

The daemon runs in the foreground and must stay up for scheduled runs to
fire. The agent id is printed by the setup script and by
`uv run jarvis agents list`. The status page lands at
`~/FlorasAuto/status/title-watch.md`.

### Things to know about managed agents

- **Template strategy fields are stored but not applied.** The template's
  `memory_extraction`, `observation_compression`, `retrieval_strategy`,
  `task_decomposition`, `max_turns`, and `temperature` are saved with the
  agent but the executor does not pass them to the agent, which runs with
  its defaults (25 turns). The GUI shows the stored values.
- **`jarvis agents create` takes no instruction.** The setup script writes
  the folder paths into the template's standing instruction before
  installing it, which is how the agent learns where to look.
- **`jarvis agents logs` reports no history after `agents run`.** The run
  count and findings do show in `agents info` and `agents list`.
- **Managed agents auto-approve sensitive tools** when run from the CLI,
  the same as `jarvis ask`. This template includes no shell tool, and file
  access is fenced, so the exposure is limited to the two folders.
- Memory is shared with the other Floras agents on the same machine. Keep
  the memory store phrase "Title watch previous run" in the stored note,
  as the template instructs, so recall finds the right entry first.

Verified in the sandbox on 2026-11-02 with a stand-in engine that drives a
fixed four-step tick: the setup script installed the config and template
and created the agent; one run recalled memory, read the notes inside the
fence, stored a dated summary, and wrote the status page; a second run found
the first run's summary in memory. Real judgement about deadlines still
needs a machine with Ollama.

## Office assistant: multi-step help with tools

The orchestrator is the agent that picks tools itself, turn by turn. Ours is
set up as an office assistant: it looks things up in the indexed notes with
a cited search, does fee and margin arithmetic with a calculator, stores
reminders, and drafts emails or checklists as files in a shared folder. No
shell, no code execution, no web. The model runs on Ollama.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/office-assistant.toml` | Config with the orchestrator agent, six tools, and file access fenced to the notes and drafts folders. |
| `configs/floras-auto/personas/office/SOUL.md` | Tells the assistant when to use each tool and how to report. Installed to `~/.openjarvis/personas/floras-office/`. |
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

Verified in the sandbox on 2026-11-02 with a stand-in engine that drives a
three-step request: the setup script installed the config and persona and
indexed a sample notes file; one request ran memory search (found the
note), calculator (correct total), and file write (draft landed in the
drafts folder) across four turns. Real reasoning still needs a machine with
Ollama.

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
| `configs/floras-auto/intake-checker.toml` | Config with the `native_react` agent, five tools, and file access fenced to the notes and intake folders. |
| `configs/floras-auto/prompts/native_react_system_prompt.md` | The agent's system prompt: the checklist, the rules, and the ReAct format block. |
| `scripts/floras-auto/setup-intake-checker.sh` | Installs the config, installs the prompt with the intake path written in, and indexes the notes. |

Set it up and run one unit:

```bash
scripts/floras-auto/setup-intake-checker.sh ~/FlorasAuto/overnight-notes ~/FlorasAuto/intake
```

```bash
uv run jarvis ask "Intake checklist for the IAA SUV"
```

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

Verified in the sandbox on 2026-11-02 with a stand-in engine that speaks
the ReAct text format: the setup script installed the config and override
and indexed a sample notes file; one request ran three turns, a memory
search that found the note, a file write that landed in the intake folder,
and a final answer; the engine's system prompt contained the override, the
intake path, and the tool list. Real checklist judgement still needs a
machine with Ollama.

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
| `configs/floras-auto/deal-calculator.toml` | Config with the `native_openhands` agent, five tools, and file access fenced to the notes and deals folders. |
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

Verified in the sandbox on 2026-11-02 with a stand-in engine that speaks
the CodeAct format: the setup script installed the config and override;
one request ran three turns, a Python block that printed the fee, tax, and
landed cost, a file write that saved the deal sheet, and a final answer;
the engine's prompt contained the override, the fee schedule, the deals
path, and the tool list. Real code quality and arithmetic from the model
still need a machine with Ollama.

## Weekly auction recap: a scheduled operator

The operative agent is the persistent, scheduled agent, and the operators
subsystem runs it from a TOML manifest. Ours is a weekly recap: every
Friday at 5 PM it reads the week's notes, reads last week's recap, counts
units by source, titles resolved and pending, transport spend, and parts
promises, and rewrites a one-page recap with a JSON block of totals for the
next run to compare against.

Files:

| Path | Purpose |
|---|---|
| `configs/floras-auto/operators/floras_weekly_recap.toml` | The operator manifest: cron schedule, tools, and the five-phase protocol. |
| `configs/floras-auto/weekly-recap.toml` | Global config with the scheduler and operators enabled, sqlite memory, and file access fenced to the notes and recaps folders. |
| `scripts/floras-auto/setup-weekly-recap.sh` | Installs the config and the manifest with the folder paths written into its prompt. |

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
  from `[agent] max_turns` in the global config, which this config sets to 20.
- **Memory tools are not wired on this path.** `memory_store` and
  `memory_retrieve` are built without a backend for operator ticks, so the
  manifest uses `retrieval`, which is wired, plus `file_read` and
  `file_write`. Week-over-week comparison comes from reading last week's
  recap file, which is why the prompt starts there.
- **State persistence was not observed in the sandbox.** Two runs created
  a session row for the operator but saved no messages and no state. The
  recap-file approach makes the agent independent of that, but the team
  should confirm on a real run whether the restored-state feature works.
- The manifest's prompt describes the two folders by name; the setup script
  writes the real paths in when it installs the manifest.

Verified in the sandbox on 2026-11-02 with a stand-in engine that drives
file reads and writes: the setup script installed the config and the
manifest with the paths substituted; `operators list` showed the operator
with its Friday cron; one run read the notes file inside the fence and
wrote the recap to the recaps folder; activation created the scheduler task
with the correct next run, and the duplicate was found and cancelled. Real
counting and judgement still need a machine with Ollama.

## Known quirks

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
