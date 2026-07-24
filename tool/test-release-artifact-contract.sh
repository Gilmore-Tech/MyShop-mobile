#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_SCRIPT="$ROOT_DIR/tool/build.sh"
VERIFIER="$ROOT_DIR/tool/verify-release-artifact.sh"
SOURCE_SHA="55d7823b6d81aac5ebd2c6b00d26c3e83261c435"

require_source_text() {
  local file="$1"
  local value="$2"
  local label="$3"
  if ! grep -Fq -- "$value" "$file"; then
    echo "FAIL: $label" >&2
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

bash -n "$BUILD_SCRIPT" "$VERIFIER"

for app in client provider; do
  require_source_text \
    "$ROOT_DIR/apps/$app/android/app/src/main/AndroidManifest.xml" \
    'com.gilmoretechnologies.myshop.SOURCE_COMMIT' \
    "$app Android manifest must expose source provenance"
  require_source_text \
    "$ROOT_DIR/apps/$app/android/app/src/main/AndroidManifest.xml" \
    'com.gilmoretechnologies.myshop.RELEASE_IDENTITY' \
    "$app Android manifest must bind the combined release identity"
  require_source_text \
    "$ROOT_DIR/apps/$app/android/app/build.gradle.kts" \
    'manifestPlaceholders["MYSHOP_SOURCE_COMMIT"]' \
    "$app Android build must bind source provenance"
  require_source_text \
    "$ROOT_DIR/apps/$app/ios/Runner/Info.plist" \
    '<key>MyShopSourceCommit</key>' \
    "$app iOS plist must expose source provenance"
  require_source_text \
    "$ROOT_DIR/apps/$app/ios/Runner/Info.plist" \
    '<key>MyShopReleaseIdentity</key>' \
    "$app iOS plist must bind the combined release identity"
done

require_source_text "$BUILD_SCRIPT" \
  'echo "MYSHOP_SOURCE_COMMIT=$SOURCE_COMMIT" >> "$GRADLE_PROPS"' \
  "Android build must write the reviewed source SHA"
require_source_text "$BUILD_SCRIPT" \
  'MYSHOP_SOURCE_COMMIT = $SOURCE_COMMIT' \
  "iOS build must write the reviewed source SHA"
require_source_text "$BUILD_SCRIPT" \
  'verify-release-artifact.sh' \
  "all release builds must invoke the package verifier"
require_source_text "$VERIFIER" \
  'EXPECTED_ANDROID_UPLOAD_CERT_SHA1=' \
  "Android upload identities must be pinned"
require_source_text "$VERIFIER" \
  'MyShopSourceCommit' \
  "iOS artifact verification must check source provenance"
require_source_text "$VERIFIER" \
  'PrivacyInfo.xcprivacy' \
  "iOS artifact verification must check the app privacy manifest"

expect_failure "missing verifier arguments" bash "$VERIFIER"
expect_failure "invalid app" \
  bash "$VERIFIER" artisan android /nonexistent 1.4.1 24 "$SOURCE_SHA"
expect_failure "invalid platform" \
  bash "$VERIFIER" client windows /nonexistent 1.4.1 24 "$SOURCE_SHA"
expect_failure "invalid source SHA" \
  bash "$VERIFIER" client android /nonexistent 1.4.1 24 short

# Historical artifacts are intentionally not test fixtures, but when they are
# present on the release machine they must fail the new provenance gate.
OLD_ANDROID="$ROOT_DIR/build/releases/1.4.1+23/MyShop-Client-Android-1.4.1+23.aab"
if [[ -f "$OLD_ANDROID" ]]; then
  expect_failure "historical Android artifact without native provenance" \
    bash "$VERIFIER" client android "$OLD_ANDROID" 1.4.1 23 "$SOURCE_SHA"
fi

OLD_IOS="$ROOT_DIR/build/releases/1.4.1+23/MyShop-Client-iOS-1.4.1+23.ipa"
if [[ -f "$OLD_IOS" ]]; then
  expect_failure "historical iOS artifact without native provenance" \
    env MYSHOP_EXPECTED_APPLE_TEAM_ID=KJ76HLC9YT \
    bash "$VERIFIER" client ios "$OLD_IOS" 1.4.1 23 "$SOURCE_SHA"
fi

echo "Release-artifact contract tests passed"
