#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

ALLOW_UNSIGNED=0
APP_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-unsigned)
      ALLOW_UNSIGNED=1
      shift
      ;;
    *)
      if [[ -z "$APP_PATH" ]]; then
        APP_PATH="$1"
      else
        fail "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$APP_PATH" ]] || fail "usage: $0 [--allow-unsigned] <app-path>"
[[ -d "$APP_PATH" ]] || fail "app bundle not found: $APP_PATH"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]] || fail "missing app Info.plist: $INFO_PLIST"
plutil -lint "$INFO_PLIST" >/dev/null

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)"
[[ -n "$BUNDLE_ID" ]] || fail "CFBundleIdentifier is missing"
[[ -n "$EXECUTABLE_NAME" ]] || fail "CFBundleExecutable is missing"
[[ -x "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" ]] || fail "app executable is missing or not executable"

if codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/tmp/i2message-codesign-verify.log 2>&1; then
  SIGN_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
  if ! grep -q 'runtime' <<< "$SIGN_DETAILS"; then
    fail "hardened runtime flag is missing from app signature"
  fi
  if [[ -n "${APPLE_TEAM_ID:-}" ]] && ! grep -q "TeamIdentifier=$APPLE_TEAM_ID" <<< "$SIGN_DETAILS"; then
    fail "app signature TeamIdentifier does not match APPLE_TEAM_ID"
  fi

  ENTITLEMENTS="$(mktemp)"
  trap 'rm -f "$ENTITLEMENTS"' EXIT
  if ! codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS" 2>/dev/null; then
    fail "could not extract signed entitlements"
  fi
  if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.automation.apple-events' "$ENTITLEMENTS" 2>/dev/null | grep -q true; then
    fail "signed app is missing com.apple.security.automation.apple-events entitlement"
  fi
  log "validated signed app bundle: $APP_PATH"
else
  if [[ "$ALLOW_UNSIGNED" -eq 1 ]]; then
    warn "app is unsigned; bundle structure only was validated"
    log "validated unsigned app bundle: $APP_PATH"
  else
    cat /tmp/i2message-codesign-verify.log >&2 || true
    fail "app signature validation failed"
  fi
fi
