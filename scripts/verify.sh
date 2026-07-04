#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/generate-xcodeproj.sh"
"$ROOT_DIR/scripts/build.sh"
"$ROOT_DIR/scripts/test.sh"
