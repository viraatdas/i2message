#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

ensure_release_dir

[[ -n "${DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64:-}" ]] || fail "DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64 is required"
[[ -n "${DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD:-}" ]] || fail "DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD is required"
[[ -n "${KEYCHAIN_PASSWORD:-}" ]] || fail "KEYCHAIN_PASSWORD is required"

require_cmd base64
require_cmd security

CERT_PATH="$(mktemp "$RELEASE_DIR/developer-id-application.XXXXXX.p12")"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-$RELEASE_DIR/i2message-signing.keychain-db}"

cleanup() {
  rm -f "$CERT_PATH"
}
trap cleanup EXIT

if ! printf '%s' "$DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64" | base64 --decode > "$CERT_PATH" 2>/dev/null; then
  printf '%s' "$DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64" | base64 -D > "$CERT_PATH"
fi

rm -f "$KEYCHAIN_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" \
  -P "$DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

existing_keychains=()
while IFS= read -r keychain; do
  keychain="${keychain//\"/}"
  [[ -n "$keychain" ]] && existing_keychains+=("$keychain")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN_PATH" "${existing_keychains[@]}"

if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -q "Developer ID Application"; then
  fail "Developer ID Application identity was not found after certificate import"
fi

write_github_env KEYCHAIN_PATH "$KEYCHAIN_PATH"
log "Developer ID Application certificate imported into temporary keychain"
