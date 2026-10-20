---
name: mercury-3
description: Ask, query, or get a second opinion from Inception Labs' mercury-3 diffusion LLM via its chat completions API. Use when the user asks for mercury, mercury-3, Inception, or a fast diffusion-LLM answer.
---

Paths are relative to the repo root.

## Run

```bash
bash .claude/skills/mercury-3/ask.sh "<prompt>" [low|medium|high] [mercury-3|mercury-2] [max_tokens]
```

Defaults: `mercury-3`, `low` reasoning effort, 4000 tokens. Prints the reply; exits 1 with the raw response on stderr if the reply is empty.

Prerequisites: `curl` and `jq`. No API key in the repo: the session's network proxy injects the bearer token for `api.inceptionlabs.ai`, so the environment must have that host configured with a bearer credential.

To keep the call out of the main context, use the `mercury` subagent (`.claude/agents/mercury.md`).

## Gotchas

- Only `POST /v1/chat/completions` is allowed on the host; other paths return 403.
- Plain `mercury` returns `model_access_denied` for accounts created after 2026-02-24. Use `mercury-3` or `mercury-2`.
- It is a reasoning model: with a small `max_tokens` the reasoning uses the whole budget and `content` is `null` with `finish_reason: "length"`. Keep `max_tokens` at 1000 or more.
- Attribute the answer to mercury-3; it is not verified.
