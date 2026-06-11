#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/DesktopPet.app"

if [[ -e "$APP_PATH" ]]; then
  APP_PATH="$DIST_DIR/DesktopPet-$(date +%Y%m%d%H%M%S).app"
fi

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources/assets"

cp "$ROOT_DIR/.build/release/DesktopPet" "$APP_PATH/Contents/MacOS/DesktopPet"
cp "$ROOT_DIR/macos/Info.plist" "$APP_PATH/Contents/Info.plist"
ditto "$ROOT_DIR/assets/sprites" "$APP_PATH/Contents/Resources/assets/sprites"
if [[ -d "$ROOT_DIR/assets/gifs" ]]; then
  ditto "$ROOT_DIR/assets/gifs" "$APP_PATH/Contents/Resources/assets/gifs"
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_PATH" >/dev/null
fi

echo "$APP_PATH"
