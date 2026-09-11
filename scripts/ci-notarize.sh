#!/usr/bin/env bash
# Archive Lantern with Developer ID, notarize, and staple.
# Required env:
#   APPLE_TEAM_ID
#   APPLE_API_KEY_ID
#   APPLE_API_ISSUER
#   APPLE_API_KEY_P8   (PEM text, or base64 of the .p8)
# Developer ID cert must already be in the default keychain
# (apple-actions/import-codesign-certs in CI).
#
# Writes: dist/notarized/Lantern.app and dist/notarized/Lantern-<tag>.dmg
# Optional env: TAG_NAME (e.g. v0.2.0). Falls back to version.txt.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

need() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing env $name. Add it as a GitHub Actions secret." >&2
    exit 1
  fi
}

need APPLE_TEAM_ID
need APPLE_API_KEY_ID
need APPLE_API_ISSUER
need APPLE_API_KEY_P8

ARCHIVE="$ROOT/build/Lantern.xcarchive"
EXPORT_DIR="$ROOT/dist/notarized"
EXPORT_PLIST="$ROOT/build/ExportOptions.plist"
API_KEY_FILE="$ROOT/build/AuthKey_${APPLE_API_KEY_ID}.p8"
NOTARIZE_ZIP="$ROOT/build/Lantern-notarize.zip"

mkdir -p "$ROOT/build" "$EXPORT_DIR"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$NOTARIZE_ZIP"
mkdir -p "$EXPORT_DIR"

cleanup() {
  rm -f "$API_KEY_FILE" "$NOTARIZE_ZIP"
}
trap cleanup EXIT

if [[ "$APPLE_API_KEY_P8" == *"BEGIN PRIVATE KEY"* ]]; then
  printf '%s\n' "$APPLE_API_KEY_P8" > "$API_KEY_FILE"
else
  printf '%s\n' "$APPLE_API_KEY_P8" | base64 --decode > "$API_KEY_FILE"
fi
chmod 600 "$API_KEY_FILE"

command -v xcodegen >/dev/null 2>&1 && xcodegen generate

cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${APPLE_TEAM_ID}</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
EOF

echo "Available signing identities:"
security find-identity -v -p codesigning || true

xcodebuild archive \
  -project Lantern.xcodeproj \
  -scheme Lantern \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$ROOT/build/DerivedData" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

APP="$EXPORT_DIR/Lantern.app"
if [[ ! -d "$APP" ]]; then
  echo "Export did not produce Lantern.app in $EXPORT_DIR" >&2
  ls -la "$EXPORT_DIR" >&2 || true
  exit 1
fi

ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"

xcrun notarytool submit "$NOTARIZE_ZIP" \
  --key "$API_KEY_FILE" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER" \
  --wait \
  --timeout 30m

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Notarized app: $APP"

# First-run download: UDZO image with an Applications drop target.
# Sparkle still ships the zip; the DMG is notarized separately.
TAG="${TAG_NAME:-}"
if [[ -z "$TAG" && -f "$ROOT/version.txt" ]]; then
  TAG="v$(tr -d '[:space:]' < "$ROOT/version.txt")"
fi
[[ -n "$TAG" ]] || TAG="dev"
[[ "$TAG" == v* ]] || TAG="v$TAG"
STEM="Lantern-${TAG}"

STAGE="$ROOT/build/dmg-root"
DMG="$EXPORT_DIR/${STEM}.dmg"
rm -rf "$STAGE" "$DMG" "$EXPORT_DIR/Lantern.dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Lantern.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "Lantern" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG"

xcrun notarytool submit "$DMG" \
  --key "$API_KEY_FILE" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER" \
  --wait \
  --timeout 30m

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# Stable name so README can use /releases/latest/download/Lantern.dmg
ditto "$DMG" "$EXPORT_DIR/Lantern.dmg"

echo "Notarized DMG: $DMG"
