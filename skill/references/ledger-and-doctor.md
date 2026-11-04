# delegate-edit: ledger and doctor

## Ledger and doctor

Every run (success or failure) appends one JSON line to
`~/.local/state/delegate/log.jsonl`: timestamp, run_id, dir, model, backend,
lane, lanes_skipped, files, created, the full instruction, exit code, session,
retries, turns, tokens_in, tokens_out, cost_usd and cost_source ("provider"
when billed, "catalogue" for a list-price estimate), protocol, trace (one
line per tool call: turn, tool, path, ok or the error the model saw),
duration, diff stat, and diff_file, the run's patch saved under `diffs/`
beside the ledger (1 MB cap).
`make admin` serves the ledger as a web page: search, filter, star, tag, note,
the diff per run, re-run and revert commands, and stats per lane.
`DELEGATE_LOG=<path>` moves it; `DELEGATE_LOG=0` disables it. Failure records
are the routing evidence; do not disable the ledger to "clean up" output.

`delegate-edit --doctor` (or `make doctor`) verifies a machine: delegate-edit
and delegate-agent on PATH, GNU timeout present, skill installed, hook
registered, kill switch off, ledger writable, lock free. It lists which lanes
have keys that resolve and gateways that answer. It also reports brief
economy: the median brief size over the last 50 runs, how many exceeded 2000
chars, and how many files were created. A rising median means delegation has
drifted back into dictation.

`delegate-cost` (or `make cost SINCE=YYYY-MM-DD`) reads the Claude Code
transcripts and the ledger: where the orchestrator's input cost goes (prefix,
tool results by tool, attachments, cache re-reads), what large file reads
cost, and what delegation saved by output size. Measure with it before
building a new delegation verb. `make unmeasured` lists catalogue models no
matrix has scored yet.
