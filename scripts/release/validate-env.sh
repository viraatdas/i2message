#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

MODE="release"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --release)
      MODE="release"
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

case "$MODE" in
  release|dry-run) ;;
  *) fail "mode must be release or dry-run" ;;
esac

require_cmd xcodebuild
require_cmd xcrun
require_cmd xcodegen
require_cmd hdiutil
require_cmd shasum
require_cmd plutil
require_cmd codesign

if [[ ! -x /usr/libexec/PlistBuddy ]]; then
  fail "/usr/libexec/PlistBuddy is required"
fi

if [[ "$MODE" == "dry-run" ]]; then
  log "release environment validated for unsigned dry run"
  exit 0
fi

require_cmd security
require_cmd spctl
require_cmd ditto

missing=()
require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    missing+=("$name")
  fi
}

require_env APPLE_TEAM_ID
require_env DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64
require_env DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD
require_env KEYCHAIN_PASSWORD

case "$(notarization_auth_mode)" in
  app-store-connect)
    log "notarization auth: App Store Connect API key"
    ;;
  apple-id)
    log "notarization auth: Apple ID fallback"
    ;;
  none)
    missing+=("APP_STORE_CONNECT_KEY_ID + APP_STORE_CONNECT_ISSUER_ID + APP_STORE_CONNECT_API_KEY_P8 or APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD")
    ;;
esac

if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'error: missing required release environment variables:\n' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 64
fi

log "release environment validated"
