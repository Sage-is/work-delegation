# Delegate this edit

Delegate the requested file edit to a cheap model instead of typing it yourself. You stay the reviewer.

1. Write a brief. Name the target files and say in-place or new file. Enumerate the exact change. Spell out style rules. State what must not change. Keep it under ~2000 chars: state outcomes and invariants, do not dictate every element and property — that cancels the savings. For conventions, point the delegate at a reference file in the project (it can read locally) instead of transcribing them. The wrapper warns past 2000 chars and refuses past 3500 (exit 8) — measured: every brief that long has stalled or errored, and a brief that long means you typed the artifact yourself. One artifact per run.
1b. Creating a file: name the new path as a trailing arg after the brief and the wrapper seeds it, or just say "create `<path>`" in the brief and let the delegate write it. Either way the run prints a `--- created ---` list and records intent-to-add so the new file shows up in your diff.
2. Run the wrapper:

   ```sh
   ~/bin/oc-edit <project-dir> opencode/deepseek-v4-flash-free "<brief>"
   ```

3. Read the full git diff in the project, created files included. Do not trust the edit blind.
4. Wrong diff? One retry: re-instruct the same session with `opencode run -s <sessionID> "fix: ..." --dir <project-dir> -m <model> --auto`. Still wrong? Revert and edit inline yourself — `git checkout -- <file>` for an edit, `git reset -- <file> && rm <file>` for a creation.
5. Report done only after the diff passes your review.

Do not delegate load-bearing logic, small edits, or hardlinked files. Exit 6 means a stall and exit 7 means another delegation holds the lock — in both cases edit inline rather than retrying into the problem. OC_DELEGATE=0 disables delegation; when it is set, edit directly.
