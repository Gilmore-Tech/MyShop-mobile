#!/usr/bin/env bash
# Build a MyShop mobile app for production.
#
#   RELEASE_SOURCE_COMMIT=<reviewed-origin-main-sha> RELEASE_BUILD_NUMBER=<console-verified> tool/build.sh client android
#   RELEASE_SOURCE_COMMIT=<reviewed-origin-main-sha> RELEASE_BUILD_NUMBER=<console-verified> tool/build.sh client ios
#   RELEASE_SOURCE_COMMIT=<reviewed-origin-main-sha> RELEASE_BUILD_NUMBER=<console-verified> tool/build.sh provider android
#   RELEASE_SOURCE_COMMIT=<reviewed-origin-main-sha> RELEASE_BUILD_NUMBER=<console-verified> tool/build.sh provider ios
#   tool/build.sh provider android --validate-only  # config check, no build
#
# Reads `.env.prod` (gitignored — copy from `.env.prod.example` and fill in
# the PRODUCTION-restricted keys) and threads the values through every
# build surface that needs them.
#
# Google Maps keys are restricted per app AND per platform — an Android key
# carries an Android app restriction, an iOS key an iOS one, so they cannot
# be the same key. `.env.prod` therefore holds four keys and this script
# selects the one matching the (app, platform) being built:
#
#   GOOGLE_MAPS_API_KEY_CLIENT_ANDROID
#   GOOGLE_MAPS_API_KEY_CLIENT_IOS
#   GOOGLE_MAPS_API_KEY_PROVIDER_ANDROID
#   GOOGLE_MAPS_API_KEY_PROVIDER_IOS
#
# (A single legacy `GOOGLE_MAPS_API_KEY` is still honoured as a fallback.)
# The selected key is threaded through every build surface:
#
#   - Dart code: `--dart-define=GOOGLE_MAPS_API_KEY=<selected>` (plus a
#     `--dart-define` for every other line in `.env.prod`).
#   - Android native: writes `apps/<app>/android/gradle.properties`'s
#     `MAPS_API_KEY` so AndroidManifest's `${MAPS_API_KEY}` placeholder
#     resolves at native build time.
#   - iOS native: writes `apps/<app>/ios/Flutter/Secrets.xcconfig` so the
#     `Info.plist` `$(GOOGLE_MAPS_API_KEY)` substitution resolves. Both
#     Debug.xcconfig and Release.xcconfig `#include?` it.
#
# All three files are gitignored. The script is the only thing that touches
# them — never commit them, never paste keys into the Xcode UI.

set -euo pipefail

is_placeholder() {
  case "$1" in
    ""|*"..."*|*"replace-me"*|*"REPLACE"*|*"YOUR_"*|*"your-account"*)
      return 0
      ;;
  esac
  return 1
}

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

if [[ $# -lt 2 ]]; then
  echo "usage: RELEASE_BUILD_NUMBER=<console-verified integer> tool/build.sh <client|provider> <android|android-apk|ios> [extra flutter args...]" >&2
  exit 2
fi

APP="$1"
PLATFORM="$2"
shift 2
VALIDATE_ONLY=false
if [[ "${1:-}" == "--validate-only" ]]; then
  VALIDATE_ONLY=true
  shift
fi

case "$APP" in
  client|provider) ;;
  *)
    echo "error: app must be 'client' or 'provider', got '$APP'" >&2
    exit 2
    ;;
esac

case "$PLATFORM" in
  android|android-apk|ios) ;;
  *)
    echo "error: platform must be 'android', 'android-apk', or 'ios', got '$PLATFORM'" >&2
    exit 2
    ;;
esac

SOURCE_COMMIT=""
if [[ "$VALIDATE_ONLY" == false ]]; then
  SOURCE_COMMIT="${RELEASE_SOURCE_COMMIT:-}"
  bash "$REPO_ROOT/tool/verify-release-source.sh" \
    "$SOURCE_COMMIT" "$REPO_ROOT"
fi

ENV_FILE="$REPO_ROOT/.env.prod"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found. Copy .env.dev.example to .env.prod and fill in the PRODUCTION-restricted keys." >&2
  exit 1
fi

