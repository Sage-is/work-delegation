---
name: delegate-edit
description: Delegate a file edit to a cheaper model via the delegate-edit wrapper; the orchestrating assistant writes the brief and reviews the diff. Use when generating long prose or commit messages, doing mechanical multi-file sweeps, or when the user says "delegate this" or "/delegate-edit". Say "/delegate-edit off" to disable delegation for the session.
---

# delegate-edit: hand file edits to a cheaper model

STATUS: MEASURED 2026-10-05. Three matrix runs in `results/matrix-2026-10-05*.md` scored fourteen lanes across six tasks, and `delegate-cost` measured the ledger and the transcripts. Routing and the 4000-char line below come from them. Install with `make install`.

## Kill switch

`DELEGATE=0` disables everything: the wrapper exits 3, and this skill must not delegate. Edit directly instead. The user saying "/delegate-edit off" means: set `DELEGATE=0` for the session's Bash calls and stop delegating.

The enforcement hook has its own, independent switch: `DELEGATE_ENFORCE=1` arms `delegate-hook.sh` (PreToolUse on Edit|Write), which denies 4000+ char direct generations to `.md`/`.py`/`.txt`/`.rst` and redirects them here. `DELEGATE_MIN_CHARS` moves the line. Below it, delegating costs the orchestrator more than typing: the ledger to 2026-10-05 shows -93% under 2000 chars of output, -23% at 2000-4000, +41% at 4000-8000. Test files (`tests/`, `test_*`, `*_test.py`) always pass: tests stay inline. The hook allows a direct edit when the ledger's last row is a stall or wedge under 30 minutes old, so a flaky backend never traps the session. Never require `DELEGATE=0` to bypass the hook; the two must stay separable.

## Ledger and doctor

Every run (success or failure) appends one JSON line to
`~/.local/state/delegate/log.jsonl`: timestamp, run_id, dir, model, backend,
lane, lanes_skipped, files, created, the full instruction, exit code, session,
retries, turns, tokens_in, tokens_out, cost_usd and cost_source ("provider"
when billed, "catalogue" for a list-price estimate), protocol, trace (one
line per tool call: turn, tool, path, ok or the error the model saw),
duration, diff stat, and diff_file, the run's patch saved under `diffs/`
beside the ledger (1 MB cap).
`make admin` serves the ledger as a web page: search, filter, star, tag, note,
the diff per run, re-run and revert commands, and stats per lane.
`DELEGATE_LOG=<path>` moves it; `DELEGATE_LOG=0` disables it. Failure records
are the routing evidence; do not disable the ledger to "clean up" output.

`delegate-edit --doctor` (or `make doctor`) verifies a machine: delegate-edit
and delegate-agent on PATH, GNU timeout present, skill installed, hook
registered, kill switch off, ledger writable, lock free. It lists which lanes
have keys that resolve and gateways that answer. It also reports brief
economy: the median brief size over the last 50 runs, how many exceeded 2000
chars, and how many files were created. A rising median means delegation has
drifted back into dictation.

`delegate-cost` (or `make cost SINCE=YYYY-MM-DD`) reads the Claude Code
transcripts and the ledger: where the orchestrator's input cost goes (prefix,
tool results by tool, attachments, cache re-reads), what large file reads
cost, and what delegation saved by output size. Measure with it before
building a new delegation verb. `make unmeasured` lists catalogue models no
matrix has scored yet.

## The wrapper

```bash
delegate-edit <dir> <lanes> "<brief>" [files...]
```

`<lanes>` is one model, or a comma list of direct lanes tried in order that
may end in one `opencode/` lane.
The first lane's prefix picks the backend; see Backends and lanes.

Location: `scripts/delegate-edit` beside this file; `make install` also puts it at
`~/bin/delegate-edit`.

The wrapper, whatever the backend:

- Seeds named-but-missing files as empty create targets (see Creating files)
- Refuses hardlinked targets (exit 4); edit those inline with the tmp-file +
  `cat >` method. Never bypass this guard
- Prints a diff stat at the end, on failure too when there is anything to show
- Appends one ledger row per run
- Sweeps `__pycache__` the delegate left from verifying its own edit
- Detects a silent no-op (exit 5) and a wedge (exit 9)

Per-run knobs: `DELEGATE_BUDGET` caps wall time for a direct or claude run
(default 480s; a whole-document rewrite on a slow lane needs the room).
`DELEGATE_MAX_TURNS` caps tool turns on those paths (default 20).
`DELEGATE_REQUEST_TIMEOUT` is the longest silence a direct lane may keep,
before its first byte or between two (default 120s). Answers stream, so a
long file that keeps arriving never trips it.
`DELEGATE_MAX_USD` is the hard spend cap for the claude backend (default
$0.50).

## Backends and lanes

The first lane's prefix picks the backend:

