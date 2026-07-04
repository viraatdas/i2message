#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

ARTIFACT_PATH="${1:-}"
[[ -n "$ARTIFACT_PATH" ]] || fail "usage: $0 <app-or-dmg-path>"
[[ -e "$ARTIFACT_PATH" ]] || fail "artifact not found: $ARTIFACT_PATH"

xcrun stapler staple "$ARTIFACT_PATH"
xcrun stapler validate "$ARTIFACT_PATH"

if [[ -d "$ARTIFACT_PATH" && "$ARTIFACT_PATH" == *.app ]]; then
  if command -v spctl >/dev/null 2>&1; then
    spctl --assess --type execute -vv "$ARTIFACT_PATH"
  else
    warn "spctl unavailable; skipped app Gatekeeper assessment"
  fi
  "$ROOT_DIR/scripts/release/validate-app.sh" "$ARTIFACT_PATH"
  log "stapled and assessed app: $ARTIFACT_PATH"
  exit 0
fi

if [[ "$ARTIFACT_PATH" == *.dmg ]]; then
  if command -v spctl >/dev/null 2>&1; then
    spctl --assess --type open --context context:primary-signature -vv "$ARTIFACT_PATH"
  else
    warn "spctl unavailable; skipped DMG Gatekeeper assessment"
  fi

  MOUNT_POINT="$(mktemp -d "$RELEASE_DIR/dmg-assess.XXXXXX")"
  cleanup() {
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  hdiutil attach "$ARTIFACT_PATH" \
    -readonly \
    -nobrowse \
    -noautoopen \
    -mountpoint "$MOUNT_POINT" >/dev/null

  APP_IN_DMG="$MOUNT_POINT/$APP_NAME.app"
  [[ -d "$APP_IN_DMG" ]] || fail "mounted DMG does not contain $APP_NAME.app"
  "$ROOT_DIR/scripts/release/validate-app.sh" "$APP_IN_DMG"
  if command -v spctl >/dev/null 2>&1; then
    spctl --assess --type execute -vv "$APP_IN_DMG"
  fi
  log "stapled and assessed DMG: $ARTIFACT_PATH"
  exit 0
fi

fail "unsupported artifact for stapling: $ARTIFACT_PATH"
