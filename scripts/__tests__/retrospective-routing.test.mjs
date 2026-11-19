import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { routeRetrospectiveFinding } from "../retrospective-router.mjs";

const autonomousFixtures = [
  ["mechanical failure", "check-or-automation"],
  ["navigation cost", "pointer-or-tool"],
  ["judgment failure", "review-standard"],
  ["duplicated process", "consolidate-or-remove"],
  ["no recurring waste", "explicit-no-change"],
];

for (const [finding, evidence] of autonomousFixtures) {
  test(`${finding} becomes an autonomous environment improvement`, () => {
    assert.deepEqual(routeRetrospectiveFinding({ finding }), {
      owner: "agent",
      gate: "continue",
      evidence,
    });
  });
}

for (const area of [
  "authority",
  "privacy",
  "security",
  "verification-coverage",
  "preview",
  "meaningful-cost",
  "ship",
]) {
  test(`${area} redesign stops at Baah`, () => {
    assert.deepEqual(
      routeRetrospectiveFinding({ finding: "material redesign", area }),
      {
        owner: "Baah",
        gate: "stop-for-explicit-decision",
        evidence: "material-redesign-proposal",
      },
    );
  });
}

test("an autonomous category cannot bypass a protected area", () => {
  assert.deepEqual(
    routeRetrospectiveFinding({ finding: "duplicated process", area: "ship" }),
    {
      owner: "Baah",
      gate: "stop-for-explicit-decision",
      evidence: "material-redesign-proposal",
    },
  );
});

test("an unclassified retrospective finding fails closed", () => {
  assert.throws(
    () => routeRetrospectiveFinding({ finding: "something else" }),
    /Unclassified retrospective finding/,
  );
});

test("the workflow requires a durable retrospective outcome", () => {
  const workflow = readFileSync("docs/workflow.md", "utf8");
  assert.match(
    workflow,
    /resulting check, pointer, review standard, tool, process removal, or explicit no-change conclusion/i,
  );
  assert.match(
    workflow,
    /authority, privacy, security, verification coverage, Preview, meaningful cost, or Ship[^.]*Baah/i,
  );
});
