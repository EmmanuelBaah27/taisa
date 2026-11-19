import assert from "node:assert/strict";
import test from "node:test";

import { parseReviewArguments, startWithCleanup } from "../review-simulator.mjs";

test("requires an explicit simulator UDID", () => {
  assert.throws(() => parseReviewArguments([]), /--udid/i);
});

test("parses one explicit simulator and review port", () => {
  assert.deepEqual(parseReviewArguments(["--udid", "1234-ABCD", "--port", "3210"]), {
    udid: "1234-ABCD",
    port: 3210,
    helperPort: 3100,
  });
});

test("accepts a separate helper port", () => {
  assert.deepEqual(parseReviewArguments(["--udid", "1234", "--helper-port", "3110"]), {
    udid: "1234",
    port: 3200,
    helperPort: 3110,
  });
});

test("rejects an invalid review port", () => {
  assert.throws(() => parseReviewArguments(["--udid", "1234", "--port", "80"]), /port/i);
});

test("stops the selected helper when the review server fails to start", async () => {
  let stopped = false;
  await assert.rejects(
    startWithCleanup(
      async () => { throw new Error("port in use"); },
      () => { stopped = true; },
    ),
    /port in use/,
  );
  assert.equal(stopped, true);
});

