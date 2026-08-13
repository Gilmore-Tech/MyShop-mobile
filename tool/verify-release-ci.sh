#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: verify-release-ci.sh <source-sha> [workflow-runs-json]" >&2
  exit 2
fi

SOURCE_COMMIT="$1"
RUNS_FILE="${2:-}"

if [[ ! "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: release CI source must be a full lowercase 40-character SHA" >&2
  exit 1
fi

TMP_RESPONSE=""
if [[ -z "$RUNS_FILE" ]]; then
  if [[ -z "${GITHUB_REPOSITORY:-}" || -z "${GH_TOKEN:-}" ]]; then
    echo "error: GITHUB_REPOSITORY and GH_TOKEN are required to verify Mobile CI" >&2
    exit 1
  fi
  TMP_RESPONSE=$(mktemp "${TMPDIR:-/tmp}/myshop-mobile-ci-runs.XXXXXX")
  trap 'rm -f "$TMP_RESPONSE"' EXIT
  gh api \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "/repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$SOURCE_COMMIT&event=push&branch=main&status=completed&per_page=100" \
    > "$TMP_RESPONSE"
  RUNS_FILE="$TMP_RESPONSE"
fi

if [[ ! -f "$RUNS_FILE" ]]; then
  echo "error: workflow-runs response is unavailable: $RUNS_FILE" >&2
  exit 1
fi

if ! jq -e --arg source "$SOURCE_COMMIT" '
  [
    .workflow_runs[]
    | select(
        .head_sha == $source and
        .head_branch == "main" and
        .event == "push" and
        .status == "completed" and
        .conclusion == "success" and
        (.path | split("@")[0]) == ".github/workflows/ci.yml"
      )
  ]
  | length > 0
' "$RUNS_FILE" >/dev/null; then
  echo "error: exact source $SOURCE_COMMIT has no completed successful Mobile CI push run on main" >&2
  exit 1
fi

echo "Mobile CI verified for exact source: $SOURCE_COMMIT"
