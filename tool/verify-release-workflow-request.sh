#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "usage: verify-release-workflow-request.sh <source-sha> <expected-source-sha> <build-number> <client|provider|both> [repository-root]" >&2
  exit 2
fi

SOURCE_COMMIT="$1"
EXPECTED_SOURCE_COMMIT="$2"
BUILD_NUMBER="$3"
APP_SELECTION="$4"
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REPO_ROOT="${5:-$ROOT_DIR}"

if [[ "${GITHUB_EVENT_NAME:-}" != "workflow_dispatch" ]]; then
  echo "error: mobile releases must be started by workflow_dispatch" >&2
  exit 1
fi

if [[ "${GITHUB_REF:-}" != "refs/heads/main" ]]; then
  echo "error: mobile releases must be dispatched from exact main" >&2
  exit 1
fi

if [[ "${GITHUB_SHA:-}" != "$SOURCE_COMMIT" ]]; then
  echo "error: RELEASE_SOURCE_COMMIT must match the dispatched GitHub SHA" >&2
  exit 1
fi

if [[ "$EXPECTED_SOURCE_COMMIT" != "$SOURCE_COMMIT" ]]; then
  echo "error: operator-supplied expected source must match the dispatched GitHub SHA" >&2
  exit 1
fi

case "$APP_SELECTION" in
  client|provider|both) ;;
  *)
    echo "error: release app selection must be client, provider, or both" >&2
    exit 1
    ;;
esac

bash "$ROOT_DIR/tool/verify-release-source.sh" "$SOURCE_COMMIT" "$REPO_ROOT"

# Resolve both apps even for a single-app dispatch. Their shared marketing
# version and occupied-build floor must never drift silently.
for app in client provider; do
  RELEASE_BUILD_NUMBER="$BUILD_NUMBER" \
    bash "$ROOT_DIR/tool/resolve-release-version.sh" "$app" >/dev/null
done

echo "Release workflow request verified: source=$SOURCE_COMMIT build=$BUILD_NUMBER app=$APP_SELECTION"
