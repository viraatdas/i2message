#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

if bool_true "${I2_RELEASE_DRY_RUN:-0}"; then
  exec "$ROOT_DIR/scripts/release/local-dry-run.sh"
fi

"$ROOT_DIR/scripts/release/validate-env.sh" --release
"$ROOT_DIR/scripts/release/import-developer-id-certificate.sh"
"$ROOT_DIR/scripts/release/build-archive.sh"

VERSION="$(sanitize_artifact_component "$(release_version)")"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-notary.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

ZIP_PATH="$ZIP_PATH" "$ROOT_DIR/scripts/release/zip-app.sh" "$APP_BUNDLE_PATH" >/dev/null
"$ROOT_DIR/scripts/release/notarize.sh" "$ZIP_PATH"
"$ROOT_DIR/scripts/release/staple-and-assess.sh" "$APP_BUNDLE_PATH"
rm -f "$ZIP_PATH"

"$ROOT_DIR/scripts/release/package-dmg.sh" --app "$APP_BUNDLE_PATH" --dmg "$DMG_PATH" >/dev/null
"$ROOT_DIR/scripts/release/notarize.sh" "$DMG_PATH"
"$ROOT_DIR/scripts/release/staple-and-assess.sh" "$DMG_PATH"
"$ROOT_DIR/scripts/release/checksums.sh" "$DMG_PATH"

write_github_env DMG_PATH "$DMG_PATH"
write_github_env CHECKSUM_FILE "$RELEASE_DIR/SHA256SUMS.txt"

log "release artifacts ready:"
printf '  %s\n' "$DMG_PATH" "$RELEASE_DIR/SHA256SUMS.txt"
