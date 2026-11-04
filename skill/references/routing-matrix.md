# delegate-edit: routing matrix

## Routing (matrix 2026-10-05)

Direct lanes run in order and stop at the first that answers. A list may end
in one `opencode/` lane: when every direct lane fails before editing, the
wrapper hands the brief to the opencode CLI. One list serves each tier:

- Go plan: `go/gpt-6-luna` answers over the Responses API, 6/6 on
  2026-10-05 (the four small tasks plus a 9-12 KB new file and an 11.6 KB
  rewrite), 5-56s, $0.0002-0.0031 a task at list price. It has no real-use
  record yet; the ledger will build one. `go/deepseek-v4.1-flash` is second:
  41/42 in real use from 2026-09-16, 8/10 across today's three runs (on t5
  it added a `## Contents` heading the brief ruled out). Go answers 400
  `MissingSessionID` without a stable `x-opencode-session`; the agent sends
  one per lane.
- Free, keyless: with no Go key the go/ lanes skip in milliseconds and
  `opencode/big-pickle` runs through the CLI with no key and no login, 4/4
  at 18-44s on 2026-09-13. Zen's free tier answers only inside OpenCode,
  which is why it is an `opencode/` lane. Free models may train on what you
  send, so never hand them client files. Offline and keyless:
  `ollama/<model>` before the tail, e.g.
  `ollama/qwen3.5:9b,opencode/big-pickle` (2/4 on 2026-09-04, a fallback).
- Zen API: opt in with your own list, e.g.
  `zen/deepseek-v4-flash,zen/minimax-m3,opencode/big-pickle`. Zen bills per
  request and auto-reloads $20, so no default spends it. Untested here: this
  machine has no Zen billing (401).

Also measured 2026-10-05 (`results/matrix-2026-10-05*.md`, one run per cell):
`go/glm-5.3-flash` 9/10 across the three runs, 7-18s on small tasks; `go/minimax-m3` 5/6; `go/hy4-preview` 6/6 but slow on long output
(144s, 10 turns); `go/grok-4.7` 4/4 at 25-130x the cost of gpt-6-luna;
`go/gpt-5.6-luna` 3/4; `go/mimo-v2.6-flash` 5/6, its t5 run looping on edits
to the 20-turn cap. `go/deepseek-v4-pro`, `go/qwen3.8-max`, `go/mimo-v2.6-pro`
4/4 on the small tasks only. Run `make unmeasured` for what no matrix has
scored, then `make matrix LANES=... TASKS=...`.

- `claude/haiku`: 5/6 at $0.03-0.07 a task. `claude/sonnet`: 5/6 at $0.10-0.14
  a task (its t5 page came in 1400 chars short). Use them when the cheap
  lanes botch the diff.
