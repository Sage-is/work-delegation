#!/usr/bin/env python3
"""Correctness check for one matrix task: check.py <task-id> <repo>. Exit 0 = correct."""
import ast
import re
import sys

task, repo = sys.argv[1], sys.argv[2]


def read(rel):
    with open(f"{repo}/{rel}", encoding="utf-8") as fh:
        return fh.read()


def load(rel):
    ns = {}
    exec(compile(read(rel), rel, "exec"), ns)  # noqa: S102 - fixture code under test
    return ns


if task == "t1-prose-gen":
    text = read("docs/backup.md")
    heads = re.findall(r"^## (.+)$", text, re.M)
    assert heads == ["Why Volume-Level Backups Win", "Weekly Schedule", "Restore Drill"], heads
    assert text.startswith("# Backing Up Your App"), text[:40]
    assert 25 <= text.count("\n") <= 80, text.count("\n")
    assert re.search(r"^1\. ", text, re.M), "no numbered steps"
elif task == "t2-prose-rewrite":
    text = read("docs/upload-guide.md")
    assert text.startswith("# Uploading Documents\n"), text[:40]
    low = text.lower()
    for filler in ("it should be noted", "actually", "basically", "in order to",
                   "it is important to note", "whatsoever", "commencement"):
        assert filler not in low, filler
    for fact in ("admin panel", "upper right", "upload", "pdf", "docx", "txt", "later"):
        assert fact in low, fact
    assert len(text) < 700, len(text)
elif task == "t3-py-sweep":
    src = read("src/metrics.py")
    tree = ast.parse(src)
    funcs = [n for n in tree.body if isinstance(n, ast.FunctionDef)]
    assert [f.name for f in funcs] == ["mean", "variance", "zscore", "rolling"], [f.name for f in funcs]
    for f in funcs:
        assert ast.get_docstring(f), f"{f.name} has no docstring"
        assert not any(isinstance(n, (ast.Import, ast.ImportFrom)) for n in ast.walk(f)), f.name
    assert any(isinstance(n, ast.Import) and n.names[0].name == "math" for n in tree.body), "no top import"
    m = load("src/metrics.py")
    assert m["mean"]([1, 2, 3]) == 2 and m["rolling"]([1, 2, 3, 4], 2) == [1.5, 2.5, 3.5]
    assert abs(m["zscore"](3, [1, 2, 3]) - 1.2247448713915889) < 1e-9
elif task == "t4-py-logic":
    p = load("src/paginate.py")["paginate"]
    assert p([1, 2, 3, 4, 5], 2) == [[1, 2], [3, 4], [5]]
    assert p([1, 2, 3, 4], 2) == [[1, 2], [3, 4]]
    assert p([], 3) == []
    assert "Split items into pages" in read("src/paginate.py")
else:
    sys.exit(f"unknown task {task}")
print("correct")
