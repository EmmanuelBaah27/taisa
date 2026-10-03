#!/usr/bin/env bash

set -euo pipefail

required_version='2.46.0'
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen ${required_version} is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

actual_version="$(xcodegen version)"
if [[ "$actual_version" != "Version: ${required_version}" && "$actual_version" != "${required_version}" ]]; then
  echo "XcodeGen ${required_version} is required; found ${actual_version}." >&2
  exit 1
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apple_root="$(cd "${script_directory}/.." && pwd)"
"${script_directory}/generate-build-metadata.sh"
exec xcodegen generate --spec "${apple_root}/project.yml" --project "${apple_root}"
