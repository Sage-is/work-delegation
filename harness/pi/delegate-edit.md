---
description: Delegate a file edit to a cheaper model via delegate-edit; review the diff before done.
argument-hint: [what to change, and in which files]
---

Delegate this file edit to a cheaper model through the delegate-edit wrapper instead of typing it yourself. You stay the reviewer.

Request: $ARGUMENTS

1. Write a brief. Name the target files and say in-place or new file. Enumerate the exact change. Spell out style rules. State what must not change. Under ~2000 chars: outcomes and invariants, not every element and property. For conventions, point the delegate at a reference file in the project instead of transcribing it. One artifact per run; independent artifacts are separate runs, and they may run at the same time as long as each names its own files.
2. Run the wrapper. Lanes are tried in order; a lane that fails before editing hands off to the next one in seconds:

   ```sh
   ~/bin/delegate-edit <project-dir> go/deepseek-v4-flash,go/kimi-k3,zen/big-pickle "<brief>" <files...>
   ```

   `ollama/<model>` runs offline on this machine; `claude/<model>` hands the job to Claude Code with Read, Edit, and Write only.
3. Read the full git diff in the project, created files included. Do not trust the edit blind.
4. Wrong diff? One retry with a sharper brief. Still wrong? Revert and edit inline: `git checkout -- <file>` for an edit, `git reset -- <file> && rm <file>` for a creation.
5. Report done only after the diff passes your review.

Do not delegate load-bearing logic, small edits, or hardlinked files. Exit 6 is a timeout and exit 1 a failed backend: both print the diff stat, because a failed run can still have landed an edit, so read the diff before editing inline. Exit 2 means no lane was usable (key, model, or gateway). Exit 9 means the wrapper wedged: edit inline and report it. DELEGATE=0 disables delegation; when it is set, edit directly.
