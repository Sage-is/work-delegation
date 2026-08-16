# Fix opencode delegation stalls — measure the cause, then pick the cheapest fix

## ELI5 summary

Delegated edits keep freezing. A frozen run dies during startup, before it
creates a session or asks any model for anything — the logs are unambiguous
about that. What is *not* settled is why, and there are three live suspects:
other opencode processes fighting over a lock, the shared account being rate
limited by teammates, or the third-party auth plugin hanging on startup. I
have twice been confident and twice been wrong, so this plan measures before
it builds: one instrumented capture of a live freeze tells us which suspect it
is, and only then do we write the fix that suspect calls for. It also retires
a mistake from the last session — the "orphan reaper" I wrote is wrong and
unsafe, and it already cost Alexander a running TUI session.

## Context

Delegation shipped as `~/Documents/Projects/GitHub/work-delegation`. Prose
delegation worked twice (README.md, marketing/copy.md), then runs began
stalling for 90-240s each. Four files were reverted to inline writing and are
now deleted at HEAD (commit 498bf0a), awaiting a working delegation path.

### What the evidence establishes

1. **Stalls happen during bootstrap, before any model request.** Every stalled
   run in `~/.local/share/opencode/log/opencode.log` ends at `message=init` or
   the 60s-later `message=cleanup`, with **zero** `created id=ses_`, zero
   `agent=title`, zero `agent=build`. In healthy runs that step takes
   **0.61-0.70s** (measured across six runs).
   **Correction to my earlier claim:** this proves the stall precedes the
   *model* call, not that it precedes *all* network activity. Bootstrap also
   loads plugins, refreshes OAuth tokens, and resolves providers — all of
   which can block on the network. My "local, not gateway" conclusion was
   overstated, which is what makes Alexander's shared-usage hypothesis live.
2. **opencode has an unbounded local lock wait.** The binary contains
   `waiting for lock: ${n.key}` inside a retry/await loop, alongside
   file-lock primitives (`mkdir`/`stat`/`utimes`/`rm`, sha1-hashed keys,
   `lockfile` ×269). SQLite is configured `PRAGMA busy_timeout = 5000` and
   `journal_mode = WAL`, so a database lock would error after 5s rather than
   hang — the unbounded hang has to be the application lock.
3. **Killing other opencode processes cleared a stall instantly.** A brief
   that had stalled twice ran immediately after two bare `opencode` processes
   were killed. Single observation, uncontrolled.
4. **opencode spawns detached children** (`detached:!0` in the binary). This
   is why `timeout` does not reap them: GNU timeout kills its own process
   group, and a detached child leaves that group.
5. **Stalls hit two different project directories** (sandbox and
   work-delegation), so contention is global, not per-project.
6. Bootstrap is ~0.65s in-process; a trivial round trip is ~5s wall; a real
   200-word generation is 8-15s. **Stalls cost 90-240s.** Stall rate dominates
   every other efficiency metric by two orders of magnitude.
7. **A third-party auth plugin runs on every bootstrap and mutates shared
   state.** `opencode.jsonc` loads `opencode-antigravity-auth@beta`. Its state
   file `~/.config/opencode/antigravity-accounts.json` was rewritten at
   **10:14 today**, inside the stall window, even though its account's
   `lastUsed` is January. It holds **one** account with a `refreshToken` and a
   `rateLimitResetTimes` map — a rotation design with nowhere to rotate to.
   Two concurrent bootstraps both writing this file is a real contention
   point, and a token refresh here is a network call on the critical path.
8. **Credentials that force refresh at startup.** `auth.json` holds
   `github-copilot` with `expires=0` and `google` expired since
   **2026-01-21**. `opencode-go` is a bare API key with no expiry, and there
   is **no** entry for the free `opencode` tier at all.
