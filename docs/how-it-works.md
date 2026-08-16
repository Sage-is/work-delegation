# How work-delegation works

## The wrapper

The whole toolkit runs through one entry point:

```sh
oc-edit <dir> <model> "<instruction>" [files...]
```

Underneath it runs:

```sh
opencode run --dir <dir> -m <model> --auto --format json --pure
```

It attaches any listed files to the message. It prints the opencode session id. It shows a diff stat of what changed.

| Code | Meaning |
| ---- | ------- |
| 1 | opencode failed |
| 2 | usage error |
| 3 | delegation disabled via OC_DELEGATE=0 |
| 4 | hardlink guard refused a target |
| 5 | silent no-op: the model changed nothing |
| 6 | stall: two timeouts in a row |
| 7 | lock busy: another delegation held the machine-wide lock past the wait |

## One delegation at a time

The wrapper takes a machine-wide mkdir lock at `/tmp/oc-edit-<uid>.lock` before running. A second delegation waits up to `OC_LOCK_WAIT` seconds (default 90), then exits 7 with a clear message. A lock whose holder process is dead is reclaimed automatically. Serialization is the no-regrets guard from the 2026-08-16 stall investigation: it removes the only local contention delegation itself can create, and it cost 15 lines.

## The permission layer

The wrapper exports `OPENCODE_PERMISSION`, a JSON policy for the delegated session. It denies git commands, `rm -rf`, nested opencode calls, web fetch, and web search. Other bash commands stay allowed so the model can inspect its work. One trap: the LAST matching rule wins, so the wildcard allow rule must come first and the deny rules after it, or the denies never fire.

## Plugins stay out

The wrapper passes `--pure`, which skips external opencode plugins. Measured on 2026-08-16: the antigravity auth plugin rewrites its state file on every non-pure bootstrap (5 of 5 runs), and every model family delegation routes to (free opencode, opencode-go, github-copilot) authenticates fine without it.

## The stall oracle

`skill/scripts/oc-stall-verdict` is the single executable definition of a stall. It wraps a command, then classifies every opencode invocation that logged during it by the log's per-line `run=` id: OK when bootstrap reached a created session, STALL when it logged init but never created one, UNKNOWN when no init appeared. Count stalls per wrapper invocation (exit 6), never per run id.

## The hardlink guard

Editors write a new file and replace the inode, which silently severs a hardlinked pair — the other name keeps the old content. The wrapper checks the link count of every target and refuses any file with more than one link (exit 4). Edit those files by hand with an inode-preserving method.

## The brief format

A good brief leaves no room for taste.

1. Name the target files and say in-place edit or new file.
2. Enumerate the exact change, no improve verbs.
3. Spell out the style rules.
4. State what must not change.

## The review loop

The orchestrator reads the full diff before anything counts as done. Wrong diff: one retry, re-instructing the same opencode session with `-s <sessionID>` so its context survives. If the retry misses, revert the file and edit inline. Delegation earns its keep on bulk typing, not on back-and-forth.

## The optional hook

An opt-in PreToolUse hook for Claude Code denies large prose or Python generations with a message pointing to delegation. It stays inert unless the session sets `OC_DELEGATE=1`. A transparent-rewrite variant, where the hook would call opencode itself and report success, was rejected: the orchestrator must never believe it wrote text another model produced.
