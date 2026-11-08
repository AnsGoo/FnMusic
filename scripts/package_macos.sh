#!/usr/bin/env bash
# Builds the Flutter macOS app and wraps it in a distributable DMG.
#
#   ./scripts/package_macos.sh                 # release build + DMG in dist/
#   VERSION=1.0.1 ./scripts/package_macos.sh   # override the file name
#
# The app is signed ad-hoc, so first launch on another Mac needs
# right-click > Open (or `xattr -dr com.apple.quarantine`).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/flutter_app"
FLUTTER="${FLUTTER:-$HOME/development/flutter/bin/flutter}"
VERSION="${VERSION:-1.0.0}"
OUT="$ROOT/dist/MusicFly-$VERSION-macos.dmg"
STAGE="$(mktemp -d)/stage"

echo "==> flutter build macos --release"
cd "$APP_DIR"
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  "$FLUTTER" build macos --release

APP="$APP_DIR/build/macos/Build/Products/Release/MusicFly.app"
test -d "$APP" || { echo "missing $APP"; exit 1; }

echo "==> signing"
# Xcode rewrites App.framework (the Dart code) on every build but does not
# always re-sign it, which breaks `codesign --verify --deep --strict`. Ad-hoc
# signing the whole bundle is enough for local distribution.
codesign --force --sign - --timestamp=none "$APP/Contents/Frameworks/App.framework"
codesign --force --sign - --timestamp=none "$APP"

echo "==> staging"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> hdiutil"
# dist/ 被 gitignore，CI 全新 checkout 时不存在；hdiutil 不会自动建输出目录，
# 缺了就报 "create failed - No such file or directory"。
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create -volname "MusicFly" -srcfolder "$STAGE" -ov \
  -format UDZO -fs HFS+ "$OUT" >/dev/null

echo "==> verifying"
codesign --verify --deep --strict "$APP"
MNT="$(hdiutil attach "$OUT" -nobrowse -readonly | tail -1 | awk -F'\t' '{print $NF}')"
test -d "$MNT/MusicFly.app" || { echo "DMG is missing MusicFly.app"; exit 1; }
hdiutil detach "$MNT" -quiet

rm -rf "$(dirname "$STAGE")"
ls -lh "$OUT"
