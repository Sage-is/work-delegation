"""The admin app against a temporary ledger and marks db: run with
python3 -m unittest app/test_admin.py (make test does)."""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import admin as ledger  # noqa: E402

ROWS = [
    {"ts": "2026-09-01T07:00:00+0000", "dir": "/tmp/alpha-sibling", "model": "opencode-go/kimi-k3", "files": [],
     "instruction": "Sibling dir and colliding lane prefix", "brief_chars": 38, "rc": 0, "duration_s": 5,
     "diff_stat": "1 file changed", "session": "ghi", "retries": 0},
    {"ts": "2026-09-04T10:00:00+0000", "dir": "/tmp/alpha", "model": "go/deepseek-v4-flash", "backend": "api",
     "lane": "go/deepseek-v4-flash", "lanes_skipped": ["zen/big-pickle: HTTP 429"], "files": ["/tmp/alpha/notes.md"],
     "instruction": "Edit notes.md: add a Rules section with three bullets", "brief_chars": 57, "rc": 0,
     "turns": 3, "tokens_in": 2670, "tokens_out": 283, "cost_usd": None, "duration_s": 10,
     "diff_stat": "1 file changed, 6 insertions(+)", "session": "abc", "retries": 0, "wedged": None,
     "created": ["/tmp/alpha/new.md"], "run_id": "20260904T100000-1", "diff_file": "PATCH"},
    {"ts": "2026-09-03T12:00:00+0000", "dir": "/tmp/beta", "model": "go/kimi-k3,zen/big-pickle", "backend": "api",
     "lane": None, "lanes_skipped": ["go/kimi-k3: HTTP 500", "zen/big-pickle: HTTP 429"], "files": [],
     "instruction": "Failed before any edit", "brief_chars": 22, "rc": 2, "duration_s": 3, "diff_stat": None},
    {"ts": "2026-09-03T09:00:00+0000", "dir": "/tmp/beta", "model": "opencode/big-pickle", "files": [],
     "instruction": "Write the <script>alert(1)</script> guide", "brief_chars": 40, "rc": 6, "duration_s": 257,
     "diff_stat": None, "session": None, "retries": 1},
    {"ts": "2026-09-02T08:00:00+0000", "dir": "/tmp/alpha", "model": "claude/haiku", "backend": "claude",
     "lane": "claude/haiku", "files": ["/tmp/alpha/guide.md"], "instruction": "Add a Setup section",
     "brief_chars": 19, "rc": 0, "turns": 4, "cost_usd": 0.0354, "duration_s": 23,
     "diff_stat": "1 file changed, 6 insertions(+)", "session": "def", "retries": 0},
]


class LedgerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.log = os.path.join(self.tmp.name, "log.jsonl")
        self.patch = os.path.join(self.tmp.name, "diffs", "20260904T100000-1.patch")
        os.makedirs(os.path.dirname(self.patch))
        with open(self.patch, "w", encoding="utf-8") as fh:
            fh.write("diff --git a/notes.md b/notes.md\n--- a/notes.md\n+++ b/notes.md\n@@ -1,3 +1,9 @@\n # Notes\n+\n+## Rules\n+- Start on time.\n")
        with open(self.log, "w", encoding="utf-8") as fh:
            for r in ROWS:
                fh.write(json.dumps({**r, "diff_file": self.patch} if r.get("diff_file") == "PATCH" else r) + "\n")
            fh.write("not json\n")
            fh.write("null\n")
            fh.write("[1, 2]\n")
        ledger.app.config.update(LEDGER=self.log, MARKS=os.path.join(self.tmp.name, "marks.db"),
                                 LIVE=15, TESTING=True)
        self.c = ledger.app.test_client()
        self.ids = [ledger.row_id(r) for r in ROWS]

    def tearDown(self):
        self.tmp.cleanup()

    def test_list_newest_first_and_skips_bad_lines(self):
        html = self.c.get("/").get_data(as_text=True)
        self.assertIn("5 of 5 runs", html)
        self.assertLess(html.index("2026-09-04"), html.index("2026-09-02"))

    def test_brief_is_escaped(self):
        html = self.c.get("/").get_data(as_text=True)
        self.assertNotIn("<script>alert", html)
        self.assertIn("&lt;script&gt;", html)

    def test_filters(self):
        self.assertIn("1 of 5", self.c.get("/?q=rules+section").get_data(as_text=True))
        self.assertIn("3 of 5", self.c.get("/?rc=0").get_data(as_text=True))
        self.assertIn("1 of 5", self.c.get("/?lane=claude").get_data(as_text=True))
        self.assertIn("1 of 5", self.c.get("/?backend=claude").get_data(as_text=True))
        self.assertIn("3 of 5", self.c.get("/?dir=alpha").get_data(as_text=True))
        self.assertIn("1 of 5", self.c.get("/?since=2026-09-04").get_data(as_text=True))
        self.assertIn("0 of 5", self.c.get("/?starred=1").get_data(as_text=True))

    def test_lane_is_a_segment_not_a_prefix(self):
        self.assertIn("1 of 5", self.c.get("/?lane=opencode").get_data(as_text=True))
        self.assertIn("1 of 5", self.c.get("/?lane=opencode-go").get_data(as_text=True))

    def test_absolute_dir_is_a_path_prefix(self):
        self.assertIn("2 of 5", self.c.get("/?dir=/tmp/alpha").get_data(as_text=True))
        self.assertIn("1 of 5", self.c.get("/?dir=/tmp/alpha-sibling").get_data(as_text=True))

    def test_bad_page_and_bad_lines_do_not_500(self):
        for u in ("/?page=abc", "/?page=0", "/?page=99", "/status"):
            self.assertEqual(self.c.get(u).status_code, 200, u)

    def test_next_must_be_local(self):
        rid = self.ids[1]
        r = self.c.post(f"/m/{rid}/star", data={"next": "https://evil.example/"})
        self.assertEqual(r.headers["Location"].split("?")[0], f"/m/{rid}")
        r = self.c.post(f"/m/{rid}/star", data={"next": "//evil.example/"})
        self.assertEqual(r.headers["Location"].split("?")[0], f"/m/{rid}")

    def test_untrusted_host_refused(self):
        self.assertEqual(self.c.get("/", headers={"Host": "attacker.example:5077"}).status_code, 400)

    def test_every_token_and_prop_exists_in_the_vendored_css(self):
        """The startr.style build we ship defines the tokens and props the pages use."""
        import re
        css = open(os.path.join(os.path.dirname(__file__), "static", "vendor", "startr.style", "style.css"),
                   encoding="utf-8").read()
        pages = [self.c.get(u).get_data(as_text=True) for u in ("/", f"/m/{self.ids[1]}", "/stats")]
        tokens = {t for p in pages for t in re.findall(r"var\(--([a-z0-9-]+)\)", p)}
        missing = sorted(t for t in tokens if f"--{t}:" not in css)
        self.assertEqual(missing, [], f"undefined tokens: {missing}")
        props = {m for p in pages for m in re.findall(r"--([a-z]+(?:-[a-z]+)*?)(?:-(?:sm|md|lg|xl))?:", p)}
        props -= tokens
        unknown = sorted(p for p in props if f'[style*="--{p}:"]' not in css and f'[style*="--{p}-md:"]' not in css)
        self.assertEqual(unknown, [], f"props with no rule: {unknown}")

    def test_star_persists_and_toggles(self):
        rid = self.ids[1]
        r = self.c.post(f"/m/{rid}/star", data={"next": "/?starred=1"})
        self.assertEqual(r.status_code, 302)
        self.assertIn("1 of 5", self.c.get("/?starred=1").get_data(as_text=True))
        self.assertIn('aria-pressed="true"', self.c.get(f"/m/{rid}").get_data(as_text=True))
        self.c.post(f"/m/{rid}/star")
        self.assertIn("0 of 5", self.c.get("/?starred=1").get_data(as_text=True))

    def test_note_and_tags_searchable(self):
        rid = self.ids[3]
        self.c.post(f"/m/{rid}/note", data={"tags": "#docs, keeper", "note": "the one to reuse"})
        html = self.c.get(f"/m/{rid}").get_data(as_text=True)
        self.assertIn('value="docs keeper"', html)
        self.assertIn("the one to reuse", html)
        self.assertIn("1 of 5", self.c.get("/?tag=keeper").get_data(as_text=True))
        self.assertIn("1 of 5", self.c.get("/?q=reuse").get_data(as_text=True))

    def test_detail_rerun_and_404(self):
        html = self.c.get(f"/m/{self.ids[1]}").get_data(as_text=True)
        self.assertIn("delegate-edit /tmp/alpha go/deepseek-v4-flash", html)
        self.assertIn("zen/big-pickle: HTTP 429", html)
        self.assertEqual(self.c.get("/m/nope").status_code, 404)

    def test_cross_site_post_refused(self):
        r = self.c.post(f"/m/{self.ids[1]}/star", headers={"Sec-Fetch-Site": "cross-site"})
        self.assertEqual(r.status_code, 403)

    def test_status_stats_export(self):
        s = self.c.get("/status").get_json()
        self.assertEqual((s["rows"], s["newest"]), (5, "2026-09-04T10:00:00+0000"))
        html = self.c.get("/stats").get_data(as_text=True)
        self.assertIn("go/deepseek-v4-flash", html)
        self.assertIn("rc 6", html)
        r = self.c.get("/export.jsonl?rc=0")
        self.assertEqual(r.mimetype, "application/x-ndjson")
        self.assertEqual(len(r.get_data(as_text=True).strip().splitlines()), 3)

    def test_diff_view_revert_and_files_on_rows(self):
        rid = self.ids[1]
        html = self.c.get(f"/m/{rid}").get_data(as_text=True)
        self.assertIn('<code>notes.md</code>', html)
        self.assertIn('class="add">+- Start on time.', html)
        self.assertIn("git -C /tmp/alpha checkout -- /tmp/alpha/notes.md", html)
        self.assertIn("git -C /tmp/alpha reset -- /tmp/alpha/new.md &amp;&amp; rm /tmp/alpha/new.md", html)
        self.assertIn("new.md, notes.md", self.c.get("/").get_data(as_text=True))
        os.remove(self.patch)
        self.assertIn("patch file for this run is gone", self.c.get(f"/m/{rid}").get_data(as_text=True))
        self.assertIn("No patch was recorded", self.c.get(f"/m/{self.ids[3]}").get_data(as_text=True))

    def test_stats_bucket_pre_edit_failures_as_no_lane(self):
        html = self.c.get("/stats").get_data(as_text=True)
        self.assertIn("no lane", html)
        self.assertNotIn("go/kimi-k3,zen/big-pickle", html)

    def test_live_toggle_reflects_config(self):
        self.assertIn('data-interval="15"', self.c.get("/").get_data(as_text=True))


if __name__ == "__main__":
    unittest.main()
