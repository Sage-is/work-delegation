#!/usr/bin/env bash
# PreToolUse hook (Edit|Write): nudge large prose/python generations toward
# opencode delegation. Opt-in: inert unless DELEGATE_ENFORCE=1.
# DELEGATE stays the wrapper kill switch; the two are independent —
# DELEGATE=0 must never be required to bypass this hook.
#
# Registered globally (2026-08-16) in ~/.claude/settings.json:
#   "hooks": { "PreToolUse": [ { "matcher": "Edit|Write",
#     "hooks": [ { "type": "command", "command": "bash ~/.claude/skills/delegate-edit/scripts/delegate-hook.sh" } ] } ] }
# with "env": { "DELEGATE_ENFORCE": "1" } to arm it.
#
# Variant: deny-with-feedback only. The transparent-rewrite variant (hook runs
# the delegate itself and reports success) is rejected: it breaks the review
# loop — the orchestrator would believe its own text was written when a
# different model's was.
#
# Outage fallback: when the ledger's last row is a stall (rc 6) or a wedge (rc 9)
# younger than 30 minutes, the evidence that delegation is failing right now is
# already on disk, so the hook allows the direct edit with a reason instead of
# sending the contributor to read SKILL.md mid-outage (TODO 2026-09-02).
set -euo pipefail

[ "${DELEGATE_ENFORCE:-0}" = "1" ] || exit 0   # inert unless opted in
[ "${DELEGATE_NESTED:-0}" = "1" ] && exit 0    # the typist under claude/: never bounce it

payload=$(cat)

decision=$(DELEGATE_PAYLOAD="$payload" DELEGATE_HOOK_LOG="${DELEGATE_LOG:-$HOME/.local/state/delegate/log.jsonl}" python3 - <<'PY'
import json, os, time
from datetime import datetime

MIN_CHARS = 2000  # below this, delegation overhead exceeds savings
OUTAGE_WINDOW_S = 30 * 60


def recent_failure():
    """The last ledger row, if it is a stall or wedge inside the outage window."""
    path = os.environ.get("DELEGATE_HOOK_LOG") or ""
    try:
        with open(path, "rb") as fh:
            fh.seek(0, 2)
            size = fh.tell()
            fh.seek(max(size - 65536, 0))
            lines = fh.read().decode("utf-8", errors="replace").splitlines()
        row = json.loads(lines[-1])
        if row.get("rc") not in (6, 9):
            return None
        ts = datetime.strptime(row["ts"], "%Y-%m-%dT%H:%M:%S%z").timestamp()
        return row if time.time() - ts < OUTAGE_WINDOW_S else None
    except Exception:
        return None


data = json.loads(os.environ["DELEGATE_PAYLOAD"])
tool = data.get("tool_name", "")
ti = data.get("tool_input", {})
path = ti.get("file_path", "")
content = ti.get("content", "") if tool == "Write" else ti.get("new_string", "")

delegable = path.endswith((".md", ".py", ".txt", ".rst"))
big = len(content) >= MIN_CHARS
plan_file = "/plans/" in path or "/memory/" in path or "/.claude/" in path

if delegable and big and not plan_file and (row := recent_failure()):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": (
                f"DELEGATE: direct edit permitted — the last delegation ({row.get('model')}) "
                f"failed with rc={row.get('rc')} at {row.get('ts')}; delegation is failing "
                "per the ledger."
            ),
        }
    }))
elif delegable and big and not plan_file:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                f"DELEGATE: this {len(content)}-char generation to {path} "
                "should be delegated. Write a brief and run delegate-edit "
                "(see /delegate-edit skill), then review the diff. "
                "To force a direct edit, retry after DELEGATE_ENFORCE=0."
            ),
        }
    }))
PY
)

[ -n "$decision" ] && printf '%s\n' "$decision"
exit 0