- `zen/`, `go/`, `nvidia/`, `openrouter/`, `ollama/`, `api/`: direct API
  through `delegate-agent`, a small Python typist. Each model gets the
  protocol opencode's catalogue (`~/.cache/opencode/models.json`) names for
  it: OpenAI's Responses API for `@ai-sdk/openai` models (GPT, Grok and Muse
  on Go, which refuse chat with `ModelProtocolUnsupported`), chat completions
  for the rest. Every request streams. The catalogue's list prices fill
  `cost_usd` when the gateway reports none. The named files' contents go
  with the brief, so the model starts editing. Keys resolve from each
  provider's env var, or from opencode's auth.json for `zen/`, `go/`, and
  `nvidia/`. `DELEGATE_API_KEY` plus `DELEGATE_BASE_URL` drive the generic
  `api/` prefix. `ollama/` needs no key and works offline. `zen/` is paid Zen
  models only, key required; Zen's free models answer only inside OpenCode,
  so they run as `opencode/` lanes.
- `claude/<model>`: runs `claude -p` with only the Read, Edit, and Write
  tools, `--permission-mode acceptEdits`, and the `DELEGATE_MAX_USD` spend
  cap. No Bash.
- Anything else (`opencode/…`, `opencode-go/…`): `opencode run`, the
  original path, with the permission policy and the machine-wide lock.

Lane fallback: a comma list of direct lanes is tried in order. A lane
hands off to the next one on any failure before its first write or edit.
After that first mutation the lane is committed: a later failure exits (1
for an API error, 6 for a timeout) with the diff left in place for review.
The list may end in one `opencode/` lane: when no direct lane was usable
and none began editing, the wrapper runs that lane through the opencode CLI.
Any other mix is a usage error; the claude and opencode backends own their
own loop and cannot hop.

## The tool jail

`delegate-agent` gives the model five tools: read, write, edit, ls, done.
There is no shell and no git. Every path must resolve under the project
directory. Hardlinked targets are refused, because editors replace inodes.
Edit requires its old text to match exactly once, so a vague match fails
instead of guessing. The run ends with done, or when the model stops
calling tools after touching a file.

## Creating files

delegate-edit creates files as well as edits them. Two ways, both supported:

- Name the new path as a trailing arg. The wrapper seeds it as an empty
  file (parent dirs included), and the preamble tells the delegate an
  empty named file is a new file to write in full. A seed the delegate
  never fills is removed again, on success and on failure alike.
- Or just say "create `<path>`" in the brief with no trailing arg, and
  let the delegate pick the path and write it.

New files are untracked, and `git diff` ignores untracked files, so a
created file would otherwise review as an empty diff. On success the
wrapper `git add -N`s every path that appeared during the run, so the
creation shows up in the reviewer's diff like any other change. The run
prints a `--- created ---` list and the exact `git reset --` undo.
`DELEGATE_NO_INDEX_ADD=1` skips the intent-to-add; review those files with
`cat` instead.

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 1 | backend failure |
| 2 | usage error, or no usable lane |
| 3 | delegation disabled via `DELEGATE=0` |
| 4 | hardlink guard refused a target |
| 5 | silent no-op: the model changed nothing |
| 6 | stall, timeout, or budget exhausted |
| 7 | lock busy (opencode path) |
| 8 | max turns reached |
| 9 | wedged: ran past its ceiling with no session and no diff |

Exits 1 and 6 print the diff stat: a failed run can still have landed an
edit, so read the diff before assuming nothing happened. On exit 6, do not
immediately retry; hop to the next lane, edit inline, or come back minutes
later. On exit 7, another opencode-path delegation holds the lock; inspect it
with `delegate-edit --unlock`, wait for it, or edit inline.

Exit 9 is evidence against the wrapper, not against the model. Do not
re-route away from a model that returned it. Report it instead.

## Concurrent runs

Direct lanes take no lock. One artifact per run, and independent artifacts
run at the same time, each naming its files. The opencode path keeps the
machine-wide lock: a second opencode-path delegation waits up to
`DELEGATE_LOCK_WAIT` (default 90s), then exits 7.

## When to delegate

Delegate long text when the spec is precise and the output will run to
about 4000 characters or more. Below that, the brief plus reading the diff
back costs more than typing it (ledger, 2026-10-05):

- Long prose generation (new docs pages, guides, changelogs)
- Prose rewrites with clear rules (house style passes) of a large file
- Mechanical Python/code sweeps (docstrings, renames, import moves) across
  enough code to clear the line

Do NOT delegate:

- Load-bearing logic (config, routers, migrations, tests, security code)
- Small edits and short texts, commit messages included: verification
  costs more than typing them
- Hardlinked files, or anything in bot-owned paths
- When `DELEGATE=0`

## Routing (matrix 2026-10-05)

Default lanes, for every tier:

```bash
delegate-edit <dir> go/gpt-6-luna,go/deepseek-v4.1-flash,opencode/big-pickle "<brief>" [files...]
```