# Parse `.env.prod` once into a flat `--dart-define` array. The Google Maps
# keys are handled specially: rather than passing all four as dart-defines
# (which would bake every app/platform key into every build), we capture them
# as shell variables and select the one for this (app, platform) afterwards.
#
# Pre-initialise all four (plus the legacy generic) to empty so the indirect
# lookup `${!SPECIFIC_VAR}` is safe under `set -u`. Avoids `declare -A` so the
# script works on macOS's stock bash 3.2 as well as bash 5+ on CI runners.
DEFINES=()
GOOGLE_MAPS_API_KEY=""
GOOGLE_MAPS_API_KEY_CLIENT_ANDROID=""
GOOGLE_MAPS_API_KEY_CLIENT_IOS=""
GOOGLE_MAPS_API_KEY_PROVIDER_ANDROID=""
GOOGLE_MAPS_API_KEY_PROVIDER_IOS=""
MAPS_ANDROID_CERT_SHA1=""
MAPS_ANDROID_CERT_SHA1_CLIENT=""
MAPS_ANDROID_CERT_SHA1_PROVIDER=""
API_BASE_URL=""
MAPBOX_ACCESS_TOKEN=""
MAPBOX_STYLE_URL=""
while IFS='=' read -r key value; do
  key="${key#"${key%%[![:space:]]*}"}"
  [[ -z "$key" || "$key" == \#* ]] && continue
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  if [[ "$key" == "MYSHOP_SOURCE_COMMIT" ]]; then
    echo "error: MYSHOP_SOURCE_COMMIT is controlled by RELEASE_SOURCE_COMMIT, not $ENV_FILE" >&2
    exit 1
  fi
  # Capture the per-(app[,platform]) Maps keys and Android cert SHA-1s into
  # like-named shell vars and skip the dart-define — the selected ones are
  # appended after the loop. `printf -v` (bash 3.1+) is the bash-3.2-safe way
  # to assign to a dynamically-named variable.
  if [[ "$key" == "GOOGLE_MAPS_API_KEY" || "$key" == GOOGLE_MAPS_API_KEY_* \
     || "$key" == "MAPS_ANDROID_CERT_SHA1" || "$key" == MAPS_ANDROID_CERT_SHA1_* ]]; then
    printf -v "$key" '%s' "$value"
    continue
  fi
  case "$key" in
    API_BASE_URL|MAPBOX_ACCESS_TOKEN|MAPBOX_STYLE_URL)
      printf -v "$key" '%s' "$value"
      ;;
  esac
  DEFINES+=("--dart-define=${key}=${value}")
done < "$ENV_FILE"

if [[ -n "$SOURCE_COMMIT" ]]; then
  # Retain exact source provenance in the compiled Dart snapshot. The same
  # value is also embedded in native Android/iOS metadata below.
  DEFINES+=("--dart-define=MYSHOP_SOURCE_COMMIT=${SOURCE_COMMIT}")
fi

# Production builds must never fall back to a staging URL or placeholder
# service credentials. Fail before invoking Flutter so CI cannot publish a
# healthy-looking binary wired to the wrong backend.
for REQUIRED_VAR in API_BASE_URL MAPBOX_ACCESS_TOKEN MAPBOX_STYLE_URL; do
  REQUIRED_VAL="${!REQUIRED_VAR}"
  if is_placeholder "$REQUIRED_VAL"; then
    echo "error: $REQUIRED_VAR is missing or still a placeholder in $ENV_FILE" >&2
    exit 1
  fi
done
case "$API_BASE_URL" in
  https://*/v1) ;;
  *)
    echo "error: API_BASE_URL must be HTTPS and end in /v1, got '$API_BASE_URL'" >&2
    exit 1
    ;;
esac
case "$MAPBOX_STYLE_URL" in
  mapbox://styles/*/*) ;;
  *)
    echo "error: MAPBOX_STYLE_URL must look like mapbox://styles/account/style" >&2
    exit 1
    ;;
esac

# Select the Maps key for this (app, platform). android and android-apk
# share the Android key; ios uses the iOS key.
case "$PLATFORM" in
  android|android-apk) MAPS_PLATFORM="ANDROID" ;;
  ios)                 MAPS_PLATFORM="IOS" ;;
esac
case "$APP" in
  client)   MAPS_APP="CLIENT" ;;
  provider) MAPS_APP="PROVIDER" ;;
esac
SPECIFIC_VAR="GOOGLE_MAPS_API_KEY_${MAPS_APP}_${MAPS_PLATFORM}"
SPECIFIC_VAL="${!SPECIFIC_VAR}"
if is_placeholder "$SPECIFIC_VAL"; then SPECIFIC_VAL=""; fi
if is_placeholder "$GOOGLE_MAPS_API_KEY"; then GOOGLE_MAPS_API_KEY=""; fi
if [[ -n "$SPECIFIC_VAL" ]]; then
  GOOGLE_MAPS_API_KEY="$SPECIFIC_VAL"
  echo "→ Maps key: $SPECIFIC_VAR"
