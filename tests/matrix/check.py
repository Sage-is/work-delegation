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
elif task == "t5-long-gen":
    text = read("docs/runbook.md")
    want = ["Daily Checks", "Weekly Backups", "Restore From Backup", "Upgrading",
            "Rotating Secrets", "Disk Space", "Incident Response", "Decommissioning"]
    assert text.startswith("# Ledgerly Operations Runbook"), text[:40]
    assert re.findall(r"^## (.+?)\s*$", text, re.M) == want, re.findall(r"^## (.+)$", text, re.M)
    head = text.split("\n## ", 1)[0]
    assert len(re.findall(r"\[[^]]+\]\(#[a-z0-9-]+\)", head)) == 8, "contents list needs eight anchor links"
    for body in text.split("\n## ")[1:]:
        steps = re.findall(r"^\d+\. \S", body, re.M)
        assert len(steps) >= 5, f"{body.splitlines()[0]}: {len(steps)} steps"
    assert len(text) >= 8000, len(text)
    assert not re.search(r"lorem|TODO|TBD|\.\.\.$", text, re.I | re.M), "placeholder"
elif task == "t6-big-rewrite":
    import pathlib
    orig = (pathlib.Path(__file__).parent / "fixtures/docs/install-guide.md").read_text()
    text = read("docs/install-guide.md")
    assert text.splitlines()[0] == orig.splitlines()[0], text[:40]
    heads = lambda t: re.findall(r"^## (.+)$", t, re.M)
    assert heads(text) == heads(orig), heads(text)
    for block in re.findall(r"^```.*?^```", orig, re.M | re.S):
        assert block in text, f"code block changed: {block[:40]}"
    for url in re.findall(r"https://\S+[^.\s]", orig):
        assert url in text, f"lost {url}"
    assert len(text) <= 0.6 * len(orig), f"{len(text)} > 60% of {len(orig)}"
    low = text.lower()
    for filler in ("it should be noted", "basically", "in order to", "it is important to note",
                   "as a matter of fact", "needless to say", "actually", "whatsoever"):
        assert filler not in low, filler
else:
    sys.exit(f"unknown task {task}")
print("correct")
