# Delegate this edit

Delegate the requested file edit to a cheap model instead of typing it
yourself. You stay the reviewer.

1. Write a brief. Name the target files and say in-place or new file.
   Enumerate the exact change. Spell out style rules. State what must
   not change.
2. Run the wrapper:

   ```sh
   ~/bin/oc-edit <project-dir> opencode/deepseek-v4-flash-free "<brief>"
   ```

3. Read the full `git diff` in the project. Do not trust the edit blind.
4. Wrong diff? One retry: re-instruct the same session with
   `opencode run -s <sessionID> "fix: ..." --dir <project-dir> -m <model> --auto`.
   Still wrong? Revert the file and edit inline yourself.
5. Report done only after the diff passes your review.

Do not delegate load-bearing logic, small edits, or hardlinked files.
`OC_DELEGATE=0` disables delegation; when it is set, edit directly.
