#!/usr/bin/env bash
# The enforce hook: denies big direct generations, passes small ones, exempts
# plan/memory paths, and allows with a reason during a delegation outage the
# ledger already records. Never touches the real ledger.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
HOOK=$ROOT/skill/scripts/delegate-hook.sh
T=$(mktemp -d "${TMPDIR:-/tmp}/delegate-hook-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS  $1"; }
bad() { fail=$((fail + 1)); echo "FAIL  $1"; }
check() { [ "$2" = "$3" ] && ok "$1 ($2)" || bad "$1 (want $3, got $2)"; }

big=$(python3 -c 'print("x" * 2500)')
payload() { python3 -c "import json,sys; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':sys.argv[1],'content':sys.argv[2]}}))" "$1" "$2"; }
decision() { printf '%s' "$1" | DELEGATE_ENFORCE=1 DELEGATE_LOG=$T/log.jsonl bash "$HOOK" | python3 -c "import json,sys; d=sys.stdin.read().strip(); print(json.loads(d)['hookSpecificOutput']['permissionDecision'] if d else 'pass')"; }
row() { python3 -c "import json,time,sys; print(json.dumps({'ts':time.strftime('%Y-%m-%dT%H:%M:%S%z', time.localtime(time.time()-int(sys.argv[1]))),'model':'go/x','rc':int(sys.argv[2])}))" "$1" "$2"; }

: > "$T/log.jsonl"
check "1 big generation denied" "$(decision "$(payload /p/doc.md "$big")")" deny
check "2 small edit passes" "$(decision "$(payload /p/doc.md short)")" pass
check "3 plan path exempt" "$(decision "$(payload /u/.claude/plans/x.md "$big")")" pass
check "4b nested typist passes" "$(printf '%s' "$(payload /p/doc.md "$big")" | DELEGATE_ENFORCE=1 DELEGATE_NESTED=1 bash "$HOOK" | wc -c | tr -d ' ')" 0
check "4 inert without DELEGATE_ENFORCE" "$(printf '%s' "$(payload /p/doc.md "$big")" | DELEGATE_ENFORCE=0 bash "$HOOK" | wc -c | tr -d ' ')" 0
row 60 6 > "$T/log.jsonl"
check "5 recent stall allows" "$(decision "$(payload /p/doc.md "$big")")" allow
row 3600 6 > "$T/log.jsonl"
check "6 old stall still denies" "$(decision "$(payload /p/doc.md "$big")")" deny
row 60 0 > "$T/log.jsonl"
check "7 recent success denies" "$(decision "$(payload /p/doc.md "$big")")" deny
row 60 9 > "$T/log.jsonl"
check "8 recent wedge allows" "$(decision "$(payload /p/doc.md "$big")")" allow

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
