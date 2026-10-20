#!/usr/bin/env bash
# Usage: ask.sh "prompt" [effort=low|medium|high] [model=mercury-3] [max_tokens=4000]
# The network proxy injects the bearer token for api.inceptionlabs.ai.
set -euo pipefail
prompt="${1:?prompt required}"; effort="${2:-low}"; model="${3:-mercury-3}"; max="${4:-4000}"
resp=$(jq -n --arg m "$model" --arg e "$effort" --arg p "$prompt" --argjson t "$max" \
  '{model:$m,reasoning_effort:$e,max_tokens:$t,messages:[{role:"user",content:$p}]}' |
  curl -sS https://api.inceptionlabs.ai/v1/chat/completions -H 'Content-Type: application/json' -d @-)
out=$(jq -r '.choices[0].message.content // empty' <<<"$resp")
if [ -z "$out" ]; then echo "mercury error/empty: $resp" >&2; exit 1; fi
printf '%s\n' "$out"
