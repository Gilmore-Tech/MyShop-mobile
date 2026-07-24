#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_SCRIPT="$ROOT_DIR/tool/build.sh"
EXPORT_OPTIONS="$ROOT_DIR/ExportOptions.plist"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS export contract skipped: macOS is required"
  exit 0
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :method' "$EXPORT_OPTIONS")" != "app-store-connect" ]]; then
  echo "FAIL: iOS export method must be app-store-connect" >&2
  exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :destination' "$EXPORT_OPTIONS")" != "export" ]]; then
  echo "FAIL: local release builds must export without uploading" >&2
  exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :manageAppVersionAndBuildNumber' "$EXPORT_OPTIONS")" != "false" ]]; then
  echo "FAIL: Xcode must not replace the console-verified build number" >&2
  exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :uploadSymbols' "$EXPORT_OPTIONS")" != "true" ]]; then
  echo "FAIL: iOS release exports must include available archive symbols" >&2
  exit 1
fi

if ! grep -Fq 'export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"' "$BUILD_SCRIPT"; then
  echo "FAIL: iOS export must prefer Apple's matching rsync implementation" >&2
  exit 1
fi

if ! grep -Fq 'verify-ios-archive-symbols.sh' "$BUILD_SCRIPT"; then
  echo "FAIL: iOS release builds must verify archive symbol coverage" >&2
  exit 1
fi

if [[ "$(PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" command -v rsync)" != "/usr/bin/rsync" ]]; then
  echo "FAIL: the release PATH does not resolve Apple's rsync" >&2
  exit 1
fi

echo "iOS export contract tests passed"