9. **Both free and paid models stalled** (`deepseek-v4-flash-free`,
   `big-pickle`, `kimi-k3`, `glm-5.3`, `deepseek-v4-flash`). Pure free-tier
   quota exhaustion would not stall paid models, so if usage limiting is the
   cause it acts at the account or bootstrap level, not per-tier.

### Correction: the reaper is wrong and unsafe — do not ship it

The uncommitted `reap_orphans` in `skill/scripts/oc-edit` kills bare
`opencode` processes whose parent is PID 1. Two problems:

- **It would not have worked.** The two processes whose death unblocked the
  stall had real parents (PIDs 96106 and 44658, both terminal shells), not
  PID 1. A PPID==1 filter matches neither.
- **Killing by process name is dangerous.** PID 33515 was started at 09:25:46
  in `/Users/somma/bin/TodoScope` from a VS Code terminal — almost certainly
  Alexander's own interactive TUI session, which I killed at ~10:12. A new
  `opencode` appeared at 10:14:01, consistent with a restart. **A fix that can
  kill the user's interactive session is disqualified regardless of how well
  it scores.**

### Poka-yoke pass, 2026-08-16

A mistake-proofing audit of this plan (4 lens finders, 10 findings confirmed
under adversarial verification, 0 refuted) produced four devices:

- **A — applied.** Reaper retired everywhere: wrapper reverted to HEAD,
  installed copies removed via `make uninstall`, reinstall deferred to the
  gated `make install` in Phase 3.
- **B — applied.** Kill hard-gate made mechanical: `guard-no-name-kills` in
  the Makefile blocks installing any wrapper containing
  `pgrep`/`pkill`/`killall`; test kills go through a PID-ledger `kill-mine`
  that refuses unledgered PIDs; the preflight STOPs instead of killing.
- **C — applied.** The stall oracle is one script,
  `skill/scripts/oc-stall-verdict`, not prose re-derived per test.
- **D — declined (Alexander).** The exit-124 blind retry stays in oc-edit
  despite the finding that under H1 it retries into the surviving child's
  lock and doubles worst-case stall to ~255s. Stall counts are therefore per
  wrapper invocation, never per run-ID. Revisit if T0 confirms H1.

### Three live hypotheses — all fit the evidence so far

| # | Mechanism | Supported by | Fix if true |
| --- | --- | --- | --- |
| **H1 Local contention** | Concurrent or leftover instances block on opencode's file lock during bootstrap | (2)(3)(4)(5)(7) | Serialize delegation; never spawn a second instance |
| **H2 Shared usage limiting** | The account behind `opencode-go`/free tier is throttled by others in Alexander's network, and bootstrap blocks on the throttled call | (1 corrected)(8)(9), Alexander's report | Backoff plus fail-fast; schedule around peak team usage; separate credential |
| **H3 Auth plugin** | `opencode-antigravity-auth` hangs on token refresh or on its own state file during bootstrap | (7)(8) | Drop or pin the plugin; run delegation with `--pure` |

These are **not mutually exclusive** — H1 and H3 compound (two bootstraps
fighting over one plugin state file), and H2 would make any of them worse.
The single "kill processes, stall cleared" observation is one data point and
is equally consistent with a rate-limit window simply expiring, so it must not
be treated as proof of H1.

## Phase 0 — Relocate this work to its own repo

All remaining work happens in `~/Documents/Projects/GitHub/work-delegation`,
not in the AI-UI session. This plan lives at
`~/.claude/plans/explore-the-idea-of-noble-wadler.md`; **step one in the new
session is to copy it to `docs/stall-investigation.md` in that repo** so it is
tracked with the code it describes.

State a fresh session must know, since none of it is inferable from the repo:

- **Done 2026-08-16 (poka-yoke pass):** the uncommitted `reap_orphans` was
  reverted (`git checkout -- skill/scripts/oc-edit`) and every installed copy
  was removed (`make uninstall` — the reaper had already been deployed to
  `~/.claude/skills/delegate-edit/scripts/oc-edit` by an earlier
  `make install`). The tree is clean at `5e7bff9` plus `docs/`. Delegation
  entry points stay uninstalled until the gated `make install` in Phase 3.
