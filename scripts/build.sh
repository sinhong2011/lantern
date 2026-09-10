#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate

DERIVED="${ROOT}/build/DerivedData"
xcodebuild \
  -project Lantern.xcodeproj \
  -scheme Lantern \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES

APP="$DERIVED/Build/Products/Debug/Lantern.app"
echo "Built: $APP"
echo "Run:   open \"$APP\""
