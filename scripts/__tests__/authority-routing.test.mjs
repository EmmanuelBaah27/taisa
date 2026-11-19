import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { selectDecisionOwner } from "../authority-router.mjs";

const autonomousFixtures = [
  ["technical plan", { decision: "technical-plan" }],
  ["test selection", { decision: "test-selection" }],
  ["branch mechanics", { decision: "branch-mechanics" }],
  ["routine implementation", { decision: "implementation" }],
];

for (const [name, input] of autonomousFixtures) {
  test(`${name} remains agent-owned`, () => {
    assert.deepEqual(selectDecisionOwner(input), {
      owner: "agent",
      gate: "continue",
    });
  });
}

const baahFixtures = [
  ["product intent", { decision: "product-intent" }],
  ["material experience", { decision: "material-experience" }],
  ["security", { decision: "security" }],
  ["privacy", { decision: "privacy" }],
  ["destructive data", { decision: "destructive-data" }],
  ["paid service", { decision: "paid-service" }],
  ["difficult to reverse", { decision: "difficult-to-reverse" }],
  ["physical QA", { decision: "physical-qa" }],
  ["perceptual QA", { decision: "perceptual-qa" }],
  ["Ship", { decision: "ship" }],
];

for (const [name, input] of baahFixtures) {
  test(`${name} stops at Baah`, () => {
    assert.deepEqual(selectDecisionOwner(input), {
      owner: "Baah",
      gate: "stop-for-explicit-decision",
    });
  });
}

test("unknown decisions fail closed", () => {
  assert.throws(
    () => selectDecisionOwner({ decision: "unclassified" }),
    /Unclassified decision/,
  );
});

test("the Linear adapter keeps ordinary plans agent-owned", () => {
  const adapter = readFileSync("docs/agents/issue-tracker.md", "utf8");
  assert.match(adapter, /ordinary technical Plan[^.]*agent-owned/i);
  assert.match(adapter, /Baah[^.]*product intent[^.]*material[^.]*Ship/i);
});

test("the Linear adapter records only decisions and stable checkpoints", () => {
  const adapter = readFileSync("docs/agents/issue-tracker.md", "utf8");
  assert.match(adapter, /only decisions or stable delivery checkpoints/i);
});
