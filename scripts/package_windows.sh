#!/usr/bin/env bash
# Builds the Flutter Windows app and wraps it in a distributable installer + ZIP.
#
#   ./scripts/package_windows.sh                 # release build + setup.exe + ZIP
#   VERSION=1.0.1 ./scripts/package_windows.sh   # override the version
#   NO_ZIP=1 ./scripts/package_windows.sh        # installer only
#   NO_INSTALLER=1 ./scripts/package_windows.sh  # portable ZIP only
#
# Build prerequisites: Visual Studio 2022 (Desktop development with C++) for the
# runner, and Inno Setup 6 for the installer (winget install JRSoftware.InnoSetup).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/flutter_app"

# Flutter SDK lookup order: $FLUTTER > $FLUTTER_HOME > D:\flutter > PATH.
FLUTTER_HOME_CAND="${FLUTTER:-${FLUTTER_HOME:-/d/flutter}}"
if [ -x "$FLUTTER_HOME_CAND/bin/flutter" ]; then
  FLUTTER="$FLUTTER_HOME_CAND/bin/flutter"
else
  FLUTTER="$(command -v flutter || true)"
  [ -n "$FLUTTER" ] || { echo "flutter not found: set FLUTTER=/path/to/sdk"; exit 1; }
fi

# Version comes from pubspec.yaml unless overridden on the command line.
VERSION="${VERSION:-$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$APP_DIR/pubspec.yaml")}"
[ -n "$VERSION" ] || { echo "cannot read version from pubspec.yaml"; exit 1; }

DIST="$ROOT/dist"
ZIP="$DIST/MusicFly-$VERSION-windows-x64.zip"
SETUP="$DIST/MusicFly-$VERSION-windows-x64-setup.exe"
BUNDLE="$APP_DIR/build/windows/x64/runner/Release"
STAGE_BASE="$(mktemp -d)"
STAGE="$STAGE_BASE/MusicFly"

echo "==> flutter build windows --release"
cd "$APP_DIR"
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  "$FLUTTER" build windows --release

test -f "$BUNDLE/musicfly.exe" || { echo "missing $BUNDLE/musicfly.exe"; exit 1; }
# dist/ 被 gitignore，全新 checkout 时不存在；先清掉旧包避免混淆。
mkdir -p "$DIST"

if [ "${NO_ZIP:-0}" != "1" ]; then
  echo "==> staging"
  mkdir -p "$STAGE"
  cp -R "$BUNDLE/." "$STAGE/"

  echo "==> zip"
  rm -f "$ZIP"
  # Git Bash 自带 GNU tar 写不了 zip；优先 zip，其次 7z，最后退回 PowerShell。
  if command -v zip >/dev/null 2>&1; then
    (cd "$STAGE/.." && zip -qr "$ZIP" MusicFly)
  elif command -v 7z >/dev/null 2>&1; then
    7z a -tzip "$ZIP" "$STAGE" >/dev/null
  else
    # Git Bash 的 /d/... 路径 PowerShell 不认，先转成 Windows 形式。
    powershell.exe -NoProfile -Command \
      "Compress-Archive -Path '$(cygpath -w "$STAGE")' -DestinationPath '$(cygpath -w "$ZIP")' -Force"
  fi

  # 直接从 zip 里确认可执行文件被打进去了（PowerShell 打包用 \ 分隔，zip / 都有）。
  test -s "$ZIP" || { echo "zip is empty: $ZIP"; exit 1; }
  if command -v unzip >/dev/null 2>&1; then
    unzip -l "$ZIP" | grep -Eq "MusicFly[/\\\\]musicfly.exe" \
      || { echo "zip is missing MusicFly/musicfly.exe"; exit 1; }
  fi
fi

if [ "${NO_INSTALLER:-0}" != "1" ]; then
  echo "==> installer (Inno Setup)"
  # 优先用 Inno Setup 6（脚本用到 6.3+ 的 x64compatible、modern 向导和 6.5 中文语言包），
  # PATH 上的 iscc 可能是旧版 choco 包，放在最后兜底。
  ISCC="${ISCC:-}"
  if [ -z "$ISCC" ]; then
    for c in "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
             "/c/Program Files/Inno Setup 6/ISCC.exe"; do
      [ -f "$c" ] && { ISCC="$c"; break; }
    done
  fi
  [ -n "$ISCC" ] || ISCC="$(command -v iscc || true)"
  [ -n "$ISCC" ] || { echo "Inno Setup 6 not found: install it or set ISCC=/path/to/ISCC.exe"; exit 1; }

  rm -f "$SETUP"
  # MSYS 会把 /Qp、/D... 当路径改写，导致 ISCC 报 "more than one script filename"，
  # 调用前关掉参数路径转换。
  MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 "$ISCC" /Qp \
    "/DAppVersion=$VERSION" \
    "/DSourceDir=$(cygpath -w "$BUNDLE")" \
    "/DOutputDir=$(cygpath -w "$DIST")" \
    "$(cygpath -w "$ROOT/scripts/musicfly.iss")"
  test -s "$SETUP" || { echo "installer not produced: $SETUP"; exit 1; }
fi

# mktemp 在 Git Bash 里返回 C:\... 形式，转成 /c/... 再删。
rm -rf "$(cygpath -u "$STAGE_BASE")"

echo "==> done"
ls -lh "$DIST"/MusicFly-"$VERSION"-windows-x64*
