#!/bin/sh
set -eu

GRAPH_URL="https://graphql.morrisons.site/"

apt-get update >/dev/null
apt-get install -y --no-install-recommends curl jq ca-certificates >/dev/null
update-ca-certificates >/dev/null

jq --version
curl --version | head -1

# Temporarily commented out while invoke_llm is stubbed for debugging; restore
# once the real LLM call is restored.
# npm install -g @anthropic-ai/claude-code >/dev/null

invoke_llm() {
  prompt="$1"
  # Temporarily stubbed to isolate and debug the pendingPrompts validation
  # failure upstream of this call, without risking real Claude usage while
  # that's being diagnosed. Restore the real call once the validation bug
  # is confirmed fixed.
  # claude -p "$prompt" --allowedTools WebSearch
  echo "STUB RESPONSE: invoke_llm temporarily disabled for debugging"
}

pending_http_status=$(curl -sf -o /tmp/pending_response.json -w '%{http_code}' -X POST "$GRAPH_URL" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ claude { pendingPrompts { id prompt } } }"}') || {
  echo "failed to reach $GRAPH_URL to fetch pending prompts (http status: ${pending_http_status:-none}, body: $(cat /tmp/pending_response.json 2>/dev/null))" >&2
  exit 1
}
pending_response=$(cat /tmp/pending_response.json)

if ! jq_error=$(echo "$pending_response" | jq -e '.data.claude.pendingPrompts | type == "array"' 2>&1 1>/dev/null); then
  echo "unexpected pendingPrompts response from $GRAPH_URL: $pending_response" >&2
  echo "jq validation error: ${jq_error:-none}" >&2
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

  report_http_status=$(curl -sf -o /tmp/report_response.json -w '%{http_code}' -X POST "$GRAPH_URL" \
    -H "Content-Type: application/json" \
    -d "$payload") || {
    echo "failed to report result for job $id to $GRAPH_URL (http status: ${report_http_status:-none}, body: $(cat /tmp/report_response.json 2>/dev/null))" >&2
    exit 1
  }

  echo "job $id: reported result"
done
