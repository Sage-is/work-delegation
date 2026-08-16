---
description: Delegate a file edit to a cheap model via oc-edit; review the diff before done
---

Delegate the requested file edit to a cheap model through the oc-edit
wrapper instead of editing directly. You stay the reviewer.

1. Write a brief: target files (in-place or new), the exact change
   enumerated, style rules spelled out, and what must not change.
2. Run:

   ```sh
   ~/bin/oc-edit <project-dir> opencode/deepseek-v4-flash-free "<brief>"
   ```

3. Read the full `git diff`. Never trust the edit blind.
4. Wrong diff? One retry by re-instructing the same session with
   `-s <sessionID>`. Still wrong? Revert and edit inline.
5. Report done only after the diff passes review.

Never delegate load-bearing logic, small edits, or hardlinked files.
`OC_DELEGATE=0` disables delegation entirely.
