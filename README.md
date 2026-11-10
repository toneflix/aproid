<p align="center">
  <img src="branding/app-icon.svg" width="112" alt="Aproid">
</p>

<h1 align="center">Aproid</h1>

<p align="center"><strong>Your Android phone and your computer, finally on speaking terms.</strong></p>

<p align="center">For Android, Mac and Windows. Free, open source, and it never leaves your home network.</p>

---

iPhone owners get a quiet little luxury: their phone and their Mac just work together. A text arrives and they answer it from the laptop. A photo goes from pocket to desktop in a second. The phone rings in the other room and they pick up from where they're sitting.

If you carry an Android phone, you've mostly had to go without. Aproid is our answer to that. Install it on your phone and your computer, pair them once, and from then on they behave like they were made for each other.

![The Aproid panel on a Mac with two phones paired, a call coming in, and the Messages window](web/public/screens/mac-overview.png)

## What it does

**Your notifications, where you're looking.** Phone notifications show up on your computer with the app's own icon. Reply to a chat without picking up the phone, tap an action button, or dismiss it on the computer and watch it clear on the phone too.

**Texts and calls from your desk.** Read and send SMS in a proper Messages window. When the phone rings, a card shows you who it is so you can answer or decline. Start a call from your contacts. On a Mac you can even take the call through the Mac's own speakers and microphone (still experimental).

**Files without the cable.** Drag a file onto the panel, use the Share menu on your Mac or Windows PC, or share from any app on your phone. Big videos keep going if the connection drops and pick up where they left off. Click a received file to open it.

**Your phone's screen, on your screen.** Mirror the phone into a window, sound and all, and use it with your mouse and keyboard. Handy for the apps that only exist on your phone.

**Photos, the moment you take them.** Browse recent photos and screenshots from the computer and pull down the ones you want. On Windows they also appear in File Explorer.

**One clipboard.** Copy on one device and paste on the other. Text, images and files.

**The little things.** Battery level at a glance with a low-battery heads up. Media controls for whatever is playing. Ring your phone when it has slipped between the sofa cushions, and see where it was last seen on a map.

**More than one phone, more than one computer.** Pair a work phone and a personal one, or one phone with your Mac and your PC. Each device gets its own card, and you swipe or click between them.

**Computers, too.** Pair your Mac with your Windows PC, or two of either, to share files, the clipboard and links between them, check each other's battery, ring a misplaced laptop and control music on the other machine.

**Works when the Wi-Fi doesn't.** Hotel network blocking devices? Aproid can find your phone over Bluetooth and connect through your phone's own hotspot instead.

![Swipe between paired devices on Android and the Mac](web/public/screens/android-carousel.png)

## Private by design

Aproid has no servers, no accounts and no analytics. Your phone and your computer talk to each other directly over your local network (or Bluetooth), and every connection is encrypted. Devices only connect after you pair them and confirm the same code on both screens. Your messages, photos and notifications go from your phone to your computer and nowhere else.

It also speaks the [KDE Connect](https://kdeconnect.kde.org/) protocol, so it gets along with KDE Connect on Linux and other devices.

## Get it

Download the latest version for each platform from the [Releases page](https://github.com/toneflix/aproid/releases).

| | Needs | How it installs |
| --- | --- | --- |
| **Android** | Android 8.0 or later | APK, Google Play coming soon |
| **Mac** | macOS 13 Ventura or later | Signed app, updates itself |
| **Windows** | Windows 10 (1809) or later | Installer, updates itself |

### Setting up

1. Put your phone and computer on the same Wi-Fi (or turn on your phone's hotspot and join it).
2. Open Aproid on both. Each one shows the other within a few seconds.
3. Tap **Pair**, check the code matches on both screens, and accept.
4. On the phone, allow notification access and whichever extras you want (messages, calls, screen control). Aproid explains each one when you turn it on.

Some phones, especially Tecno, Infinix, itel and Xiaomi models, close background apps aggressively. If the connection drops when you put the phone away, let Aproid run in the background in your phone's battery settings.

If KDE Connect is open on the same device it may hold the same network port. Aproid moves to the next free one, but finding devices works best with KDE Connect closed.

## For developers

Aproid is three native apps sharing one protocol.

| Folder | What's inside |
| --- | --- |
| `android/protocol` | The protocol in plain Kotlin: packets, identity, pairing, discovery. |
| `android/app` | The Android app (Kotlin, Jetpack Compose). |
| `macos/Sources/AproidKit` | The protocol in Swift. |
| `macos/Sources/Aproid` | The Mac menu bar app (SwiftUI). |
| `windows/src/Aproid.Core` | The protocol in C#. |
| `windows/src/Aproid` | The Windows tray app (WinUI 3). |
| `web` | The website (Next.js). |
| `branding` | The logo and the scripts that generate every app icon. |
| `docs` | [Architecture](docs/ARCHITECTURE.md) and [roadmap](docs/ROADMAP.md). |

**Android** (JDK 17 and the Android SDK):

```sh
cd android
./gradlew :protocol:test        # protocol tests, no Android SDK needed
./gradlew :app:installDebug     # build and install on a connected phone
```

**Mac** (Xcode 15 or later):

```sh
cd macos
swift test
./scripts/bundle.sh             # builds macos/build/Aproid.app
open build/Aproid.app
```

Run it as a bundle. Without one, macOS won't show notifications or the Share menu entry.

**Windows** (.NET 8 SDK, and Windows for the app itself):

```sh
cd windows
dotnet test tests/Aproid.Core.Tests    # runs on any OS
```

See [windows/README.md](windows/README.md) for building the app and the installer.

**Website** (Node 20 or later):

```sh
cd web
npm install
npm run dev
```

### Releasing

Push a version tag such as `1.2.3` and `.github/workflows/release.yml` builds and publishes all three apps in one release. Use `android-1.2.3`, `macos-1.2.3` or `windows-1.2.3` to release a single app. The signing secrets each app needs are listed at the top of the workflow.

## License

MIT. See [LICENSE](LICENSE).
