# work-delegation

![Art Deco travel poster: a small tugboat at full steam tows a great ocean liner across calm water at sunrise. Caption: work delegation — expensive models plan and judge, cheap models type.](docs/art/hero.svg)

Expensive AI models should plan and judge. Cheap models should tug and type.

A toolkit from Sage.is (AGPL-3.0). It lets a slower, more expensive, but smarter orchestrating AI assistant (Claude Code, Codex, opencode, Pi, or similar) hand typing work to cheaper models. The assistant writes a precise work order, called a brief. A small wrapper called delegate-edit hands it to a cheaper model over a direct API call, with five file tools and no shell, and tries the next lane in seconds when one fails. The assistant reviews the resulting git diff before anything counts as done.

## Why

Generating file content is the expensive part of an AI coding session. Reading a diff costs less than writing the file. You keep the judgment on the expensive model and push the typing down to a free tier.

## The numbers

On 2026-08-15 we ran our matrix of 8 tasks across 4 types through delegate-edit against a sandbox git repo. Every diff was reviewed line by line. Both logic fixes were verified with assertions.

Working with the free tier (opencode/deepseek-v4-flash-free): 4/4 correct, zero retries, at 7-15 seconds per task, cost zero.

With the paid tier (opencode-go/kimi-k3): 4/4 correct, zero retries, 38-70 seconds per task, cost in cents!

Quality matched at this task size. The free tier wins on speed and cost. Default routing is free first, with kimi-k3 for retries only. Other models can easily be switched to for strengths and privacy.

The gateway retired `deepseek-v4-flash-free` on 2026-08-21, and the opencode CLI stalled on about half of all runs after that. On 2026-09-04 the same four tasks ran again through direct API lanes (`make matrix`, results in `results/matrix-2026-09-04.md`): `go/kimi-k3` 4/4 at 6-38s, `go/deepseek-v4-flash` 3/4 at 7-13s, `claude/sonnet` 4/4 at 18-22s for about 10 cents a task, `ollama/qwen3.5:9b` offline 2/4. The free Zen lane was rate-limited all day and hopped in one second. Run `delegate-edit --doctor` for the lanes this machine can reach today.

## How it works

```text
┌──────────────────┐    brief    ┌──────────────────┐
│    THE LINER     │ ──────────▶ │     THE TUG      │
│  expensive model │             │  cheap or free   │
│  plans and judges│ ◀────────── │  model, types    │
└──────────────────┘    diff     └──────────────────┘
```

The loop has four steps:

1. You write a brief. It names the target files, the exact change, the style rules, and what must not change. It states outcomes and constraints; an oversized brief that dictates every detail cancels the savings.
2. delegate-edit hands the brief to the first lane in your list. A lane is a provider and a model: `zen/big-pickle`, `go/kimi-k3`, `nvidia/…`, `openrouter/…`, `ollama/…` for a local model, `claude/sonnet` for Claude Code itself, or an `opencode/…` model through the opencode CLI. A lane that fails before its first edit hands off to the next one in seconds.
3. The model works through five tools, read, write, edit, ls, and done, jailed to the project directory. No shell, no git, no network.
4. You read the full diff and review it before anything counts as done.

A hardlink guard refuses to touch files with more than one link; those need the inline tmp-file method. Direct lanes take no lock, so independent edits run at the same time when each names its own files.

Our DELEGATE=0 environment variable is the kill switch. It stops the wrapper, passes the hook through, and keeps this work in your hands. When it is set, your coding agent edits directly instead of handing off.

Every run writes one JSON line to ~/.local/state/delegate/log.jsonl: the brief, lane, lanes skipped, files, exit code, turns, tokens, cost, duration, and diff stat. Failures log too; that is the routing evidence. Setting DELEGATE_ENFORCE=1 arms a PreToolUse hook that bounces oversized direct edits toward delegation. Run delegate-edit --doctor (or make doctor) to verify a machine end to end.

## Install

```sh
make install
```

Installs the skill, the wrapper, and the harness prompts for Claude Code, Codex, opencode, and Pi.

```sh
make uninstall
```

Removes everything the install targets placed.

## Repository layout

- skill/  The canonical skill and its scripts
- harness/  Codex, opencode, and Pi adapters
- tests/  Four stub-backed suites and the repeatable matrix
- results/  Raw patches and logs, with RESULTS.md as the summary
- marketing/  Landing copy
- docs/

## License

AGPL-3.0. See the LICENSE file.
