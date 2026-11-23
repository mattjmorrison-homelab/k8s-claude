#!/bin/sh
set -eu

GRAPH_URL="https://graphql.morrisons.site/"

apt-get update >/dev/null
apt-get install -y --no-install-recommends curl jq ca-certificates >/dev/null
update-ca-certificates >/dev/null
npm install -g @anthropic-ai/claude-code >/dev/null

invoke_llm() {
  prompt="$1"
  claude -p "$prompt" --allowedTools WebSearch
}

pending_response=$(curl -sf -X POST "$GRAPH_URL" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ claude { pendingPrompts { id prompt } } }"}') || {
  echo "failed to reach $GRAPH_URL to fetch pending prompts" >&2
  exit 1
}

if ! echo "$pending_response" | jq -e '.data.claude.pendingPrompts | type == "array"' >/dev/null 2>&1; then
  echo "unexpected pendingPrompts response from $GRAPH_URL: $pending_response" >&2
  exit 1
fi

jobs=$(echo "$pending_response" | jq -c '.data.claude.pendingPrompts[]')

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
    -d "$payload" >/dev/null || {
    echo "failed to report result for job $id to $GRAPH_URL" >&2
    exit 1
  }

  echo "job $id: reported result"
done
