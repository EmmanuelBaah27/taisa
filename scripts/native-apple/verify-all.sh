#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/../.." && pwd)"
artifact_root="${TAISA_NATIVE_ARTIFACTS:-$(mktemp -d "${TMPDIR:-/tmp}/taisa-native-verification.XXXXXX")}"
mkdir -p "${artifact_root}"

cd "${repository_root}"
bash scripts/native-apple/verify-generated-project.sh
bash apple/scripts/generate-build-metadata.sh
node --test scripts/native-apple/__tests__/*.test.mjs
npm run verify:native-contracts
(cd apple/Packages/TaisaFoundation && swift test)
npm run verify:native-design-system

simulator_inventory="$(xcrun simctl list devices available --json)"
iphone_name="${TAISA_IPHONE_SIMULATOR_NAME:-$(printf '%s' "${simulator_inventory}" | node scripts/native-apple/select-simulator.mjs iPhone)}"
ipad_name="${TAISA_IPAD_SIMULATOR_NAME:-$(printf '%s' "${simulator_inventory}" | node scripts/native-apple/select-simulator.mjs iPad)}"

xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination "platform=iOS Simulator,name=${iphone_name}" -derivedDataPath "${artifact_root}/DerivedData-Dev" -resultBundlePath "${artifact_root}/Taisa-Dev.xcresult"
xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Preview -destination "platform=iOS Simulator,name=${ipad_name}" -derivedDataPath "${artifact_root}/DerivedData-Preview" -resultBundlePath "${artifact_root}/Taisa-Preview.xcresult"
xcodebuild build -quiet -project apple/Taisa.xcodeproj -scheme Taisa -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath "${artifact_root}/DerivedData-Release" CODE_SIGNING_ALLOWED=NO

TAISA_PRODUCTION_BUNDLE="${artifact_root}/DerivedData-Release/Build/Products/Release-iphonesimulator/Taisa.app" node scripts/native-apple/verify.mjs
npm run verify:workflow
echo "Complete native Apple verification passed."
