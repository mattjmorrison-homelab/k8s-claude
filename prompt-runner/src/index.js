"use strict";

const { execFileSync } = require("node:child_process");

const GRAPH_URL = process.env.GRAPH_URL || "https://graphql.morrisons.site/";

async function postGraphql(url, query, variables) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(variables === undefined ? { query } : { query, variables }),
  });
  const body = await response.text();
  return { response, body };
}

async function fetchPendingPrompts(url) {
  const { response, body } = await postGraphql(url, "{ claude { pendingPrompts { id prompt } } }");

  let parsed;
  try {
    parsed = JSON.parse(body);
  } catch {
    parsed = undefined;
  }

  const pendingPrompts = parsed?.data?.claude?.pendingPrompts;
  if (!Array.isArray(pendingPrompts)) {
    throw new Error(
      `unexpected pendingPrompts response from ${url} (http status: ${response.status}): ${body}`
    );
  }

  return pendingPrompts;
}

function invokeLlm(prompt) {
  return execFileSync("claude", ["-p", prompt, "--allowedTools", "WebSearch"], { encoding: "utf8" });
}

async function reportResult(url, { id, response, error }) {
  const query =
    error === undefined
      ? "mutation($id: ID!, $response: String!) { claude { completePrompt(id: $id, response: $response) { id } } }"
      : "mutation($id: ID!, $error: String!) { claude { failPrompt(id: $id, error: $error) { id } } }";
  const variables = error === undefined ? { id, response } : { id, error };

  const { response: httpResponse, body } = await postGraphql(url, query, variables);
  if (!httpResponse.ok) {
    throw new Error(
      `failed to report result for job ${id} to ${url} (http status: ${httpResponse.status}): ${body}`
    );
  }
}

const api = { fetchPendingPrompts, invokeLlm, reportResult };

async function main() {
  const pendingPrompts = await api.fetchPendingPrompts(GRAPH_URL);

  if (pendingPrompts.length === 0) {
    console.log("no pending prompts");
    return;
  }

  for (const job of pendingPrompts) {
    const { id, prompt } = job;

    let result;
    try {
      const response = api.invokeLlm(prompt);
      result = { id, response };
    } catch {
      result = { id, error: "invoke_llm failed - see job logs" };
    }

    await api.reportResult(GRAPH_URL, result);
    console.log(`job ${id}: reported result`);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = { GRAPH_URL, fetchPendingPrompts, invokeLlm, reportResult, api, main };
