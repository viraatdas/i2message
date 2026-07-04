#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

[[ $# -gt 0 ]] || fail "usage: $0 <artifact> [artifact...]"

CHECKSUM_FILE="${CHECKSUM_FILE:-$RELEASE_DIR/SHA256SUMS.txt}"
mkdir -p "$(dirname "$CHECKSUM_FILE")"
: > "$CHECKSUM_FILE"

for artifact in "$@"; do
  [[ -f "$artifact" ]] || fail "artifact not found: $artifact"
  (
    cd "$(dirname "$artifact")"
    shasum -a 256 "$(basename "$artifact")"
  ) >> "$CHECKSUM_FILE"
done

log "wrote checksums: $CHECKSUM_FILE"
cat "$CHECKSUM_FILE"
