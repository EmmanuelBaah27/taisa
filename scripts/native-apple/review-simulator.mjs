#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "../..");
const toolRoot = resolve(repositoryRoot, "tools/simulator-review");
const serveSim = resolve(toolRoot, "node_modules/.bin/serve-sim");

export function parseReviewArguments(args) {
  let udid;
  let port = 3200;
  let helperPort = 3100;
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === "--udid") udid = args[++index];
    else if (args[index] === "--port") port = Number(args[++index]);
    else if (args[index] === "--helper-port") helperPort = Number(args[++index]);
    else throw new Error(`Unknown argument: ${args[index]}`);
  }
  if (!udid?.trim()) throw new Error("Pass one explicit simulator with --udid <UDID>");
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error("Port must be between 1024 and 65535");
  if (!Number.isInteger(helperPort) || helperPort < 1024 || helperPort > 65535 || helperPort === port) {
    throw new Error("Helper port must be valid and different from the review port");
  }
  return { udid: udid.trim(), port, helperPort };
}

export async function startWithCleanup(startServer, stopHelper) {
  try {
    return await startServer();
  } catch (error) {
    stopHelper();
    throw error;
  }
}

async function main() {
  const options = parseReviewArguments(process.argv.slice(2));
  const build = spawnSync("npm", ["run", "build"], { cwd: toolRoot, stdio: "inherit" });
  if (build.status !== 0) process.exit(build.status ?? 1);

  const helper = spawnSync(serveSim, ["--detach", "--no-preview", "--port", String(options.helperPort), options.udid], { stdio: "inherit" });
  if (helper.status !== 0) process.exit(helper.status ?? 1);

  const { startReviewServer } = await import(resolve(toolRoot, "src/server.mjs"));
  const stopHelper = () => spawnSync(serveSim, ["--kill", options.udid], { stdio: "inherit" });
  const server = await startWithCleanup(
    () => startReviewServer({
      ...options,
      revision: spawnSync("git", ["rev-parse", "--short", "HEAD"], { cwd: repositoryRoot, encoding: "utf8" }).stdout.trim(),
    }),
    stopHelper,
  );
  console.log(`Simulator review: http://127.0.0.1:${options.port}/`);

  const stop = () => {
    stopHelper();
    server.closeAllConnections?.();
    server.close(() => process.exit(0));
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
