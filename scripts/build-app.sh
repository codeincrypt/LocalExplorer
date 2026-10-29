#!/usr/bin/env bash
# Builds "Local Explorer.app" (native arm64) from the Swift package.
#
#   scripts/build-app.sh                 # release build into ./build
#   APP_NAME="My Files" BUNDLE_ID=com.example.files scripts/build-app.sh
#   CONFIGURATION=debug scripts/build-app.sh
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#
# Requires macOS 14+ and Xcode 16+ (or the matching Command Line Tools).
# Works fully offline: the package has no external dependencies.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="${APP_NAME:-Local Explorer}"
BUNDLE_ID="${BUNDLE_ID:-app.localexplorer.LocalExplorer}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
CONFIGURATION="${CONFIGURATION:-release}"
ARCH="${ARCH:-arm64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc signature for local use
OUT_DIR="${OUT_DIR:-build}"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: the app target builds only on macOS." >&2
  exit 1
fi

echo "==> Building LocalExplorer ($CONFIGURATION, $ARCH)"
swift build -c "$CONFIGURATION" --arch "$ARCH" --product LocalExplorer
BIN_DIR="$(swift build -c "$CONFIGURATION" --arch "$ARCH" --show-bin-path)"

APP="$OUT_DIR/$APP_NAME.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LocalExplorer" "$APP/Contents/MacOS/LocalExplorer"

sed -e "s|__APP_NAME__|$APP_NAME|g" \
    -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD__|$BUILD_NUMBER|g" \
    Support/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# App icon from the bundled 1024px PNG (no network, uses sips + iconutil).
if [[ -f Support/AppIcon.png ]] && command -v iconutil >/dev/null; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Signing ($SIGN_IDENTITY)"
codesign --force --options runtime --timestamp=none \
  --entitlements Support/LocalExplorer.entitlements \
  --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "==> Done: $APP"
echo "    Run with: open \"$APP\""
