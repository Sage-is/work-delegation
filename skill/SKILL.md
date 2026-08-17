---
name: delegate-edit
description: Delegate a file edit to opencode's CLI via the oc-edit wrapper — the orchestrating assistant writes the brief and reviews the diff; a cheap/free model does the typing. Use when generating large prose, doing mechanical multi-file sweeps, or when the user says "delegate this", "use opencode", or "/delegate-edit". Say "/delegate-edit off" to disable delegation for the session.
---

# delegate-edit — hand file edits to opencode

STATUS: MEASURED. The 2026-08-15 matrix (8 runs, see RESULTS.md and `results/` in this repository) scored the free tier 4/4 correct at 7-15s/task; the paid tier also 4/4 but 5-7x slower (38-70s). Routing below
is validated. Install with `make install` (every harness).

## Kill switch

`OC_DELEGATE=0` disables everything: the wrapper exits 3, and this skill must not delegate — edit directly instead. The user saying "/delegate-edit off" means: set `OC_DELEGATE=0` for the session's Bash calls and stop delegating.

The enforcement hook has its own, independent switch: `OC_DELEGATE_ENFORCE=1` arms `oc-delegate-hook.sh` (PreToolUse on Edit|Write), which denies 2000+ char direct generations to `.md`/`.py`/`.txt`/`.rst` and redirects them here. Never require `OC_DELEGATE=0` to bypass the hook — the two must stay separable.

## Ledger and doctor

Every run (success or failure) appends one JSON line to
`~/.local/state/oc-edit/log.jsonl`: timestamp, dir, model, files, the full
instruction, exit code, session, retries, duration, diff stat. `OC_LOG=<path>`
moves it; `OC_LOG=0` disables it. Failure records (exit 4/5/6/7) are the
routing evidence — do not disable the ledger to "clean up" output.

`oc-edit --doctor` (or `make doctor`) verifies a machine: opencode and oc-edit
on PATH, skill installed, hook registered, kill switch off, ledger writable.

## The wrapper

```bash
oc-edit <dir> <model> "<instruction>" [files...]
```

Location: `scripts/oc-edit` beside this file; `make install` also puts it at
`~/bin/oc-edit`.

It runs `opencode run --dir <dir> -m <model> --auto --format json --pure`,
with:

- `OPENCODE_PERMISSION` denying `git*`, `rm -rf*`, `opencode*`, webfetch,
  websearch (rule order matters — LAST matching rule wins, so
  `"*": "allow"` first)
- A machine-wide mutex: one delegation at a time; a second waits up to
  `OC_LOCK_WAIT` (default 90s) then exits 7
- `--pure` — external plugins stay out of the bootstrap (measured
  2026-08-16: the auth plugin rewrote shared state on every non-pure run;
  all routed model families work without it)
- A hardlink guard (exit 4) — never bypass it; hardlinked files must be
  edited inline with the tmp-file + `cat >` method
- Seeding: missing targets are created as empty files (parent dirs too)
  so create-new briefs attach cleanly — no need to pre-touch files; a
  failed run removes any seed it left empty, and the ledger records
  seeded paths per run
- Silent no-op detection (exit 5), stall fail-fast (exit 6 after two capped
  attempts), and a diff stat on success

## Stalls (exit 6) and busy lock (exit 7)

The stall signature: the run logs `init` but never `created id=ses_` — `skill/scripts/oc-stall-verdict <command...>` is the executable check. Stalls arrive in short self-clearing windows and correlate with large instruction payloads (docs/stall-investigation.md). On exit 6: do NOT immediately retry — edit inline, or come back minutes later. On exit 7: another delegation is running; wait for it or edit inline. Never kill opencode processes by name; `make install` refuses wrappers that try.

## When to delegate

Delegate when the *generated output* is large and the spec is precise:

- Long prose generation (new docs pages, guides, changelogs)
- Prose rewrites with clear rules (house style passes)
- Mechanical Python/code sweeps (docstrings, renames, import moves)

Do NOT delegate:

- Load-bearing logic (config, routers, migrations, tests, security code)
- Small edits — verification costs more than typing them
- Hardlinked files, or anything in bot-owned paths
- When `OC_DELEGATE=0`

## Routing (validated 2026-08-15)

| Task class | First try | Escalate to |
| --- | --- | --- |
| Prose gen / rewrite | `opencode/deepseek-v4-flash-free` | `opencode-go/kimi-k3` |
| Mechanical code sweep | `opencode/deepseek-v4-flash-free` | `opencode-go/kimi-k3` |
| Small logic fix | do it inline | — |

The free tier matched the paid tier on quality across all four task classes and ran 5-7x faster. Escalation to kimi-k3 is for retries only.

## The brief format

One instruction string containing:

1. Target file(s) by path, and "in place" or "create new"
2. The exact change, enumerated — no "improve" verbs
3. Style rules spelled out (for prose: short sentences, active voice, no
   filler; for code: match surrounding idiom, change nothing else)
4. What must NOT change (facts, sections, other functions)

Precision means enumerating what must not change — not dictating every
property of what may. See Brief economy.

## Brief economy

The savings live in the asymmetry: short spec in, long artifact out. A
brief approaching the size of its expected output has stopped delegating —
the expensive model already did the typing, as a prose spec.

A brief holds three kinds of content, each with a rule:

1. **Invariants** — verbatim strings, paths, facts, what must not change.
   Always inline. This is the brief's real payload.
2. **Tooling and conventions** (framework props, house style) — a compact
   inline list is acceptable; a pointer is smarter. Name the file that
   already holds the reference (a skill file, a repo doc, an existing page
   to match) and have the delegate read it first — local reads are
   allowed. One line instead of a kilobyte, and it stays current.
3. **Implementation dictation** — every element, property, and sentence —
   never. Telling a weaker model every single step defeats the point of
   work delegation. Leave latitude; diff review catches taste cheaper than
   pre-specifying it.

Hard numbers:

- Target under ~2000 chars — the enforce hook's threshold in reverse:
  content that big gets delegated, briefs that big get trimmed, split, or
  converted to pointers.
- One artifact per run; splitting isolates retries.
- Evidence (ledger 2026-08-16): four 4-7 KB dictation briefs all stalled
  (exit 6, ~255s each plus retry); a 60-char brief ran in 6s.
  docs/stall-investigation.md: every clean run used a one-line brief; both
  live stalls carried multi-KB briefs.

## The loop

1. Write the brief. Run `oc-edit`.
2. Read the FULL diff (`git -C <dir> diff`). Never trust the edit blind.
3. Wrong diff → either re-instruct in-session
   (`opencode run -s <sessionID> "fix: ..." --dir <dir> -m <model> --auto`)
   or `git checkout -- <file>` and do it inline. One retry max, then inline.
4. Report done only after the diff is reviewed.
