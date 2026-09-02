# TODO: work-delegation

## 🔥 Urgent

- [ ] **The brief-size stall ceiling rests on a correlation that did not replicate.** `oc-edit` refuses briefs over 3500 chars (exit 8) and warns over 2000, on the strength of 20 runs from 2026-08-18.
  - [ ] 2026-08-21: a 528-char brief and a 2069-char brief stalled identically, exit 6 at 258s, on `big-pickle` and `kimi-k3`, minutes apart.
  - [ ] 2026-09-02: the correlation now runs the WRONG WAY. A 386-char brief stalled; a 2599-char brief succeeded in 38s. Full set that session: rc=0 at 2008/2599/2294 chars, rc=6 at 1146/386. The smallest brief of the day was the one that hung.
  - [ ] 2026-09-02: durations are bimodal with nothing between. Every success 27-38s, every stall 257-262s -- which is 120s cap + 15s pause + 120s cap. A stall is not a slow answer; both attempts hit the ceiling and return nothing.
  - [ ] 2026-09-02 hypothesis, untested: both stalls that day targeted a DOTFILE (`.commitmsg`); every success wrote a normal path. Seeding a dot-prefixed target may be the trigger, or coincidence in a 2-sample set. Cheap to test: same brief against `commitmsg.txt`.
  - [ ] Alexander reports no trouble with long prompts in the opencode TUI.
  - [ ] Re-derive the ceiling from the current ledger, or drop the gate. Same question for the fenced-lines warning.
  - [ ] Sources to update if it goes: `skill/scripts/oc-edit:95-104`, `docs/stall-investigation.md`, `skill/SKILL.md`, `RESULTS.md`.

- [ ] **Commit messages are a bad delegation target; the skill should say so.** 2026-09-02: four attempts across both routed models, all rc=6, for one commit message.
  - [ ] The structural reason is already in SKILL.md's brief-economy rule. A brief must carry every fact the message states, so brief and artifact converge in size -- the definition of "stopped delegating". The expensive model writes the message as a prose spec and a second model retypes it.
  - [ ] The enforce hook does not fire on commit messages, since they are not file writes. Nothing pushed toward delegation here except habit. Add them to SKILL.md's "Do NOT delegate" list, beside small edits.

- [ ] **The enforce hook has no fallback when the gateway is down.** 2026-09-02: with delegation failing 4/4, the hook still blocked a direct edit whose whole content was the record of that failure.
  - [ ] `OC_DELEGATE_ENFORCE=0` is the documented bypass and it works, but a contributor hitting this mid-outage has to read SKILL.md to find it. The denial message names the variable -- good -- yet still frames delegation as the expected path.
  - [ ] Consider: on a recent rc=6 in the ledger, downgrade the hook to a warning rather than a denial. The evidence for "the gateway is stalling right now" is already on disk.

- [ ] **Exit 6 can leave a completed edit in the worktree.** Observed 2026-08-21: a capped attempt finished its edit, then the run returned 6. Cleanup only removes unfilled seeds, so "stall" does not mean "nothing happened".
  - [ ] The harness adapters now say to read the diff first. The wrapper should say it too, on the exit-6 line itself.
  - [ ] Better: print the diff stat on exit 6 instead of staying silent about it.

- [ ] **A delegation is silent for up to 120 seconds, then emits one line.** No sign of life while waiting. (Alexander, 2026-08-21)
  - [ ] Minimum viable: echo the model, brief size, and target files at the start, then a heartbeat with elapsed seconds.
  - [ ] The run already writes to a temp file; tailing it would give real progress for a few lines of code.

- [ ] **Two multi-hour hangs overlapped under a machine-wide mutex.** Back-computed starts of 2026-08-20 ~15:55 and ~16:09, which the lock should have made impossible.
  - [ ] Not answerable from the current ledger. The new `lock_reclaimed` field records it if it recurs.
  - [ ] Do not chase this by inference — wait for evidence.

## Planned

- [ ] **Split `oc-edit` into an `oc-work` command set.** Editing is not the only thing worth delegating (Alexander, 2026-08-21).
  - [ ] Non-edit verbs worth having: `review` (read a diff, return findings), `ask` (answer a question about the repo), `run` (scoped command plus a summary).
  - [ ] Existing verbs: `edit`, `create`, `heal`, `doctor`, `lock`.
  - [ ] Keep `oc-edit` as an alias so installed skills, hooks, and harness adapters keep working.
  - [ ] Shared library for lock, ledger, and brief-gate logic.

## Housekeeping

- [ ] **Push `develop` and reconcile with `origin/develop`.** Ahead 1, behind 1 as of 2026-08-21.
- [ ] **Re-validate `opencode-go/kimi-k3`.** Marked unvalidated in the routing table; stalled at 258s on 2026-08-21 inside a degraded gateway window, so that reading is not conclusive.

---

## Previous Weeks

### 2026-08-21

- [x] **Root-caused the long hangs, and it was not the gateway.** Argless `shasum` in `fingerprint()` took no file arguments, fell back to reading the wrapper's own stdin, and blocked for an EOF that never came. All three hangs (12min, 18.6h, 19.2h) log `retries=0` and no session, so none reached opencode. Fixed with one `/dev/null` redirect. Field note in `RESULTS.md`.
- [x] **Capped the run at the source.** `timeout -k`, output to a temp file instead of `$(...)`, and 137 treated as capped alongside 124 — measured, `-k` returns 137, so testing only 124 would have looked like a fix and not been one.
- [x] **Made the lock self-healing.** One staleness test — holder gone, or older than `OC_LOCK_MAX_AGE` — reclaimed by atomic rename, plus `oc-edit --unlock [--force]`, which never signals a process.
- [x] **Stopped wedges logging as successes.** New exit 9 for a run past its ceiling with no session and no diff; `--doctor` now flags implausible ledger rows and reports lock health.
- [x] **Repointed routing off the retired `deepseek-v4-flash-free`** to `opencode/big-pickle`, and added a model preflight that exits 2 in about 3 seconds instead of stalling for 256.
- [x] **Added `tests/lock.sh` and `make test`.** 13 assertions; cases 4 and 7 both hang on the pre-fix wrapper, so the suite bites.
