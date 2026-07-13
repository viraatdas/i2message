#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

"$ROOT_DIR/scripts/generate-xcodeproj.sh"

# Debug builds sign with a stable local identity when one exists so macOS TCC
# grants keyed to the app's designated requirement — notably Full Disk Access —
# survive rebuilds and reinstalls. Unsigned/ad-hoc builds get a new code
# identity every build, which silently revokes FDA each time.
#
# Override the lookup with I2MESSAGE_CODE_SIGN_IDENTITY (set it to the empty
# string to force the unsigned fallback, e.g. I2MESSAGE_CODE_SIGN_IDENTITY= ./scripts/build.sh).
resolve_signing_identity() {
  if [[ -n "${I2MESSAGE_CODE_SIGN_IDENTITY+set}" ]]; then
    printf '%s' "${I2MESSAGE_CODE_SIGN_IDENTITY}"
    return
  fi

  local identities kind match
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  for kind in "Apple Development" "Developer ID Application"; do
    match="$(printf '%s\n' "$identities" | grep -o "\"${kind}: [^\"]*\"" | head -n 1 | tr -d '"')"
    if [[ -n "$match" ]]; then
      printf '%s' "$match"
      return
    fi
  done
}

SIGNING_IDENTITY="$(resolve_signing_identity)"

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "build.sh: signing Debug build with stable identity: ${SIGNING_IDENTITY}"
  SIGNING_ARGS=(
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=${SIGNING_IDENTITY}"
    PROVISIONING_PROFILE_SPECIFIER=
  )
else
  echo "build.sh: no code-signing identity found; building unsigned (Full Disk Access will not persist across rebuilds)"
  SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
fi

xcodebuild \
  -project i2Message.xcodeproj \
  -scheme i2Message \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' \
  -skipPackagePluginValidation \
  "${SIGNING_ARGS[@]}" \
  build
