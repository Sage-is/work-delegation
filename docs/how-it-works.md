# How work-delegation works

## The wrapper

The whole toolkit runs through one entry point:

```sh
delegate-edit <dir> <lanes> "<brief>" [files...]
```

`<lanes>` is one model or a comma list. The first lane's prefix picks the backend. The wrapper attaches any listed files, seeds missing ones as empty create targets, and prints a diff stat of what changed.

Environment: `DELEGATE=0` disables delegation entirely (exit 3). `DELEGATE_LOG` moves the ledger; `DELEGATE_LOG=0` disables it. The default ledger is `~/.local/state/delegate/log.jsonl`, one JSON line per run. `DELEGATE_BUDGET` caps the wall time of a direct or claude run (default 480s). `DELEGATE_MAX_TURNS` caps tool turns on those paths (default 20). `DELEGATE_ENFORCE=1` arms the hook described below.

| Code | Meaning |
| ---- | ------- |
| 1 | backend failure |
| 2 | usage error, or no usable lane |
| 3 | delegation disabled via DELEGATE=0 |
| 4 | hardlink guard refused a target |
| 5 | silent no-op: the model changed nothing |
| 6 | stall, timeout, or budget exhausted |
| 7 | lock busy: another delegation held the opencode-path lock past the wait |
| 8 | max turns reached |
| 9 | wedged: the run outlived its own ceiling with no session and no diff |

Exits 1 and 6 print the diff stat: a failed run can still have landed an edit, so read it before assuming nothing happened. Exit 9 is evidence against the wrapper, not against the model. Do not re-route away from a model that returned it.

## Three backends

The wrapper dispatches on the first lane's prefix:

- **Direct API.** The `zen/`, `go/`, `nvidia/`, `openrouter/`, `ollama/`, and `api/` prefixes run through `delegate-agent`, a small Python typist that speaks one OpenAI-compatible request shape to every provider. Keys come from each provider's env var, or from opencode's auth.json for `zen/`, `go/`, and `nvidia/`. `DELEGATE_API_KEY` and `DELEGATE_BASE_URL` drive the generic `api/` prefix. On `zen/` lanes the User-Agent leads with the installed CLI's identity, `opencode/<version> delegate-agent/1 (work-delegation)`: the tier behind Zen's free models refuses every other client with a 429 that reads like a quota error, measured 2026-09-04. On `zen/` lanes the User-Agent leads with the installed CLI's identity, `opencode/<version> delegate-agent/1 (work-delegation)`: the tier behind Zen's free models refuses every other client with a 429 that reads like a quota error, measured 2026-09-04.
- **claude/.** A `claude/<model>` lane runs `claude -p` with only the Read, Edit, and Write tools, `--permission-mode acceptEdits`, and a hard spend cap (`DELEGATE_MAX_USD`, default $0.50). No Bash.
- **opencode.** Anything else (`opencode/…`, `opencode-go/…`) runs `opencode run`, the original path: `--auto --format json --pure`, with the permission policy and the lock described below.

## Lane fallback

A comma list is tried in order, direct lanes only. The other two backends own their own loop and cannot hop, so a comma list with a `claude/` or opencode lane is a usage error.

A lane hands off to the next one on any failure before its first write or edit. After that first mutation the lane is committed: a later failure exits (1 for an API error, 6 for a timeout) with the diff left in place for review. If every lane timed out, the exit is 6, the stall code, rather than 2.

## The tool jail

`delegate-agent` gives the model five tools: read, write, edit, ls, done. There is no shell. Every path must resolve under the project directory, and hardlinked targets are refused, because editors replace inodes. Edit requires its old text to match exactly once, so a vague match fails instead of guessing. The run ends with done, or when the model stops calling tools after touching a file.

## Capping the run

Each attempt runs under GNU `timeout -k`, so SIGKILL follows SIGTERM and a child that ignores SIGTERM still dies. On the opencode path each attempt is capped at `DELEGATE_TIMEOUT` (default 120s); a capped attempt is retried once after a 15s pause, and a second cap exits 6. The direct and claude paths instead get one run under `DELEGATE_BUDGET`. Output goes to a temp file rather than a command substitution. That second detail is the load-bearing one: `$(...)` holds the stdout pipe open until every descendant closes it, so a single surviving grandchild blocks the wrapper long after the cap has passed. Measured, a one-second cap took four seconds with one backgrounded grandchild and zero when redirected to a file.

