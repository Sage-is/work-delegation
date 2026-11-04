---
name: delegate-edit
description: Delegate a file edit to a cheaper model via the delegate-edit wrapper; the orchestrating assistant writes the brief and reviews the diff. Use when generating long prose or commit messages, doing mechanical multi-file sweeps, or when the user says "delegate this" or "/delegate-edit". Say "/delegate-edit off" to disable delegation for the session.
---

# delegate-edit: hand file edits to a cheaper model

STATUS: MEASURED 2026-10-05. Three matrix runs in `results/matrix-2026-10-05*.md` scored fourteen lanes across six tasks, and `delegate-cost` measured the ledger and the transcripts. Routing and the 4000-char line below come from them. Install with `make install`.

## Kill switch

`DELEGATE=0` disables everything: the wrapper exits 3, and this skill must not delegate. Edit directly instead. The user saying "/delegate-edit off" means: set `DELEGATE=0` for the session's Bash calls and stop delegating.

The enforcement hook has its own, independent switch: `DELEGATE_ENFORCE=1` arms `delegate-hook.sh` (PreToolUse on Edit|Write), which denies 4000+ char direct generations to `.md`/`.py`/`.txt`/`.rst` and redirects them here. `DELEGATE_MIN_CHARS` moves the line. Below it, delegating costs the orchestrator more than typing: the ledger to 2026-10-05 shows -93% under 2000 chars of output, -23% at 2000-4000, +41% at 4000-8000. Test files (`tests/`, `test_*`, `*_test.py`) always pass: tests stay inline. The hook allows a direct edit when the ledger's last row is a stall or wedge under 30 minutes old, so a flaky backend never traps the session. Never require `DELEGATE=0` to bypass the hook; the two must stay separable.

## The wrapper

```bash
delegate-edit <dir> <lanes> "<brief>" [files...]
```

`<lanes>` is one model, or a comma list of direct lanes tried in order that
may end in one `opencode/` lane.
The first lane's prefix picks the backend; see [Backends and lanes](references/backends-and-lanes.md).

Location: `scripts/delegate-edit` beside this file; `make install` also puts it at
`~/bin/delegate-edit`.

The wrapper, whatever the backend:

- Refuses hardlinked targets (exit 4); edit those inline with the tmp-file +
  `cat >` method. Never bypass this guard

Its other duties, the tool jail, creating files and concurrent runs: [references/wrapper-internals.md](references/wrapper-internals.md).

The ledger, `--doctor` and `delegate-cost`: [references/ledger-and-doctor.md](references/ledger-and-doctor.md).

Per-run knobs: `DELEGATE_BUDGET` caps wall time for a direct or claude run
(default 480s; a whole-document rewrite on a slow lane needs the room).
`DELEGATE_MAX_TURNS` caps tool turns on those paths (default 20).
`DELEGATE_REQUEST_TIMEOUT` is the longest silence a direct lane may keep,
before its first byte or between two (default 120s). Answers stream, so a
long file that keeps arriving never trips it.
`DELEGATE_MAX_USD` is the hard spend cap for the claude backend (default
$0.50).

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

Free models may train on what you send, so never hand them client files.

Small logic fixes stay inline.

Per-tier lanes and the measured matrix: [references/routing-matrix.md](references/routing-matrix.md).

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

The three kinds of brief content: [references/brief-economy.md](references/brief-economy.md).

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
