import assert from "node:assert/strict";
import test from "node:test";

import { createServerOptions, interceptPreviewHtml } from "../src/server.mjs";

test("binds the review server to loopback and disables host execution", () => {
  assert.deepEqual(createServerOptions({ udid: "1234-ABCD", port: 3200 }), {
    host: "127.0.0.1",
    port: 3200,
    middleware: {
      basePath: "/",
      device: "1234-ABCD",
      proxyHelpers: true,
      allowExec: false,
    },
  });
});

test("rejects a server configuration without an explicit UDID", () => {
  assert.throws(() => createServerOptions({ port: 3200 }), /simulator UDID/i);
});

test("injects review scripts when middleware sets HTML headers with writeHead", () => {
  let output = "";
  const headers = new Map();
  const response = {
    writeHead(_status, nextHeaders) {
      for (const [name, value] of Object.entries(nextHeaders)) headers.set(name.toLowerCase(), value);
    },
    getHeader() { return undefined; },
    removeHeader(name) { headers.delete(name.toLowerCase()); },
    end(chunk) { output = String(chunk); },
  };

  interceptPreviewHtml(response, { udid: "1234", revision: "abc1234" });
  response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  response.end("<html><body>Simulator</body></html>");

  assert.match(output, /window\.__TAISA_REVIEW__/);
  assert.match(output, /\/__taisa-review\/agentation\.js/);
});

