# TODO: work-delegation

## 🔥 Urgent

- [ ] **Two multi-hour hangs overlapped under a machine-wide mutex.** Back-computed starts of 2026-08-20 ~15:55 and ~16:09, which the lock should have made impossible.
  - [ ] Not answerable from the current ledger. The `lock_reclaimed` field records it if it recurs.
  - [ ] Do not chase this by inference. Direct lanes take no lock, so it can only recur on the opencode path.

## Planned

- [ ] **Non-edit verbs.** Editing is not the only thing worth delegating (Alexander, 2026-08-21).
  - [ ] `delegate-review` (read a diff, return findings), `delegate-ask` (answer a question about the repo), `delegate-run` (scoped command plus a summary).
  - [ ] Share the provider table, lane fallback, and ledger from `delegate-agent`.

- [ ] **Phase 4, only if the matrix asks for it.** `ollama/qwen3.5:9b` scored 2/4 on 2026-09-04 with one 90s timeout.
  - [ ] A no-tools `direct` mode (named files inlined, model returns full contents) for small models.
  - [ ] NLT grid mode via `nlt-py` if `direct` is not enough.
  - [ ] Pi as an engine (`pi/` prefix) behind the same dispatch.

- [ ] **Opencode path is legacy.** It keeps the lock, the two capped attempts, and the silent 120s. Retire it once the direct lanes have a month of ledger behind them.

## Housekeeping

- [ ] **Push `develop` and reconcile with `origin/develop`.** Ahead 2, behind 1 as of 2026-08-21.
- [ ] **Add `OPENROUTER_API_KEY`** if the OpenRouter lane is wanted; the doctor lists it as unkeyed.
- [ ] **`make doctor` fails on five historical wedge rows** (2026-08-19 and 2026-08-21) until 50 newer rows push them out of the window.

---

## Previous Weeks

### 2026-09-05

- [x] **1920s art for the README.** Three flat-colour Deco scenes (how it works, the lanes, the admin) and seven single-colour heading emblems, hand-authored SVG in the hero's palette, no lettering; a four-judge panel returned 37 findings, all applied. Files under `docs/art/`.
- [x] **Emblems: padding, border, night version.** Art inset 8 units in an 80-unit box, 4-unit border on the tile, README size 28 to 32 so the ink weight holds. An inline `prefers-color-scheme` style flips cream tile with navy ink to navy tile with cream ink; it follows the OS preference, not GitHub's theme picker, and both mismatches stay legible.
- [x] **Delegate admin.** `make admin`: search, filter, star, tag, note, export, stats over the live ledger; the diff of every run, coloured per file; re-run and revert commands to paste; startr.style + startr.swap vendored and pinned; 17 tests; `make kit_check` fails on pin drift. A 70-agent review found 49 real faults before it shipped, the worst being colour tokens from the skill's table that the pinned build does not define.
- [x] **Patch per run.** The wrapper saves each run's `git diff` under `~/.local/state/delegate/diffs/`, keyed by a run id in the ledger row; `make diffs_prune` after 90 days.
- [x] **Stats flushed.** `make ledger_archive` moved the 119 test-era rows to a dated archive; what follows is post-fix evidence.

### 2026-09-04

- [x] **Found and fixed the free-lane refusal.** Zen's free models 429 any User-Agent not starting with `opencode/`, before quota; the error text says rate limit. zen/ lanes now send `opencode/<version> delegate-agent/1`; big-pickle edits in 7.6s. The real limit is per IP per UTC day, shared with the TUI; balance and Go do not change it. `zen/claude-*` needs Zen billing (401).
- [x] **Went direct to the gateways.** `delegate-agent` calls Zen, Go, NVIDIA NIM, OpenRouter, Ollama, or any OpenAI-compatible endpoint with the keys already in opencode's `auth.json`; five tools (read, write, edit, ls, done), no shell, paths jailed to the project dir. Lanes hop on any failure before the first edit.
- [x] **Renamed everything to `delegate-*`, no aliases.** `oc-edit` → `delegate-edit`, `OC_*` → `DELEGATE_*`, ledger moved to `~/.local/state/delegate/`; settings.json and the global CLAUDE.md updated in the same step.
- [x] **Dropped the brief-size ceiling.** The correlation ran the wrong way by 2026-09-02 (successes at 2008-2884 chars, stalls at 80-1146). The >2000 warning stays as brief economy only.
- [x] **Commit messages are delegable after all.** The 2026-09-02 failures were four gateway stalls, not a structural limit. Any long text gets delegated.
- [x] **Enforce hook allows a direct edit during an outage** the ledger already records: last row rc 6 or 9, younger than 30 minutes.
- [x] **Exits 1 and 6 print the diff stat.** A failed run can still have landed an edit.
- [x] **Sign of life.** Direct lanes print one line per turn; lane hops print the reason.
- [x] **Direct lanes take no lock.** Concurrent runs in one repo each name their files; fingerprint and diff stat scope to those files.
- [x] **`claude/<model>` backend.** `claude -p` with Read, Edit, Write, a turn cap and a dollar cap. `--bare` drops the login, so the hook is told via `DELEGATE_NESTED=1` instead.
- [x] **Repeatable matrix.** `tests/matrix/` rebuilds the 2026-08-15 fixtures; `make matrix LANES=...` scores every lane on the same four tasks. Results in `results/matrix-2026-09-04.md`.
- [x] **Re-validated `go/kimi-k3`.** 4/4 on the direct lane; the 2026-08-21 stall was the opencode CLI, not the model.
- [x] **Pi harness.** `/delegate-edit` prompt and the skill dir install to `~/.pi/agent/`.
- [x] **Four test suites** (`lock`, `agent`, `wrapper`, `hook`), 70 assertions, all against stubs.

### 2026-08-21

- [x] **Root-caused the long hangs, and it was not the gateway.** Argless `shasum` in `fingerprint()` took no file arguments, fell back to reading the wrapper's own stdin, and blocked for an EOF that never came. All three hangs (12min, 18.6h, 19.2h) log `retries=0` and no session, so none reached opencode. Fixed with one `/dev/null` redirect. Field note in `RESULTS.md`.
- [x] **Capped the run at the source.** `timeout -k`, output to a temp file instead of `$(...)`, and 137 treated as capped alongside 124.
- [x] **Made the lock self-healing.** One staleness test, reclaimed by atomic rename, plus `delegate-edit --unlock [--force]`, which never signals a process.
- [x] **Stopped wedges logging as successes.** New exit 9 for a run past its ceiling with no session and no diff; `--doctor` flags implausible ledger rows and reports lock health.
- [x] **Repointed routing off the retired `deepseek-v4-flash-free`** to `opencode/big-pickle`, and added a model preflight that exits 2 in about 3 seconds instead of stalling for 256.
- [x] **Added `tests/lock.sh` and `make test`.** 13 assertions; cases 4 and 7 both hang on the pre-fix wrapper, so the suite bites.