- **Sandbox fixtures are gone.** The old test repo lived in a session-scoped
  scratchpad. Recreate a throwaway git repo with a couple of small files
  (`calc.py`, `notes.md`, `greet.sh`) as the test target — never run these
  tests against the real repo.
- **Wrapper contract:** `oc-edit <dir> <model> "<instruction>" [files...]`;
  exit codes 1 opencode failure, 2 usage, 3 disabled via `OC_DELEGATE=0`,
  4 hardlink refusal, 5 silent no-op, 6 stall.
- **Known-good models measured 2026-08-16:** free `opencode/big-pickle` and
  `opencode/deepseek-v4-flash-free` at 9s for a 200-word generation; all seven
  free models healthy; 16 of 19 `opencode-go/*` healthy.
- **Log oracle:** `~/.local/share/opencode/log/opencode.log`. A stall reaches
  `message=init` and never reaches `created id=ses_`. The executable
  definition is `skill/scripts/oc-stall-verdict` (groups log lines by their
  per-invocation `run=` ID); every test and stall count goes through it, not
  through ad-hoc greps.

## Phase 1 — Prove the mechanism

Run in the scratchpad sandbox repo, one variable at a time, with
`~/.local/share/opencode/log/opencode.log` as the oracle (a stall = reaches
`init`, never reaches `created id=ses_`).

**[MANUALLY] Alexander closes his opencode TUI before Phase 1 begins**, so the
instance count is known. I confirm zero live `opencode` processes before the
first test and never kill a process I did not spawn. **[MANUALLY] He reopens
it before the coexistence check at the end of Phase 2.**

**T0 — Instrument first; this is the decisive measurement.** On the next
stall, capture what the process is actually waiting on:
`lsof -nP -i -p <pid>` (open and pending sockets), `sample <pid> 5` (where it
is blocked in code), and re-run under `--print-logs --log-level DEBUG` to
surface `waiting for lock:` and any HTTP retry or 429 — neither appears at
INFO. Sockets pending to an API endpoint with no lock line points at H2/H3; a
`waiting for lock:` line with no pending sockets points at H1. Write the
verdict down before touching the wrapper.

- **T1 — Leftover causation (H1).** Baseline: one trivial edit, clean machine,
  record wall time. Then start a long `opencode run` as
  `opencode run ... & CLI_PID=$!` and capture
  `CHILD_PID=$(pgrep -P "$CLI_PID")` **before** any signal — once the CLI
  dies, the child reparents to launchd and only a name-based search could
  find it, which is forbidden. Ledger both PIDs, SIGTERM only the CLI,
  confirm the detached child survives (`ps -eo pid,ppid,command`). Repeat the
  trivial edit. Then kill `$CHILD_PID` via kill-mine (ledgered PIDs only) and
  repeat again.
  *Discriminates:* does a leftover instance alone cause the stall?
- **T2 — Clean concurrency (H1).** With no leftovers, launch 2, then 3, then 4
  concurrent `opencode run` calls that all complete naturally.
  *Discriminates:* is plain concurrency sufficient to stall, and is there a
  ceiling (e.g. everything past N stalls)?
- **T4 — Shared usage limiting (H2).** Three probes:
  (a) **[MANUALLY] Alexander confirms** whether the `opencode-go` API key or
  the opencode account is shared with teammates, and who was active during the
  stall windows (07:52-08:20 and 09:45-10:15 today);
  (b) 10 identical trivial calls spaced 30s apart, charting stalls against
  wall-clock — quota effects cluster in windows and clear on a boundary, while
  contention effects track instance count instead;
  (c) stall rate on `opencode-go/*` compared with `github-copilot/*` and
  `google/*`, which authenticate through entirely different credentials. If
  only the opencode-family calls stall, H2 rises sharply.
