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
# A catalogue of our own: go/gpt-x speaks the Responses API, go/priced has list prices.
cat > "$T/catalogue.json" <<'JSON'
{"opencode-go": {"npm": "@ai-sdk/openai-compatible", "models": {
  "gpt-x": {"provider": {"npm": "@ai-sdk/openai"}, "cost": {"input": 1, "output": 2}},
  "priced": {"cost": {"input": 1, "output": 2}}}}}
JSON
export DELEGATE_CATALOGUE=$T/catalogue.json

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
check "9 zen without a key skips" "$(OPENCODE_API_KEY= DELEGATE_AUTH_JSON=/nonexistent agent --lanes zen/m1)" 2
check "9 zen reason names the variable" "$(out lanes_skipped | grep -c OPENCODE_API_KEY)" 1

# 9b. NIM model ids keep their vendor; NVIDIA's own get it back.
reset_repo
script '[{"tool":"done","args":{"summary":"ok"}}]'
NVIDIA_API_KEY=k agent --lanes nvidia/nemotron-x > /dev/null
check "9b nvidia bare id completed" "$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readlines()[-1])['body']['model'])")" nvidia/nemotron-x
NVIDIA_API_KEY=k agent --lanes nvidia/moonshotai/kimi-k3 > /dev/null
check "9b nvidia vendor id kept" "$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readlines()[-1])['body']['model'])")" moonshotai/kimi-k3

# 9c. Every lane names this client, zen/ included; none claims to be opencode.
reset_repo
script '[{"tool":"done","args":{"summary":"ok"}}]'
ua() { python3 -c "import json; print({k.lower(): v for k, v in json.loads(open('$T/record.jsonl').readlines()[-1])['headers'].items()}.get('user-agent',''))"; }
OPENCODE_API_KEY=k agent --lanes zen/m1 > /dev/null
check "9c zen sends our UA" "$(ua)" "delegate-agent/1 (work-delegation)"
agent --lanes api/m1 > /dev/null
check "9c other lanes send our UA" "$(ua)" "delegate-agent/1 (work-delegation)"

# 9d. opencode.ai lanes send one stable x-opencode-session per conversation.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}}]'
OPENCODE_GO_API_KEY=k agent --lanes go/m1 > /dev/null
# Header names are case-insensitive; urllib sends this one as X-opencode-session.
sid() { python3 -c "import json,sys; print(' '.join({k.lower(): v for k, v in json.loads(l)['headers'].items()}.get('x-opencode-session','none') for l in open('$T/record.jsonl').readlines()[-$1:]))"; }
sids=$(sid 2)
check "9d go sends a session id" "$(printf '%s' "$sids" | grep -c '^delegate-[0-9a-f]\{32\} ')" 1
check "9d same id on every turn" "$(printf '%s' "$sids" | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')" 1
agent --lanes api/m1 > /dev/null
check "9d other lanes send none" "$(sid 1)" none

# 10. Two agents at once in one repo, each on its own file.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}},{"tool":"write","args":{"path":"g.md","content":"second"}},{"tool":"done","args":{"summary":"ok"}}]'
python3 "$AGENT" --dir "$T/repo" --brief-file "$T/brief" --lanes api/m1 > "$T/o1.json" 2>/dev/null & p1=$!
sleep 0.3
python3 "$AGENT" --dir "$T/repo" --brief-file "$T/brief" --lanes api/m1 > "$T/o2.json" 2>/dev/null & p2=$!
wait $p1; r1=$?; wait $p2; r2=$?
check "10 concurrent runs both succeed" "$r1$r2" 00
check "10 both files landed" "$(cat "$T/repo/f.md" "$T/repo/g.md" | tr '\n' ' ' | sed 's/ *$//')" "delegated second"

