#!/usr/bin/env bash
# Regression suite for delegate-agent: the tool jail, lane fallback, commit
# semantics, budgets, and key resolution — against a scripted stub server.
# Nothing here reaches a real provider or the real ledger. Every process this
# script starts is recorded and stopped by its own pid, never by name.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel)
AGENT=$ROOT/skill/scripts/delegate-agent
T=$(mktemp -d "${TMPDIR:-/tmp}/delegate-agent-test.XXXXXX")
PIDS=$T/pids; : > "$PIDS"
cleanup() { while read -r p; do kill -9 "$p" 2>/dev/null; done < "$PIDS"; rm -rf "$T"; }
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS  $1"; }
bad() { fail=$((fail + 1)); echo "FAIL  $1"; }
check() { [ "$2" = "$3" ] && ok "$1 ($2)" || bad "$1 (want $3, got $2)"; }

# --- stub server ------------------------------------------------------------
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
echo '[]' > "$T/script.json"
python3 "$ROOT/tests/stub_llm.py" "$PORT" "$T/script.json" "$T/record.jsonl" &
echo $! >> "$PIDS"
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/reset" -X POST && break; sleep 0.1; done
export DELEGATE_BASE_URL="http://127.0.0.1:$PORT" DELEGATE_API_KEY=fake-api-key
unset OPENCODE_API_KEY OPENCODE_GO_API_KEY NVIDIA_API_KEY OPENROUTER_API_KEY

script() { printf '%s' "$1" > "$T/script.json"; : > "$T/record.jsonl"; curl -s -o /dev/null -X POST "http://127.0.0.1:$PORT/reset"; }
reset_repo() {
  rm -rf "$T/repo"; mkdir -p "$T/repo"
  printf 'base\n' > "$T/repo/f.md"; printf 'a a\n' > "$T/repo/two.md"
  printf 'edit f.md\n' > "$T/brief"
}
# Runs the agent; echoes its exit code; JSON summary lands in $T/out.json.
agent() { python3 "$AGENT" --dir "$T/repo" --brief-file "$T/brief" "$@" > "$T/out.json" 2> "$T/err.txt"; echo $?; }
out() { python3 -c "import json,sys; v=json.load(open('$T/out.json')).get('$1'); print(len(v) if isinstance(v,list) and '${2:-}'=='len' else v)"; }
# Content of the tool result the agent sent back in request N (0-based).
tool_result() { python3 -c "
import json
rows=[json.loads(l) for l in open('$T/record.jsonl')]
msgs=rows[$1]['body']['messages']
print([m for m in msgs if m['role']=='tool'][-1]['content'][:60])"; }

# --- cases ------------------------------------------------------------------

# 1. The happy path: edit, then done.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}}]'
check "1 edit then done" "$(agent --lanes api/m1 --file "$T/repo/f.md")" 0
check "1 file changed" "$(cat "$T/repo/f.md")" delegated
check "1 lane recorded" "$(out lane)" api/m1
check "1 turns counted" "$(out turns)" 2
check "1 touched listed" "$(out touched len)" 1

# 2. A write outside --dir is refused and nothing is created.
reset_repo
script '[{"tool":"write","args":{"path":"../evil.md","content":"x"}},{"tool":"done","args":{"summary":"ok"}}]'
agent --lanes api/m1 > /dev/null
[ -e "$T/evil.md" ] && bad "2 outside write blocked" || ok "2 outside write blocked"
check "2 model told why" "$(tool_result 1 | cut -c1-15)" "error: refused:"

# 3. edit must match exactly once.
reset_repo
script '[{"tool":"edit","args":{"path":"two.md","old":"a","new":"b"}},{"tool":"done","args":{"summary":"ok"}}]'
agent --lanes api/m1 > /dev/null
check "3 ambiguous edit refused" "$(cat "$T/repo/two.md")" "a a"
check "3 model told the count" "$(tool_result 1 | cut -c1-24)" "error: old matches 2 tim"

# 4. First lane 429 before any edit -> next lane does the work.
reset_repo
script '[{"status":429,"error":"Rate limit exceeded"},{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}}]'
check "4 hops past 429" "$(agent --lanes api/m1,api/m2 --file "$T/repo/f.md")" 0
check "4 second lane did it" "$(out lane)" api/m2
check "4 skip recorded" "$(out lanes_skipped len)" 1
check "4 file changed" "$(cat "$T/repo/f.md")" delegated

# 5. Failure after an edit: committed, exit 1, diff kept.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"status":500,"error":"boom"}]'
check "5 post-commit failure is rc 1" "$(agent --lanes api/m1,api/m2)" 1
check "5 diff kept" "$(cat "$T/repo/f.md")" delegated
check "5 no hop after commit" "$(out lanes_skipped len)" 0

# 6. Every lane fails before commit -> rc 2.
reset_repo
script '[{"status":404,"error":"model not found"}]'
check "6 no lane usable" "$(agent --lanes api/m1,api/m2)" 2
check "6 both skips recorded" "$(out lanes_skipped len)" 2

# 7. A request timeout before commit hops; every lane timing out is rc 6.
reset_repo
script '[{"delay":3,"text":"slow"},{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}}]'
check "7 timeout hops" "$(agent --lanes api/m1,api/m2 --request-timeout 1)" 0
check "7 skip reason is timeout" "$(out lanes_skipped | grep -c 'no response')" 1
reset_repo
script '[{"delay":3,"text":"slow"}]'
check "7 all lanes time out is rc 6" "$(agent --lanes api/m1,api/m2 --request-timeout 1)" 6

# 8. Max turns -> rc 8, work so far kept.
reset_repo
script '[{"tool":"read","args":{"path":"f.md"}}]'
check "8 max turns" "$(agent --lanes api/m1 --max-turns 2)" 8
check "8 stopped at the cap" "$(out turns)" 2

# 9. Keys: env var first, then opencode's auth.json; a missing key skips the lane.
reset_repo
printf '{"opencode-go":{"type":"api","key":"fake-go-key"}}' > "$T/auth.json"
script '[{"tool":"done","args":{"summary":"ok"}}]'
DELEGATE_AUTH_JSON=$T/auth.json agent --lanes go/m1 > /dev/null
check "9 key from auth.json" "$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readlines()[-1])['auth'])")" "Bearer fake-go-key"
OPENCODE_GO_API_KEY=env-wins DELEGATE_AUTH_JSON=$T/auth.json agent --lanes go/m1 > /dev/null
check "9 env var wins" "$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readlines()[-1])['auth'])")" "Bearer env-wins"
check "9 no key skips a keyed lane" "$(DELEGATE_AUTH_JSON=/nonexistent agent --lanes go/m1)" 2
check "9 reason names the variable" "$(out lanes_skipped | grep -c OPENCODE_GO_API_KEY)" 1
check "9 zen runs keyless" "$(DELEGATE_AUTH_JSON=/nonexistent agent --lanes zen/m1)" 0
check "9 zen keyless sends no auth" "$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readlines()[-1])['auth'])")" None

