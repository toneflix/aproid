# Aproid

Android phone + Mac continuity app speaking the KDE Connect protocol (v8). See docs/ARCHITECTURE.md.

- The protocol is implemented twice: `android/protocol` (Kotlin) and `macos/Sources/AproidKit` (Swift). Keep names, behaviour and tests in sync when changing either.
- Do not copy KDE Connect source code (GPL). This repo is MIT.
- Our own packet types use the `aproid.` prefix and must be listed in capabilities.
- Android: `cd android && ./gradlew :protocol:test` works without the Android SDK; `:app` is only included when the SDK is found.
- Mac: `cd macos && swift test`. Needs macOS and Xcode; CI runs it on macos-15.
