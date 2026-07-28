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
APPROVED_MARKETING_VERSION=1.4.1
# The owner confirmed that build 25 was released on all four targets. It is
# permanently occupied even if a private console later hides an old artifact.
LOCAL_BUILD_NUMBER_FLOOR=25
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
case "$BUILD_NUMBER" in
  [1-9]|[1-9][0-9]*) ;;
  *)
    echo "error: RELEASE_BUILD_NUMBER must be a positive decimal integer" >&2
    exit 1
    ;;
esac

if (( BUILD_NUMBER <= LOCAL_BUILD_NUMBER_FLOOR )); then
  echo "error: RELEASE_BUILD_NUMBER must be greater than the local build-number floor $LOCAL_BUILD_NUMBER_FLOOR" >&2
  exit 1
fi

if (( BUILD_NUMBER > MAX_PORTABLE_BUILD_NUMBER )); then
  echo "error: RELEASE_BUILD_NUMBER must not exceed the Android-compatible maximum $MAX_PORTABLE_BUILD_NUMBER" >&2
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
