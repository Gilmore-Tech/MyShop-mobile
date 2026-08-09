#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [[ $# -ne 6 ]]; then
  echo "usage: verify-release-artifact.sh <client|provider> <android|ios> <artifact> <version> <build> <source-sha>" >&2
  exit 2
fi

APP="$1"
PLATFORM="$2"
ARTIFACT="$3"
EXPECTED_VERSION="$4"
EXPECTED_BUILD="$5"
EXPECTED_SOURCE="$6"
EXPECTED_RELEASE_IDENTITY="${EXPECTED_VERSION}+${EXPECTED_BUILD}@${EXPECTED_SOURCE}"
PRODUCTION_API_ENDPOINT="${MYSHOP_PRODUCTION_API_ENDPOINT:-https://api.myshop.gilmoretechnologiesgh.com/v1}"
EXPECTED_APPLE_TEAM_ID="${MYSHOP_EXPECTED_APPLE_TEAM_ID:-}"

case "$APP" in
  client)
    EXPECTED_ANDROID_ID="com.gilmoretech.myshopclient"
    EXPECTED_IOS_ID="com.gilmoretech.myshopclient"
    EXPECTED_ANDROID_UPLOAD_CERT_SHA1="AC:34:81:89:11:BE:68:9C:34:E8:D2:E8:2C:B4:D8:98:CA:5D:E6:F9"
    ;;
  provider)
    EXPECTED_ANDROID_ID="com.gilmoretech.myshopprovider"
    EXPECTED_IOS_ID="com.gilmoretech.myshopprovider"
    EXPECTED_ANDROID_UPLOAD_CERT_SHA1="01:E7:6B:07:01:8C:28:8E:75:C3:84:5A:04:34:A4:D9:A7:42:72:6D"
    ;;
  *)
    echo "error: app must be client or provider" >&2
    exit 2
    ;;
esac

case "$PLATFORM" in
  android|ios) ;;
  *)
    echo "error: platform must be android or ios" >&2
    exit 2
    ;;
esac

