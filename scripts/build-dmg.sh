#!/usr/bin/env bash
# Packages "Local Explorer.app" into a drag-to-install .dmg.
#
#   scripts/build-dmg.sh                 # builds the app first, then build/LocalExplorer.dmg
#   SKIP_APP_BUILD=1 scripts/build-dmg.sh   # reuse the existing app in ./build
#
# Honors the same APP_NAME / VERSION / SIGN_IDENTITY variables as scripts/build-app.sh.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="${APP_NAME:-Local Explorer}"
VERSION="${VERSION:-0.1.0}"
OUT_DIR="${OUT_DIR:-build}"
APP="$OUT_DIR/$APP_NAME.app"
DMG="$OUT_DIR/LocalExplorer-$VERSION.dmg"

if [[ -z "${SKIP_APP_BUILD:-}" ]]; then
  scripts/build-app.sh
fi
[[ -d "$APP" ]] || { echo "error: $APP not found; run scripts/build-app.sh first." >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging $APP_NAME.app"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> Done: $DMG"
