#!/bin/sh
# Builds Aproid.app in macos/build. Notification Center only works for a bundled app,
# so use this instead of `swift run` to try notifications.
set -eu

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP="build/Aproid.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Aproid"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Bundle/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/Aproid"

# Ad-hoc signature so macOS accepts it locally.
codesign --force --sign - "$APP"

echo "Built $APP. Open it with: open $APP"
