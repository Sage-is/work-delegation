#!/usr/bin/env python3
"""delegate ledger — review and manage every delegation the wrapper has logged.

One Flask module. The ledger file (~/.local/state/delegate/log.jsonl) is read
on every request, so the row a delegation appended a second ago is already on
the page; nothing is imported and nothing goes stale. Stars, tags, and notes
live beside it in marks.db, keyed by a content hash of the row, so they survive
the ledger being moved or rewritten.

Run:   python3 app/ledger.py            (or: make ledger)
Env:   DELEGATE_LOG           ledger path (default ~/.local/state/delegate/log.jsonl)
       DELEGATE_MARKS         marks db   (default ~/.local/state/delegate/marks.db)
       DELEGATE_LEDGER_PORT   port       (default 5077, bound to 127.0.0.1 only)
       DELEGATE_LEDGER_LIVE   seconds between live checks (default 15; 0 = off)
"""
from __future__ import annotations

import hashlib
import json
import os
import shlex
import sqlite3
import statistics
from collections import Counter, defaultdict
from datetime import datetime

from flask import (Flask, Response, abort, g, jsonify, redirect, render_template,
                   request, url_for)

PAGE = 50

app = Flask(__name__, static_folder="static", template_folder="templates")
app.config.update(
    LEDGER=os.environ.get("DELEGATE_LOG") or os.path.expanduser("~/.local/state/delegate/log.jsonl"),
    MARKS=os.path.abspath(os.environ.get("DELEGATE_MARKS") or os.path.expanduser("~/.local/state/delegate/marks.db")),
    LIVE=max(int(os.environ.get("DELEGATE_LEDGER_LIVE") or 15), 0),
    # The app binds to 127.0.0.1, and a page on a rebinding hostname must not
    # count as same-origin to the browser: refuse every other Host header.
    TRUSTED_HOSTS=["127.0.0.1", "localhost"],
)


# ── rows ────────────────────────────────────────────────────────────────────

def row_id(r: dict) -> str:
    """Stable id from the fields that make a run what it was. rc and duration are
    in the key so a retry logged in the same second gets its own id."""
    key = "|".join(str(r.get(k) or "") for k in ("ts", "dir", "model", "instruction", "rc", "duration_s"))
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]


def load_rows() -> list[dict]:
    rows = []
    try:
        with open(app.config["LEDGER"], encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh):
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(r, dict):
                    continue
                for k in ("ts", "dir", "model"):
                    r[k] = str(r.get(k) or "")
                r["files"] = [str(f) for f in (r.get("files") or []) if f]
                r["id"] = row_id(r)
                r["line"] = n + 1
                r["lane_or_model"] = r.get("lane") or r.get("model") or ""
                r["brief"] = r.get("instruction") or ""
                rows.append(r)
    except OSError:
        pass
    rows.sort(key=lambda r: r.get("ts") or "", reverse=True)  # newest first, whatever the file order
    return rows


def matches(r: dict, f: dict, mark: dict) -> bool:
    if f["q"]:
        hay = " ".join([r["brief"], r.get("dir") or "", r["lane_or_model"], r.get("model") or "",
                        r.get("diff_stat") or "", " ".join(r.get("files") or []),
                        mark.get("tags") or "", mark.get("note") or ""]).lower()
        if any(term not in hay for term in f["q"].lower().split()):
            return False
    if f["rc"] != "" and str(r.get("rc")) != f["rc"]:
        return False
    if f["backend"] and (r.get("backend") or "opencode") != f["backend"]:
        return False
    if f["lane"]:
        # A lane segment, not a prefix: "opencode" must not match "opencode-go/…".
        seg = f["lane"].rstrip("/") + "/"
        if not (r["lane_or_model"].startswith(seg) or r["model"].startswith(seg)
                or f["lane"] in (r["lane_or_model"], r["model"])):
            return False
    if f["dir"]:
        d = r["dir"]
        if f["dir"].startswith("/"):
            if d != f["dir"].rstrip("/") and not d.startswith(f["dir"].rstrip("/") + "/"):
                return False
        elif f["dir"] not in d:
            return False
    if f["starred"] and not mark.get("starred"):
        return False
    if f["tag"] and f["tag"] not in (mark.get("tags") or "").split():
        return False
    ts = (r.get("ts") or "")[:10]
    if f["since"] and ts < f["since"]:
        return False
    if f["until"] and ts > f["until"]:
        return False
    return True


def filters() -> dict:
    a = request.args
    return {k: (a.get(k) or "").strip() for k in
            ("q", "rc", "backend", "lane", "dir", "tag", "since", "until")} | {
        "starred": a.get("starred") == "1"}


# ── marks ───────────────────────────────────────────────────────────────────

def db() -> sqlite3.Connection:
    if "db" not in g:
        os.makedirs(os.path.dirname(os.path.abspath(app.config["MARKS"])), exist_ok=True)
        g.db = sqlite3.connect(app.config["MARKS"])
        g.db.row_factory = sqlite3.Row
        g.db.execute("""CREATE TABLE IF NOT EXISTS marks (
            id TEXT PRIMARY KEY, starred INTEGER NOT NULL DEFAULT 0,
            tags TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '',
            updated TEXT NOT NULL DEFAULT '')""")
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def all_marks() -> dict[str, dict]:
    return {m["id"]: dict(m) for m in db().execute("SELECT * FROM marks")}


