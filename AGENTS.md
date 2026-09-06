# AGENTS.md

The developer guide for this repository lives in [`CLAUDE.md`](CLAUDE.md):
architecture invariants, the data model, the helpers worth knowing, the
decision log with the reasoning behind every accounting rule, and the
smoke-test recipe. Read it before changing anything; it applies to any
coding assistant, not only the one it is named after.

Two rules that are easy to miss:

- `pocket-envelopes.app` is plain UTF-8 HTML with a non-`.html` extension.
  If your tooling refuses to open it, copy it to a `.html` twin, edit that,
  and copy it back byte-for-byte.
- Never test against a real `finance-data.json`. Use `?demo=1` or a scratch
  copy of the server on another port.
