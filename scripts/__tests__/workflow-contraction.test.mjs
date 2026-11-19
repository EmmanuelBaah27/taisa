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
