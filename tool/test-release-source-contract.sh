#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERIFIER="$ROOT_DIR/tool/verify-release-source.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/myshop-release-source.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

expect_failure() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $label unexpectedly succeeded" >&2
    exit 1
  fi
}

bash -n "$VERIFIER"

REPO="$TMP_ROOT/repository"
git init -q "$REPO"
git -C "$REPO" config user.name "Release Contract"
git -C "$REPO" config user.email "release-contract@example.invalid"
printf '%s\n' "reviewed" > "$REPO/release.txt"
git -C "$REPO" add release.txt
git -C "$REPO" commit -qm "reviewed source"
REVIEWED_SOURCE=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" update-ref refs/remotes/origin/main "$REVIEWED_SOURCE"

bash "$VERIFIER" "$REVIEWED_SOURCE" "$REPO" >/dev/null
expect_failure "malformed source SHA" bash "$VERIFIER" short "$REPO"
expect_failure "reviewed SHA mismatch" \
  bash "$VERIFIER" 0000000000000000000000000000000000000000 "$REPO"

printf '%s\n' "not reviewed" >> "$REPO/release.txt"
git -C "$REPO" commit -qam "unreviewed commit"
UNREVIEWED_SOURCE=$(git -C "$REPO" rev-parse HEAD)
expect_failure "commit not at origin/main" \
  bash "$VERIFIER" "$UNREVIEWED_SOURCE" "$REPO"

git -C "$REPO" reset -q --hard "$REVIEWED_SOURCE"
printf '%s\n' "dirty" >> "$REPO/release.txt"
expect_failure "dirty tracked file" \
  bash "$VERIFIER" "$REVIEWED_SOURCE" "$REPO"

git -C "$REPO" reset -q --hard "$REVIEWED_SOURCE"
printf '%s\n' "untracked" > "$REPO/untracked.txt"
expect_failure "untracked file" \
  bash "$VERIFIER" "$REVIEWED_SOURCE" "$REPO"

echo "Release-source contract tests passed"
