export function createServerOptions({ udid, port = 3200 }) {
  const device = udid?.trim();
  if (!device) throw new Error("An explicit simulator UDID is required");

  return {
    host: "127.0.0.1",
    port,
    middleware: {
      basePath: "/",
      device,
      proxyHelpers: true,
      allowExec: false,
    },
  };
}

import { createReadStream } from "node:fs";
import { createServer } from "node:http";
import { stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { simMiddleware } from "serve-sim/middleware";

import { injectAgentation } from "./inject-agentation.mjs";
import { createReviewMetadata } from "./review-metadata.mjs";

const bundlePath = fileURLToPath(new URL("../dist/agentation.js", import.meta.url));

export function interceptPreviewHtml(response, metadata) {
  const originalEnd = response.end.bind(response);
  const originalWriteHead = response.writeHead.bind(response);
  let writtenContentType = "";
  response.writeHead = function reviewWriteHead(status, statusMessageOrHeaders, maybeHeaders) {
    const headers = typeof statusMessageOrHeaders === "string" ? maybeHeaders : statusMessageOrHeaders;
    if (headers) {
      for (const [name, value] of Object.entries(headers)) {
        if (name.toLowerCase() === "content-type") writtenContentType = String(value);
      }
    }
    return originalWriteHead(status, statusMessageOrHeaders, maybeHeaders);
  };
  response.end = function reviewEnd(chunk, encoding, callback) {
    const contentType = String(response.getHeader("content-type") || writtenContentType);
    if (!contentType.toLowerCase().includes("text/html") || chunk === undefined) {
      return originalEnd(chunk, encoding, callback);
    }
    const html = Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
    const config = `<script>window.__TAISA_REVIEW__=${JSON.stringify(metadata)}</script>`;
    const entry = '<script type="module" src="/__taisa-review/agentation.js"></script>';
    return originalEnd(injectAgentation(injectAgentation(html, config), entry), encoding, callback);
  };
}

export async function startReviewServer(input) {
  const options = createServerOptions(input);
  const metadata = createReviewMetadata(input);
  const middleware = simMiddleware(options.middleware);
  const server = createServer(async (request, response) => {
    if (request.url === "/__taisa-review/agentation.js") {
      const info = await stat(bundlePath);
      response.writeHead(200, {
        "Content-Type": "text/javascript; charset=utf-8",
        "Content-Length": info.size,
        "Cache-Control": "no-store",
      });
      createReadStream(bundlePath).pipe(response);
      return;
    }
    interceptPreviewHtml(response, metadata);
    await middleware(request, response);
  });
  middleware.setServerPort(options.port);
  server.on("upgrade", (request, socket, head) => middleware.handleUpgrade(request, socket, head));
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(options.port, options.host, resolve);
  });
  return server;
}
