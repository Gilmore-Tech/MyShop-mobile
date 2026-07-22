#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RESOLVER="$ROOT_DIR/tool/resolve-release-version.sh"

expect_failure() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $label unexpectedly succeeded" >&2
    exit 1
  fi
}

expect_output() {
  local label="$1"
  local expected="$2"
  shift 2
  local actual
  actual=$("$@" 2>/dev/null)
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label returned unexpected release arguments" >&2
    exit 1
  fi
}

expect_failure "missing build number" env RELEASE_BUILD_NUMBER= bash "$RESOLVER" client
expect_failure "non-decimal build number" env RELEASE_BUILD_NUMBER=twenty-one bash "$RESOLVER" client
expect_failure "leading-zero build number" env RELEASE_BUILD_NUMBER=021 bash "$RESOLVER" client
expect_failure "old build number" env RELEASE_BUILD_NUMBER=23 bash "$RESOLVER" client
expect_failure "non-portable build number" env RELEASE_BUILD_NUMBER=2100000001 bash "$RESOLVER" client
expect_failure "unknown app" env RELEASE_BUILD_NUMBER=24 bash "$RESOLVER" artisan

EXPECTED=$'--build-name=1.4.1\n--build-number=24\n--dart-define=MYSHOP_MARKETING_VERSION=1.4.1'
expect_output "client release" "$EXPECTED" env RELEASE_BUILD_NUMBER=24 bash "$RESOLVER" client
expect_output "provider release" "$EXPECTED" env RELEASE_BUILD_NUMBER=24 bash "$RESOLVER" provider

echo "Release-version contract tests passed"
