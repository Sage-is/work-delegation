# Delegation experiment results — 2026-08-15

Matrix: 4 tasks × 2 model tiers, run through `scripts/oc-edit` against a
sandbox git repo. Every diff reviewed line-by-line in the Claude session.
Both t4 bug fixes verified with assertions (partial page, exact fit, empty).
Raw patches and logs in `results/`.

## Scoreboard

| Run | Correct | Time | Notes |
| --- | --- | --- | --- |
| t1 prose-gen free | yes | 15s | 40-line guide, all 3 required sections, house style held |
| t2 prose-rewrite free | yes | 7s | every filler phrase cut, all facts kept |
| t3 py-sweep free | yes | 9s | docstrings + import move, nothing else touched |
| t4 py-logic free | yes | 8s | idiomatic `range(0, len, step)` fix; assertions pass |
| t1 prose-gen paid (kimi-k3) | yes | 70s | slightly richer prose, no correctness edge |
| t2 prose-rewrite paid | yes | 51s | equivalent to free |
| t3 py-sweep paid | yes | 52s | correct; left `__pycache__` droppings (wrapper now sweeps them) |
| t4 py-logic paid | yes | 38s | ceil-division fix; assertions pass |

Free tier: 4/4, zero retries, 7-15s. Paid tier: 4/4, zero retries, 38-70s.
Cost: free tier $0; total opencode account spend over 4 days of all usage
is $0.34, so the paid runs cost cents.

## Verdict

- Quality parity at this task size; the free tier wins on speed and cost.
- Default routing: free first, `opencode-go/kimi-k3` for retries only.
- The win case is large generated output: Claude writes a ~10-line brief and
  reads a diff instead of generating 40+ lines of premium output tokens.
- Small logic edits stay inline; verification overhead cancels the savings.

## Guardrails proven in test

- `OPENCODE_PERMISSION` deny rules hold, but rule order matters:
  LAST matching rule wins. `{"*":"allow","git*":"deny"}` blocks git;
  the reverse order does not. Verified by forcing a `git log` attempt (DENIED).
- Hardlink guard fires (exit 4) on a 2-link fixture.
- `OC_DELEGATE=0` kill switch exits 3 without touching opencode.
- Hook (deny-with-feedback): inert without `OC_DELEGATE=1`; denies ≥2000-char
  `.md/.py/.txt/.rst` generations; passes small edits; exempts plan/memory/
  .claude paths. Transparent-rewrite variant REJECTED — it breaks the
  review loop (Claude would believe its own text was written).

## Field notes — 2026-08-16 (dogfooding run)

This repository's own prose was built through the wrapper. Findings:

- README.md and marketing/copy.md were delegated successfully to the free
  tier (one in-session retry fixed two weak lines of copy).
- Mid-session, the opencode gateway degraded: trivial probes returned in
  seconds while any substantive generation stalled indefinitely, on the free
  tier and on kimi-k3 alike. Per the review-loop rule, the remaining files
  were reverted to inline writing. Delegation needs this fallback; treat
  gateway stalls as expected weather, not as a wrapper bug.
- New deny rule: `opencode*`. A brief that quotes runnable opencode commands
  can tempt the model to spawn a nested opencode session that never returns.
- Wrapper fix: no-op detection now fingerprints untracked files too. Plain
  `git diff` misses edits to files that were never committed, which produced
  a false "silent no-op" on a real edit.

## Adoption menu (user decision — nothing below is active yet)

1. Promote `scripts/oc-edit` to `~/bin/oc-edit` — enables on-demand + skill use.
2. Optionally install `scripts/oc-delegate-hook.sh` as a PreToolUse hook on
   `Edit|Write` in `~/.claude/settings.json`; it stays inert unless a session
   sets `OC_DELEGATE=1`.
3. Full off at any time: `OC_DELEGATE=0` (wrapper refuses, hook passes through,
   skill instructs direct edits).
