#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

ALLOW_UNSIGNED=0
DMG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-unsigned)
      ALLOW_UNSIGNED=1
      shift
      ;;
    *)
      if [[ -z "$DMG_PATH" ]]; then
        DMG_PATH="$1"
      else
        fail "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$DMG_PATH" ]] || fail "usage: $0 [--allow-unsigned] <dmg-path>"
[[ -f "$DMG_PATH" ]] || fail "DMG not found: $DMG_PATH"

hdiutil verify "$DMG_PATH" >/dev/null

if codesign --verify --verbose=2 "$DMG_PATH" >/tmp/i2message-dmg-codesign.log 2>&1; then
  log "validated DMG signature"
elif [[ "$ALLOW_UNSIGNED" -eq 1 ]]; then
  warn "DMG is unsigned; disk image structure only was validated"
else
  cat /tmp/i2message-dmg-codesign.log >&2 || true
  fail "DMG signature validation failed"
fi

MOUNT_POINT="$(mktemp -d "$RELEASE_DIR/dmg-mount.XXXXXX")"
cleanup() {
  hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" \
  -readonly \
  -nobrowse \
  -noautoopen \
  -mountpoint "$MOUNT_POINT" >/dev/null

APP_IN_DMG="$MOUNT_POINT/$APP_NAME.app"
[[ -d "$APP_IN_DMG" ]] || fail "DMG does not contain $APP_NAME.app at the volume root"
[[ -d "$APP_IN_DMG/Contents" ]] || fail "DMG app bundle is missing Contents directory"
[[ -e "$MOUNT_POINT/Applications" ]] || fail "DMG is missing /Applications symlink"

if [[ "$ALLOW_UNSIGNED" -eq 1 ]]; then
  "$ROOT_DIR/scripts/release/validate-app.sh" --allow-unsigned "$APP_IN_DMG"
else
  "$ROOT_DIR/scripts/release/validate-app.sh" "$APP_IN_DMG"
fi

log "validated DMG bundle structure: $DMG_PATH"
