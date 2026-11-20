#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/../.." && pwd)"
default_artifact_parent="${repository_root}/apple/DerivedData"
mkdir -p "${default_artifact_parent}"
artifact_root="${TAISA_NATIVE_ARTIFACTS:-$(mktemp -d "${default_artifact_parent}/taisa-native-fast.XXXXXX")}"
export TMPDIR="${repository_root}/.native-tmp"
mkdir -p "${TMPDIR}"

cd "${repository_root}"
bash scripts/native-apple/verify-generated-project.sh
bash apple/scripts/generate-build-metadata.sh
node --test scripts/native-apple/__tests__/*.test.mjs
node --test apple/scripts/__tests__/*.test.mjs
npm run verify:native-contracts
(cd apple/Packages/TaisaFoundation && swift test)
npm run verify:native-design-system
npm run verify:workflow

echo "Fast native Apple verification passed."