elif [[ -n "$GOOGLE_MAPS_API_KEY" ]]; then
  # Legacy single-key .env.prod that predates the per-platform split — all
  # four targets share this one key.
  echo "→ Maps key: $SPECIFIC_VAR unset — falling back to legacy GOOGLE_MAPS_API_KEY"
else
  echo "error: no Maps key for this build. Set $SPECIFIC_VAR (preferred) or a" >&2
  echo "       legacy GOOGLE_MAPS_API_KEY in $ENV_FILE." >&2
  exit 1
fi

# Dart side reads String.fromEnvironment('GOOGLE_MAPS_API_KEY').
DEFINES+=("--dart-define=GOOGLE_MAPS_API_KEY=${GOOGLE_MAPS_API_KEY}")

# Android cert SHA-1 for the `X-Android-Cert` header that MapsConfig attaches
# to direct REST calls (Places / Directions / Roads / Static Maps) so an
# Android-application-restricted key accepts them. Per app — client and
# provider are signed with different certs. Only used on Android (ignored by
# MapsConfig.restApiHeaders on iOS), so it's harmless in an iOS build.
CERT_VAR="MAPS_ANDROID_CERT_SHA1_${MAPS_APP}"
CERT_VAL="${!CERT_VAR}"
if is_placeholder "$CERT_VAL"; then CERT_VAL=""; fi
if [[ -z "$CERT_VAL" ]]; then CERT_VAL="$MAPS_ANDROID_CERT_SHA1"; fi
if is_placeholder "$CERT_VAL"; then CERT_VAL=""; fi
DEFINES+=("--dart-define=MAPS_ANDROID_CERT_SHA1=${CERT_VAL}")
if [[ -z "$CERT_VAL" && ( "$PLATFORM" == "android" || "$PLATFORM" == "android-apk" ) ]]; then
  echo "error: no $CERT_VAR (or generic MAPS_ANDROID_CERT_SHA1) in $ENV_FILE." >&2
  echo "       Android-restricted Maps web-service calls require the app signing SHA-1." >&2
  exit 1
fi

if [[ "$VALIDATE_ONLY" == true ]]; then
  echo "✓ production config valid for $APP/$PLATFORM"
  exit 0
fi

APP_DIR="$REPO_ROOT/apps/$APP"
for EXTRA_ARG in "$@"; do
  case "$EXTRA_ARG" in
    --build-name|--build-name=*|--build-number|--build-number=*)
      echo "error: do not pass $EXTRA_ARG directly; set RELEASE_BUILD_NUMBER after checking both private store consoles" >&2
      exit 2
      ;;
    *MYSHOP_MARKETING_VERSION*)
      echo "error: do not override MYSHOP_MARKETING_VERSION; it is pinned by resolve-release-version.sh" >&2
      exit 2
      ;;
  esac
done

RELEASE_VERSION_ARGS=()
while IFS= read -r VERSION_ARG; do
  RELEASE_VERSION_ARGS+=("$VERSION_ARG")
done < <(bash "$REPO_ROOT/tool/resolve-release-version.sh" "$APP")
RELEASE_MARKETING_VERSION="${RELEASE_VERSION_ARGS[0]#--build-name=}"

if [[ "$PLATFORM" == "android" || "$PLATFORM" == "android-apk" ]]; then
  # Native Maps SDK reads MAPS_API_KEY via the `${MAPS_API_KEY}`
  # manifestPlaceholder, which build.gradle.kts resolves from Gradle's
  # `project.findProperty("MAPS_API_KEY")` (android/gradle.properties).
  #
  # We use gradle.properties — not local.properties — because Flutter
  # regenerates local.properties on every debug `flutter run`, wiping
  # any custom keys. gradle.properties is gitignored and stable.
  GRADLE_PROPS="$APP_DIR/android/gradle.properties"
  if [[ -f "$GRADLE_PROPS" ]]; then
    sed -i.bak \
      -e '/^MAPS_API_KEY=/d' \
      -e '/^MYSHOP_SOURCE_COMMIT=/d' \
      -e '/^android\.useAndroidX=/d' \
      "$GRADLE_PROPS"
    rm -f "$GRADLE_PROPS.bak"
    if [[ -n "$(tail -c 1 "$GRADLE_PROPS")" ]]; then
      printf '\n' >> "$GRADLE_PROPS"
    fi
  fi
  if [[ ! -f "$GRADLE_PROPS" ]] || ! grep -q '^org\.gradle\.jvmargs=' "$GRADLE_PROPS"; then
    echo 'org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError' >> "$GRADLE_PROPS"
  fi
  echo 'android.useAndroidX=true' >> "$GRADLE_PROPS"
  echo "MAPS_API_KEY=$GOOGLE_MAPS_API_KEY" >> "$GRADLE_PROPS"
  echo "MYSHOP_SOURCE_COMMIT=$SOURCE_COMMIT" >> "$GRADLE_PROPS"
  echo "→ wrote release Maps configuration and source provenance to $GRADLE_PROPS"
