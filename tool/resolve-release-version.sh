#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: resolve-release-version.sh <client|provider>" >&2
  exit 2
fi

APP="$1"
case "$APP" in
  client|provider) ;;
  *)
    echo "error: app must be 'client' or 'provider', got '$APP'" >&2
    exit 2
    ;;
esac

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PUBSPEC="$ROOT_DIR/apps/$APP/pubspec.yaml"
APPROVED_MARKETING_VERSION=1.4.8
# Builds through 40 are occupied by retained release artifacts, store uploads,
# or delivery attempts. They remain unavailable even if a console later hides
# an old or failed artifact.
LOCAL_BUILD_NUMBER_FLOOR=40
MAX_PORTABLE_BUILD_NUMBER=2100000000

PUBSPEC_VERSION=$(awk '$1 == "version:" { print $2; exit }' "$PUBSPEC")
case "$PUBSPEC_VERSION" in
  "$APPROVED_MARKETING_VERSION"+*) ;;
  *)
    echo "error: apps/$APP/pubspec.yaml must declare approved marketing version $APPROVED_MARKETING_VERSION, got '${PUBSPEC_VERSION:-missing}'" >&2
    exit 1
    ;;
esac

BUILD_NUMBER="${RELEASE_BUILD_NUMBER:-}"
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: RELEASE_BUILD_NUMBER must be a positive decimal integer" >&2
  exit 1
fi

MAX_BUILD_NUMBER_DIGITS=${#MAX_PORTABLE_BUILD_NUMBER}
if (( ${#BUILD_NUMBER} > MAX_BUILD_NUMBER_DIGITS )) || \
  { (( ${#BUILD_NUMBER} == MAX_BUILD_NUMBER_DIGITS )) && \
    [[ "$BUILD_NUMBER" > "$MAX_PORTABLE_BUILD_NUMBER" ]]; }; then
  echo "error: RELEASE_BUILD_NUMBER must not exceed the Android-compatible maximum $MAX_PORTABLE_BUILD_NUMBER" >&2
  exit 1
fi

# Decimal conversion is safe only after the length/range guard above. The 10#
# prefix also prevents Bash from treating a decimal-looking value as octal.
BUILD_NUMBER_VALUE=$((10#$BUILD_NUMBER))

if (( BUILD_NUMBER_VALUE <= LOCAL_BUILD_NUMBER_FLOOR )); then
  echo "error: RELEASE_BUILD_NUMBER must be greater than the local build-number floor $LOCAL_BUILD_NUMBER_FLOOR" >&2
  exit 1
fi

cat >&2 <<EOF
release version: $APPROVED_MARKETING_VERSION+$BUILD_NUMBER ($APP)
operator requirement: confirm $BUILD_NUMBER is greater than every existing private App Store Connect and Play Console build for this app before continuing
EOF

printf '%s\n' \
  "--build-name=$APPROVED_MARKETING_VERSION" \
  "--build-number=$BUILD_NUMBER" \
  "--dart-define=MYSHOP_MARKETING_VERSION=$APPROVED_MARKETING_VERSION"
