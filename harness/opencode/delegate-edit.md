---
description: Delegate a file edit to a cheap model via oc-edit; review the diff before done.
---

Delegate the requested file edit to a cheap model through the oc-edit wrapper instead of editing directly. You stay the reviewer.

1. Write a brief: target files (in-place or new), the exact change enumerated, style rules spelled out, and what must not change. Keep it under ~2000 chars: outcomes and invariants, not every element and property — that cancels the savings. Point the delegate at a reference file in the project for conventions (local reads are allowed) instead of transcribing them. The wrapper warns past 2000 chars and refuses past 3500 (exit 8) — measured: every brief that long has stalled or errored, and a brief that long means you typed the artifact yourself. One artifact per run.
   To create a file, name the new path as a trailing arg after the brief (the wrapper seeds it) or say "create `<path>`" in the brief. The run prints a `--- created ---` list and records intent-to-add so the new file appears in your diff.
2. Run:

   ```sh
   ~/bin/oc-edit <project-dir> opencode/deepseek-v4-flash-free "<brief>"
   ```

3. Read the full git diff, created files included. Never trust the edit blind.
4. Wrong diff? One retry by re-instructing the same session with `-s <sessionID>`. Still wrong? Revert and edit inline — `git checkout -- <file>` for an edit, `git reset -- <file> && rm <file>` for a creation.
5. Report done only after the diff passes review.

Never delegate load-bearing logic, small edits, or hardlinked files. Exit 6 is a stall and exit 7 is a busy lock — edit inline instead of retrying into either. OC_DELEGATE=0 disables delegation entirely.