fi

if [[ "$PLATFORM" == "ios" ]]; then
  # The Info.plist `$(GOOGLE_MAPS_API_KEY)` substitution resolves via the
  # active xcconfig chain. We write a small Secrets.xcconfig — gitignored,
  # rewritten on every build — and Debug/Release.xcconfig `#include?` it.
  SECRETS_XCCONFIG="$APP_DIR/ios/Flutter/Secrets.xcconfig"
  cat > "$SECRETS_XCCONFIG" <<EOF
// Auto-generated by tool/build.sh from .env.prod — do NOT commit.
// Re-run tool/build.sh after rotating production keys.
GOOGLE_MAPS_API_KEY = $GOOGLE_MAPS_API_KEY
MYSHOP_SOURCE_COMMIT = $SOURCE_COMMIT
EOF
  echo "→ wrote $SECRETS_XCCONFIG"
fi

cd "$APP_DIR"

case "$PLATFORM" in
  android)
    echo "→ flutter build appbundle (release) for apps/$APP with ${#DEFINES[@]} dart-defines"
    flutter build appbundle --release "${RELEASE_VERSION_ARGS[@]}" "${DEFINES[@]}" "$@"
    MYSHOP_PRODUCTION_API_ENDPOINT="$API_BASE_URL" \
      bash "$REPO_ROOT/tool/verify-release-artifact.sh" \
      "$APP" android "$APP_DIR/build/app/outputs/bundle/release/app-release.aab" \
      "$RELEASE_MARKETING_VERSION" "$RELEASE_BUILD_NUMBER" "$SOURCE_COMMIT"
    ;;
  android-apk)
    echo "→ flutter build apk (release, fat APK) for apps/$APP with ${#DEFINES[@]} dart-defines"
    echo "  Output: $APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
    echo "  Install on a phone with: adb install -r <path>/app-release.apk"
    flutter build apk --release "${RELEASE_VERSION_ARGS[@]}" "${DEFINES[@]}" "$@"
    MYSHOP_PRODUCTION_API_ENDPOINT="$API_BASE_URL" \
      bash "$REPO_ROOT/tool/verify-release-artifact.sh" \
      "$APP" android "$APP_DIR/build/app/outputs/flutter-apk/app-release.apk" \
      "$RELEASE_MARKETING_VERSION" "$RELEASE_BUILD_NUMBER" "$SOURCE_COMMIT"
    ;;
  ios)
    echo "→ flutter build ipa (release) for apps/$APP with ${#DEFINES[@]} dart-defines"
    echo "  Exports via $REPO_ROOT/ExportOptions.plist (uploadSymbols=false) to"
    echo "  dodge the 'exportArchive Copy failed' dSYM bug. Output IPA in"
    echo "  build/ios/ipa/ — upload with Transporter."
    flutter build ipa --release \
      --export-options-plist "$REPO_ROOT/ExportOptions.plist" \
      "${RELEASE_VERSION_ARGS[@]}" "${DEFINES[@]}" "$@"
    IPA_FILES=("$APP_DIR"/build/ios/ipa/*.ipa)
    if [[ "${#IPA_FILES[@]}" -ne 1 || ! -f "${IPA_FILES[0]}" ]]; then
      echo "error: expected exactly one exported IPA in $APP_DIR/build/ios/ipa" >&2
      exit 1
    fi
    APPLE_TEAM_ID=$(
      /usr/libexec/PlistBuddy -c 'Print :teamID' "$REPO_ROOT/ExportOptions.plist"
    )
    MYSHOP_PRODUCTION_API_ENDPOINT="$API_BASE_URL" \
      MYSHOP_EXPECTED_APPLE_TEAM_ID="$APPLE_TEAM_ID" \
      bash "$REPO_ROOT/tool/verify-release-artifact.sh" \
      "$APP" ios "${IPA_FILES[0]}" \
      "$RELEASE_MARKETING_VERSION" "$RELEASE_BUILD_NUMBER" "$SOURCE_COMMIT"
    ;;
esac
