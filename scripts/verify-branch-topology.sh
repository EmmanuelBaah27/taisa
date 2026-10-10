#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Branch topology check failed: %s\n' "$1" >&2
  exit 1
}

mode="${1:-}"
test -n "$mode" || fail 'mode is required (build, ship, or preview-sync)'
shift

work_ref=HEAD
branch="$(git branch --show-current)"
main_ref=origin/main
preview_ref=origin/preview/taisa
pr_base=
shipped_ref=

while (($#)); do
  case "$1" in
    --work-ref) work_ref="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --main-ref) main_ref="$2"; shift 2 ;;
    --preview-ref) preview_ref="$2"; shift 2 ;;
    --pr-base) pr_base="$2"; shift 2 ;;
    --shipped-ref) shipped_ref="$2"; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

for ref in "$main_ref" "$preview_ref"; do
  git rev-parse --verify "${ref}^{commit}" >/dev/null 2>&1 || fail "required ref is unavailable: $ref"
done

verify_work_branch() {
  git rev-parse --verify "${work_ref}^{commit}" >/dev/null 2>&1 || fail "work ref is unavailable: $work_ref"
  case "$branch" in
    main|preview/taisa) fail "$branch cannot be a work branch" ;;
  esac
  git merge-base --is-ancestor "$main_ref" "$work_ref" ||
    fail "$work_ref does not contain current main $main_ref"

  local preview_commit
  while IFS= read -r preview_commit; do
    if git merge-base --is-ancestor "$preview_commit" "$work_ref"; then
      fail "$work_ref contains preview-only history from $preview_ref"
    fi
  done < <(git rev-list "${main_ref}..${preview_ref}")
}

case "$mode" in
  build)
    verify_work_branch
    ;;
  ship)
    verify_work_branch
    test "$pr_base" = main || fail "pull request base must be main, got ${pr_base:-<unset>}"
    if ! git merge-tree --write-tree "$preview_ref" "$work_ref" >/dev/null 2>&1; then
      fail "$work_ref conflicts with preview $preview_ref; reconcile before Ship"
    fi
    ;;
  preview-sync)
    test -n "$shipped_ref" || fail '--shipped-ref is required for preview-sync'
    git rev-parse --verify "${shipped_ref}^{commit}" >/dev/null 2>&1 || fail "shipped ref is unavailable: $shipped_ref"
    git merge-base --is-ancestor "$shipped_ref" "$main_ref" ||
      fail "$shipped_ref is not contained in current main $main_ref"
    git merge-base --is-ancestor "$shipped_ref" "$preview_ref" ||
      fail "$preview_ref does not contain shipped main $shipped_ref"
    ;;
  *) fail "unsupported mode: $mode" ;;
esac

printf 'Branch topology check passed: %s\n' "$mode"
