#!/usr/bin/env bash
# Regression suite for delegate-edit's direct-API path: dispatch by prefix,
# scoped no-op detection and diff stat, the diff on a failed exit, the ledger
# fields, and two runs at once in one repo. Uses the scripted stub server; the
# opencode path is covered by tests/lock.sh. Every process this script starts is
# recorded and stopped by its own pid, never by name.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel)
WRAP=$ROOT/skill/scripts/delegate-edit
T=$(mktemp -d "${TMPDIR:-/tmp}/delegate-wrapper-test.XXXXXX")
PIDS=$T/pids; : > "$PIDS"
cleanup() { while read -r p; do kill -9 "$p" 2>/dev/null; done < "$PIDS"; rm -rf "$T"; }
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS  $1"; }
bad() { fail=$((fail + 1)); echo "FAIL  $1"; }
check() { [ "$2" = "$3" ] && ok "$1 ($2)" || bad "$1 (want $3, got $2)"; }

PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
echo '[]' > "$T/script.json"
python3 "$ROOT/tests/stub_llm.py" "$PORT" "$T/script.json" "$T/record.jsonl" &
echo $! >> "$PIDS"
for _ in $(seq 1 50); do curl -s -o /dev/null -X POST "http://127.0.0.1:$PORT/reset" && break; sleep 0.1; done
export DELEGATE_BASE_URL="http://127.0.0.1:$PORT" DELEGATE_API_KEY=fake-api-key
export DELEGATE_LOCK=$T/lock DELEGATE_LOG=$T/log.jsonl
script() { printf '%s' "$1" > "$T/script.json"; curl -s -o /dev/null -X POST "http://127.0.0.1:$PORT/reset"; }
reset_repo() {
  rm -rf "$T/repo"; mkdir -p "$T/repo"; git -C "$T/repo" init -q
  printf 'base\n' > "$T/repo/f.md"; printf 'other\n' > "$T/repo/g.md"
  git -C "$T/repo" add -A; git -C "$T/repo" -c user.email=t@t -c user.name=t commit -qm base
  rm -f "$T/log.jsonl"
}
run() { bash "$WRAP" "$@" > "$T/out.txt" 2> "$T/err.txt"; echo $?; }
row() { tail -1 "$T/log.jsonl" | python3 -c "import json,sys; v=json.load(sys.stdin).get('$1'); print(len(v) if isinstance(v,list) else v)"; }

# 1. A direct lane through the wrapper: rc 0, diff stat, ledger fields.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}}]'
check "1 api lane via wrapper" "$(run "$T/repo" api/m1 'edit f.md' f.md)" 0
check "1 diff stat printed" "$(grep -c 'diff stat' "$T/out.txt")" 1
check "1 ledger backend" "$(row backend)" api
check "1 ledger lane" "$(row lane)" api/m1
check "1 ledger turns" "$(row turns)" 2
check "1 ledger session" "$(row session)" stub-0
check "1 no lock taken" "$([ -d "$T/lock" ] && echo held || echo free)" free

# 2. Silent no-op is still caught when the model changes nothing.
reset_repo
script '[{"tool":"read","args":{"path":"f.md"}},{"tool":"done","args":{"summary":"nothing to do"}}]'
check "2 no-op is rc 5" "$(run "$T/repo" api/m1 'edit f.md' f.md)" 5

# 3. Scoped fingerprint: a pre-existing unrelated change does not mask a no-op,
#    and does not show in the diff stat of a scoped run.
reset_repo
printf 'unrelated\n' > "$T/repo/g.md"
script '[{"tool":"done","args":{"summary":"nothing"}}]'
check "3 no-op despite dirty tree" "$(run "$T/repo" api/m1 'edit f.md' f.md)" 5
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}}]'
run "$T/repo" api/m1 'edit f.md' f.md > /dev/null
check "3 diff stat scoped to named file" "$(grep -c 'g.md' "$T/out.txt")" 0

# 4. Failure after an edit: rc 1 and the diff stat is still printed.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"status":500,"error":"boom"}]'
check "4 post-commit failure rc 1" "$(run "$T/repo" api/m1 'edit f.md' f.md)" 1
check "4 diff shown on failure" "$(grep -c 'f.md' "$T/out.txt")" 1

# 5. A comma list with a non-direct prefix is a usage error, not a run.
reset_repo
check "5 comma list needs direct prefixes" "$(run "$T/repo" opencode/x,go/y 'edit f.md' f.md)" 2

# 6. Two wrapper runs at once in one repo, each naming its own file.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}},{"tool":"edit","args":{"path":"g.md","old":"other","new":"second"}},{"tool":"done","args":{"summary":"ok"}}]'
bash "$WRAP" "$T/repo" api/m1 'edit f.md' f.md > "$T/o1.txt" 2>/dev/null & p1=$!
sleep 0.3
bash "$WRAP" "$T/repo" api/m1 'edit g.md' g.md > "$T/o2.txt" 2>/dev/null & p2=$!
wait $p1; r1=$?; wait $p2; r2=$?
check "6 concurrent wrapper runs succeed" "$r1$r2" 00
check "6 first stat lists only f.md" "$(grep -c 'g.md' "$T/o1.txt")" 0
check "6 second stat lists only g.md" "$(grep -c 'f.md' "$T/o2.txt")" 0
check "6 two ledger rows" "$(wc -l < "$T/log.jsonl" | tr -d ' ')" 2

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
