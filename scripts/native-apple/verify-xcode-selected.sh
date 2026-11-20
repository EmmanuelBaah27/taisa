#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 1 || test -z "$1"; then
  echo "usage: verify-xcode-selected.sh <comma-separated-test-targets>" >&2
  exit 2
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/../.." && pwd)"
artifact_root="${TAISA_NATIVE_ARTIFACTS:-}"
if test -z "${artifact_root}"; then
  artifact_root="$(mktemp -d "${TMPDIR:-/tmp}/taisa-native-xcode-tests.XXXXXX")"
fi
mkdir -p "${artifact_root}"
cd "${repository_root}"

simulator_inventory="$(xcrun simctl list devices available --json)"
iphone_udid="${TAISA_IPHONE_SIMULATOR_UDID:-$(printf '%s' "${simulator_inventory}" | node scripts/native-apple/select-simulator.mjs --udid)}"
xcrun simctl boot "${iphone_udid}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${iphone_udid}" -b >/dev/null
trap 'xcrun simctl shutdown "${iphone_udid}" >/dev/null 2>&1 || true' EXIT

IFS=',' read -r -a targets <<< "$1"
for target in "${targets[@]}"; do
  case "${target}" in
    TaisaPersonalTests|TaisaPersonalUITests)
      scheme=Taisa-Personal
      configuration=Personal
      bundle_identifier=com.taisa.app.personal
      signing=(CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES)
      ;;
    TaisaPreviewUITests)
      scheme=Taisa-Preview
      configuration=Preview
      bundle_identifier=com.taisa.app.preview
      signing=(CODE_SIGNING_ALLOWED=NO)
      ;;
    TaisaUnitTests|TaisaUITests)
      scheme=Taisa-Dev
      configuration=Debug
      bundle_identifier=com.taisa.app.dev
      signing=(CODE_SIGNING_ALLOWED=NO)
      ;;
    *)
      echo "Unknown Xcode test target: ${target}" >&2
      exit 2
      ;;
  esac

  xcrun simctl uninstall "${iphone_udid}" "${bundle_identifier}" >/dev/null 2>&1 || true
  xcodebuild test -quiet \
    -project apple/Taisa.xcodeproj \
    -scheme "${scheme}" \
    -configuration "${configuration}" \
    -destination "platform=iOS Simulator,id=${iphone_udid}" \
    -only-testing:"${target}" \
    -retry-tests-on-failure \
    -test-iterations 2 \
    -parallel-testing-enabled YES \
    -parallel-testing-worker-count 2 \
    -derivedDataPath "${artifact_root}/DerivedData-${target}" \
    -resultBundlePath "${artifact_root}/${target}.xcresult" \
    "${signing[@]}"
done

echo "Focused Xcode tests passed for: $1"
