# work-delegation

Expensive AI models should plan and judge. Cheap models should type.

A toolkit from Sage.is (AGPL-3.0). It lets an expensive orchestrating AI assistant (Claude Code, Codex, opencode, or similar) hand file typing to a cheap or free model driven through opencode's CLI. The assistant writes a precise work order, called a brief. A small wrapper script called oc-edit passes it to opencode running headless. The assistant reviews the resulting git diff before anything counts as done.

## Why

Generating file content is the expensive part of an AI coding session. Reading a diff costs less than writing the file. You keep the judgment on the expensive model and push the typing down to a free tier. 

## The numbers

The 2026-08-15 matrix ran 8 tasks across 4 types through oc-edit against a sandbox git repo. Every diff was reviewed line by line. Both logic fixes were verified with assertions. 

Free tier (opencode/deepseek-v4-flash-free): 4/4 correct, zero retries, 7-15 seconds per task, cost zero.

Paid tier (opencode-go/kimi-k3): 4/4 correct, zero retries, 38-70 seconds per task, cost in cents.

Quality matched at this task size. The free tier wins on speed and cost. Default routing is free first, with kimi-k3 for retries only.

## How it works

The loop has four steps:

1. You write a brief. It names the target files, the exact change, the style rules, and what must not change.
2. oc-edit hands the brief to opencode running headless with a fixed model.
3. opencode edits the file and returns a diff.
4. You read the full diff and review it before anything counts as done.

A permission layer denies git commands, web fetch, and web search inside the delegated session, so a free model cannot rewrite history or wander off. A hardlink guard refuses to touch files with more than one link; those need the inline tmp-file method. The OC_DELEGATE=0 environment variable is the kill switch. It stops the wrapper, passes the hook through, and keeps this work in your hands. When it is set, edit directly.

## Install

```sh
make install
```

Installs the for Claude Code, Codex, Opencode..

```sh
make uninstall
```

Removes everything the install targets placed.

## Repository layout

- skill/  The canonical skill and its scripts
- harness/  Codex and opencode adapters
- results/  Raw patches and logs, with RESULTS.md as the summary
- marketing/  Landing copy
- docs/

## License

AGPL-3.0. See the LICENSE file.
