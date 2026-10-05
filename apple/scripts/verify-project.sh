#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apple_root="$(cd "${script_directory}/.." && pwd)"
repository_root="$(cd "${apple_root}/.." && pwd)"

node "${repository_root}/scripts/native-apple/verify.mjs"
xcodebuild -project "${apple_root}/Taisa.xcodeproj" -list >/dev/null
echo "Native Apple project verification passed."
