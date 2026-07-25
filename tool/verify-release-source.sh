#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: verify-release-source.sh <reviewed-source-sha> [repository-root]" >&2
  exit 2
fi

EXPECTED_SOURCE="$1"
REPO_ROOT="${2:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"

if [[ ! "$EXPECTED_SOURCE" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: RELEASE_SOURCE_COMMIT must be the full lowercase 40-character reviewed main commit SHA" >&2
  exit 1
fi

if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: release source is not an inspectable Git worktree: $REPO_ROOT" >&2
  exit 1
fi

CURRENT_SOURCE=$(git -C "$REPO_ROOT" rev-parse HEAD)
if [[ "$CURRENT_SOURCE" != "$EXPECTED_SOURCE" ]]; then
  echo "error: HEAD $CURRENT_SOURCE does not match reviewed source $EXPECTED_SOURCE" >&2
  exit 1
fi

if ! git -C "$REPO_ROOT" rev-parse \
  --verify refs/remotes/origin/main >/dev/null 2>&1; then
  echo "error: origin/main is unavailable; fetch and review the remote before building" >&2
  exit 1
fi

REMOTE_MAIN=$(git -C "$REPO_ROOT" rev-parse refs/remotes/origin/main)
if [[ "$CURRENT_SOURCE" != "$REMOTE_MAIN" ]]; then
  echo "error: release builds must use exact origin/main $REMOTE_MAIN, got $CURRENT_SOURCE" >&2
  exit 1
fi

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" ]]; then
  echo "error: release builds require a clean worktree; commit or remove every change first" >&2
  exit 1
fi

echo "Release source verified: $CURRENT_SOURCE"
