#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
printf 'Deprecated: use edge-guard.sh update instead.\n' >&2
exec "$ROOT_DIR/edge-guard.sh" update "$@"
