# How work-delegation works

## The wrapper

```sh
oc-edit <dir> <model> "<instruction>" [files...]
```

Underneath, the wrapper runs:

```sh
opencode run --dir <dir> -m <model> --auto --format json
```

It attaches any listed files to the message, prints the opencode session id,
and shows a diff stat of what changed. Exit codes:

| Code | Meaning |
|------|---------|
| 1 | opencode failed |
| 2 | usage error |
| 3 | delegation disabled via `OC_DELEGATE=0` |
| 4 | hardlink guard refused a target |
| 5 | silent no-op: the model changed nothing |

## The permission layer

The wrapper exports `OPENCODE_PERMISSION`, a JSON policy for the delegated
session. It denies git commands, `rm -rf`, nested opencode calls, web fetch,
and web search. Other bash commands stay allowed so the model can inspect its
work. One trap: the LAST matching rule wins. The wildcard allow rule must come
first and the deny rules after it, or the denies never fire.

## The hardlink guard

Editors write a new file and replace the inode. That silently severs a
hardlinked pair: the other name keeps the old content. The wrapper checks the
link count of every target and refuses any file with more than one link
(exit 4). Edit those files by hand with an inode-preserving method.

## The brief format

A good brief leaves no room for taste:

1. Name the target files. Say in-place edit or new file.
2. Enumerate the exact change. No "improve" verbs.
3. Spell out the style rules.
4. State what must not change.

## The review loop

The orchestrator reads the full diff before anything counts as done. If the
diff is wrong, one retry: re-instruct the same opencode session with
`-s <sessionID>` so its context survives. If the retry misses too, revert the
file and edit inline. Delegation earns its keep on bulk typing, not on
back-and-forth.

## The optional hook

An opt-in PreToolUse hook for Claude Code denies large prose or Python
generations with a message that points to delegation. It stays inert unless
the session sets `OC_DELEGATE=1`. A transparent-rewrite variant, where the
hook would call opencode itself and report success, was rejected: the
orchestrator must never believe it wrote text another model produced.
