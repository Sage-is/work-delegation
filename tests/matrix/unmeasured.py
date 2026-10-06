#!/usr/bin/env python3
"""Which models the catalogue offers that no matrix has scored, and which scored lanes
it no longer lists. Usage: unmeasured.py [prefix] (default go)."""
import json
import os
import re
import sys
from pathlib import Path

PREFIX = sys.argv[1] if len(sys.argv) > 1 else "go"
PROVIDER = {"go": "opencode-go", "zen": "opencode"}[PREFIX]
catalogue = os.environ.get("DELEGATE_CATALOGUE") or os.path.expanduser("~/.cache/opencode/models.json")
models = json.load(open(catalogue, encoding="utf-8")).get(PROVIDER, {}).get("models", {})
results = Path(__file__).resolve().parents[2] / "results"
scored = {m for f in results.glob("matrix-*.md")
          for m in re.findall(rf"^\| {PREFIX}/([^ |]+) \|", f.read_text(), re.M)}
fresh = sorted((m for m, e in models.items() if e.get("tool_call") and m not in scored),
               key=lambda m: models[m].get("release_date", ""), reverse=True)
print(f"{PREFIX}/ models in the catalogue no matrix has scored ({len(fresh)}):")
for m in fresh:
    c = models[m].get("cost") or {}
    print(f"  {PREFIX}/{m:30} released {models[m].get('release_date', '?'):10}  "
          f"${c.get('input', '?')}/${c.get('output', '?')} per M")
gone = sorted(scored - set(models))
if gone:
    print(f"scored lanes the catalogue no longer lists: {', '.join(PREFIX + '/' + m for m in gone)}")
