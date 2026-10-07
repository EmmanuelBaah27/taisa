#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apple_root="$(cd "${script_directory}/.." && pwd)"
repository_root="$(cd "${apple_root}/.." && pwd)"

node "${repository_root}/scripts/native-apple/verify.mjs"
swift package --force-resolved-versions resolve --package-path "${apple_root}/Packages/TaisaFoundation" >/dev/null
node --input-type=module - "${apple_root}/Packages/TaisaFoundation/Package.resolved" <<'NODE'
import { readFileSync } from "node:fs";

const lock = JSON.parse(readFileSync(process.argv[2], "utf8"));
const pins = new Map(lock.pins.map((pin) => [pin.identity, pin]));
const grdb = pins.get("grdb.swift");
const sqlcipher = pins.get("sqlcipher.swift");
if (grdb?.location !== "https://github.com/sqlcipher/GRDB.swift.git"
    || grdb.state.version !== "7.11.1"
    || grdb.state.revision !== "a285e4ca87ec6b3584c97b0ec25fc61fec02de60"
    || sqlcipher?.location !== "https://github.com/sqlcipher/SQLCipher.swift.git"
    || sqlcipher.state.version !== "4.19.0"
    || sqlcipher.state.revision !== "39f212458aeb88e33bdac2200a793a3f0d55d32b"
    || pins.size !== 2) {
  throw new Error("Unexpected SQLCipher dependency graph");
}
NODE
xcodebuild -project "${apple_root}/Taisa.xcodeproj" -list >/dev/null
echo "Native Apple project verification passed."
