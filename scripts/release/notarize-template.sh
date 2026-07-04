#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "notarize-template.sh is kept for compatibility; use scripts/release/notarize.sh for releases." >&2
exec "$ROOT_DIR/scripts/release/notarize.sh" "$@"