- **T3 — Auth plugin bypass (H3).** Run the identical brief with and without
  `--pure` ("run without external plugins"), five each, alternating. Watch
  `antigravity-accounts.json` mtime across runs to confirm whether every
  bootstrap rewrites it.
  *Discriminates:* is the plugin on the stall path? Note whether free
  `opencode/*` models still work under `--pure`, since they have no
  `auth.json` entry and may depend on it.

T0 plus one decisive result from T1, T2, or T4 is enough to proceed; T3
refines the remedy. If T0 says network, the fix in Phase 2 changes from
"serialize" to "backoff, fail fast, and stop retrying into a limit" — so
**do not build any wrapper changes before T0 returns.**

## Phase 1 verdict — 2026-08-16, battery run, stall DID NOT REPRODUCE

Conditions: Alexander's TUI closed, teammates reported off opencode (sharing
status still unknown), preflight clean, sandbox fixture repo, every run
through `oc-stall-verdict`, `t-run` auto-capture armed throughout.

Roughly 35 runs, **zero stalls**:

- Baseline trivial edit: 12.7s, OK, zero leftovers.
- **T1 (twice): opencode 1.18.5 is a single process.** No child appeared
  under the CLI at any second of a 12s run (`pgrep -P` census each second),
  and SIGTERM left zero survivors. The "detached child survives timeout"
  mechanism is impossible in this version — the orphan variant of H1 is
  **refuted**. The morning's two "leftover" processes were interactive TUIs.
- **T2: clean concurrency is harmless.** 2-, 3-, and 4-way concurrent
  bootstraps all OK in 8.7-9.9s, all files created, zero leftovers.
- **T3: the auth plugin writes on every bootstrap.**
  `antigravity-accounts.json` mtime changed on 5/5 plain runs and 0/5
  `--pure` runs; wall times identical (7-9s); free-tier auth works under
  `--pure`. So do `opencode-go/kimi-k3` (17s) and
  `github-copilot/claude-haiku-4.5` (9s) — `--pure` is safe for every
  family delegation routes to.
- **T4(b): 10 spaced calls over 5 minutes, 10/10 OK at 8-10s.**
- **T4(c):** paid opencode-go OK, github-copilot OK; the google family
  fails fast and loud (expired OAuth / non-edit preview model), never hangs.

None of H1/H2/H3 is confirmed; H1's orphan mechanism is refuted outright.
The morning stalls did not recur under controlled single-session conditions.
Per plan: no-regrets fixes only — serialize delegation (mkdir mutex), add
`--pure`, keep `t-run` instrumentation armed.

### Live reproduction, same afternoon — the battery had a blind spot

Two real stalls hit during Phase 3's production re-delegation:

- **12:48:45** `run=8b15f743`, real repo, `--pure`, ~4.3 KB brief: configs
  loaded in ms, `message=init`, then nothing except the +60s `cleanup` line.
  Zero sessions. The wrapper's second attempt (12:50:52) logged **nothing at
  all** — blocked before its logger came up (open anomaly, recorded).
  Wrapper exited 6 after 2×120s with a clear message. No leftovers.
- **12:54** tiny probe, same repo: OK in 5s (`init`→`created` is a 93 ms
  step in healthy runs — the stall lives inside that step).
- **12:55** the identical 4.3 KB brief: OK in 37s. Window closed.
- **~12:58** second stall, ~2.4 KB brief, same signature, wrapper exit 6.
- **13:02-13:04** same and smaller briefs: OK, OK, OK.

