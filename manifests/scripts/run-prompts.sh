#!/bin/sh
set -eu

GRAPH_URL="https://graph-claude.morrisons.site/"

apk add --no-cache curl jq >/dev/null

invoke_llm() {
  echo "STUB: invoke_llm not yet implemented -- see k8s-claude README for what needs to replace this" >&2
  return 1
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
    payload=$(jq -nc --arg id "$id" --arg error "invoke_llm not yet implemented" \
      '{query: "mutation($id: ID!, $error: String!) { claude { failPrompt(id: $id, error: $error) { id } } }", variables: {id: $id, error: $error}}')
  fi

  curl -sf -X POST "$GRAPH_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null

  echo "job $id: reported result"
done
