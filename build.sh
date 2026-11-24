#!/bin/bash
# 编译并打包 cosmNotes.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/cosmNotes.app"
RELEASE_MODE="${1:-}"

bundle_app() {
    local executable="$1"
    local bundle="$2"
    echo "==> 打包 $bundle ..."
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/mcp"
    cp "$executable" "$bundle/Contents/MacOS/cosmNotes"
    cp Resources/Info.plist "$bundle/Contents/Info.plist"
    local sparkle_framework
    sparkle_framework="$(find .build/artifacts -type d -path '*/macos-arm64_x86_64/Sparkle.framework' -print -quit)"
    if [ -z "$sparkle_framework" ]; then
        echo "Sparkle framework missing from the resolved Swift package artifacts."
        return 1
    fi
    mkdir -p "$bundle/Contents/Frameworks"
    ditto "$sparkle_framework" "$bundle/Contents/Frameworks/Sparkle.framework"
    cp "$sparkle_framework/../../../LICENSE" "$bundle/Contents/Resources/Sparkle-LICENSE.txt"
    cp Resources/AppIcon.icns LICENSE "$bundle/Contents/Resources/"
    cp mcp/cosmnotes_mcp.py "$bundle/Contents/Resources/mcp/"
    codesign --force --deep -s - "$bundle"
    codesign --verify --deep --strict "$bundle"
}

archive_app() {
    local bundle="$1"
    local archive="$2"
    rm -f "build/$archive"
    ditto -c -k --sequesterRsrc --keepParent "$bundle" "build/$archive"
    (cd build && shasum -a 256 "$archive" > "$archive.sha256")
    echo "==> 已生成 build/$archive"
}

echo "==> 编译 (release)..."
if [ "$RELEASE_MODE" = "--release" ]; then
    STAGING="$(mktemp -d "${TMPDIR:-/tmp}/cosmnotes-build.XXXXXX")"
    trap 'rm -rf "$STAGING"' EXIT
    swift build -c release --arch arm64 --product cosmNotes
    swift build -c release --arch x86_64 --product cosmNotes
    ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/cosmNotes"
    INTEL_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/cosmNotes"

    xcrun lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$STAGING/cosmNotes"
    xcrun lipo "$STAGING/cosmNotes" -verify_arch arm64 x86_64
    bundle_app "$STAGING/cosmNotes" "$APP"

    INTEL_APP="$STAGING/Intel/cosmNotes.app"
    test "$(xcrun lipo -archs "$INTEL_BIN")" = "x86_64"
    bundle_app "$INTEL_BIN" "$INTEL_APP"

    VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
    archive_app "$APP" "cosmNotes-v$VERSION-macOS.zip"
    archive_app "$INTEL_APP" "cosmNotes-v$VERSION-macOS-Intel.zip"
else
    swift build -c release --product cosmNotes
    NATIVE_BIN="$(swift build -c release --show-bin-path)/cosmNotes"
    bundle_app "$NATIVE_BIN" "$APP"
fi

echo "==> 已生成 $APP"
