#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERIFIER="$ROOT_DIR/tool/verify-release-workflow-request.sh"
CI_VERIFIER="$ROOT_DIR/tool/verify-release-ci.sh"
ANDROID_WORKFLOW="$ROOT_DIR/.github/workflows/release-android.yml"
IOS_WORKFLOW="$ROOT_DIR/.github/workflows/release-ios.yml"
CI_WORKFLOW="$ROOT_DIR/.github/workflows/ci.yml"
README="$ROOT_DIR/README.md"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/myshop-release-workflow.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

require_source_text() {
  local file="$1"
  local value="$2"
  local label="$3"
  if ! grep -Fq -- "$value" "$file"; then
    echo "FAIL: $label" >&2
    exit 1
  fi
}

reject_source_text() {
  local file="$1"
  local value="$2"
  local label="$3"
  if grep -Fq -- "$value" "$file"; then
    echo "FAIL: $label" >&2
    exit 1
  fi
}

require_source_count() {
  local file="$1"
  local value="$2"
  local minimum="$3"
  local label="$4"
  local actual
  actual=$(grep -Fc -- "$value" "$file" || true)
  if (( actual < minimum )); then
    echo "FAIL: $label (expected at least $minimum, found $actual)" >&2
    exit 1
  fi
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $label unexpectedly succeeded" >&2
    exit 1
  fi
}

bash -n "$VERIFIER" "$CI_VERIFIER"

for workflow in "$CI_WORKFLOW" "$ANDROID_WORKFLOW" "$IOS_WORKFLOW"; do
  if grep -Eq '^[[:space:]]*-[[:space:]]+uses:[[:space:]]+[^@[:space:]]+@[^[:space:]]*(v[0-9]|main|master)([[:space:]]|$)' "$workflow"; then
    echo "FAIL: $(basename "$workflow") contains a mutable action ref" >&2
    exit 1
  fi
done

for workflow in "$ANDROID_WORKFLOW" "$IOS_WORKFLOW"; do
  require_source_text "$workflow" 'workflow_dispatch:' \
    "$(basename "$workflow") must be manually dispatched"
  reject_source_text "$workflow" '  push:' \
    "$(basename "$workflow") must not release from a push"
  reject_source_text "$workflow" '    tags:' \
    "$(basename "$workflow") must not derive a release from a tag"
  require_source_text "$workflow" 'build_number:' \
    "$(basename "$workflow") must require an explicit build number"
  require_source_text "$workflow" 'expected_source_sha:' \
    "$(basename "$workflow") must require the cross-platform source SHA"
  require_source_text "$workflow" 'RELEASE_SOURCE_COMMIT: ${{ github.sha }}' \
    "$(basename "$workflow") must bind source provenance to github.sha"
  require_source_text "$workflow" 'RELEASE_BUILD_NUMBER: ${{ inputs.build_number }}' \
    "$(basename "$workflow") must bind the operator build number"
  require_source_text "$workflow" 'RELEASE_EXPECTED_SOURCE_COMMIT: ${{ inputs.expected_source_sha }}' \
    "$(basename "$workflow") must bind the operator source SHA"
  require_source_text "$workflow" 'RELEASE_APP_SELECTION: ${{ inputs.app }}' \
    "$(basename "$workflow") must bind the operator app selection"
  require_source_text "$workflow" 'environment: mobile-store-release' \
    "$(basename "$workflow") must use the protected store-release environment"
  require_source_text "$workflow" 'cancel-in-progress: false' \
    "$(basename "$workflow") must serialize, not cancel, releases"
  require_source_text "$workflow" 'queue: max' \
    "$(basename "$workflow") must retain queued release requests"
  require_source_text "$workflow" 'verify-release-ci.sh' \
    "$(basename "$workflow") must require successful exact-source Mobile CI"
  require_source_text "$workflow" 'needs: verify-release-request' \
    "$(basename "$workflow") build must depend on request verification"
  require_source_count "$workflow" 'ref: ${{ github.sha }}' 2 \
    "$(basename "$workflow") checkouts must pin the dispatched SHA"
  require_source_count "$workflow" 'fetch-depth: 0' 2 \
    "$(basename "$workflow") must fetch complete source history"
  require_source_count "$workflow" \
    "+refs/heads/main:refs/remotes/origin/main" 3 \
    "$(basename "$workflow") must refresh exact main authority"
  require_source_count "$workflow" 'verify-release-workflow-request.sh' 2 \
    "$(basename "$workflow") must verify both the request and each build job"
  reject_source_text "$workflow" 'continue-on-error:' \
    "$(basename "$workflow") must fail when store upload fails"
  reject_source_text "$workflow" 'if: always()' \
    "$(basename "$workflow") must not report release success after failure"
