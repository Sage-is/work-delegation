#!/usr/bin/env bash
# Regression suite for the run cap and the lock reclaim.
#
# Runs the repo copy of oc-edit against a throwaway git repo with a shimmed
# opencode on PATH. It never reaches the gateway, never touches the real lock,
# and never writes to the real ledger — every case exports both OC_LOCK and
# OC_LOG into the scratch root, because one missed export would wedge the
# developer's own machine or file fake rows as routing evidence.
#
# Every process this script starts is recorded and stopped by its own pid. A
# name-based sweep already killed the user's interactive session once
# (docs/stall-investigation.md); nothing here searches the process table.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel)
OC=$ROOT/skill/scripts/oc-edit
T=$(mktemp -d "${TMPDIR:-/tmp}/oc-test.XXXXXX")
LOCK=$T/lock
LOG=$T/log.jsonl
PIDS=$T/pids
: > "$PIDS"
cleanup() {
  while read -r p; do kill -9 "$p" 2>/dev/null; done < "$PIDS"
  rm -rf "$T"
}
trap cleanup EXIT

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "PASS  $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL  $1"; }
check() { [ "$2" = "$3" ] && ok "$1 ($2)" || bad "$1 (want $3, got $2)"; }

# --- fixtures ---------------------------------------------------------------

mkdir -p "$T/bin"
cat > "$T/bin/opencode" <<'SHIM'
#!/usr/bin/env bash
# Stands in for the real CLI. `models` satisfies oc-edit's preflight; the run
# modes reproduce one gateway behaviour each.
[ "${1:-}" = models ] && { echo "test/model"; exit 0; }
case "${OC_TEST_MODE:-edit}" in
  edit)  echo '{"sessionID":"ses_test"}'; echo delegated >> "$OC_TEST_TARGET" ;;
  noop)  sleep 2; echo '{"sessionID":"ses_test"}' ;;   # answers, changes nothing
  hang)  trap "" TERM; sleep 600 & sleep 600 ;;        # ignores SIGTERM, has a grandchild
esac
SHIM
chmod +x "$T/bin/opencode"
export PATH="$T/bin:$PATH"

mkdir -p "$T/repo"
git -C "$T/repo" init -q
echo base > "$T/repo/f.md"
git -C "$T/repo" add -A
git -C "$T/repo" -c user.email=t@t -c user.name=t commit -qm base
export OC_TEST_TARGET=$T/repo/f.md

# Run the wrapper with the scratch lock and ledger, capped so a regression
# fails the suite instead of hanging it. Echoes the exit code.
run() {
  local secs=$1; shift
  OC_LOCK=$LOCK OC_LOG=$LOG timeout "$secs" bash "$OC" "$@" >/dev/null 2>&1
  echo $?
}
# A live process to stand in for a lock holder. Recorded, never searched for.
# Its stdout goes to /dev/null: a background job inherits the caller's stdout,
# and callers capture this with $(...), so leaving it attached would hold that
# pipe open for the full sleep — the same wedge this suite exists to catch.
holder() { sleep 600 >/dev/null 2>&1 & echo $! | tee -a "$PIDS"; }
seed_lock() { mkdir -p "$LOCK"; printf '%s\n' "$1" > "$LOCK/pid"; }
age_lock() { touch -t "$(date -v-1H +%Y%m%d%H%M 2>/dev/null \
                      || date -d '1 hour ago' +%Y%m%d%H%M)" "$LOCK"; }
last_row() { tail -1 "$LOG" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1'))"; }
reset() { rm -rf "$LOCK" "$LOG"; git -C "$T/repo" checkout -q -- f.md; }

# --- cases ------------------------------------------------------------------

# 1. Dead holder: the lock outlives the process that made it.
reset
dead=$(holder); kill -9 "$dead"; sleep 1
seed_lock "$dead"
check "1 dead holder reclaims" "$(run 60 "$T/repo" test/model 'edit f.md' f.md)" 0
check "1 reclaim recorded" "$(last_row lock_reclaimed)" "$dead"

# 2. Aged lock: holder still alive, but past any legitimate run length. This is
#    the 2026-08-20 wedge shape, and the case the old liveness-only check missed.
reset
live=$(holder)
seed_lock "$live"; age_lock
check "2 aged lock reclaims" "$(run 60 "$T/repo" test/model 'edit f.md' f.md)" 0

# 3. Healthy holder: a fresh lock owned by a live process must be respected.
#    The anti-regression that keeps "reclaim" from becoming "always reclaim".
reset
live=$(holder)
seed_lock "$live"
check "3 healthy lock respected" "$(OC_LOCK_WAIT=4 run 60 "$T/repo" test/model 'edit f.md' f.md)" 7
check "3 lock left intact" "$(cat "$LOCK/pid")" "$live"

# 4. The original bug: a child that ignores SIGTERM and leaves a grandchild
#    holding the stdout pipe. On the pre-fix wrapper this never returns.
reset
check "4 SIGTERM-proof stall is capped" \
  "$(OC_TEST_MODE=hang OC_TIMEOUT=2 OC_KILL_AFTER=2 run 45 "$T/repo" test/model 'edit f.md' f.md)" 6

# 5. Implausible duration is rewritten to exit 9, and keeps the body's code.
#    A ceiling of 0 makes every run overrun; the shim answers but edits nothing.
reset
check "5 overrun with no diff is wedged" \
  "$(OC_TEST_MODE=noop OC_LOCK_MAX_AGE=0 run 60 "$T/repo" test/model 'edit f.md' f.md)" 9
check "5 body's exit code kept" "$(last_row wedged)" 5

# 6. Real work is never called a wedge, however long it took.
reset
check "6 overrun with a diff keeps rc=0" \
  "$(OC_LOCK_MAX_AGE=0 run 60 "$T/repo" test/model 'edit f.md' f.md)" 0

# 7. A stdin that never reaches EOF must not hang the run. Argless shasum in
#    fingerprint() read the wrapper's own stdin and blocked there, before
#    opencode was ever invoked. The fifo below is held open for writing by fd 9
#    for the life of this script, so a reader on it waits forever.
reset
mkfifo "$T/fifo"
exec 9<> "$T/fifo"
check "7 open stdin does not hang the run" \
  "$(OC_LOCK=$LOCK OC_LOG=$LOG timeout 20 bash "$OC" "$T/repo" test/model 'edit f.md' f.md \
      < "$T/fifo" >/dev/null 2>&1; echo $?)" 0

# 8. --unlock reports a healthy lock and refuses it; --force releases.
reset
live=$(holder)
seed_lock "$live"
check "8 --unlock refuses a healthy lock" \
  "$(OC_LOCK=$LOCK OC_LOG=$LOG bash "$OC" --unlock >/dev/null 2>&1; echo $?)" 7
check "8 --unlock --force releases" \
  "$(OC_LOCK=$LOCK OC_LOG=$LOG bash "$OC" --unlock --force >/dev/null 2>&1; echo $?)" 0
[ -d "$LOCK" ] && bad "8 lock removed by --force" || ok "8 lock removed by --force"

# ----------------------------------------------------------------------------

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