Direct lanes run in order and stop at the first that answers. A list may end
in one `opencode/` lane: when every direct lane fails before editing, the
wrapper hands the brief to the opencode CLI. One list serves each tier:

- Go plan: `go/gpt-6-luna` answers over the Responses API, 6/6 on
  2026-10-05 (the four small tasks plus a 9-12 KB new file and an 11.6 KB
  rewrite), 5-56s, $0.0002-0.0031 a task at list price. It has no real-use
  record yet; the ledger will build one. `go/deepseek-v4.1-flash` is second:
  41/42 in real use from 2026-09-16, 8/10 across today's three runs (on t5
  it added a `## Contents` heading the brief ruled out). Go answers 400
  `MissingSessionID` without a stable `x-opencode-session`; the agent sends
  one per lane.
- Free, keyless: with no Go key the go/ lanes skip in milliseconds and
  `opencode/big-pickle` runs through the CLI with no key and no login, 4/4
  at 18-44s on 2026-09-13. Zen's free tier answers only inside OpenCode,
  which is why it is an `opencode/` lane. Free models may train on what you
  send, so never hand them client files. Offline and keyless:
  `ollama/<model>` before the tail, e.g.
  `ollama/qwen3.5:9b,opencode/big-pickle` (2/4 on 2026-09-04, a fallback).
- Zen API: opt in with your own list, e.g.
  `zen/deepseek-v4-flash,zen/minimax-m3,opencode/big-pickle`. Zen bills per
  request and auto-reloads $20, so no default spends it. Untested here: this
  machine has no Zen billing (401).

Also measured 2026-10-05 (`results/matrix-2026-10-05*.md`, one run per cell):
`go/glm-5.3-flash` 9/10 across the three runs, 7-18s on small tasks; `go/minimax-m3` 5/6; `go/hy4-preview` 6/6 but slow on long output
(144s, 10 turns); `go/grok-4.7` 4/4 at 25-130x the cost of gpt-6-luna;
`go/gpt-5.6-luna` 3/4; `go/mimo-v2.6-flash` 5/6, its t5 run looping on edits
to the 20-turn cap. `go/deepseek-v4-pro`, `go/qwen3.8-max`, `go/mimo-v2.6-pro`
4/4 on the small tasks only. Run `make unmeasured` for what no matrix has
scored, then `make matrix LANES=... TASKS=...`.

- `claude/haiku`: 5/6 at $0.03-0.07 a task. `claude/sonnet`: 5/6 at $0.10-0.14
  a task (its t5 page came in 1400 chars short). Use them when the cheap
  lanes botch the diff.

Small logic fixes stay inline.

## The brief format

One instruction string containing:

1. Target file(s) by path, and "in place" or "create new"
2. The exact change, enumerated; no "improve" verbs
3. Style rules spelled out (for prose: short sentences, active voice, no
   filler; for code: match surrounding idiom, change nothing else)
4. What must NOT change (facts, sections, other functions)

Precision means enumerating what must not change, not dictating every
property of what may. See Brief economy.

## Brief economy

The savings live in the asymmetry: short spec in, long artifact out. A
brief approaching the size of its expected output has stopped delegating;
the expensive model already did the typing, as a prose spec.

A brief holds three kinds of content, each with a rule:

1. **Invariants**: verbatim strings, paths, facts, what must not change.
   Always inline. This is the brief's real payload.
2. **Tooling and conventions** (framework props, house style): a compact
   inline list is acceptable; a pointer is smarter. Name the file that
   already holds the reference (a skill file, a repo doc, an existing page
   to match) and have the delegate read it first. Local reads are allowed,
   but only inside the project: a reference that lives elsewhere (a skill
   file, a style guide) gets copied into `.delegate/` in the project first,
   which the dotfile rule keeps out of git. One line instead of a kilobyte,
   and it stays current.
3. **Implementation dictation**: every element, property, and sentence.
   Never. Telling a weaker model every single step defeats the point of
   work delegation. Leave latitude; diff review catches taste cheaper than
   pre-specifying it.

Two numbers to watch. The brief stays under a third of the output it asks
for: the ledger's median run spent a 1500-char brief on 3000 chars of
output, and runs under that ratio lost tokens. And briefs stay under ~2000
chars; past that the wrapper warns, but it never refuses: the ledger shows
no relation between brief size and failure. One artifact per run;
splitting isolates retries.

## The loop

1. Write the brief. Run `delegate-edit`.
2. Read the FULL diff (`git -C <dir> diff`). Never trust the edit blind.
   Created files are in it too, via intent-to-add.
3. Wrong diff: re-brief and re-run, or revert and do it inline. Revert an
   edited file with `git checkout -- <file>`; revert a created file with
   `git -C <dir> reset -- <file> && rm <file>`, because `git checkout` on
   an intent-to-add path empties it instead of removing it. One retry max,
   then inline. If the cheap lanes botch it twice, escalate to
   `claude/sonnet` before going inline.
4. Report done only after the diff is reviewed.
