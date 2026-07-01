#!/usr/bin/env bash
# Run a MyShop mobile app with the local-dev keys baked in.
#
#   tool/run.sh client                  # run apps/client on the default device
#   tool/run.sh provider                # run apps/provider on the default device
#   tool/run.sh client ios              # use the iOS dev Maps key for the Dart side
#   tool/run.sh client android -d <id>  # explicit platform + extra flutter-run flags
#   tool/run.sh client -d <id>          # extra flags (platform defaults to android)
#
# Reads `.env.dev` (gitignored — copy from `.env.dev.example`) and passes
# every variable through to `flutter run` as a `--dart-define`.
#
# Google Maps keys are restricted per app AND per platform (an Android key
# can't also carry an iOS restriction), so `.env.dev` may hold up to four —
# GOOGLE_MAPS_API_KEY_{CLIENT,PROVIDER}_{ANDROID,IOS} — and this script picks
# the right one. A single legacy GOOGLE_MAPS_API_KEY is still honoured (used
# for whichever target lacks a specific key), so a one-key dev setup keeps
# working unchanged.
#
# Selected values are threaded through every surface:
#   - Dart: --dart-define=GOOGLE_MAPS_API_KEY=<platform key> (+ every other
#     .env.dev line, plus the per-app MAPS_ANDROID_CERT_SHA1 used for the
#     X-Android-Cert header on direct REST calls — see MapsConfig).
#   - Android native: writes android/gradle.properties' MAPS_API_KEY.
#   - iOS native: writes ios/Flutter/Secrets.xcconfig's GOOGLE_MAPS_API_KEY.
# Both native files are always written (each with its own per-platform key) so
# the map renders whichever device you pick; only the Dart-side key follows
# the [android|ios] arg since `flutter run` targets a single device.

set -euo pipefail

is_placeholder() {
  case "$1" in
    ""|*"..."*|*"replace-me"*|*"REPLACE"*|*"YOUR_"*) return 0 ;;
  esac
  return 1
}

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

if [[ $# -lt 1 ]]; then
  echo "usage: tool/run.sh <client|provider> [android|ios] [extra flutter args...]" >&2
  exit 2
fi

APP="$1"
shift

case "$APP" in
  client|provider) ;;
  *)
    echo "error: app must be 'client' or 'provider', got '$APP'" >&2
    exit 2
    ;;
esac

# Optional platform arg — decides which Maps key the Dart side gets (flutter
# run targets one device). Defaults to android; consumed only if present so
# the legacy `tool/run.sh client -d <id>` form (extra flags) still works.
PLATFORM="android"
if [[ "${1:-}" == "android" || "${1:-}" == "ios" ]]; then
  PLATFORM="$1"
  shift
fi

ENV_FILE="$REPO_ROOT/.env.dev"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found. Copy .env.dev.example and fill in the values." >&2
  exit 1
fi

# Parse `.env.dev` into a `--dart-define` array. The Maps keys and Android
# cert SHA-1s are captured into like-named shell vars (and kept OUT of the
# blanket dart-defines) so we can select the right ones per (app, platform)
# below. Pre-initialised to empty for safe `${!var}` lookup under `set -u`;
# `printf -v` (bash 3.1+) keeps it macOS-bash-3.2 compatible.
DEFINES=()
GOOGLE_MAPS_API_KEY=""
GOOGLE_MAPS_API_KEY_CLIENT_ANDROID=""
GOOGLE_MAPS_API_KEY_CLIENT_IOS=""
GOOGLE_MAPS_API_KEY_PROVIDER_ANDROID=""
GOOGLE_MAPS_API_KEY_PROVIDER_IOS=""
MAPS_ANDROID_CERT_SHA1=""
MAPS_ANDROID_CERT_SHA1_CLIENT=""
MAPS_ANDROID_CERT_SHA1_PROVIDER=""
while IFS='=' read -r key value; do
  key="${key#"${key%%[![:space:]]*}"}"
  [[ -z "$key" || "$key" == \#* ]] && continue
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  if [[ "$key" == "GOOGLE_MAPS_API_KEY" || "$key" == GOOGLE_MAPS_API_KEY_* \
     || "$key" == "MAPS_ANDROID_CERT_SHA1" || "$key" == MAPS_ANDROID_CERT_SHA1_* ]]; then
    printf -v "$key" '%s' "$value"
    continue
  fi
  DEFINES+=("--dart-define=${key}=${value}")
done < "$ENV_FILE"

case "$APP" in
  client)   MAPS_APP="CLIENT" ;;
  provider) MAPS_APP="PROVIDER" ;;
esac

