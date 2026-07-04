#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

APP_PATH=""
DMG_PATH=""
UNSIGNED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --dmg)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --unsigned)
      UNSIGNED=1
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

APP_PATH="${APP_PATH:-$APP_BUNDLE_PATH}"
VERSION="$(sanitize_artifact_component "$(release_version)")"
if [[ -z "$DMG_PATH" ]]; then
  SUFFIX=""
  [[ "$UNSIGNED" -eq 1 ]] && SUFFIX="-unsigned"
  DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION$SUFFIX.dmg"
fi

[[ -d "$APP_PATH" ]] || fail "app bundle not found: $APP_PATH"
require_cmd hdiutil
require_cmd ditto
ensure_release_dir

if [[ "$UNSIGNED" -eq 1 ]]; then
  "$ROOT_DIR/scripts/release/validate-app.sh" --allow-unsigned "$APP_PATH"
else
  "$ROOT_DIR/scripts/release/validate-app.sh" "$APP_PATH"
fi

STAGING_DIR="$RELEASE_DIR/dmg-staging"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

log "creating DMG: $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH" >/dev/null

if [[ "$UNSIGNED" -eq 0 ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION_IDENTITY" "$DMG_PATH"
fi

if [[ "$UNSIGNED" -eq 1 ]]; then
  "$ROOT_DIR/scripts/release/validate-dmg.sh" --allow-unsigned "$DMG_PATH"
else
  "$ROOT_DIR/scripts/release/validate-dmg.sh" "$DMG_PATH"
fi

write_github_env DMG_PATH "$DMG_PATH"
log "created DMG: $DMG_PATH"
printf '%s\n' "$DMG_PATH"
