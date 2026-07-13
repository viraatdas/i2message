#!/usr/bin/env bash
# Env-gated verification harness: builds the exact search index from the REAL
# ~/Library/Messages/chat.db (read-only, via a temp copy) and asserts full
# history coverage plus old-message findability.
#
# Full Disk Access belongs to the terminal running this script, not to the
# xctest process Xcode spawns, so the privileged step — cloning chat.db —
# happens here; the test only ever sees the staged copy. Everything staged is
# deleted on exit, and the test prints counts/timings only (no message
# content, no contact names).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SOURCE_DB="${I2MESSAGE_REAL_DB_PATH:-$HOME/Library/Messages/chat.db}"
if [[ ! -r "$SOURCE_DB" ]]; then
  echo "error: cannot read $SOURCE_DB — run from a terminal with Full Disk Access" >&2
  exit 1
fi

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/i2message-realdb-staging-XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

# APFS clones (-c) make these copies effectively instant; fall back to a
# plain copy on non-APFS volumes.
cp -c "$SOURCE_DB" "$STAGING/chat.db" 2>/dev/null || cp "$SOURCE_DB" "$STAGING/chat.db"
for suffix in -wal -shm; do
  if [[ -f "$SOURCE_DB$suffix" ]]; then
    cp -c "$SOURCE_DB$suffix" "$STAGING/chat.db$suffix" 2>/dev/null || cp "$SOURCE_DB$suffix" "$STAGING/chat.db$suffix"
  fi
done

"$ROOT_DIR/scripts/generate-xcodeproj.sh"

# The scheme's test action maps I2MESSAGE_REAL_DB_* environment variables to
# $(…) build-setting expansions, so passing them as xcodebuild build settings
# is what actually reaches the (unhosted) xctest process.
xcodebuild \
  -project i2Message.xcodeproj \
  -scheme i2Message \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  I2MESSAGE_REAL_DB_CHECK=1 \
  "I2MESSAGE_REAL_DB_PATH=$STAGING/chat.db" \
  -only-testing:i2MessageCoreTests/RealMessagesDatabaseIndexingTests \
  test
