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
| 8 | brief over the `OC_BRIEF_MAX` ceiling (default 3500 chars) |
| 9 | wedged: the run outlived its own ceiling with no session and no diff |

Exit 9 is evidence against the wrapper, not against the model. Do not re-route away from a model that returned it. Exit 6 is weaker evidence than it looks: a capped attempt can still have completed its edit before the cap fired, so read the diff before assuming nothing happened.

## Capping the run

Each attempt runs under GNU `timeout -k`, so SIGKILL follows SIGTERM and a child that ignores SIGTERM still dies. Output goes to a temp file rather than a command substitution. That second detail is the load-bearing one: `$(...)` holds the stdout pipe open until every descendant closes it, so a single surviving grandchild blocks the wrapper long after the cap has passed. Measured, a one-second cap took four seconds with one backgrounded grandchild and zero when redirected to a file.

`timeout` reports 124 when SIGTERM ended the child and 137 when the `-k` SIGKILL had to. Both mean capped. Testing only 124 sends every SIGTERM-ignoring stall down the generic failure path with no retry, which looks like a fix and is not one.

The fingerprint step reads from `/dev/null`, so nothing inside it can block on the wrapper's own stdin. Argless `shasum` did exactly that: with no seeded files it took no arguments, fell back to reading stdin, and waited there for an EOF that never came. That is the real shape of the long hangs — 2026-08-19 at 12 minutes, 2026-08-21 at 18.6 and 19.2 hours. Each logged `retries=0` and no session id, so none of them ever reached opencode, and none was a gateway stall.

## One delegation at a time

The wrapper takes a machine-wide mkdir lock at `/tmp/oc-edit-<uid>.lock` before running. A second delegation waits up to `OC_LOCK_WAIT` seconds (default 90), then exits 7 with a clear message. Serialization is the no-regrets guard from the 2026-08-16 stall investigation: it removes the only local contention delegation itself can create, and it cost 15 lines.

A lock is stale when its holder process is gone, or when it is older than `OC_LOCK_MAX_AGE` — twice the capped attempt length plus slack, 320 seconds by default. That single test covers all three ways a lock outlives its owner: a dead holder, a holder that died before writing its pid at all, and a live holder that has wedged. `mkdir` stamps the directory mtime at creation, so the age is readable from the moment the lock exists. Nothing writes into the lock directory after acquire, because a heartbeat would refresh that mtime and disable the check.

Reclaiming renames the lock aside rather than deleting it in place. `mv` is atomic and the source vanishes, so of two waiters that both judge a lock stale exactly one wins. Deleting in place would let both win and run unserialized, which is the hazard the lock exists to prevent. The captured directory is tested again before removal, so a lock that was released and freshly re-acquired in the gap goes back untouched.

`oc-edit --unlock` reports the holder, the age, and the verdict, and releases the lock when it is stale. `--unlock --force` releases it regardless. Neither signals a process. Freeing the mutex is a directory removal, while deciding that a process should die is a human's call with the report in hand.

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
