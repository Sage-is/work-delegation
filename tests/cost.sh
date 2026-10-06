#!/usr/bin/env bash
# delegate-cost against a made-up transcript and ledger: the read count, the
# --since filter, and the saving by output size. Never reads the real ones.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
COST=$ROOT/skill/scripts/delegate-cost
T=$(mktemp -d "${TMPDIR:-/tmp}/delegate-cost-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS  $1"; }
bad() { fail=$((fail + 1)); echo "FAIL  $1"; }
check() { [ "$2" = "$3" ] && ok "$1 ($2)" || bad "$1 (want $3, got $2)"; }

mkdir -p "$T/projects/p/s1/subagents" "$T/state/diffs"
python3 - "$T" <<'PY'
import json, sys
t = sys.argv[1]
def call(i, ts, cw, cr, tool=None):
    content = [{"type": "tool_use", "id": f"u{i}", "name": tool[0], "input": tool[1]}] if tool else [{"type": "text", "text": "ok"}]
    return {"type": "assistant", "timestamp": ts, "message": {"id": f"m{i}", "content": content,
            "usage": {"input_tokens": 0, "cache_creation_input_tokens": cw, "cache_read_input_tokens": cr, "output_tokens": 10}}}
big = "\n".join(f"{n}\tline" for n in range(400))
rows = [call(1, "2026-10-01T00:00:00Z", 1000, 0, ("Read", {"file_path": "/x/big.py"})),
        {"type": "user", "timestamp": "2026-10-01T00:00:01Z", "toolUseResult": {"file": {"numLines": 400}},
         "message": {"content": [{"type": "tool_result", "tool_use_id": "u1", "content": big}]}},
        call(2, "2026-10-01T00:00:02Z", 500, 1000), call(3, "2026-10-01T00:00:03Z", 0, 1500)]
open(f"{t}/projects/p/s1.jsonl", "w").write("\n".join(json.dumps(r) for r in rows))
old = [dict(r, timestamp="2026-01-01T00:00:00Z") for r in rows]
open(f"{t}/projects/p/old.jsonl", "w").write("\n".join(json.dumps(r) for r in old))
open(f"{t}/state/diffs/d1.patch", "w").write("+++ b/f.md\n" + "+" + "x" * 5000 + "\n")
open(f"{t}/state/log.jsonl", "w").write(json.dumps({"ts": "2026-10-01T00:00:00+0000", "rc": 0, "dir": "/r",
    "brief_chars": 1000, "duration_s": 30, "diff_file": f"{t}/state/diffs/d1.patch"}) + "\n")
PY
out=$(python3 "$COST" --since 2026-09-01 --projects "$T/projects" --ledger "$T/state/log.jsonl")
check "1 one transcript after --since" "$(printf '%s' "$out" | grep -c '1 transcripts, 3 main')" 1
check "2 the big read is counted" "$(printf '%s' "$out" | grep -c 'over 350 lines: 1 (0 in subagents, 0 followed by an edit)')" 1
check "3 cache reads summed" "$(printf '%s' "$out" | grep -c 'cache read 0.0M (12% of input)')" 1
check "4 run lands in its size bucket" "$(printf '%s' "$out" | grep -cE '4000-8000 chars +1 runs')" 1
check "5 no transcripts is said plainly" "$(python3 "$COST" --since 2030-01-01 --projects "$T/projects" --ledger "$T/none" | grep -c 'No transcripts')" 1

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
