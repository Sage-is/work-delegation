#!/usr/bin/env python3
"""Merge per-lane scoreboards into one table, taking turns, tokens, and cost from
the ledger row whose repo path names the lane and task (parallel lanes make the
"last row" unreliable). Usage: merge.py <out.md> <lane-file.md>..."""
import json
import os
import re
import sys

out, files = sys.argv[1], sys.argv[2:]
ledger = os.environ.get("DELEGATE_LOG") or os.path.expanduser("~/.local/state/delegate/log.jsonl")
rows = [json.loads(l) for l in open(ledger, encoding="utf-8") if l.strip()]


def ledger_row(lane, task):
    suffix = f"{task}-{re.sub(r'[/:]', '_', lane)}"
    hits = [r for r in rows if (r.get("dir") or "").endswith(suffix)]
    return hits[-1] if hits else {}


lines = ["| lane | task | rc | correct | s | turns | in | out | cost | note |",
         "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
for f in files:
    for line in open(f, encoding="utf-8"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 10 or cells[0] in ("lane", "---"):
            continue
        lane, task, rc, correct, secs, _, _, _, _, note = cells
        r = ledger_row(lane, task)
        cost = f"{r['cost_usd']:.4f}" if r.get("cost_usd") is not None else "-"
        lines.append(f"| {lane} | {task} | {rc} | {correct} | {secs} | {r.get('turns') or '-'} | "
                     f"{r.get('tokens_in') or '-'} | {r.get('tokens_out') or '-'} | {cost} | {note} |")
open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("\n".join(lines))