# 11. A slow answer that keeps sending is not a stall: the timeout is a silence limit.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"},"drip":0.4},{"tool":"done","args":{"summary":"ok"}}]'
check "11 slow stream outlives the timeout" "$(agent --lanes api/m1 --request-timeout 1 --file "$T/repo/f.md")" 0
check "11 file changed" "$(cat "$T/repo/f.md")" delegated
check "11 the request asked for a stream" "$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readline())['body']['stream'])")" True

# 12. Silence mid-answer before any edit is a stall: the next lane takes over.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"},"stall":3},{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}}]'
check "12 mid-stream stall hops" "$(agent --lanes api/m1,api/m2 --request-timeout 1)" 0
check "12 skip says stalled" "$(out lanes_skipped | grep -c 'stream stalled')" 1
check "12 second lane did it" "$(out lane)" api/m2

# 13. A gateway that ignores stream=true and answers one JSON body still works.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"},"json":true},{"tool":"done","args":{"summary":"ok"},"json":true}]'
check "13 plain JSON answer accepted" "$(agent --lanes api/m1)" 0
check "13 file changed" "$(cat "$T/repo/f.md")" delegated

# 14. The catalogue sends go/gpt-x to the Responses API, with tool results as items.
reset_repo
script '[{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}}]'
check "14 responses lane works" "$(OPENCODE_GO_API_KEY=k agent --lanes go/gpt-x --file "$T/repo/f.md")" 0
check "14 file changed" "$(cat "$T/repo/f.md")" delegated
check "14 protocol recorded" "$(out protocol)" responses
check "14 path is /responses" "$(python3 -c "import json; print(json.loads(open('$T/record.jsonl').readline())['path'])")" /responses
check "14 tool result sent back as an item" "$(python3 -c "
import json
body=json.loads(open('$T/record.jsonl').readlines()[1])['body']
print([i['type'] for i in body['input'] if 'type' in i], bool(body['instructions']))")" "['function_call', 'function_call_output'] True"
check "14 list price from the catalogue" "$(out cost_usd)" 0.00024
check "14 cost source" "$(out cost_source)" catalogue

# 15. Chat lanes: the gateway's own cost wins; without one, the catalogue's price.
reset_repo
script '[{"tool":"done","args":{"summary":"ok"},"cost":null}]'
OPENCODE_GO_API_KEY=k agent --lanes go/priced > /dev/null
check "15 chat lane priced from the catalogue" "$(out cost_usd) $(out cost_source) $(out protocol)" "0.00012 catalogue chat"
script '[{"tool":"done","args":{"summary":"ok"}}]'
agent --lanes api/m1 > /dev/null
check "15 gateway cost wins" "$(out cost_usd) $(out cost_source)" "0.0001 provider"

# 16. Named files that exist ride along with the brief; a new one does not.
reset_repo
script '[{"tool":"done","args":{"summary":"ok"}}]'
agent --lanes api/m1 --file "$T/repo/f.md" --file "$T/repo/new.md" > /dev/null
first_user() { python3 -c "import json; m=json.loads(open('$T/record.jsonl').readline())['body']['messages']; print([x for x in m if x['role']=='user'][0]['content'])"; }
check "16 named file preloaded" "$(first_user | grep -c '<file path="f.md">')" 1
check "16 new file not preloaded" "$(first_user | grep -c '<file path="new.md">')" 0

# 17. Every tool call lands in the trace, errors with their reason.
reset_repo
script '[{"tool":"edit","args":{"path":"two.md","old":"a","new":"b"}},{"tool":"edit","args":{"path":"f.md","old":"base","new":"delegated"}},{"tool":"done","args":{"summary":"ok"}}]'
agent --lanes api/m1 > /dev/null
check "17 trace length" "$(out trace len)" 3
check "17 trace keeps the error" "$(python3 -c "import json; print(json.load(open('$T/out.json'))['trace'][0][:34])")" "1 edit two.md error: old matches 2"
check "17 trace ends with done" "$(python3 -c "import json; print(json.load(open('$T/out.json'))['trace'][-1])")" "3 done ok"

# ----------------------------------------------------------------------------
echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
