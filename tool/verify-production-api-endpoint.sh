#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: verify-production-api-endpoint.sh <api-base-url>" >&2
  exit 2
fi

REVIEWED_PRODUCTION_API_ENDPOINT=https://api.myshop.gilmoretechnologiesgh.com/v1

if [[ "$1" != "$REVIEWED_PRODUCTION_API_ENDPOINT" ]]; then
  echo "error: API_BASE_URL must equal the reviewed production endpoint $REVIEWED_PRODUCTION_API_ENDPOINT" >&2
  exit 1
fi

echo "Production API endpoint verified: $REVIEWED_PRODUCTION_API_ENDPOINT"
