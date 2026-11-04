# delegate-edit: backends and lanes

## Backends and lanes

The first lane's prefix picks the backend:

- `zen/`, `go/`, `nvidia/`, `openrouter/`, `ollama/`, `api/`: direct API
  through `delegate-agent`, a small Python typist. Each model gets the
  protocol opencode's catalogue (`~/.cache/opencode/models.json`) names for
  it: OpenAI's Responses API for `@ai-sdk/openai` models (GPT, Grok and Muse
  on Go, which refuse chat with `ModelProtocolUnsupported`), chat completions
  for the rest. Every request streams. The catalogue's list prices fill
  `cost_usd` when the gateway reports none. The named files' contents go
  with the brief, so the model starts editing. Keys resolve from each
  provider's env var, or from opencode's auth.json for `zen/`, `go/`, and
  `nvidia/`. `DELEGATE_API_KEY` plus `DELEGATE_BASE_URL` drive the generic
  `api/` prefix. `ollama/` needs no key and works offline. `zen/` is paid Zen
  models only, key required; Zen's free models answer only inside OpenCode,
  so they run as `opencode/` lanes.
- `claude/<model>`: runs `claude -p` with only the Read, Edit, and Write
  tools, `--permission-mode acceptEdits`, and the `DELEGATE_MAX_USD` spend
  cap. No Bash.
- Anything else (`opencode/…`, `opencode-go/…`): `opencode run`, the
  original path, with the permission policy and the machine-wide lock.

Lane fallback: a comma list of direct lanes is tried in order. A lane
hands off to the next one on any failure before its first write or edit.
After that first mutation the lane is committed: a later failure exits (1
for an API error, 6 for a timeout) with the diff left in place for review.
The list may end in one `opencode/` lane: when no direct lane was usable
and none began editing, the wrapper runs that lane through the opencode CLI.
Any other mix is a usage error; the claude and opencode backends own their
own loop and cannot hop.
