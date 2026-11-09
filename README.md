# Aproid

Aproid connects an Android phone to a Mac the way an iPhone connects to one: sharing files, notifications, messages, calls, clipboard and phone controls.

It speaks the [KDE Connect](https://kdeconnect.kde.org/) protocol, so it also works with existing KDE Connect clients. The apps themselves are our own, written from scratch, with the goal of being better than both KDE Connect and Microsoft Phone Link.

> Status: early. The phone and the Mac connect over TLS, pair with a matching code, and phone notifications show on the Mac with reply and dismiss. See [docs/ROADMAP.md](docs/ROADMAP.md).

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
./scripts/bundle.sh             # builds macos/build/Aproid.app
open build/Aproid.app           # starts the menu bar app
```

`swift run Aproid` or running from Xcode also works, but without an app bundle macOS won't show notifications or the Share menu entry. The first time the app runs, macOS asks to find devices on the local network and to show notifications. Allow both.

## Trying it

1. Put the phone and the Mac on the same Wi-Fi.
2. Start the Mac app. An icon appears in the menu bar.
3. Open Aproid on the phone and tap **Start**.
4. Each device should show the other in its list within a few seconds.
5. Tap **Pair** on one side, check the code matches on both, and accept on the other.
6. On the phone, tap **Allow access** and turn on notification access for Aproid. New notifications now show on the Mac. Reply from the banner, or dismiss it to clear it on the phone too.
7. To send something from the Mac, use **Share > Aproid** in Finder, Safari, Photos or any app with a Share menu. If Aproid isn't listed, turn it on in System Settings > General > Login Items & Extensions > Sharing (on macOS 13 and 14: Privacy & Security > Extensions > Sharing).

If KDE Connect is running on either device it may hold port 1716. Aproid falls back to the next free port, but discovery is most reliable with KDE Connect closed.

## License

MIT. See [LICENSE](LICENSE).
