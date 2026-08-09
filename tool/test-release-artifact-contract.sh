#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_SCRIPT="$ROOT_DIR/tool/build.sh"
VERIFIER="$ROOT_DIR/tool/verify-release-artifact.sh"
SOURCE_VERIFIER="$ROOT_DIR/tool/verify-release-source.sh"
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

bash -n "$BUILD_SCRIPT" "$VERIFIER" "$SOURCE_VERIFIER"

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
  require_source_text \
    "$ROOT_DIR/apps/$app/ios/Runner/PrivacyInfo.xcprivacy" \
    'NSPrivacyCollectedDataTypeProductInteraction' \
    "$app iOS privacy manifest must declare product-interaction telemetry"
  require_source_text \
    "$ROOT_DIR/apps/$app/ios/Runner/PrivacyInfo.xcprivacy" \
    'NSPrivacyCollectedDataTypePurposeAnalytics' \
    "$app iOS privacy manifest must declare the telemetry analytics purpose"
done

require_source_text "$BUILD_SCRIPT" \
  'verify-release-source.sh' \
  "all release builds must verify the clean reviewed main source"
require_source_text "$BUILD_SCRIPT" \
  'echo "MYSHOP_SOURCE_COMMIT=$SOURCE_COMMIT" >> "$GRADLE_PROPS"' \
  "Android builds must write the reviewed source SHA"
require_source_text "$BUILD_SCRIPT" \
  'MYSHOP_SOURCE_COMMIT = $SOURCE_COMMIT' \
  "iOS builds must write the reviewed source SHA"
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
require_source_text "$VERIFIER" \
  'cmp -s "$reviewed_privacy_manifest" "$app_bundle/PrivacyInfo.xcprivacy"' \
  "iOS artifact verification must compare packaged privacy declarations with reviewed source"
require_source_text "$VERIFIER" \
  'API_BASE_URL is required in release builds. Use tool/build.sh.' \
  "release verification must reject the missing production API startup failure"
require_source_text "$VERIFIER" \
  "'lib/*/libapp.so'" \
  "APK verification must inspect the compiled Dart release payload"
require_source_text "$VERIFIER" \
  "'base/lib/*/libapp.so'" \
  "App Bundle verification must inspect the compiled Dart release payload"

expect_failure "missing verifier arguments" bash "$VERIFIER"
expect_failure "invalid app" \
  bash "$VERIFIER" artisan android /nonexistent 1.4.1 25 "$SOURCE_SHA"
expect_failure "invalid platform" \
  bash "$VERIFIER" client windows /nonexistent 1.4.1 25 "$SOURCE_SHA"
expect_failure "invalid source SHA" \
  bash "$VERIFIER" client android /nonexistent 1.4.1 25 short

echo "Release-artifact contract tests passed"
