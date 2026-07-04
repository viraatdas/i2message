#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/release/common.sh"

"$ROOT_DIR/scripts/release/validate-env.sh" --release

VERSION="$(release_version)"
BUILD_NUMBER_VALUE="$(release_build_number)"
EXPORT_OPTIONS_PLIST="$RELEASE_DIR/ExportOptions.DeveloperID.plist"

ensure_release_dir
cd "$ROOT_DIR"

"$ROOT_DIR/scripts/generate-xcodeproj.sh"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

log "archiving $APP_NAME $VERSION ($BUILD_NUMBER_VALUE)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  -skipPackagePluginValidation \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION_IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER_VALUE" \
  archive

cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingCertificate</key>
  <string>$DEVELOPER_ID_APPLICATION_IDENTITY</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>$APPLE_TEAM_ID</string>
  <key>thinning</key>
  <string>&lt;none&gt;</string>
</dict>
</plist>
PLIST

plutil -lint "$EXPORT_OPTIONS_PLIST" >/dev/null

log "exporting Developer ID archive"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -skipPackagePluginValidation

"$ROOT_DIR/scripts/release/validate-app.sh" "$APP_BUNDLE_PATH"

write_github_env APP_BUNDLE_PATH "$APP_BUNDLE_PATH"
log "exported app: $APP_BUNDLE_PATH"
