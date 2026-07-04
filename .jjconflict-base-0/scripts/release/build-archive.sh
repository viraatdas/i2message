#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCHIVE_PATH="$ROOT_DIR/build/Release/i2Message.xcarchive"
EXPORT_PATH="$ROOT_DIR/build/Release/export"

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/generate-xcodeproj.sh"
mkdir -p "$ROOT_DIR/build/Release"

xcodebuild \
  -project i2Message.xcodeproj \
  -scheme i2Message \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  -skipPackagePluginValidation \
  archive

rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

echo "Archive written to: $ARCHIVE_PATH"
echo "Export/staple/notarize steps are intentionally template-driven; see docs/release-signing.md."