What this changes: **every clean battery run used a one-line brief.** Both
stalls carried multi-KB briefs; the morning field note ("trivial probes in
seconds, substantive generations stall, free and paid alike") showed the
same pattern. Yesterday's dismissal of "gateway weather" overcorrected.
Current best mechanism statement: **transient stall windows, minutes long
and self-clearing, at the bootstrap step between `init` and session
creation; correlated with instruction payload size; independent of model
tier, plugin (`--pure` active), live-instance contention (mutex held,
single instance), and directory.** Local stale-lock storage remains
unproven (no lock artifacts found on disk). SQLite is exonerated
(`busy_timeout=5000` errors loudly; this hangs silently).

Falsifiable prediction for the next window: a tiny probe interleaved with a
large brief succeeds while the large brief stalls. The `t-run` watchdog now
samples the whole process tree at 45s, so the next in-window run captures
`lsof`/`sample` evidence automatically. Until then the shipped failure mode
is the fix: capped attempts, exit 6, one clear line, fall back inline or
wait minutes — never retry immediately into the window. Both live stalls
were handled exactly that way, and the work completed on later retries.

## Phase 2 — Build the fix the mechanism actually calls for

Common workload for whichever arms run: **10 sequential identical small edits**
plus **one 3-way concurrent burst**, same model (`opencode/big-pickle`, fastest
measured today), same sandbox repo. Metrics: **stall count** (primary; counted per wrapper
invocation — exit 6 — never per log run-ID, because the retained exit-124
retry can emit two stalled run-IDs for one invocation), mean
and p95 wall time, leftover processes after the arm, diff correctness, and
lines of wrapper code.

**If T0 says local contention (H1):**

| Arm | Design | Cost to build |
| --- | --- | --- |
| **A. Serialize only** | Wrapper mutex via `shlock`/mkdir lock (no `flock` on macOS); one delegation at a time; timeout kills the client only | ~15 lines |
| **B. Serialize + own-child cleanup** | Arm A, plus record the PID opencode spawns — the child PID from a pre-kill `pgrep -P "$CLI_PID"` capture, not `$!` — and kill **only that process tree** on timeout via a `ps -o pid=,ppid=` walk, never a name-based sweep | ~30 lines |

Prefer A if it scores zero stalls; B only buys cleanup that A did not need.

**If T0 says network/limiting (H2):** serialization is the wrong tool and
retrying makes it worse. Build instead:

- Fail fast on a stalled bootstrap — no blind retry into a limit; surface
  "account throttled, try later" and fall back to inline editing immediately.
- Exponential backoff with a cap, and a stall-rate log so the pattern is
  visible over days rather than rediscovered each session.
- Route around it: prefer `github-copilot/*` or `google/*` models, which use
  separate credentials, when opencode-family calls are stalling.
- **[MANUALLY]** Alexander decides whether to get delegation its own
  credential rather than sharing the team's.

**If T0 says the auth plugin (H3):** run delegation with `--pure`, or pin the
plugin off in a delegation-specific config, provided free-tier models still
authenticate. Cheapest fix of the three if it holds.

### Contingency: Arm C (persistent server), only if the chosen fix fails

One `opencode serve --port N` owns storage; every call becomes
`opencode run --attach http://127.0.0.1:N --dir <dir>`, with the mutex kept.
Two blocking prerequisites, because `OPENCODE_PERMISSION` is read by the
*server* at config load rather than per request:

1. A call through `--attach` must still be denied `git` — prove it by asking
   an attached session to run `git status` and confirming refusal. If the
   policy does not survive attach, **Arm C is disqualified on security
   grounds** and delegation stays serialized-and-slow instead.
2. `--attach` must honor `-m`, `--auto`, `--format json`, and `-f`.

## My assessment before the data

**I no longer have a confident favourite, and that is the honest answer.**
Yesterday I was confident about "gateway weather" and wrong; this morning I
was confident about "local locks" on a single uncontrolled observation. The
shared-usage hypothesis fits the corrected evidence just as well. T0 exists
precisely so the next answer comes from a measurement rather than a story.

Ranked by what the evidence currently supports:

- **H1 (contention)** — best supported for *cheapness*: an unbounded
  `waiting for lock` primitive is in the binary, opencode spawns detached
  children, and delegation has no reason to run two instances at once. Even if
  H1 is not the cause, serializing costs ~15 lines and removes a real hazard.
- **H2 (shared limiting)** — best supported by *timing*: stalls arrived in
  clusters after heavy use and cleared without any code change. Its strongest
  counter-evidence is that **paid `opencode-go` models stalled too**, so it
  requires limiting at the account or bootstrap layer, not the free tier alone.
  T4(a) settles it faster than any test I can run alone.
- **H3 (auth plugin)** — the cheapest to test and cheapest to fix. Its state
  file was rewritten at 10:14, mid-stall-window, on a bootstrap path that also
  refreshes two expired credentials. One `--pure` A/B answers it.

On efficiency, whichever mechanism wins: stalls cost 90-240s while bootstrap
costs ~0.65s, so **stall elimination outranks latency tuning by roughly 100x**.
That is why the persistent-server design stays a contingency — its 1-3s saving
per call is real but irrelevant next to a single avoided stall.

## Phase 3 — Implement and finish the job

1. Implement the fix the mechanism calls for in `skill/scripts/oc-edit`
   (`reap_orphans` was already reverted and uninstalled in the poka-yoke
   pass). Then `make install` — it must pass the Makefile's
   `guard-no-name-kills` gate — and verify
   `! grep -rq reap_orphans ~/.claude/skills/delegate-edit ~/bin/oc-edit`.
2. Record the mechanism, the numbers, and the disqualified reaper in
   `RESULTS.md` field notes, replacing the incorrect "gateway weather" entry
   and the overstated "local, not gateway" claim.
3. Update `skill/SKILL.md` with the stall signature (`init` with no
   `created id=ses_`), the one-delegation-at-a-time rule, and — if H2 holds —
   the instruction to fall back to inline editing rather than retry into a
   limit.
4. Re-delegate the four deleted files — `docs/how-it-works.md`,
   `marketing/landing.html`, `harness/codex/delegate-edit.md`,
   `harness/opencode/delegate-edit.md` — one at a time through the fixed
   wrapper, reviewing each diff.
5. [MANUALLY] Alexander commits.

## Verification

- Phase 1 produces a written mechanism statement backed by captured evidence
  (`lsof`/`sample`/DEBUG log lines), not inference. If T0 is inconclusive, say
  so and keep delegation off rather than shipping a guess.
- If the cause is H1 or H3: the fix completes **10/10 sequential runs with
  zero stalls** and leaves **zero** leftover opencode processes
  (`ps -eo pid,ppid,command`).
- If the cause is H2, zero stalls may not be achievable, and the bar changes:
  **no run hangs longer than the timeout, every throttle is reported in one
  clear line, and no retry storms into the limit.** Delegation is then a
  best-effort tool with an honest failure mode, not a reliable one.
- The 3-way concurrent burst either all succeed or fail fast with a clear
  wrapper message — never an indefinite hang.
- Coexistence: five runs with Alexander's TUI reopened, zero stalls, and his
  session still alive and responsive afterward.
- **Alexander's TUI is never killed by anything I run. Hard gate.** No
  name-based process kills at any point.
- If the contingency triggers: an attached session is provably denied
  `git status` before Arm C ships.
- The four re-delegated files pass line-by-line review before commit.

## ELI5 conclusion

We stop guessing. The next time a delegation freezes we look at what it is
waiting for — a lock on this machine, or a reply from a server — and that one
observation eliminates two of the three suspects. If it is a lock, the fix is
fifteen lines: never run two opencode instances at once. If it is the shared
account being throttled by teammates, the fix is the opposite of retrying:
give up fast, say so plainly, and write the file inline instead. If it is the
auth plugin, one flag turns it off. Each answer is cheap; picking the wrong
one without measuring is what has been expensive. The dangerous "kill anything
named opencode" idea is retired for good, because it already cost Alexander a
running session.