done

require_source_text "$ANDROID_WORKFLOW" 'tracks: internal' \
  "Android releases must upload only to Internal Testing"
require_source_text "$ANDROID_WORKFLOW" \
  'r0adkll/upload-google-play@e738b9dd8f2476ea806d921b64aacd24f34515a5' \
  "Play upload must use the immutable v1.1.5 action commit"
reject_source_text "$ANDROID_WORKFLOW" "matrix.app == 'client' && secrets." \
  "Android must not fall through from an empty client secret to provider"
require_source_text "$IOS_WORKFLOW" 'Upload to TestFlight Internal' \
  "iOS releases must upload only to TestFlight Internal"
reject_source_text "$IOS_WORKFLOW" "matrix.app == 'client' && secrets." \
  "iOS must not fall through from an empty client secret to provider"
require_source_text "$IOS_WORKFLOW" \
  'apple-actions/upload-testflight-build@1ad58030672057aa084b4e96beb6f7a8c627f9e6' \
  "TestFlight upload must use the immutable v5.2.1 action commit"
reject_source_text "$IOS_WORKFLOW" 'apple-actions/upload-testflight-build@v1' \
  "TestFlight upload must not use the obsolete Node 12/altool action"
require_source_text "$IOS_WORKFLOW" 'backend: appstore-api' \
  "TestFlight upload must use the App Store Connect API backend"
require_source_text "$IOS_WORKFLOW" "wait-for-processing: 'true'" \
  "TestFlight upload must wait for App Store processing"
require_source_text "$IOS_WORKFLOW" '--api_key_path "$API_KEY_PATH"' \
  "Match must receive explicit non-interactive App Store Connect credentials"
require_source_text "$IOS_WORKFLOW" 'gem install fastlane -v 2.237.0' \
  "iOS signing must use the reviewed Fastlane version"
for bundle_id in \
  com.gilmoretech.myshopprovider \
  com.gilmoretech.myshopprovider.NotificationService \
  com.gilmoretech.myshopprovider.RequestNotificationContent \
  com.gilmoretech.myshopprovider.RequestLiveActivity; do
  require_source_text "$IOS_WORKFLOW" "$bundle_id" \
    "Provider Match sync must include $bundle_id"
done

reject_source_text "$README" 'git push --tags' \
  "README must not claim tags trigger a release"
require_source_text "$README" 'gh workflow run release-android.yml --ref main' \
  "README must document exact-main Android dispatch"
require_source_text "$README" 'gh workflow run release-ios.yml --ref main' \
  "README must document exact-main iOS dispatch"
require_source_text "$ROOT_DIR/docs/release-setup.md" \
  'Environment secrets → Add environment secret' \
  "runbook must configure protected environment secrets before release"
reject_source_text "$ROOT_DIR/docs/release-setup.md" \
  'New repository secret' \
  "runbook must not place release credentials in repository secrets"

for app in client provider; do
  notes="$ROOT_DIR/.github/release-notes/$app/whatsnew-en-US"
  if [[ ! -s "$notes" ]]; then
    echo "FAIL: $app Play release notes are missing" >&2
    exit 1
  fi
  if (( $(wc -c < "$notes") > 500 )); then
    echo "FAIL: $app Play release notes exceed 500 bytes" >&2
    exit 1
  fi
