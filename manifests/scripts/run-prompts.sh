#!/bin/sh
set -eu

GRAPH_URL="https://graph-claude.morrisons.site/"

apt-get update >/dev/null
apt-get install -y --no-install-recommends curl jq >/dev/null
npm install -g @anthropic-ai/claude-code >/dev/null

invoke_llm() {
  prompt="$1"
  # No credential is mounted in this container; claude -p will fail with an
  # auth error until a credential-mounting mechanism (e.g. a hostPath volume
  # to an already-logged-in host, or some other auth delivery) is added
  # separately.
  claude -p "$prompt" --allowedTools WebSearch
}

jobs=$(curl -sf -X POST "$GRAPH_URL" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ claude { pendingPrompts { id prompt } } }"}' \
  | jq -c '.data.claude.pendingPrompts[]')

if [ -z "$jobs" ]; then
  echo "no pending prompts"
  exit 0
fi

echo "$jobs" | while IFS= read -r job; do
  id=$(echo "$job" | jq -r '.id')
  prompt=$(echo "$job" | jq -r '.prompt')

  if response=$(invoke_llm "$prompt"); then
    payload=$(jq -nc --arg id "$id" --arg response "$response" \
      '{query: "mutation($id: ID!, $response: String!) { claude { completePrompt(id: $id, response: $response) { id } } }", variables: {id: $id, response: $response}}')
  else
    payload=$(jq -nc --arg id "$id" --arg error "invoke_llm failed - see job logs" \
      '{query: "mutation($id: ID!, $error: String!) { claude { failPrompt(id: $id, error: $error) { id } } }", variables: {id: $id, error: $error}}')
  fi

  curl -sf -X POST "$GRAPH_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null

  echo "job $id: reported result"
done
