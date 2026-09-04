---
description: Delegate a file edit to a cheaper model via delegate-edit; review the diff before done.
---

Delegate the requested file edit to a cheaper model through the delegate-edit wrapper instead of editing directly. You stay the reviewer.

1. Write a brief: target files (in-place or new), the exact change enumerated, style rules spelled out, and what must not change. Keep it under ~2000 chars: outcomes and invariants, not every element and property. Point the delegate at a reference file in the project for conventions (local reads are allowed) instead of transcribing them. One artifact per run; independent artifacts are separate runs and may run at the same time when each names its own files.
   To create a file, name the new path as a trailing arg (the wrapper seeds it) or say "create `<path>`" in the brief. The run prints a `--- created ---` list and records intent-to-add so the new file appears in your diff.
2. Run. Lanes are tried in order; a lane that fails before editing hands off to the next one in seconds:

   ```sh
   ~/bin/delegate-edit <project-dir> go/deepseek-v4-flash,go/kimi-k3,zen/big-pickle "<brief>" <files...>
   ```

   `ollama/<model>` runs offline; `claude/<model>` hands the job to Claude Code with Read, Edit, and Write only.
3. Read the full git diff, created files included. Never trust the edit blind.
4. Wrong diff? One retry with a sharper brief. Still wrong? Revert and edit inline: `git checkout -- <file>` for an edit, `git reset -- <file> && rm <file>` for a creation.
5. Report done only after the diff passes review.

Never delegate load-bearing logic, small edits, or hardlinked files. Exit 6 is a timeout and exit 1 a failed backend: both print the diff stat, so read the diff before editing inline. Exit 2 means no lane was usable. Exit 9 means the wrapper wedged: edit inline and report it. DELEGATE=0 disables delegation entirely.
