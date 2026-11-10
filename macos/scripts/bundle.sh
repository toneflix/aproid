#!/bin/sh
# Builds Aproid.app, with its Share extension and battery widget, in macos/build. Notification Center and the
# Share menu only work for a bundled app, so use this instead of `swift run` to try them.
set -eu

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP="build/Aproid.app"
SHARE="$APP/Contents/PlugIns/AproidShare.appex"
WIDGET="$APP/Contents/PlugIns/AproidWidget.appex"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Aproid"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SHARE/Contents/MacOS" "$SHARE/Contents/Resources" "$WIDGET/Contents/MacOS"
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
        otool -L "$APP/Contents/MacOS/Aproid" | grep -i intents || echo "(the app doesn't load AppIntents.framework)"
    fi
else
    echo "Shortcuts actions: skipped (the metadata tool failed)"
fi

# Ad-hoc signatures so macOS accepts them locally. Extensions must be signed first and sandboxed.
codesign --force --sign - --entitlements Share/Share.entitlements "$SHARE"
codesign --force --sign - --entitlements Widget/Widget.entitlements "$WIDGET"
codesign --force --sign - "$APP"

# Tells the Share menu and the widget gallery about the extensions without waiting for macOS to find them.
pluginkit -a "$SHARE" 2>/dev/null || true
pluginkit -a "$WIDGET" 2>/dev/null || true

echo "Built $APP. Open it with: open $APP"
