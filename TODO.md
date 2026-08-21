# TODO: work-delegation

## 🔥 Urgent

- [ ] **Lock wedge: a stalled wrapper holds the machine-wide mutex forever.** Observed 2026-08-21 — pid 29085 held `/tmp/oc-edit-$UID.lock` for 17h24m with no live `opencode` process. Every delegation on the machine exited 7 until it was killed by hand.
  - [ ] Root cause: `run_once()` captures `timeout $OC_TIMEOUT opencode run …` via `$(…)`. `timeout` signals only the direct child, so a surviving grandchild keeps the stdout pipe open and the command substitution blocks long past the cap.
  - [ ] Fix the cap: `timeout -k 10 "$OC_TIMEOUT"` so SIGKILL follows SIGTERM.
  - [ ] Add age-based reclaim. `oc-edit:220` only tests `kill -0`, so a live-but-wedged holder is respected forever. Stamp the lock dir with a start time; reclaim past `2 × OC_TIMEOUT` plus slack.
  - [ ] Add orphan reclaim: holder alive but no live `opencode` descendant past a grace period.
  - [ ] Add `oc-edit --unlock`. Report lock age and holder health in `--doctor`.
  - [ ] Log every reclaim to the ledger so healing is evidence, not silence.
  - [ ] Regression test: wedge a fake holder, assert the next run reclaims instead of exiting 7.

- [ ] **Routed default model is retired — delegation fails out of the box.** `opencode/deepseek-v4-flash-free` returns `Model not found` from the Zen gateway (ledger 2026-08-21T10:50, rc=1 in 2s).
  - [ ] Repoint the routing table and every example. Named at `README.md:17`, `skill/SKILL.md:103-104`, `harness/codex/delegate-edit.md:10`, `harness/opencode/delegate-edit.md:12`. Leave the two `docs/stall-investigation.md` mentions as historical record.
  - [ ] Re-sync the installed copy at `~/.claude/skills/delegate-edit/SKILL.md`.
  - [ ] Verified replacement: `opencode/big-pickle` — rc=0 in 76s on a 1281-char prose brief that produced a 97-line file.
  - [ ] Current free list: `big-pickle`, `hy3-free`, `mimo-v2.5-free`, `muse-spark-1.2-contributor-free`, `nemotron-3-ultra-free`, `nemotron-3.5-lightning-free`, `x-preview-f-free`.
  - [ ] Escalation target failed too: `opencode-go/kimi-k3` hit rc=6 at 255s on a 1093-char brief. Re-validate before keeping it in the table.
  - [ ] Add a model-existence preflight (`opencode models <provider>`) so a retired model exits fast. The same retired model gave rc=6 at 256s on one run and rc=1 at 2s on the next — the stall path hides a config error.

- [ ] **A wedged run logs as a success and corrupts the routing evidence.** Ledger 2026-08-21T10:30 records `rc=0` with `duration_s=66905` — the 18.6-hour wedge, filed as a clean win.
  - [ ] Treat any duration past `2 × OC_TIMEOUT` plus slack as a failure, whatever the EXIT trap sees.
  - [ ] Have `--doctor` flag implausible durations so the ledger stays trustworthy as routing evidence.

## Planned

- [ ] **Split `oc-edit` into an `oc-work` command set.** One verb per job instead of one overloaded script.
  - [ ] Subcommands: `edit`, `create`, `heal`, `doctor`, `lock`.
  - [ ] Keep `oc-edit` as an alias so installed skills, hooks, and harness adapters keep working.
  - [ ] Shared library for lock, ledger, and brief-gate logic.
  - [ ] Decide whether `heal` runs automatically before every delegation or stays explicit.

## Housekeeping

- [ ] **Commit the Aug 18 working-tree changes.** Brief ceiling (exit 8), file creation, doctor brief-economy. Live in `~/bin/oc-edit` and the repo, uncommitted for 3 days.

---

## Previous Weeks

Completed work moves here in reverse chronological order.
