#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

ARTIFACT_PATH="${1:-}"
[[ -n "$ARTIFACT_PATH" ]] || fail "usage: $0 <zip-or-dmg-path>"
[[ -f "$ARTIFACT_PATH" ]] || fail "artifact not found: $ARTIFACT_PATH"

AUTH_MODE="$(notarization_auth_mode)"
[[ "$AUTH_MODE" != "none" ]] || fail "notarization credentials are missing"

case "$AUTH_MODE" in
  app-store-connect)
    KEY_FILE="$(mktemp "$RELEASE_DIR/AuthKey_XXXXXX.p8")"
    cleanup() {
      rm -f "$KEY_FILE"
    }
    trap cleanup EXIT
    chmod 600 "$KEY_FILE"
    if [[ "$APP_STORE_CONNECT_API_KEY_P8" == *"\\n"* ]]; then
      printf '%b' "$APP_STORE_CONNECT_API_KEY_P8" > "$KEY_FILE"
    else
      printf '%s' "$APP_STORE_CONNECT_API_KEY_P8" > "$KEY_FILE"
    fi
    log "submitting artifact for notarization with App Store Connect API key"
    xcrun notarytool submit "$ARTIFACT_PATH" \
      --key "$KEY_FILE" \
      --key-id "$APP_STORE_CONNECT_KEY_ID" \
      --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
      --wait
    ;;
  apple-id)
    log "submitting artifact for notarization with Apple ID fallback"
    xcrun notarytool submit "$ARTIFACT_PATH" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
    ;;
esac

log "notarization accepted: $ARTIFACT_PATH"
