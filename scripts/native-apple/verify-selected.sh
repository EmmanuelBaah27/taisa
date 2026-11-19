#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 1; then
  echo "usage: verify-selected.sh <comma-separated-risks>" >&2
  exit 2
fi

risks=",$1,"
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/../.." && pwd)"
artifact_root="${TAISA_NATIVE_ARTIFACTS:-$(mktemp -d "${TMPDIR:-/tmp}/taisa-native-selected.XXXXXX")}"
mkdir -p "${artifact_root}"

cd "${repository_root}"

# Every production change must compile the app that Baah uses for device QA.
xcodebuild build -quiet \
  -project apple/Taisa.xcodeproj \
  -scheme Taisa-Personal \
  -configuration Personal \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "${artifact_root}/DerivedData-Personal" \
  CODE_SIGNING_ALLOWED=NO

if [[ "${risks}" == *,ui,* ]]; then
  xcodebuild build -quiet \
    -project apple/Taisa.xcodeproj \
    -scheme Taisa-Preview \
    -configuration Preview \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${artifact_root}/DerivedData-Preview" \
    CODE_SIGNING_ALLOWED=NO
fi

if [[ "${risks}" == *,device,* ]]; then
  xcodebuild build -quiet \
    -project apple/Taisa.xcodeproj \
    -scheme Taisa-Personal \
    -configuration Personal \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "${artifact_root}/DerivedData-Personal-Device" \
    CODE_SIGNING_ALLOWED=NO
fi

echo "Risk-selected native verification passed for: $1"
