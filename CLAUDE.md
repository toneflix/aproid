# FlyyLink

Android phone + Mac and Windows continuity app speaking the KDE Connect protocol (v8). See docs/ARCHITECTURE.md.

- The app is called FlyyLink. Code, package and bundle ids, packet prefixes, the URL scheme, data folders and cloud resources keep the old `aproid` name so installs update in place.
- The protocol is implemented three times: `android/protocol` (Kotlin), `macos/Sources/AproidKit` (Swift) and `windows/src/Aproid.Core` (C#). Keep names, behaviour and tests in sync when changing any of them.
- Do not copy KDE Connect source code (GPL). This repo is proprietary (see LICENSE).
- Our own packet types use the `flyylink.` prefix and must be listed in capabilities.
- Android: `cd android && ./gradlew :protocol:test` works without the Android SDK; `:app` is only included when the SDK is found.
- Mac: `cd macos && swift test`. Needs macOS and Xcode; CI runs it on macos-15.
- Windows: `cd windows && dotnet test tests/Aproid.Core.Tests` works on any OS with the .NET 8 SDK. The WinUI app (`src/Aproid`) only builds on Windows; CI runs it on windows-latest and uploads the build.
