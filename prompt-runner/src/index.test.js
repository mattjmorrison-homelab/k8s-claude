"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { api, main, fetchPendingPrompts } = require("./index.js");

function restoreApi(mocks) {
  for (const mock of mocks) {
    mock.mock.restore();
  }
}

test("main: no pending prompts logs and makes no further calls", async (t) => {
  const fetchMock = t.mock.method(api, "fetchPendingPrompts", async () => []);
  const invokeMock = t.mock.method(api, "invokeLlm", () => {
    throw new Error("should not be called");
  });
  const reportMock = t.mock.method(api, "reportResult", async () => {
    throw new Error("should not be called");
  });
  const logMock = t.mock.method(console, "log", () => {});

  await main();

  assert.equal(fetchMock.mock.calls.length, 1);
  assert.equal(invokeMock.mock.calls.length, 0);
  assert.equal(reportMock.mock.calls.length, 0);
  assert.ok(logMock.mock.calls.some((call) => call.arguments[0] === "no pending prompts"));

  restoreApi([fetchMock, invokeMock, reportMock, logMock]);
});

test("main: successful invocation reports completePrompt with id and response", async (t) => {
  const fetchMock = t.mock.method(api, "fetchPendingPrompts", async () => [
    { id: "job-1", prompt: "what is the weather" },
  ]);
  const invokeMock = t.mock.method(api, "invokeLlm", () => "the weather is sunny");
  const reportMock = t.mock.method(api, "reportResult", async () => {});
  const logMock = t.mock.method(console, "log", () => {});

  await main();

  assert.equal(invokeMock.mock.calls.length, 1);
  assert.equal(invokeMock.mock.calls[0].arguments[0], "what is the weather");

  assert.equal(reportMock.mock.calls.length, 1);
  const [, result] = reportMock.mock.calls[0].arguments;
  assert.deepEqual(result, { id: "job-1", response: "the weather is sunny" });

  restoreApi([fetchMock, invokeMock, reportMock, logMock]);
});

test("main: failed invocation reports failPrompt with a generic error", async (t) => {
  const fetchMock = t.mock.method(api, "fetchPendingPrompts", async () => [
    { id: "job-2", prompt: "do something" },
  ]);
  const invokeMock = t.mock.method(api, "invokeLlm", () => {
    throw new Error("claude cli exited nonzero");
  });
  const reportMock = t.mock.method(api, "reportResult", async () => {});
  const logMock = t.mock.method(console, "log", () => {});

  await main();

  assert.equal(reportMock.mock.calls.length, 1);
  const [, result] = reportMock.mock.calls[0].arguments;
  assert.deepEqual(result, { id: "job-2", error: "invoke_llm failed - see job logs" });

  restoreApi([fetchMock, invokeMock, reportMock, logMock]);
});

test("fetchPendingPrompts: malformed response throws a clear diagnostic", async (t) => {
  const fetchMock = t.mock.method(globalThis, "fetch", async () => ({
    status: 500,
    ok: false,
    text: async () => JSON.stringify({ errors: [{ message: "boom" }] }),
  }));

  await assert.rejects(() => fetchPendingPrompts("https://graphql.morrisons.site/"), (err) => {
    assert.match(err.message, /unexpected pendingPrompts response/);
    assert.match(err.message, /500/);
    assert.match(err.message, /boom/);
    return true;
  });

  fetchMock.mock.restore();
});
