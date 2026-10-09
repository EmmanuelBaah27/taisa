#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/../.." && pwd)"
artifact_root="${TAISA_NATIVE_ARTIFACTS:-$(mktemp -d "${TMPDIR:-/tmp}/taisa-native-verification.XXXXXX")}"
mkdir -p "${artifact_root}"

reset_simulator_app() {
  local simulator="$1"
  local bundle_identifier="$2"
  local boot_timeout_seconds="${TAISA_SIMULATOR_BOOT_TIMEOUT_SECONDS:-300}"
  xcrun simctl boot "${simulator}" >/dev/null 2>&1 || true
  if ! /usr/bin/perl -e 'alarm shift; exec @ARGV' "${boot_timeout_seconds}" xcrun simctl bootstatus "${simulator}" -b >/dev/null; then
    echo "Simulator ${simulator} did not finish booting within ${boot_timeout_seconds}s." >&2
    return 1
  fi
  xcrun simctl uninstall "${simulator}" "${bundle_identifier}" >/dev/null 2>&1 || true
}

shutdown_simulator() {
  local simulator="$1"
  xcrun simctl shutdown "${simulator}" >/dev/null 2>&1 || true
}

cd "${repository_root}"
bash scripts/native-apple/verify-generated-project.sh
bash apple/scripts/generate-build-metadata.sh
node --test scripts/native-apple/__tests__/*.test.mjs
node --test apple/scripts/__tests__/*.test.mjs
npm run verify:native-contracts
(cd apple/Packages/TaisaFoundation && swift test)
npm run verify:native-design-system

simulator_inventory="$(xcrun simctl list devices available --json)"
iphone_name="${TAISA_IPHONE_SIMULATOR_NAME:-$(printf '%s' "${simulator_inventory}" | node scripts/native-apple/select-simulator.mjs iPhone)}"
ipad_name="${TAISA_IPAD_SIMULATOR_NAME:-$(printf '%s' "${simulator_inventory}" | node scripts/native-apple/select-simulator.mjs iPad)}"

development_destinations="$(xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Dev -showdestinations)"
preview_destinations="$(xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Preview -showdestinations)"
personal_destinations="$(xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Personal -showdestinations)"
development_can_test="$(printf '%s' "${development_destinations}" | node scripts/native-apple/select-simulator.mjs --eligible)"
preview_can_test="$(printf '%s' "${preview_destinations}" | node scripts/native-apple/select-simulator.mjs --eligible)"
personal_can_test="$(printf '%s' "${personal_destinations}" | node scripts/native-apple/select-simulator.mjs --eligible)"

if [[ "${development_can_test}" == "yes" && "${preview_can_test}" == "yes" ]]; then
  # UI verification owns deterministic app state. Xcode reinstalls builds but
  # otherwise retains prior encrypted stores and recovery journals.
  reset_simulator_app "${iphone_name}" com.taisa.app.dev
  xcodebuild test -quiet -retry-tests-on-failure -test-iterations 2 -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination "platform=iOS Simulator,name=${iphone_name}" -derivedDataPath "${artifact_root}/DerivedData-Dev" -resultBundlePath "${artifact_root}/Taisa-Dev.xcresult"
  shutdown_simulator "${iphone_name}"
  reset_simulator_app "${ipad_name}" com.taisa.app.preview
  xcodebuild test -quiet -retry-tests-on-failure -test-iterations 2 -project apple/Taisa.xcodeproj -scheme Taisa-Preview -destination "platform=iOS Simulator,name=${ipad_name}" -derivedDataPath "${artifact_root}/DerivedData-Preview" -resultBundlePath "${artifact_root}/Taisa-Preview.xcresult"
  shutdown_simulator "${ipad_name}"
else
  echo "No eligible iOS simulator runtime; compiling test bundles instead."
  xcodebuild build-for-testing -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'generic/platform=iOS Simulator' -derivedDataPath "${artifact_root}/DerivedData-Dev" CODE_SIGNING_ALLOWED=NO
  xcodebuild build-for-testing -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Preview -destination 'generic/platform=iOS Simulator' -derivedDataPath "${artifact_root}/DerivedData-Preview" CODE_SIGNING_ALLOWED=NO
fi
if [[ "${personal_can_test}" == "yes" ]]; then
  # Simulator Keychain needs a locally signed process. Ad-hoc signing does not
  # provision a team or contact Apple; physical-device verification stays unsigned.
  reset_simulator_app "${iphone_name}" com.taisa.app.personal
  xcodebuild test -quiet -retry-tests-on-failure -test-iterations 2 -project apple/Taisa.xcodeproj -scheme Taisa-Personal -configuration Personal -destination "platform=iOS Simulator,name=${iphone_name}" -derivedDataPath "${artifact_root}/DerivedData-Personal" -resultBundlePath "${artifact_root}/Taisa-Personal.xcresult" CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
  shutdown_simulator "${iphone_name}"
else
  xcodebuild build-for-testing -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Personal -configuration Personal -destination 'generic/platform=iOS Simulator' -derivedDataPath "${artifact_root}/DerivedData-Personal" CODE_SIGNING_ALLOWED=NO
fi
xcodebuild build -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Personal -configuration Personal -destination 'generic/platform=iOS' -derivedDataPath "${artifact_root}/DerivedData-Personal-Device" CODE_SIGNING_ALLOWED=NO
xcodebuild build -quiet -project apple/Taisa.xcodeproj -scheme Taisa -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath "${artifact_root}/DerivedData-Release" CODE_SIGNING_ALLOWED=NO

TAISA_PRODUCTION_BUNDLE="${artifact_root}/DerivedData-Release/Build/Products/Release-iphonesimulator/Taisa.app" TAISA_PERSONAL_BUNDLE="${artifact_root}/DerivedData-Personal-Device/Build/Products/Personal-iphoneos/TaisaPersonal.app" node scripts/native-apple/verify.mjs
npm run verify:workflow
echo "Complete native Apple verification passed."
