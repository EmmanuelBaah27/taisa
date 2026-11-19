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
risk_logic=false
risk_ui=false
risk_network=false
risk_device=false
risk_data=false
risk_security=false
risk_workflow=false

while IFS= read -r changed_path; do
  test -n "${changed_path}" || continue
  path_risk_detected=false

  case "${changed_path}" in
    .github/*|AGENTS.md|docs/workflow.md|.agents/skills/taisa-workflow/SKILL.md|scripts/verify-workflow.sh|scripts/verify-branch-topology.sh|scripts/native-apple/classify-ci-risk.sh|scripts/native-apple/validate-pr-contract.mjs|scripts/native-apple/verify-all.sh|package.json|package-lock.json)
      native_required=true
      high_risk_required=true
      risk_workflow=true
      path_risk_detected=true
      ;;
  esac

  case "${changed_path}" in
    */Tests/*|*/__tests__/*|*.test.*|*Tests.swift)
      continue
      ;;
  esac

  case "${changed_path}" in
    apple/Packages/TaisaFoundation/Sources/TaisaStorage/*|apple/Packages/TaisaFoundation/Sources/TaisaRecovery/*|apple/TaisaApp/Recovery/*|backend/src/db/schema.sql|mobile/src/db/migrations.ts|mobile/src/db/schema.ts|shared/types/migration.ts)
      native_required=true
      high_risk_required=true
      risk_data=true
      path_risk_detected=true
      ;;
  esac

  case "${changed_path}" in
    apple/Packages/TaisaFoundation/Sources/TaisaSecurity/*|apple/Packages/TaisaFoundation/Sources/*/*Credential*|apple/Packages/TaisaFoundation/Sources/*/*Privacy*|apple/Packages/TaisaFoundation/Sources/*/*Encryption*|backend/src/auth/*|backend/src/middleware/deviceAuthentication.ts|backend/src/feedback/feedbackCrypto.ts|apple/Config/*.entitlements)
      native_required=true
      high_risk_required=true
      risk_security=true
      path_risk_detected=true
      ;;
  esac

  case "${changed_path}" in
    apple/Packages/TaisaFoundation/Sources/TaisaAudio/*|apple/TaisaApp/Voice/*|apple/Config/*Info.plist|apple/Config/*.xcconfig)
      native_required=true
      high_risk_required=true
      risk_device=true
      path_risk_detected=true
      ;;
  esac

  case "${changed_path}" in
    apple/Packages/TaisaFoundation/Sources/TaisaNetworking/*|apple/Packages/TaisaFoundation/Sources/TaisaVoice/*|backend/src/routes/*|backend/src/services/*|shared/types/transcription.ts|shared/types/coaching*.ts|railway.json|backend/Dockerfile|backend/src/config/*)
      native_required=true
      risk_network=true
      path_risk_detected=true
      ;;
  esac

  case "${changed_path}" in
    railway.json|backend/Dockerfile|backend/src/config/*)
      high_risk_required=true
      ;;
  esac

  case "${changed_path}" in
    apple/TaisaApp/*View.swift|apple/TaisaApp/**/*View.swift|apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/*|apple/TaisaPreview/*)
      native_required=true
      risk_ui=true
      path_risk_detected=true
      ;;
  esac

  case "${changed_path}" in
    apple/*|scripts/native-apple/*)
      native_required=true
      if test "${path_risk_detected}" = false; then
        risk_logic=true
      fi
      ;;
  esac
done < <("${changed_paths_command[@]}")

detected_risks=""
for risk in logic ui network device data security workflow; do
  risk_variable="risk_${risk}"
  if test "${!risk_variable}" = true; then
    if test -n "${detected_risks}"; then
      detected_risks="${detected_risks},${risk}"
    else
      detected_risks="${risk}"
    fi
  fi
done

echo "native_required=${native_required}"
echo "high_risk_required=${high_risk_required}"
echo "detected_risks=${detected_risks}"
