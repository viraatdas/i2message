#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

"$ROOT_DIR/scripts/release/validate-env.sh" --dry-run

VERSION="$(release_version)"
BUILD_NUMBER_VALUE="$(release_build_number)"
SAFE_VERSION="$(sanitize_artifact_component "$VERSION")"
UNSIGNED_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME.app"
UNSIGNED_DMG_PATH="$RELEASE_DIR/$APP_NAME-$SAFE_VERSION-unsigned.dmg"

ensure_release_dir
cd "$ROOT_DIR"

"$ROOT_DIR/scripts/generate-xcodeproj.sh"

log "building unsigned Release app for local dry run"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'platform=macOS' \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER_VALUE" \
  build

"$ROOT_DIR/scripts/release/validate-app.sh" --allow-unsigned "$UNSIGNED_APP_PATH"
"$ROOT_DIR/scripts/release/package-dmg.sh" --unsigned --app "$UNSIGNED_APP_PATH" --dmg "$UNSIGNED_DMG_PATH"
"$ROOT_DIR/scripts/release/checksums.sh" "$UNSIGNED_DMG_PATH"

log "unsigned dry-run artifacts:"
printf '  %s\n' "$UNSIGNED_DMG_PATH" "$RELEASE_DIR/SHA256SUMS.txt"
