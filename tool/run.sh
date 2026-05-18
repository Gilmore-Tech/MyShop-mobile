#!/usr/bin/env bash
# Run a MyShop mobile app with the local-dev keys baked in.
#
#   tool/run.sh client                # runs apps/client on the default device
#   tool/run.sh provider              # runs apps/provider on the default device
#   tool/run.sh client -d <deviceId>  # pass extra flutter-run flags after the app name
#
# Reads `.env.dev` (gitignored — copy from `.env.dev.example`) and passes
# every variable through to `flutter run` as a `--dart-define`. Mirrors what
# the v1.0 secret cleanup expects at runtime (`GOOGLE_MAPS_API_KEY`,
# `MAPBOX_ACCESS_TOKEN`, `MAPBOX_STYLE_URL`, etc).

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

if [[ $# -lt 1 ]]; then
  echo "usage: tool/run.sh <client|provider> [extra flutter args...]" >&2
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

ENV_FILE="$REPO_ROOT/.env.dev"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found. Copy .env.dev.example and fill in the values." >&2
  exit 1
fi

# Source the env file in a way that tolerates blank lines and comments.
# Each non-comment line is `KEY=value`. We collect them into an array of
# `--dart-define` args rather than exporting to the shell, so values with
# spaces or special chars survive intact.
DEFINES=()
while IFS='=' read -r key value; do
  # Skip blank lines and comments (after trimming leading whitespace).
  key="${key#"${key%%[![:space:]]*}"}"
  [[ -z "$key" || "$key" == \#* ]] && continue
  # Trim surrounding quotes from the value if present.
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  DEFINES+=("--dart-define=${key}=${value}")
done < "$ENV_FILE"

if [[ ${#DEFINES[@]} -eq 0 ]]; then
  echo "warning: no keys found in $ENV_FILE — the build will run but maps/places will be broken" >&2
fi

cd "apps/$APP"
echo "→ flutter run for apps/$APP with ${#DEFINES[@]} dart-defines"
exec flutter run "${DEFINES[@]}" "$@"
