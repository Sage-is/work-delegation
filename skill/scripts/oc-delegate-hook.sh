#!/usr/bin/env bash
# PreToolUse hook (Edit|Write): nudge large prose/python generations toward
# opencode delegation. Opt-in: inert unless OC_DELEGATE_ENFORCE=1.
# OC_DELEGATE stays the wrapper kill switch; the two are independent —
# OC_DELEGATE=0 must never be required to bypass this hook.
#
# Registered globally (2026-08-16) in ~/.claude/settings.json:
#   "hooks": { "PreToolUse": [ { "matcher": "Edit|Write",
#     "hooks": [ { "type": "command", "command": "bash ~/.claude/skills/delegate-edit/scripts/oc-delegate-hook.sh" } ] } ] }
# with "env": { "OC_DELEGATE_ENFORCE": "1" } to arm it.
#
# Variant: deny-with-feedback only. The transparent-rewrite variant (hook runs
# opencode itself and reports success) is rejected: it breaks the review loop —
# Claude would believe its own text was written when a different model's was.
set -euo pipefail

[ "${OC_DELEGATE_ENFORCE:-0}" = "1" ] || exit 0   # inert unless opted in

payload=$(cat)

decision=$(OC_PAYLOAD="$payload" python3 - <<'PY'
import json, os

MIN_CHARS = 2000  # below this, delegation overhead exceeds savings

data = json.loads(os.environ["OC_PAYLOAD"])
tool = data.get("tool_name", "")
ti = data.get("tool_input", {})
path = ti.get("file_path", "")
content = ti.get("content", "") if tool == "Write" else ti.get("new_string", "")

delegable = path.endswith((".md", ".py", ".txt", ".rst"))
big = len(content) >= MIN_CHARS
plan_file = "/plans/" in path or "/memory/" in path or "/.claude/" in path

if delegable and big and not plan_file:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                f"OC_DELEGATE: this {len(content)}-char generation to {path} "
                "should be delegated. Write a brief and run oc-edit "
                "(see /delegate-edit skill), then review the diff. "
                "To force a direct edit, retry after OC_DELEGATE_ENFORCE=0."
            ),
        }
    }))
PY
)

[ -n "$decision" ] && printf '%s\n' "$decision"
exit 0
