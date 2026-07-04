#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

APP_PATH="${1:-$APP_BUNDLE_PATH}"
VERSION="$(sanitize_artifact_component "$(release_version)")"
ZIP_PATH="${ZIP_PATH:-$RELEASE_DIR/$APP_NAME-$VERSION-notary.zip}"

[[ -d "$APP_PATH" ]] || fail "app bundle not found: $APP_PATH"
ensure_release_dir

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
log "created notarization zip: $ZIP_PATH"
printf '%s\n' "$ZIP_PATH"
