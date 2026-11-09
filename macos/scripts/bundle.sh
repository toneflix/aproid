#!/bin/sh
# Builds Aproid.app, with its Share extension, in macos/build. Notification Center and the
# Share menu only work for a bundled app, so use this instead of `swift run` to try them.
set -eu

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP="build/Aproid.app"
SHARE="$APP/Contents/PlugIns/AproidShare.appex"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Aproid"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SHARE/Contents/MacOS" "$SHARE/Contents/Resources"
cp Bundle/Info.plist "$APP/Contents/Info.plist"
cp Bundle/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN" "$APP/Contents/MacOS/Aproid"

# SwiftPM can't build app extensions, so the Share extension is compiled directly.
OPTIMIZE="-Onone"
[ "$CONFIG" = "release" ] && OPTIMIZE="-O"
cp Share/Info.plist "$SHARE/Contents/Info.plist"
cp Bundle/AppIcon.icns "$SHARE/Contents/Resources/AppIcon.icns"
xcrun swiftc $OPTIMIZE \
    -parse-as-library \
    -application-extension \
    -module-name AproidShare \
    -target "$(uname -m)-apple-macos13.0" \
    -Xlinker -e -Xlinker _NSExtensionMain \
    Share/*.swift Sources/Aproid/ShareRequest.swift Sources/Aproid/AproidMark.swift \
    -o "$SHARE/Contents/MacOS/AproidShare"

# Ad-hoc signatures so macOS accepts them locally. The extension must be signed first and sandboxed.
codesign --force --sign - --entitlements Share/Share.entitlements "$SHARE"
codesign --force --sign - "$APP"

# Tells the Share menu about the extension without waiting for macOS to find it.
pluginkit -a "$SHARE" 2>/dev/null || true

echo "Built $APP. Open it with: open $APP"
