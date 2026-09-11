#!/usr/bin/env bash
# Package Lantern.app into a Sparkle update (zip + appcast.xml) for a GitHub Release.
# Usage:
#   SPARKLE_ED_PRIVATE_KEY=... scripts/publish-sparkle.sh path/to/Lantern.app v0.2.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?path to Lantern.app}"
TAG="${2:?git tag, e.g. v0.2.0}"
REPO="${GITHUB_REPOSITORY:-sinhong2011/lantern}"
OUT="$ROOT/dist/updates"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.6}"

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  exit 1
fi
if [[ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  echo "SPARKLE_ED_PRIVATE_KEY is required (Sparkle EdDSA seed, base64)." >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

# GitHub Release notes become the Sparkle item description.
if command -v gh >/dev/null 2>&1; then
  gh release view "$TAG" --repo "$REPO" --json body --jq .body > "$OUT/Lantern.md" || true
fi

ditto -c -k --keepParent "$APP" "$OUT/Lantern.zip"

TOOLS="$ROOT/build/sparkle-tools"
if [[ ! -x "$TOOLS/bin/generate_appcast" ]]; then
  mkdir -p "$TOOLS"
  curl -L --fail -o /tmp/Sparkle-"$SPARKLE_VERSION".tar.xz \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  tar -xJf /tmp/Sparkle-"$SPARKLE_VERSION".tar.xz -C "$TOOLS"
fi

PREFIX="https://github.com/${REPO}/releases/download/${TAG}/"
printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" | "$TOOLS/bin/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "$PREFIX" \
  --link "https://github.com/${REPO}" \
  --embed-release-notes \
  -o "$OUT/appcast.xml" \
  "$OUT"

echo "Wrote $OUT/Lantern.zip and $OUT/appcast.xml"