# 9b. NIM model ids keep their vendor; NVIDIA's own get it back.
reset_repo
script '[{"tool":"done","args":{"summary":"ok"}}]'
NVIDIA_API_KEY=k agent --lanes nvidia/nemotron-x > /dev/null
check "9b nvidia bare id completed" "$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readlines()[-1])['body']['model'])")" nvidia/nemotron-x
NVIDIA_API_KEY=k agent --lanes nvidia/moonshotai/kimi-k3 > /dev/null
check "9b nvidia vendor id kept" "$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readlines()[-1])['body']['model'])")" moonshotai/kimi-k3

# 9c. zen/ lanes lead with the opencode client identity; others do not.
reset_repo
script '[{"tool":"done","args":{"summary":"ok"}}]'
OPENCODE_API_KEY=k agent --lanes zen/m1 > /dev/null
ua=$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readlines()[-1])['headers'].get('User-Agent',''))")
check "9c zen UA starts with opencode/" "$(printf '%s' "$ua" | grep -c '^opencode/[0-9]')" 1
check "9c zen UA still names us" "$(printf '%s' "$ua" | grep -c 'delegate-agent/1')" 1
agent --lanes api/m1 > /dev/null
check "9c other lanes keep our UA" "$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readlines()[-1])['headers'].get('User-Agent',''))")" "delegate-agent/1 (work-delegation)"

# 10. Two agents at once in one repo, each on its own file.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}},{"tool":"write","args":{"path":"g.md","content":"second"}},{"tool":"done","args":{"summary":"ok"}}]'
python3 "$AGENT" --dir "$T/repo" --brief-file "$T/brief" --lanes api/m1 > "$T/o1.json" 2>/dev/null & p1=$!
sleep 0.3
python3 "$AGENT" --dir "$T/repo" --brief-file "$T/brief" --lanes api/m1 > "$T/o2.json" 2>/dev/null & p2=$!
wait $p1; r1=$?; wait $p2; r2=$?
check "10 concurrent runs both succeed" "$r1$r2" 00
check "10 both files landed" "$(cat "$T/repo/f.md" "$T/repo/g.md" | tr '\n' ' ' | sed 's/ *$//')" "delegated second"

# ----------------------------------------------------------------------------
echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
