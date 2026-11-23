#!/bin/bash
# 编译并打包 cosmNotes.app
set -e
cd "$(dirname "$0")"

APP="build/cosmNotes.app"
RELEASE_MODE="${1:-}"

echo "==> 编译 (release)..."
if [ "$RELEASE_MODE" = "--release" ]; then
    swift build -c release --arch arm64 --product cosmNotes
    swift build -c release --arch x86_64 --product cosmNotes
    ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/cosmNotes"
    INTEL_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/cosmNotes"
else
    swift build -c release --product cosmNotes
fi

echo "==> 打包 $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/mcp"
if [ "$RELEASE_MODE" = "--release" ]; then
    xcrun lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP/Contents/MacOS/cosmNotes"
    xcrun lipo "$APP/Contents/MacOS/cosmNotes" -verify_arch arm64 x86_64
else
    cp .build/release/cosmNotes "$APP/Contents/MacOS/cosmNotes"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns LICENSE "$APP/Contents/Resources/"
cp mcp/cosmnotes_mcp.py "$APP/Contents/Resources/mcp/"

echo "==> 签名 (ad-hoc)..."
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"

if [ "$RELEASE_MODE" = "--release" ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
    ARCHIVE="cosmNotes-v$VERSION-macOS.zip"
    rm -f "build/$ARCHIVE"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "build/$ARCHIVE"
    (cd build && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
    echo "✅ 已生成 build/$ARCHIVE"
fi

echo "✅ 已生成 $APP"
