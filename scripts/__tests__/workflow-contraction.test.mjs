import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(path, "utf8");
const lines = (text) => text.trimEnd().split("\n").length;

test("always-loaded instructions stay short", () => {
  assert.ok(lines(read("AGENTS.md")) <= 100);
});

test("the Taisa skill is a thin trigger adapter", () => {
  const skill = read(".agents/skills/taisa-workflow/SKILL.md");
  assert.ok(lines(skill) <= 140);
  for (const duplicate of [
    "Feature tiers",
    "Work ownership and maps",
    "Stages and automatic skill routing",
    "Discussion Map",
    "Verification matrix",
  ]) {
    assert.doesNotMatch(skill, new RegExp(`^## .*${duplicate}`, "mi"));
  }
  assert.match(skill, /Preview, QA, repair, or Ship.*docs\/workflow\.md/is);
});

test("the bounded Goal template points to the authoritative workflow", () => {
  const template = read(".agents/skills/taisa-workflow/templates/bounded-goal.md");
  assert.ok(lines(template) <= 70);
  assert.match(template, /docs\/workflow\.md/);
});

test("removed legacy routes cannot be selected", () => {
  const active = [read("AGENTS.md"), read(".agents/skills/taisa-workflow/SKILL.md")].join("\n");
  for (const legacy of [
    "separate Scope and Plan approval",
    "persistent Platform/Product/Integration",
    "Platform and independent Product foundation",
    "Integration begins only when both",
  ]) {
    assert.doesNotMatch(active, new RegExp(legacy, "i"));
  }
});

test("the release workflow does not reimplement Matt-owned process", () => {
  const workflow = read("docs/workflow.md");
  for (const heading of [
    "Feature tiers",
    "Approval-path decision",
    "The six stages",
    "Bounded Goal runs",
    "Work Map",
    "Multi-session tracer delivery",
    "Discussion Map",
    "Architecture diagrams",
    "Scope",
    "Product design between Scope and Plan",
    "Plan",
    "Build",
    "Workflow activation",
    "Cycle orientation",
    "Linear operating rules",
    "Deferred-capability stewardship",
    "Monthly reconciliation heartbeat",
  ]) {
    assert.doesNotMatch(workflow, new RegExp(`^#{2,3} ${heading}$`, "mi"));
  }
  assert.match(workflow, /^## Review and release safety$/m);
});

test("the Linear adapter owns deferred-capability operations", () => {
  const adapter = read("docs/agents/issue-tracker.md");
  assert.match(adapter, /^## Deferred-capability stewardship$/m);
  assert.match(adapter, /^## Monthly reconciliation heartbeat$/m);
  for (const legacyGate of [
    "readable Scope and Plan",
    "does not authorize Scope",
    "Before Scope or Plan",
    "never approves Scope, Plan",
  ]) {
    assert.doesNotMatch(adapter, new RegExp(legacyGate, "i"));
  }
});

test("active instructions do not describe APF-80 as an expand phase", () => {
  assert.doesNotMatch(read("AGENTS.md"), /APF-80's expand phase/i);
});

test("active instructions preserve reasoned documentation-only tracer exceptions", () => {
  const agents = read("AGENTS.md");
  const skill = read(".agents/skills/taisa-workflow/SKILL.md");

  assert.match(agents, /non-empty\s+reason why Preview is not meaningful/i);
  assert.match(agents, /no reviewable product experience requires a non-empty\s+reason/i);
  assert.match(skill, /no reviewable product experience requires a non-empty reason/i);
});
