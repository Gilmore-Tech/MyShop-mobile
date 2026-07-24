#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: verify-ios-archive-symbols.sh <Runner.xcarchive>" >&2
  exit 2
fi

ARCHIVE="$1"
APP_ROOT="$ARCHIVE/Products/Applications"
DSYM_ROOT="$ARCHIVE/dSYMs"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: iOS archive symbol verification requires macOS" >&2
  exit 2
fi

if [[ ! -d "$APP_ROOT" || ! -d "$DSYM_ROOT" ]]; then
  echo "error: not a complete Xcode archive: $ARCHIVE" >&2
  exit 1
fi

UUIDS_FILE=$(mktemp "${TMPDIR:-/tmp}/myshop-ios-dsym-uuids.XXXXXX")
BINARIES_FILE=$(mktemp "${TMPDIR:-/tmp}/myshop-ios-binaries.XXXXXX")
trap 'rm -f "$UUIDS_FILE" "$BINARIES_FILE"' EXIT

while IFS= read -r -d '' dsym; do
  dwarfdump --uuid "$dsym" 2>/dev/null |
    awk '/^UUID:/ { print toupper($2) }' >> "$UUIDS_FILE"
done < <(find "$DSYM_ROOT" -maxdepth 1 -type d -name '*.dSYM' -print0)
sort -u "$UUIDS_FILE" -o "$UUIDS_FILE"

while IFS= read -r -d '' bundle; do
  executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "$bundle/Info.plist" 2>/dev/null || true)
  if [[ -n "$executable" && -f "$bundle/$executable" ]]; then
    printf '%s\n' "$bundle/$executable" >> "$BINARIES_FILE"
  fi
done < <(find "$APP_ROOT" \( -type d -name '*.app' -o -type d -name '*.appex' \) -print0)

while IFS= read -r -d '' framework; do
  executable=$(basename "$framework" .framework)
  if [[ -f "$framework/$executable" ]]; then
    printf '%s\n' "$framework/$executable" >> "$BINARIES_FILE"
  fi
done < <(find "$APP_ROOT" -type d -name '*.framework' -print0)
sort -u "$BINARIES_FILE" -o "$BINARIES_FILE"

checked=0
required_missing=0
vendor_missing=0

while IFS= read -r binary; do
  [[ -n "$binary" ]] || continue
  executable=$(basename "$binary")
  binary_uuids=$(dwarfdump --uuid "$binary" 2>/dev/null |
    awk '/^UUID:/ { print toupper($2) }')

  if [[ -z "$binary_uuids" ]]; then
    echo "ERROR: $executable has no Mach-O build UUID" >&2
    required_missing=$((required_missing + 1))
    continue
  fi

  checked=$((checked + 1))
  while IFS= read -r uuid; do
    [[ -n "$uuid" ]] || continue
    if grep -Fxq "$uuid" "$UUIDS_FILE"; then
      continue
    fi

    case "$executable" in
      MapboxCommon|MapboxCoreMaps|WebRTC|objective_c)
        echo "VENDOR SYMBOL GAP: $executable UUID $uuid" >&2
        vendor_missing=$((vendor_missing + 1))
        ;;
      *)
        echo "ERROR: missing dSYM for $executable UUID $uuid" >&2
        required_missing=$((required_missing + 1))
        ;;
    esac
  done <<< "$binary_uuids"
done < "$BINARIES_FILE"

if (( required_missing > 0 )); then
  echo "iOS archive symbol verification failed: $required_missing required UUID(s) missing; $vendor_missing known vendor UUID(s) missing" >&2
  exit 1
fi

if (( vendor_missing > 0 )); then
  echo "iOS archive app-owned symbol verification passed for $checked binaries; $vendor_missing known precompiled-vendor UUID(s) need vendor dSYMs" >&2
  exit 0
fi

echo "iOS archive symbol verification passed for $checked binaries"
