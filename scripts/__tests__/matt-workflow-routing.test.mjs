import assert from "node:assert/strict";
import test from "node:test";

import { selectMattRoute } from "../matt-workflow-router.mjs";

const fixtures = [
  ["hard bug overrides session size", { workType: "bug", phase: "implementation", sessions: 1 }, "diagnosing-bugs"],
  ["foggy work is clarified first", { workType: "feature", clarity: "foggy", phase: "discovery" }, "wayfinder"],
  ["feature discovery is grilled", { workType: "feature", clarity: "clear", phase: "discovery" }, "grill-with-docs"],
  ["one-session build is implemented directly", { workType: "feature", clarity: "clear", phase: "implementation", sessions: 1 }, "implement"],
  ["multi-session build becomes spec and tracer tickets", { workType: "feature", clarity: "clear", phase: "implementation", sessions: "multiple" }, "to-spec -> to-tickets -> per-ticket implement"],
  ["delivery waste closes with retro", { workType: "process", clarity: "clear", phase: "closeout" }, "retro"],
];

for (const [name, input, expected] of fixtures) {
  test(name, () => assert.equal(selectMattRoute(input), expected));
}

test("underspecified work fails closed", () => {
  assert.throws(() => selectMattRoute({ workType: "feature" }), /Insufficient/);
});
