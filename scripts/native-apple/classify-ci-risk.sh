#!/usr/bin/env bash
set -euo pipefail

if test "$#" -eq 2; then
  changed_paths_command=(git diff --name-only "$1" "$2")
elif test "$#" -eq 0; then
  changed_paths_command=(cat)
else
  echo "usage: classify-ci-risk.sh [<base-sha> <head-sha>]" >&2
  exit 2
fi

native_required=false
high_risk_required=false

while IFS= read -r changed_path; do
  test -n "${changed_path}" || continue

  case "${changed_path}" in
    */Tests/*|*/__tests__/*|*.test.*|*Tests.swift)
      continue
      ;;
  esac

  case "${changed_path}" in
    .github/workflows/*|AGENTS.md|docs/workflow.md|.agents/skills/taisa-workflow/SKILL.md|scripts/verify-workflow.sh|scripts/native-apple/classify-ci-risk.sh|scripts/native-apple/verify-all.sh|railway.json|backend/Dockerfile|apple/Config/Release.xcconfig|apple/Packages/TaisaFoundation/Sources/TaisaStorage/*|apple/Packages/TaisaFoundation/Sources/TaisaSecurity/*|apple/Packages/TaisaFoundation/Sources/TaisaRecovery/*|apple/TaisaApp/Recovery/*|backend/src/db/schema.sql|backend/src/auth/*|backend/src/middleware/deviceAuthentication.ts|backend/src/feedback/feedbackCrypto.ts|mobile/src/db/migrations.ts|mobile/src/db/schema.ts|shared/types/migration.ts)
      native_required=true
      high_risk_required=true
      ;;
    apple/*|scripts/native-apple/*|package.json|package-lock.json)
      native_required=true
      ;;
  esac
done < <("${changed_paths_command[@]}")

echo "native_required=${native_required}"
echo "high_risk_required=${high_risk_required}"