`timeout` reports 124 when SIGTERM ended the child and 137 when the `-k` SIGKILL had to. Both mean capped. Testing only 124 sends every SIGTERM-ignoring stall down the generic failure path with no retry, which looks like a fix and is not one.

The fingerprint step reads from `/dev/null`, so nothing inside it can block on the wrapper's own stdin. Argless `shasum` did exactly that: with no seeded files it took no arguments, fell back to reading stdin, and waited there for an EOF that never came. That is the real shape of the long hangs: 2026-08-19 at 12 minutes, 2026-08-21 at 18.6 and 19.2 hours. Each logged `retries=0` and no session id, so none of them ever reached opencode, and none was a gateway stall.

## One delegation at a time

On the opencode path, the wrapper takes a machine-wide mkdir lock at `/tmp/delegate-<uid>.lock` before running. The direct and claude paths do not take it. A second opencode-path delegation waits up to `DELEGATE_LOCK_WAIT` seconds (default 90), then exits 7 with a clear message. Serialization is the no-regrets guard from the 2026-08-16 stall investigation: it removes the only local contention delegation itself can create, and it cost 15 lines.

A lock is stale when its holder process is gone, or when it is older than `DELEGATE_LOCK_MAX_AGE`, twice the capped attempt length plus slack, 320 seconds by default. That single test covers all three ways a lock outlives its owner: a dead holder, a holder that died before writing its pid at all, and a live holder that has wedged. `mkdir` stamps the directory mtime at creation, so the age is readable from the moment the lock exists. Nothing writes into the lock directory after acquire, because a heartbeat would refresh that mtime and disable the check.

Reclaiming renames the lock aside rather than deleting it in place. `mv` is atomic and the source vanishes, so of two waiters that both judge a lock stale exactly one wins. Deleting in place would let both win and run unserialized, which is the hazard the lock exists to prevent. The captured directory is tested again before removal, so a lock that was released and freshly re-acquired in the gap goes back untouched.

`delegate-edit --unlock` reports the holder, the age, and the verdict, and releases the lock when it is stale. `--unlock --force` releases it regardless. Neither signals a process. Freeing the mutex is a directory removal, while deciding that a process should die is a human's call with the report in hand.

## The permission layer

The opencode path exports `OPENCODE_PERMISSION`, a JSON policy for the delegated session. It denies git commands, `rm -rf`, nested opencode calls, web fetch, and web search. Other bash commands stay allowed so the model can inspect its work. One trap: the LAST matching rule wins, so the wildcard allow rule must come first and the deny rules after it, or the denies never fire. The other two backends need no policy: the tool jail has no shell at all, and the claude path runs with Read, Edit, and Write only.

## Plugins stay out

The opencode path passes `--pure`, which skips external opencode plugins. Measured on 2026-08-16: the antigravity auth plugin rewrites its state file on every non-pure bootstrap (5 of 5 runs), and every model family delegation routes to (free opencode, opencode-go, github-copilot) authenticates fine without it.

## The stall oracle

`skill/scripts/delegate-stall-verdict` is the single executable definition of a stall. It wraps a command, then classifies every opencode invocation that logged during it by the log's per-line `run=` id: OK when bootstrap reached a created session, STALL when it logged init but never created one, UNKNOWN when no init appeared. Count stalls per wrapper invocation (exit 6), never per run id.

## The hardlink guard

Editors write a new file and replace the inode, which silently severs a hardlinked pair; the other name keeps the old content. The wrapper checks the link count of every target and refuses any file with more than one link (exit 4). Edit those files by hand with an inode-preserving method.

## The brief format

A good brief leaves no room for taste.

1. Name the target files and say in-place edit or new file.
2. Enumerate the exact change, no improve verbs.
3. Spell out the style rules.
4. State what must not change.

## The review loop

The orchestrator reads the full diff before anything counts as done. On the opencode path a wrong diff gets one retry, re-instructing the same opencode session with `-s <sessionID>` so its context survives. On the other paths, re-brief and re-run. If the retry misses, revert the file and edit inline. Delegation earns its keep on bulk typing, not on back-and-forth.

## The optional hook

An opt-in PreToolUse hook for Claude Code denies large prose or Python generations with a message pointing to delegation. It is inert unless `DELEGATE_ENFORCE=1`. It allows a direct edit when the ledger shows a stall or wedge younger than 30 minutes, so a flaky backend never traps the session. The claude backend exports `DELEGATE_NESTED=1` so the hook does not bounce the delegate's own Write back to delegation. A transparent-rewrite variant, where the hook would call the delegate itself and report success, was rejected: the orchestrator must never believe it wrote text another model produced.
