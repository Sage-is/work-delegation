---
name: delegate-edit
description: Delegate a file edit to a cheaper model via the delegate-edit wrapper; the orchestrating assistant writes the brief and reviews the diff. Use when generating long prose or commit messages, doing mechanical multi-file sweeps, or when the user says "delegate this" or "/delegate-edit". Say "/delegate-edit off" to disable delegation for the session.
---

# delegate-edit: hand file edits to a cheaper model

STATUS: MEASURED 2026-09-04. The matrix in `results/matrix-2026-09-04.md` ran eight lanes across four tasks. Routing below comes from that run. Install with `make install`.

## Kill switch

`DELEGATE=0` disables everything: the wrapper exits 3, and this skill must not delegate. Edit directly instead. The user saying "/delegate-edit off" means: set `DELEGATE=0` for the session's Bash calls and stop delegating.

The enforcement hook has its own, independent switch: `DELEGATE_ENFORCE=1` arms `delegate-hook.sh` (PreToolUse on Edit|Write), which denies 2000+ char direct generations to `.md`/`.py`/`.txt`/`.rst` and redirects them here. The hook allows a direct edit when the ledger's last row is a stall or wedge under 30 minutes old, so a flaky backend never traps the session. Never require `DELEGATE=0` to bypass the hook; the two must stay separable.

## Ledger and doctor

Every run (success or failure) appends one JSON line to
`~/.local/state/delegate/log.jsonl`: timestamp, dir, model, backend, lane,
lanes_skipped, files, the full instruction, exit code, session, retries,
turns, tokens_in, tokens_out, cost_usd, duration, diff stat.
`DELEGATE_LOG=<path>` moves it; `DELEGATE_LOG=0` disables it. Failure records
are the routing evidence; do not disable the ledger to "clean up" output.

`delegate-edit --doctor` (or `make doctor`) verifies a machine: delegate-edit
and delegate-agent on PATH, GNU timeout present, skill installed, hook
registered, kill switch off, ledger writable, lock free. It lists which lanes
have keys that resolve and gateways that answer. It also reports brief
economy: the median brief size over the last 50 runs, how many exceeded 2000
chars, and how many files were created. A rising median means delegation has
drifted back into dictation.

## The wrapper

```bash
delegate-edit <dir> <lanes> "<brief>" [files...]
```

`<lanes>` is one model or a comma list tried in order (direct lanes only).
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
`DELEGATE_MAX_USD` is the hard spend cap for the claude backend (default
$0.50).

## Backends and lanes

The first lane's prefix picks the backend:

- `zen/`, `go/`, `nvidia/`, `openrouter/`, `ollama/`, `api/`: direct API
  through `delegate-agent`, a small Python typist that speaks one
  OpenAI-compatible request shape to every provider. Keys resolve from each
  provider's env var, or from opencode's auth.json for `zen/`, `go/`, and
  `nvidia/`. `DELEGATE_API_KEY` plus `DELEGATE_BASE_URL` drive the generic
  `api/` prefix. `ollama/` needs no key and works offline.
- `claude/<model>`: runs `claude -p` with only the Read, Edit, and Write
  tools, `--permission-mode acceptEdits`, and the `DELEGATE_MAX_USD` spend
  cap. No Bash.
- Anything else (`opencode/…`, `opencode-go/…`): `opencode run`, the
  original path, with the permission policy and the machine-wide lock.

Lane fallback: a comma list is tried in order, direct lanes only. A lane
hands off to the next one on any failure before its first write or edit.
After that first mutation the lane is committed: a later failure exits (1
for an API error, 6 for a timeout) with the diff left in place for review.
Comma lists on the other two backends are a usage error; they own their own
loop and cannot hop.

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

Delegate any long text when the spec is precise, commit messages included:

- Long prose generation (new docs pages, guides, changelogs)
- Commit messages
- Prose rewrites with clear rules (house style passes)
- Mechanical Python/code sweeps (docstrings, renames, import moves)

Do NOT delegate:

- Load-bearing logic (config, routers, migrations, tests, security code)
- Small edits: verification costs more than typing them
- Hardlinked files, or anything in bot-owned paths
- When `DELEGATE=0`

## Routing (matrix 2026-09-04)

Default lanes:

```bash
delegate-edit <dir> go/deepseek-v4-flash,go/kimi-k3,zen/big-pickle "<brief>" [files...]
```

The agent walks the list and stops at the first lane that answers. Measured
2026-09-04 (`results/matrix-2026-09-04.md`):

- `go/deepseek-v4-flash`: the go-to (Alexander, 2026-09-04). 3/4 correct at
  7-13s per task, the fastest lane; its one miss was a guide that came out
  shorter than asked, not a wrong edit.
- `go/kimi-k3`: 4/4 correct, 6-38s per task. Second lane, and the one to pick
  for long prose.
- `ollama/qwen3.5:9b`: the offline lane. No key, no network. 2/4 correct at
  17-72s with one 90s timeout; a fallback, not a first choice.
- `claude/sonnet`: 4/4 correct at about $0.10 a task. Use it when the cheap
  lanes botch the diff.
- `nvidia/nemotron-3.5-lightning-30b-a3b`: 3/4 correct, 10s on short tasks,
  timed out on the long guide. A free lane to add after the Go pair.
- `zen/big-pickle`: the free lane, third in the list, 4/4 correct at 6-14s
  once the client gate is passed. Zen's free models
  answer 429 `FreeUsageLimitError` to any client whose User-Agent does not
  start with `opencode/`, before quota is looked at; the agent sends
  `opencode/<installed version> delegate-agent/1 (work-delegation)` on zen/
  lanes for that reason. The real limit is per IP per UTC day and is shared
  with the TUI; a genuine 429 costs a second and the list hops on.
- `zen/claude-*` returns 401 without Zen billing.

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
   to match) and have the delegate read it first. Local reads are allowed.
   One line instead of a kilobyte, and it stays current.
3. **Implementation dictation**: every element, property, and sentence.
   Never. Telling a weaker model every single step defeats the point of
   work delegation. Leave latitude; diff review catches taste cheaper than
   pre-specifying it.

One number to watch: keep briefs under ~2000 chars. That is the enforce
hook's threshold in reverse; content that big gets delegated, briefs that
big get trimmed, split, or converted to pointers. Past 2000 the wrapper
warns, but it never refuses: the ledger shows no relation between brief
size and failure. One artifact per run; splitting isolates retries.

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
