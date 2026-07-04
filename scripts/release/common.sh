#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "common.sh must be sourced, not executed" >&2
  exit 64
fi

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="${APP_NAME:-i2Message}"
SCHEME="${SCHEME:-i2Message}"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/i2Message.xcodeproj}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
RELEASE_DIR="${RELEASE_DIR:-$BUILD_DIR/Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_DIR/DerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$RELEASE_DIR/$APP_NAME.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$RELEASE_DIR/export}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-$EXPORT_PATH/$APP_NAME.app}"
DEFAULT_SIGNING_IDENTITY="Developer ID Application"
DEVELOPER_ID_APPLICATION_IDENTITY="${DEVELOPER_ID_APPLICATION_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"

log() {
  printf '==> %s\n' "$*" >&2
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

bool_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

xcconfig_value() {
  local key="$1"
  awk -F= -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' "$ROOT_DIR/App/i2Message.xcconfig"
}

release_version() {
  if [[ -n "${APP_VERSION:-}" ]]; then
    printf '%s\n' "$APP_VERSION"
    return
  fi

  if [[ "${GITHUB_REF_TYPE:-}" == "tag" && -n "${GITHUB_REF_NAME:-}" ]]; then
    printf '%s\n' "${GITHUB_REF_NAME#v}"
    return
  fi

  local configured
  configured="$(xcconfig_value MARKETING_VERSION)"
  printf '%s\n' "${configured:-0.1.0}"
}

release_build_number() {
  if [[ -n "${BUILD_NUMBER:-}" ]]; then
    printf '%s\n' "$BUILD_NUMBER"
  elif [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    printf '%s\n' "$GITHUB_RUN_NUMBER"
  else
    date -u '+%Y%m%d%H%M'
  fi
}

sanitize_artifact_component() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

notarization_auth_mode() {
  if [[ -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" && -n "${APP_STORE_CONNECT_API_KEY_P8:-}" ]]; then
    printf 'app-store-connect\n'
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    printf 'apple-id\n'
  else
    printf 'none\n'
  fi
}

write_github_env() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_ENV"
  fi
}

ensure_release_dir() {
  mkdir -p "$RELEASE_DIR"
}