if [[ ! "$EXPECTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: expected version must be a three-part semantic version" >&2
  exit 2
fi
if [[ ! "$EXPECTED_BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: expected build must be a positive decimal integer" >&2
  exit 2
fi
if [[ ! "$EXPECTED_SOURCE" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: expected source SHA must be 40 lowercase hexadecimal characters" >&2
  exit 2
fi
if [[ ! -f "$ARTIFACT" ]]; then
  echo "error: artifact not found: $ARTIFACT" >&2
  exit 1
fi

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/myshop-release-artifact.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

require_text() {
  local file="$1"
  local value="$2"
  local label="$3"
  if ! grep -aFq -- "$value" "$file"; then
    echo "error: $label is absent from the packaged metadata" >&2
    exit 1
  fi
}

require_extracted_text() {
  local value="$1"
  local label="$2"
  if ! grep -R -aFq -- "$value" "$TMP_ROOT"; then
    echo "error: $label is absent from the artifact contents" >&2
    exit 1
  fi
}

find_android_tool() {
  local name="$1"
  local candidate=""
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return
  fi
  for sdk in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" "$HOME/Library/Android/sdk"; do
    [[ -n "$sdk" && -d "$sdk" ]] || continue
    if [[ "$name" == "apkanalyzer" && -x "$sdk/cmdline-tools/latest/bin/apkanalyzer" ]]; then
      printf '%s\n' "$sdk/cmdline-tools/latest/bin/apkanalyzer"
      return
    fi
    candidate=$(
      find "$sdk/build-tools" -type f -name "$name" -perm -111 2>/dev/null |
        sort -V |
        tail -n 1
    )
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  return 1
}

verify_android() {
  local extension="${ARTIFACT##*.}"
  local manifest="$TMP_ROOT/AndroidManifest.xml"
  local actual_cert_sha1=""

  case "$extension" in
    apk)
      local analyzer
      local signer
      analyzer=$(find_android_tool apkanalyzer) || {
        echo "error: apkanalyzer was not found in PATH or the Android SDK" >&2
        exit 1
      }
      signer=$(find_android_tool apksigner) || {
        echo "error: apksigner was not found in PATH or the Android SDK" >&2
        exit 1
      }
      [[ "$("$analyzer" manifest application-id "$ARTIFACT" 2>/dev/null)" == "$EXPECTED_ANDROID_ID" ]] || {
        echo "error: Android application ID does not match $EXPECTED_ANDROID_ID" >&2
        exit 1
      }
      [[ "$("$analyzer" manifest version-name "$ARTIFACT" 2>/dev/null)" == "$EXPECTED_VERSION" ]] || {
        echo "error: Android version name does not match $EXPECTED_VERSION" >&2
        exit 1
      }
      [[ "$("$analyzer" manifest version-code "$ARTIFACT" 2>/dev/null)" == "$EXPECTED_BUILD" ]] || {
        echo "error: Android version code does not match $EXPECTED_BUILD" >&2
        exit 1
      }
      "$analyzer" manifest print "$ARTIFACT" > "$manifest" 2>/dev/null
      "$signer" verify --verbose "$ARTIFACT" >/dev/null
      actual_cert_sha1=$(
        "$signer" verify --print-certs "$ARTIFACT" |
          awk -F': ' '/certificate SHA-1 digest:/ { print toupper($2); exit }' |
          sed 's/../&:/g; s/:$//'
      )
      ;;
    aab)
      command -v jarsigner >/dev/null 2>&1 &&
        command -v keytool >/dev/null 2>&1 || {
        echo "error: jarsigner and keytool are required to verify an Android App Bundle" >&2
        exit 1
      }
      unzip -tq "$ARTIFACT" >/dev/null
      unzip -Z1 "$ARTIFACT" |
        awk '$0 == "BundleConfig.pb" { found=1 } END { exit !found }' || {
        echo "error: Android App Bundle is missing BundleConfig.pb" >&2
        exit 1
      }
      unzip -Z1 "$ARTIFACT" |
        awk '$0 == "base/resources.pb" { found=1 } END { exit !found }' || {
        echo "error: Android App Bundle is missing base/resources.pb" >&2
        exit 1
      }
      unzip -p "$ARTIFACT" base/manifest/AndroidManifest.xml > "$manifest"
      [[ -s "$manifest" ]] || {
        echo "error: Android App Bundle has no base manifest" >&2
        exit 1
      }
      require_text "$manifest" "$EXPECTED_ANDROID_ID" "Android application ID"
      require_text "$manifest" "$EXPECTED_VERSION" "Android version name"
      require_text "$manifest" \
        "com.gilmoretechnologies.myshop.BUILD_NUMBER" \
        "build-number provenance key"
      require_text "$manifest" "$EXPECTED_BUILD" \
        "Android build-number provenance value"
      jarsigner -verify "$ARTIFACT" >/dev/null
      actual_cert_sha1=$(
        keytool -printcert -jarfile "$ARTIFACT" |
          awk '/SHA1:/ { print toupper($2); exit }'
      )
      ;;
    *)
      echo "error: Android artifact must be an .apk or .aab" >&2
      exit 2
      ;;
  esac

  require_text "$manifest" \
    "com.gilmoretechnologies.myshop.SOURCE_COMMIT" \
    "source provenance key"
  require_text "$manifest" "$EXPECTED_SOURCE" "reviewed source SHA"
  require_text "$manifest" \
    "com.gilmoretechnologies.myshop.MARKETING_VERSION" \
    "marketing-version provenance key"
  require_text "$manifest" \
    "com.gilmoretechnologies.myshop.RELEASE_IDENTITY" \
    "release-identity key"
  require_text "$manifest" "$EXPECTED_RELEASE_IDENTITY" \
    "combined release identity"

  actual_cert_sha1=$(
    printf '%s' "$actual_cert_sha1" | tr '[:lower:]' '[:upper:]'
  )
  [[ "$actual_cert_sha1" == "$EXPECTED_ANDROID_UPLOAD_CERT_SHA1" ]] || {
    echo "error: Android artifact signer SHA-1 does not match the reviewed upload identity" >&2
    exit 1
  }

  unzip -qq "$ARTIFACT" -d "$TMP_ROOT/package"
}

verify_ios() {
  [[ "$ARTIFACT" == *.ipa ]] || {
    echo "error: iOS artifact must be an .ipa" >&2
    exit 2
  }
  [[ "$(uname -s)" == "Darwin" ]] || {
    echo "error: iOS artifact verification requires macOS" >&2
    exit 2
  }
  [[ "$EXPECTED_APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || {
    echo "error: MYSHOP_EXPECTED_APPLE_TEAM_ID must be the reviewed 10-character team ID" >&2
    exit 2
  }

  unzip -qq "$ARTIFACT" -d "$TMP_ROOT/package"
  local app_bundle
  app_bundle=$(
    find "$TMP_ROOT/package/Payload" \
      -maxdepth 1 -type d -name '*.app' -print |
      head -n 1
  )
  [[ -n "$app_bundle" && -f "$app_bundle/Info.plist" ]] || {
    echo "error: IPA does not contain one inspectable application bundle" >&2
    exit 1
  }

  [[ "$(plutil -extract CFBundleIdentifier raw -o - "$app_bundle/Info.plist")" == "$EXPECTED_IOS_ID" ]] || {
    echo "error: iOS bundle ID does not match $EXPECTED_IOS_ID" >&2
    exit 1
  }
  [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$app_bundle/Info.plist")" == "$EXPECTED_VERSION" ]] || {
    echo "error: iOS marketing version does not match $EXPECTED_VERSION" >&2
    exit 1
  }
  [[ "$(plutil -extract CFBundleVersion raw -o - "$app_bundle/Info.plist")" == "$EXPECTED_BUILD" ]] || {
    echo "error: iOS build number does not match $EXPECTED_BUILD" >&2
    exit 1
  }
  [[ "$(plutil -extract MyShopSourceCommit raw -o - "$app_bundle/Info.plist" 2>/dev/null || true)" == "$EXPECTED_SOURCE" ]] || {
    echo "error: iOS artifact is not bound to reviewed source SHA $EXPECTED_SOURCE" >&2
    exit 1
  }
  [[ "$(plutil -extract MyShopReleaseIdentity raw -o - "$app_bundle/Info.plist" 2>/dev/null || true)" == "$EXPECTED_RELEASE_IDENTITY" ]] || {
    echo "error: iOS release identity does not match $EXPECTED_RELEASE_IDENTITY" >&2
    exit 1
  }
  [[ -f "$app_bundle/PrivacyInfo.xcprivacy" ]] || {
    echo "error: iOS application privacy manifest is absent" >&2
    exit 1
  }
  local reviewed_privacy_manifest="$ROOT_DIR/apps/$APP/ios/Runner/PrivacyInfo.xcprivacy"
  [[ -f "$reviewed_privacy_manifest" ]] || {
    echo "error: reviewed iOS application privacy manifest is absent from source" >&2
    exit 1
  }
  plutil -lint "$app_bundle/PrivacyInfo.xcprivacy" >/dev/null || {
    echo "error: packaged iOS application privacy manifest is invalid" >&2
    exit 1
  }
  cmp -s "$reviewed_privacy_manifest" "$app_bundle/PrivacyInfo.xcprivacy" || {
    echo "error: packaged iOS privacy declarations differ from reviewed source" >&2
    exit 1
  }
  [[ -f "$app_bundle/embedded.mobileprovision" &&
    -d "$app_bundle/_CodeSignature" ]] || {
    echo "error: iOS distribution provisioning or code-signature payload is absent" >&2
    exit 1
  }
  codesign --verify --deep --strict "$app_bundle" >/dev/null 2>&1 || {
    echo "error: iOS application signature verification failed" >&2
    exit 1
  }
  local signature_details
  signature_details=$(codesign -d --verbose=4 "$app_bundle" 2>&1) || {
    echo "error: iOS CodeDirectory could not be inspected" >&2
    exit 1
  }
  grep -Fq "Identifier=$EXPECTED_IOS_ID" <<< "$signature_details" || {
    echo "error: iOS signature identifier does not match $EXPECTED_IOS_ID" >&2
    exit 1
  }
  grep -Fqx "TeamIdentifier=$EXPECTED_APPLE_TEAM_ID" <<< "$signature_details" || {
    echo "error: iOS signature TeamIdentifier does not match $EXPECTED_APPLE_TEAM_ID" >&2
    exit 1
  }
}

case "$PLATFORM" in
  android) verify_android ;;
  ios) verify_ios ;;
esac

require_extracted_text "$PRODUCTION_API_ENDPOINT" "production API endpoint"
if grep -R -aFq -- \
  "API_BASE_URL is required in release builds. Use tool/build.sh." \
  "$TMP_ROOT"; then
  echo "error: packaged app still contains the missing production API startup failure" >&2
  exit 1
fi
if grep -R -aFq -- "myshop-api-test.onrender.com" "$TMP_ROOT"; then
  echo "error: staging API endpoint is embedded in the release artifact" >&2
  exit 1
fi

echo "Release artifact verified: $APP/$PLATFORM $EXPECTED_VERSION+$EXPECTED_BUILD @ $EXPECTED_SOURCE"
