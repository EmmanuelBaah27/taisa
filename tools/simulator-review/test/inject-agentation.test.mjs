import assert from "node:assert/strict";
import test from "node:test";

import { injectAgentation, transformPreviewResponse } from "../src/inject-agentation.mjs";

const tag = '<script type="module" src="/__taisa-review/agentation.js"></script>';

test("injects the Agentation entry before the closing body tag", () => {
  const html = "<!doctype html><html><body><main>Simulator</main></body></html>";
  assert.equal(injectAgentation(html, tag), `<!doctype html><html><body><main>Simulator</main>${tag}</body></html>`);
});

test("rejects HTML without a closing body tag", () => {
  assert.throws(() => injectAgentation("<html><main>Simulator</main></html>", tag), /closing body tag/i);
});

test("does not inject the Agentation entry twice", () => {
  const html = `<html><body>${tag}</body></html>`;
  assert.equal(injectAgentation(html, tag), html);
});

test("preserves non-HTML responses unchanged", () => {
  const body = Buffer.from([0, 1, 2, 3]);
  assert.equal(transformPreviewResponse(body, "image/jpeg", tag), body);
});
