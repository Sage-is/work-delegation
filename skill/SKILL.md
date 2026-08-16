---
name: delegate-edit
description: Delegate a file edit to opencode's CLI via the oc-edit wrapper — the orchestrating assistant writes the brief and reviews the diff; a cheap/free model does the typing. Use when generating large prose, doing mechanical multi-file sweeps, or when the user says "delegate this", "use opencode", or "/delegate-edit". Say "/delegate-edit off" to disable delegation for the session.
---

# delegate-edit — hand file edits to opencode

STATUS: MEASURED. The 2026-08-15 matrix (8 runs, see RESULTS.md and
`results/` in this repository) scored the free tier 4/4 correct at
7-15s/task; the paid tier also 4/4 but 5-7x slower (38-70s). Routing below
is validated. Install with `make install` (every harness).

## Kill switch

`OC_DELEGATE=0` disables everything: the wrapper exits 3, the hook passes
through, and this skill must not delegate — edit directly instead. The user
saying "/delegate-edit off" means: set `OC_DELEGATE=0` for the session's
Bash calls and stop delegating.

## The wrapper

```bash
oc-edit <dir> <model> "<instruction>" [files...]
```

Location: `scripts/oc-edit` beside this file; `make install` also puts it at
`~/bin/oc-edit`.
It runs `opencode run --dir <dir> -m <model> --auto --format json`, with:

- `OPENCODE_PERMISSION` denying `git*`, `rm -rf*`, webfetch, websearch
  (rule order matters — LAST matching rule wins, so `"*": "allow"` first)
- A hardlink guard (exit 4) — never bypass it; hardlinked files must be
  edited inline with the tmp-file + `cat >` method
- Silent no-op detection (exit 5) and a diff stat on success

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

The free tier matched the paid tier on quality across all four task classes
and ran 5-7x faster. Escalation to kimi-k3 is for retries only.

## The brief format

One instruction string containing:

1. Target file(s) by path, and "in place" or "create new"
2. The exact change, enumerated — no "improve" verbs
3. Style rules spelled out (for prose: short sentences, active voice, no
   filler; for code: match surrounding idiom, change nothing else)
4. What must NOT change (facts, sections, other functions)

## The loop

1. Write the brief. Run `oc-edit`.
2. Read the FULL diff (`git -C <dir> diff`). Never trust the edit blind.
3. Wrong diff → either re-instruct in-session
   (`opencode run -s <sessionID> "fix: ..." --dir <dir> -m <model> --auto`)
   or `git checkout -- <file>` and do it inline. One retry max, then inline.
4. Report done only after the diff is reviewed.
