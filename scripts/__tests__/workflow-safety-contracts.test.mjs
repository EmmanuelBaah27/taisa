import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import test from "node:test";

const read = (path) => readFileSync(path, "utf8");

test("workflow metadata matches the latest workflow change", () => {
  const workflow = read("docs/workflow.md");
  const recorded = workflow.match(/^\*\*Last updated:\*\* (\d{4}-\d{2}-\d{2})$/m)?.[1];
  let dirty = false;
  try {
    execFileSync("git", ["diff", "--quiet", "HEAD", "--", "docs/workflow.md"]);
  } catch {
    dirty = true;
  }
  const changed = dirty
    ? new Date().toISOString().slice(0, 10)
    : execFileSync("git", ["log", "-1", "--format=%cs", "--", "docs/workflow.md"], {
        encoding: "utf8",
      }).trim();
  assert.equal(recorded, changed);
});

test("local Markdown links in active workflow authorities resolve", () => {
  const files = [
    "AGENTS.md",
    "CLAUDE.md",
    "docs/workflow.md",
    "docs/agents/issue-tracker.md",
    ".agents/skills/taisa-workflow/SKILL.md",
    ".agents/skills/taisa-workflow/templates/bounded-goal.md",
  ];

  for (const file of files) {
    for (const match of read(file).matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) {
      const target = match[1].replace(/^<|>$/g, "").split("#", 1)[0];
      if (!target || /^[a-z]+:/i.test(target)) continue;
      assert.ok(existsSync(resolve(dirname(file), target)), `${file} has a broken link: ${target}`);
    }
  }
});

test("compatibility skills remain links to canonical skills", () => {
  const skills = readdirSync(".agents/skills", { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .filter((skill) => existsSync(`.agents/skills/${skill}/SKILL.md`));

  for (const skill of skills) {
    const canonical = `.agents/skills/${skill}/SKILL.md`;
    const compatibility = `.claude/skills/${skill}/SKILL.md`;
    assert.ok(lstatSync(compatibility).isSymbolicLink(), `${compatibility} must be a symlink`);
    assert.equal(realpathSync(compatibility), realpathSync(canonical));
  }
});

test("retained safety contracts keep one authoritative release order", () => {
  const agents = read("AGENTS.md");
  const workflow = read("docs/workflow.md");

  assert.match(agents, /Every Product build is design-system-first/i);
  assert.match(agents, /missing semantic role is a DS gap/i);
  assert.match(agents, /Clear Ship approval authorizes only the verified pull-request merge/i);

  const focused = workflow.indexOf("Complete implementation and the smallest applicable focused checks.");
  const review = workflow.indexOf("Run a fresh whole-candidate review before the complete matrix.");
  const freeze = workflow.indexOf("Freeze the clean candidate revision.");
  const matrix = workflow.indexOf("run the complete applicable matrix once on that exact");
  assert.ok(focused >= 0 && focused < review && review < freeze && freeze < matrix);

  assert.match(workflow, /REPAIR_QUARANTINE/);
  assert.match(workflow, /one named broken interaction/i);
  assert.match(workflow, /not `QA_READY`, Ship-ready, shippable, or merge-ready/i);
  assert.match(workflow, /Never reopen or start the successor issue/i);
  assert.match(workflow, /verify-branch-topology\.sh ship/);
  assert.match(workflow, /verify-branch-topology\.sh preview-sync/);
});

test("pull request verification is risk based and fails closed", () => {
  const workflow = read("docs/workflow.md");
  const orchestrator = read(".agents/skills/taisa-workflow/SKILL.md");

  for (const authority of [workflow, orchestrator]) {
    assert.match(authority, /Normal-risk pull requests use fast and focused checks/i);
    assert.match(authority, /High-risk and release pull requests\s+require the complete applicable matrix/i);
    assert.match(authority, /If classification is uncertain, classify the pull request as high risk/i);
    assert.match(authority, /Exact-revision evidence\s+remains reusable/i);
  }
});
