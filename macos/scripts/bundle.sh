#!/bin/sh
# Builds Aproid.app, with its Share extension and battery widget, in macos/build. Notification Center and the
# Share menu only work for a bundled app, so use this instead of `swift run` to try them.
#
# Without settings it signs ad hoc for this Mac. The release workflow sets:
#   VERSION, BUILD_NUMBER          the version shown and the one Sparkle compares
#   SIGN_IDENTITY                  a "Developer ID Application" identity in the keychain
#   SPARKLE_FEED_URL, SPARKLE_PUBLIC_KEY   turn on automatic updates
set -eu

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP="build/Aproid.app"
SHARE="$APP/Contents/PlugIns/AproidShare.appex"
WIDGET="$APP/Contents/PlugIns/AproidWidget.appex"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Aproid"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" \
    "$SHARE/Contents/MacOS" "$SHARE/Contents/Resources" "$WIDGET/Contents/MacOS"
cp Bundle/Info.plist "$APP/Contents/Info.plist"
cp Bundle/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN" "$APP/Contents/MacOS/Aproid"
# Keep the framework's symlinks, or its signature breaks.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

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

# The battery widget, compiled the same way. WidgetKit supplies its entry point.
cp Widget/Info.plist "$WIDGET/Contents/Info.plist"
xcrun swiftc $OPTIMIZE \
    -parse-as-library \
    -application-extension \
    -module-name AproidWidget \
    -target "$(uname -m)-apple-macos13.0" \
    Widget/*.swift Sources/Aproid/WidgetSnapshot.swift Sources/Aproid/AproidMark.swift \
    -o "$WIDGET/Contents/MacOS/AproidWidget"

# Shortcuts finds the app's actions through metadata Xcode normally writes. SwiftPM doesn't, so ask the
# same tool for it. If this Xcode's tool wants something else, the app still works, just without the actions.
SWIFT_FILES="$(mktemp)"
EMPTY_LIST="$(mktemp)"
ls "$PWD"/Sources/Aproid/*.swift > "$SWIFT_FILES"
if xcrun appintentsmetadataprocessor \
    --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
    --module-name Aproid \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" \
    --platform-family macOS \
    --deployment-target 13.0 \
    --bundle-identifier com.toneflix.aproid.app \
    --output "$APP/Contents/Resources" \
    --target-triple "$(uname -m)-apple-macos13.0" \
    --binary-file "$APP/Contents/MacOS/Aproid" \
    --dependency-file "$(mktemp)" \
    --stringsdata-file "$(mktemp)" \
    --source-file-list "$SWIFT_FILES" \
    --metadata-file-list "$EMPTY_LIST" \
    --static-metadata-file-list "$EMPTY_LIST" \
    --swift-const-vals-list "$EMPTY_LIST" \
    --no-app-shortcuts-localization; then
    if [ -d "$APP/Contents/Resources/Metadata.appintents" ]; then
        echo "Shortcuts actions: added"
    else
        echo "Shortcuts actions: the metadata tool ran but wrote nothing"
    fi
else
    echo "Shortcuts actions: skipped (the metadata tool failed)"
fi

# Versions and update settings, in the app and both extensions.
for PLIST in "$APP/Contents/Info.plist" "$SHARE/Contents/Info.plist" "$WIDGET/Contents/Info.plist"; do
    if [ -n "${VERSION:-}" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
    fi
    if [ -n "${BUILD_NUMBER:-}" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
    fi
done
if [ -n "${SPARKLE_FEED_URL:-}" ] && [ -n "${SPARKLE_PUBLIC_KEY:-}" ]; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$APP/Contents/Info.plist"
fi

# Sign from the inside out. Ad hoc is enough for this Mac; a Developer ID release also needs the
# hardened runtime and a timestamp for notarization. Extensions are sandboxed.
sign() {
    if [ "$SIGN_IDENTITY" = "-" ]; then
        codesign --force --sign - "$@"
    else
        codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$@"
    fi
}
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements Share/Share.entitlements "$SHARE"
sign --entitlements Widget/Widget.entitlements "$WIDGET"
sign "$APP"
codesign --verify --deep --strict "$APP"

# Tells the Share menu and the widget gallery about the extensions without waiting for macOS to find them.
pluginkit -a "$SHARE" 2>/dev/null || true
pluginkit -a "$WIDGET" 2>/dev/null || true

echo "Built $APP. Open it with: open $APP"
