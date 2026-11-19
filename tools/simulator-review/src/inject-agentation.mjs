export function injectAgentation(html, scriptTag) {
  if (html.includes(scriptTag)) return html;

  const closingBody = html.match(/<\/body\s*>/i);
  if (!closingBody || closingBody.index === undefined) {
    throw new Error("Simulator preview HTML has no closing body tag");
  }

  return `${html.slice(0, closingBody.index)}${scriptTag}${html.slice(closingBody.index)}`;
}

export function transformPreviewResponse(body, contentType, scriptTag) {
  if (!contentType?.toLowerCase().includes("text/html")) return body;
  const html = Buffer.isBuffer(body) ? body.toString("utf8") : String(body);
  return Buffer.from(injectAgentation(html, scriptTag));
}
