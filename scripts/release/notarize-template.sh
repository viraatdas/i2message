#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: NOTARY_PROFILE=<keychain-profile> $0 <zip-or-dmg-path>" >&2
  exit 64
fi

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "error: NOTARY_PROFILE is required. Create it locally with xcrun notarytool store-credentials." >&2
  exit 64
fi

ARTIFACT_PATH="$1"

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "error: artifact not found: $ARTIFACT_PATH" >&2
  exit 66
fi

xcrun notarytool submit "$ARTIFACT_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "Notarization completed. Staple the final .app, .dmg, or .pkg before distribution."
