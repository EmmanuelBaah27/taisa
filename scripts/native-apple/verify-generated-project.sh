#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/../.." && pwd)"
temporary_parent="${repository_root}/apple/DerivedData"
mkdir -p "${temporary_parent}"
temporary_root="$(mktemp -d "${temporary_parent}/taisa-generated-project.XXXXXX")"
trap 'rm -rf "${temporary_root}"' EXIT

mkdir -p "${temporary_root}/apple"
rsync -a --exclude '.build' --exclude 'DerivedData' --exclude 'Taisa.xcodeproj' "${repository_root}/apple/" "${temporary_root}/apple/"
TAISA_REPOSITORY_ROOT="${repository_root}" "${temporary_root}/apple/scripts/generate-project.sh" >/dev/null

diff -u "${repository_root}/apple/Taisa.xcodeproj/project.pbxproj" "${temporary_root}/apple/Taisa.xcodeproj/project.pbxproj"
diff -u "${repository_root}/apple/Taisa.xcodeproj/project.xcworkspace/contents.xcworkspacedata" "${temporary_root}/apple/Taisa.xcodeproj/project.xcworkspace/contents.xcworkspacedata"
diff -ru "${repository_root}/apple/Taisa.xcodeproj/xcshareddata/xcschemes" "${temporary_root}/apple/Taisa.xcodeproj/xcshareddata/xcschemes"
echo "Generated Xcode project matches project.yml."
