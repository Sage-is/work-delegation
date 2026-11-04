# delegate-edit: wrapper internals

## The wrapper

The wrapper, whatever the backend:

- Seeds named-but-missing files as empty create targets (see Creating files)
- Prints a diff stat at the end, on failure too when there is anything to show
- Appends one ledger row per run
- Sweeps `__pycache__` the delegate left from verifying its own edit
- Detects a silent no-op (exit 5) and a wedge (exit 9)

## The tool jail

`delegate-agent` gives the model five tools: read, write, edit, ls, done.
There is no shell and no git. Every path must resolve under the project
directory. Hardlinked targets are refused, because editors replace inodes.
Edit requires its old text to match exactly once, so a vague match fails
instead of guessing. The run ends with done, or when the model stops
calling tools after touching a file.

## Creating files

delegate-edit creates files as well as edits them. Two ways, both supported:

- Name the new path as a trailing arg. The wrapper seeds it as an empty
  file (parent dirs included), and the preamble tells the delegate an
  empty named file is a new file to write in full. A seed the delegate
  never fills is removed again, on success and on failure alike.
- Or just say "create `<path>`" in the brief with no trailing arg, and
  let the delegate pick the path and write it.

New files are untracked, and `git diff` ignores untracked files, so a
created file would otherwise review as an empty diff. On success the
wrapper `git add -N`s every path that appeared during the run, so the
creation shows up in the reviewer's diff like any other change. The run
prints a `--- created ---` list and the exact `git reset --` undo.
`DELEGATE_NO_INDEX_ADD=1` skips the intent-to-add; review those files with
`cat` instead.

## Concurrent runs

Direct lanes take no lock. One artifact per run, and independent artifacts
run at the same time, each naming its files. The opencode path keeps the
machine-wide lock: a second opencode-path delegation waits up to
`DELEGATE_LOCK_WAIT` (default 90s), then exits 7.
