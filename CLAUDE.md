# FlyyLink

Android phone + Mac and Windows continuity app speaking the KDE Connect protocol (v8). See docs/ARCHITECTURE.md.

- The app was called Aproid. Don't bring that name back.
- The protocol is implemented three times: `android/protocol` (Kotlin), `macos/Sources/FlyyLinkKit` (Swift) and `windows/src/FlyyLink.Core` (C#). Keep names, behaviour and tests in sync when changing any of them.
- Do not copy KDE Connect source code (GPL). This repo is proprietary (see LICENSE).
- Our own packet types use the `flyylink.` prefix and must be listed in capabilities.
- Android: `cd android && ./gradlew :protocol:test` works without the Android SDK; `:app` is only included when the SDK is found.
- Mac: `cd macos && swift test`. Needs macOS and Xcode; CI runs it on macos-15.
- Windows: `cd windows && dotnet test tests/FlyyLink.Core.Tests` works on any OS with the .NET 8 SDK. The WinUI app (`src/FlyyLink`) only builds on Windows; CI runs it on windows-latest and uploads the build.