def set_mark(rid: str, **fields) -> None:
    cur = db().execute("SELECT * FROM marks WHERE id = ?", (rid,)).fetchone()
    m = dict(cur) if cur else {"id": rid, "starred": 0, "tags": "", "note": ""}
    m.update(fields)
    m["updated"] = datetime.now().isoformat(timespec="seconds")
    db().execute("INSERT OR REPLACE INTO marks (id, starred, tags, note, updated) VALUES (?,?,?,?,?)",
                 (rid, int(m["starred"]), m["tags"], m["note"], m["updated"]))
    db().commit()


def same_site() -> bool:
    """POSTs come from this page or nowhere: a cross-site form must not star rows."""
    return request.headers.get("Sec-Fetch-Site", "same-origin") in ("same-origin", "none")


def local_next(default: str) -> str:
    """A redirect target is a path on this app or it is ignored."""
    n = request.form.get("next") or ""
    return n if n.startswith("/") and not n.startswith("//") else default


def page_url(**changes) -> str:
    """The current list URL with some query fields changed; drops empties."""
    args = request.args.to_dict() | changes
    return url_for("index", **{k: v for k, v in args.items() if v not in ("", None)})


# ── views ───────────────────────────────────────────────────────────────────

def rerun_command(r: dict) -> str:
    parts = ["delegate-edit", r.get("dir") or ".", r.get("model") or "", r["brief"]] + list(r.get("files") or [])
    return " ".join(shlex.quote(p) for p in parts)


@app.context_processor
def inject():
    return {"live": app.config["LIVE"], "rerun_command": rerun_command, "page_url": page_url}


@app.get("/")
def index():
    rows, marks, f = load_rows(), all_marks(), filters()
    hits = [r for r in rows if matches(r, f, marks.get(r["id"], {}))]
    pages = max((len(hits) + PAGE - 1) // PAGE, 1)
    page = min(max(request.args.get("page", 1, type=int) or 1, 1), pages)
    shown = hits[(page - 1) * PAGE: page * PAGE]
    lanes = sorted({r["lane_or_model"].split("/")[0] for r in rows if r["lane_or_model"]})
    tags = Counter(t for m in marks.values() for t in (m["tags"] or "").split())
    return render_template("list.html", rows=shown, marks=marks, f=f, total=len(rows),
                           hits=len(hits), page=page, pages=pages,
                           lanes=lanes, tags=tags.most_common(12), newest=rows[0]["ts"] if rows else None)


@app.get("/m/<rid>")
def detail(rid):
    r = next((r for r in load_rows() if r["id"] == rid), None) or abort(404)
    return render_template("detail.html", r=r, m=all_marks().get(rid, {}))


@app.post("/m/<rid>/star")
def star(rid):
    same_site() or abort(403)
    m = all_marks().get(rid, {})
    set_mark(rid, starred=0 if m.get("starred") else 1)
    return redirect(local_next(url_for("detail", rid=rid)))


@app.post("/m/<rid>/note")
def note(rid):
    same_site() or abort(403)
    tags = " ".join(t.strip("#,") for t in (request.form.get("tags") or "").split() if t.strip("#,"))
    set_mark(rid, tags=tags, note=(request.form.get("note") or "").strip())
    return redirect(url_for("detail", rid=rid))


@app.get("/stats")
def stats():
    rows = load_rows()
    by = defaultdict(list)
    for r in rows:
        by[r["lane_or_model"] or "?"].append(r)
    table = []
    for lane, rs in sorted(by.items(), key=lambda kv: -len(kv[1])):
        # rc 0 past an hour is a wedge filed as a win (ledger 2026-08-21); it is
        # neither a success nor a timing sample.
        ok = [r for r in rs if r.get("rc") == 0 and not (isinstance(r.get("duration_s"), int) and r["duration_s"] >= 3600)]
        secs = [r["duration_s"] for r in ok if isinstance(r.get("duration_s"), int) and not isinstance(r.get("duration_s"), bool)]
        table.append({"lane": lane, "runs": len(rs), "ok": len(ok),
                      "rate": round(100 * len(ok) / len(rs)) if rs else 0,
                      "median_s": int(statistics.median(secs)) if secs else None,
                      "cost": round(sum(r.get("cost_usd") or 0 for r in rs), 4)})
    rcs = Counter(r.get("rc") for r in rows)
    briefs = [r.get("brief_chars") or len(r["brief"]) for r in rows[:50]]
    return render_template("stats.html", table=table, rcs=sorted(rcs.items(), key=lambda kv: str(kv[0])),
                           total=len(rows), brief_median=int(statistics.median(briefs)) if briefs else 0,
                           starred=sum(1 for m in all_marks().values() if m["starred"]))


@app.get("/status")
def status():
    rows = load_rows()
    return jsonify(rows=len(rows), newest=rows[0]["ts"] if rows else None)


@app.get("/export.jsonl")
def export():
    rows, marks, f = load_rows(), all_marks(), filters()
    hits = [r for r in rows if matches(r, f, marks.get(r["id"], {}))]
    body = "".join(json.dumps({k: v for k, v in r.items() if k not in ("line", "lane_or_model", "brief")}
                              | {"mark": marks.get(r["id"])}, ensure_ascii=False) + "\n" for r in hits)
    return Response(body, mimetype="application/x-ndjson",
                    headers={"Content-Disposition": "attachment; filename=delegations.jsonl"})


if __name__ == "__main__":
    port = int(os.environ.get("DELEGATE_LEDGER_PORT") or 5077)
    print(f"delegate ledger: http://127.0.0.1:{port}  ledger={app.config['LEDGER']}  marks={app.config['MARKS']}")
    app.run(host="127.0.0.1", port=port, debug=False)