done

REPO="$TMP_ROOT/repository"
git init -q "$REPO"
git -C "$REPO" config user.name "Release Contract"
git -C "$REPO" config user.email "release-contract@example.invalid"
printf '%s\n' "reviewed" > "$REPO/release.txt"
git -C "$REPO" add release.txt
git -C "$REPO" commit -qm "reviewed source"
REVIEWED_SOURCE=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" update-ref refs/remotes/origin/main "$REVIEWED_SOURCE"

env \
  GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_REF=refs/heads/main \
  GITHUB_SHA="$REVIEWED_SOURCE" \
  bash "$VERIFIER" "$REVIEWED_SOURCE" "$REVIEWED_SOURCE" 38 both "$REPO" >/dev/null

expect_failure "non-dispatch event" env \
  GITHUB_EVENT_NAME=push \
  GITHUB_REF=refs/heads/main \
  GITHUB_SHA="$REVIEWED_SOURCE" \
  bash "$VERIFIER" "$REVIEWED_SOURCE" "$REVIEWED_SOURCE" 38 both "$REPO"
expect_failure "non-main ref" env \
  GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_REF=refs/heads/staging \
  GITHUB_SHA="$REVIEWED_SOURCE" \
  bash "$VERIFIER" "$REVIEWED_SOURCE" "$REVIEWED_SOURCE" 38 both "$REPO"
expect_failure "source different from event SHA" env \
  GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_REF=refs/heads/main \
  GITHUB_SHA=0000000000000000000000000000000000000000 \
  bash "$VERIFIER" "$REVIEWED_SOURCE" "$REVIEWED_SOURCE" 38 both "$REPO"
expect_failure "operator source mismatch" env \
  GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_REF=refs/heads/main \
  GITHUB_SHA="$REVIEWED_SOURCE" \
  bash "$VERIFIER" "$REVIEWED_SOURCE" 0000000000000000000000000000000000000000 38 both "$REPO"
expect_failure "invalid app selection" env \
  GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_REF=refs/heads/main \
  GITHUB_SHA="$REVIEWED_SOURCE" \
  bash "$VERIFIER" "$REVIEWED_SOURCE" "$REVIEWED_SOURCE" 38 artisan "$REPO"
expect_failure "occupied build number" env \
  GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_REF=refs/heads/main \
  GITHUB_SHA="$REVIEWED_SOURCE" \
  bash "$VERIFIER" "$REVIEWED_SOURCE" "$REVIEWED_SOURCE" 37 both "$REPO"
expect_failure "overflow build number" env \
  GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_REF=refs/heads/main \
  GITHUB_SHA="$REVIEWED_SOURCE" \
  bash "$VERIFIER" "$REVIEWED_SOURCE" "$REVIEWED_SOURCE" 18446744073709551654 both "$REPO"

CI_FIXTURE="$TMP_ROOT/mobile-ci.json"
cat > "$CI_FIXTURE" <<EOF
{"workflow_runs":[{"head_sha":"$REVIEWED_SOURCE","head_branch":"main","event":"push","status":"completed","conclusion":"success","path":".github/workflows/ci.yml@main"}]}
EOF
bash "$CI_VERIFIER" "$REVIEWED_SOURCE" "$CI_FIXTURE" >/dev/null

cat > "$CI_FIXTURE" <<EOF
{"workflow_runs":[{"head_sha":"$REVIEWED_SOURCE","head_branch":"main","event":"push","status":"completed","conclusion":"failure","path":".github/workflows/ci.yml@main"}]}
EOF
expect_failure "failed Mobile CI" bash "$CI_VERIFIER" "$REVIEWED_SOURCE" "$CI_FIXTURE"

echo "Release-workflow contract tests passed"
