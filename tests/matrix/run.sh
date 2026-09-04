#!/usr/bin/env bash
# The measurement: four tasks against one or more lanes, each run through the
# real wrapper on a fresh copy of the fixtures, checked for correctness, and
# tabulated with the ledger's timing, turns, tokens, and cost.
#   tests/matrix/run.sh <lane>[,<lane>...] [out.md]
# Each lane runs on its own (no fallback list), so a failure is that lane's.
# Rows append to out.md (default results/matrix-<date>.md) and print.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
WRAP=$ROOT/skill/scripts/delegate-edit
LANES=${1:?lane list}
OUT=${2:-$ROOT/results/matrix-$(date +%Y-%m-%d).md}
LOG=${DELEGATE_LOG:-$HOME/.local/state/delegate/log.jsonl}
T=$(mktemp -d "${TMPDIR:-/tmp}/delegate-matrix.XXXXXX")
trap 'rm -rf "$T"' EXIT

[ -s "$OUT" ] || printf '| lane | task | rc | correct | s | turns | in | out | cost | note |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n' > "$OUT"

IFS=, read -r -a lanes <<< "$LANES"
n=$(python3 -c "import json; print(len(json.load(open('$ROOT/tests/matrix/tasks.json'))))")
for lane in "${lanes[@]}"; do
  for i in $(seq 0 $((n - 1))); do
    id=$(python3 -c "import json; print(json.load(open('$ROOT/tests/matrix/tasks.json'))[$i]['id'])")
    file=$(python3 -c "import json; print(json.load(open('$ROOT/tests/matrix/tasks.json'))[$i]['file'])")
    brief=$(python3 -c "import json; print(json.load(open('$ROOT/tests/matrix/tasks.json'))[$i]['brief'])")
    repo=$T/$id-$(echo "$lane" | tr '/:' '__')
    rm -rf "$repo"; mkdir -p "$repo"; cp -R "$ROOT/tests/matrix/fixtures/." "$repo/"
    git -C "$repo" init -q; git -C "$repo" add -A; git -C "$repo" -c user.email=t@t -c user.name=t commit -qm base
    start=$(date +%s)
    bash "$WRAP" "$repo" "$lane" "$brief" "$file" > "$T/out.txt" 2> "$T/err.txt"; rc=$?
    secs=$(( $(date +%s) - start ))
    correct=no
    [ "$rc" -eq 0 ] && python3 "$ROOT/tests/matrix/check.py" "$id" "$repo" > /dev/null 2> "$T/check.txt" && correct=yes
    note=""
    if [ "$rc" -ne 0 ]; then note=$(grep -m1 -oE '(lane [^→]*→ next|HTTP [0-9]+[^"]{0,40}|no lane usable|max turns[^;]*|budget[^;]*|no response[^;]*)' "$T/err.txt" | head -1 | cut -c1-60)
    elif [ "$correct" = no ]; then note=$(tail -1 "$T/check.txt" | cut -c1-60); fi
    # Pick this run's row by its repo path: lanes run in parallel, so the last
    # row may belong to another lane.
    read -r turns tin tout cost < <(python3 -c "
import json,sys
rows=[json.loads(l) for l in open('$LOG') if l.strip()]
hits=[x for x in rows if x.get('dir')=='$repo']; r=hits[-1] if hits else {}
print(r.get('turns') or '-', r.get('tokens_in') or '-', r.get('tokens_out') or '-', ('%.4f' % r['cost_usd']) if r.get('cost_usd') is not None else '-')")
    row="| $lane | $id | $rc | $correct | $secs | $turns | $tin | $tout | $cost | ${note//|/ } |"
    echo "$row"; echo "$row" >> "$OUT"
  done
done