# Resolve both platform keys (each falling back to the legacy single key) so
# we can write the right key to each native surface, then dart-define the one
# matching the device this run targets.
ANDROID_VAR="GOOGLE_MAPS_API_KEY_${MAPS_APP}_ANDROID"
IOS_VAR="GOOGLE_MAPS_API_KEY_${MAPS_APP}_IOS"
ANDROID_KEY="${!ANDROID_VAR}"
IOS_KEY="${!IOS_VAR}"
if is_placeholder "$ANDROID_KEY"; then ANDROID_KEY=""; fi
if is_placeholder "$IOS_KEY"; then IOS_KEY=""; fi
if is_placeholder "$GOOGLE_MAPS_API_KEY"; then GOOGLE_MAPS_API_KEY=""; fi
[[ -z "$ANDROID_KEY" ]] && ANDROID_KEY="$GOOGLE_MAPS_API_KEY"
[[ -z "$IOS_KEY" ]] && IOS_KEY="$GOOGLE_MAPS_API_KEY"

if [[ "$PLATFORM" == "ios" ]]; then
  DART_MAPS_KEY="$IOS_KEY"
  SEL_VAR="$IOS_VAR"
else
  DART_MAPS_KEY="$ANDROID_KEY"
  SEL_VAR="$ANDROID_VAR"
fi
DEFINES+=("--dart-define=GOOGLE_MAPS_API_KEY=${DART_MAPS_KEY}")
echo "→ Maps key (dart): $SEL_VAR for $PLATFORM"

# Android cert SHA-1 → X-Android-Cert header on direct REST calls. Per app,
# falls back to the generic. In dev the debug keystore is shared across apps,
# so a single generic MAPS_ANDROID_CERT_SHA1 usually suffices.
CERT_VAR="MAPS_ANDROID_CERT_SHA1_${MAPS_APP}"
CERT_VAL="${!CERT_VAR}"
if is_placeholder "$CERT_VAL"; then CERT_VAL=""; fi
[[ -z "$CERT_VAL" ]] && CERT_VAL="$MAPS_ANDROID_CERT_SHA1"
if is_placeholder "$CERT_VAL"; then CERT_VAL=""; fi
DEFINES+=("--dart-define=MAPS_ANDROID_CERT_SHA1=${CERT_VAL}")

if [[ -z "$DART_MAPS_KEY" ]]; then
  echo "warning: no Maps key resolved for $APP/$PLATFORM (set $SEL_VAR or a legacy" >&2
  echo "         GOOGLE_MAPS_API_KEY in $ENV_FILE) — maps/places will be broken." >&2
fi

APP_DIR="$REPO_ROOT/apps/$APP"

# Native Maps SDK reads MAPS_API_KEY via the `${MAPS_API_KEY}`
# manifestPlaceholder, which build.gradle.kts resolves from Gradle's
# `project.findProperty("MAPS_API_KEY")` (i.e. android/gradle.properties).
#
# We deliberately do NOT write to android/local.properties — `flutter run`
# regenerates that file on every debug build from the Flutter template,
# wiping any custom keys. gradle.properties is gitignored and stable.
if [[ -n "$ANDROID_KEY" ]]; then
  GRADLE_PROPS="$APP_DIR/android/gradle.properties"
  if [[ -f "$GRADLE_PROPS" ]]; then
    sed -i.bak '/^MAPS_API_KEY=/d' "$GRADLE_PROPS"
    rm -f "$GRADLE_PROPS.bak"
    # If the file doesn't end with a newline, our append would smash onto
    # the previous line (collision with whatever the last property was).
    # tail -c 1 returns empty when the last byte IS a newline.
    if [[ -n "$(tail -c 1 "$GRADLE_PROPS")" ]]; then
      printf '\n' >> "$GRADLE_PROPS"
    fi
  fi
  echo "MAPS_API_KEY=$ANDROID_KEY" >> "$GRADLE_PROPS"
  echo "→ wrote MAPS_API_KEY to $GRADLE_PROPS"
fi

# iOS native Maps SDK reads `GMSApiKey` from Info.plist, populated at build
# time from the `$(GOOGLE_MAPS_API_KEY)` xcconfig variable. We write a small
# Secrets.xcconfig — gitignored, rewritten on every run — and Debug.xcconfig
# / Release.xcconfig `#include?` it (already in the project). Without this,
# AppDelegate.swift's GMSServices.provideAPIKey() never fires and the SDK
# throws GMSServicesException on first map render.
if [[ -n "$IOS_KEY" ]]; then
  SECRETS_XCCONFIG="$APP_DIR/ios/Flutter/Secrets.xcconfig"
  cat > "$SECRETS_XCCONFIG" <<EOF
// Auto-generated by tool/run.sh from .env.dev — do NOT commit.
// Re-run tool/run.sh after rotating dev keys.
GOOGLE_MAPS_API_KEY = $IOS_KEY
EOF
  echo "→ wrote $SECRETS_XCCONFIG"
fi

cd "$APP_DIR"
echo "→ flutter run for apps/$APP with ${#DEFINES[@]} dart-defines"
exec flutter run "${DEFINES[@]}" "$@"
