# Aproid

Aproid connects an Android phone to a Mac the way an iPhone connects to one: sharing files, notifications, messages, calls, clipboard and phone controls.

It speaks the [KDE Connect](https://kdeconnect.kde.org/) protocol, so it also works with existing KDE Connect clients. The apps themselves are our own, written from scratch, with the goal of being better than both KDE Connect and Microsoft Phone Link.

> Status: early scaffold. The phone and the Mac can find each other on Wi-Fi and swap identities. Encryption, pairing in the UI and features come next. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Repository layout

| Folder | What it is |
| --- | --- |
| `android/protocol` | Shared protocol code in plain Kotlin (packets, identity, pairing, LAN discovery). Tested on any JVM. |
| `android/app` | The Android app (Kotlin, Jetpack Compose). |
| `macos/Sources/AproidKit` | The same protocol code in Swift. |
| `macos/Sources/Aproid` | The Mac menu bar app (SwiftUI). |
| `docs/` | Architecture and roadmap. |

## Building

**Android** (needs JDK 17 and the Android SDK):

```sh
cd android
./gradlew :protocol:test        # protocol tests, no Android SDK needed
./gradlew :app:installDebug     # build and install on a connected phone
```

**Mac** (needs Xcode 15 or later, macOS 13 or later):

```sh
cd macos
swift test
swift run Aproid                # starts the menu bar app
```

Or open `macos/Package.swift` in Xcode. The first time it runs, macOS asks for permission to find devices on the local network. Allow it.

## Trying it

1. Put the phone and the Mac on the same Wi-Fi.
2. Start the Mac app. An icon appears in the menu bar.
3. Open Aproid on the phone and tap **Start**.
4. Each device should show the other in its list within a few seconds.

If KDE Connect is running on either device it may hold port 1716. Aproid falls back to the next free port, but discovery is most reliable with KDE Connect closed.

## License

MIT. See [LICENSE](LICENSE).
