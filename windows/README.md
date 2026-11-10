# Aproid for Windows

A tray app that pairs with the Aproid Android app over the same protocol as the Mac app.

- `src/Aproid.Core`: the protocol in C# (.NET 8), mirroring `macos/Sources/AproidKit` and `android/protocol`. Builds and tests on any OS.
- `src/Aproid`: the WinUI 3 app. A tray icon opens a panel like the Mac menu bar panel.
- `tests/Aproid.Core.Tests`: the protocol tests, matching the Swift and Kotlin ones.

## Build and run

Needs Windows 10 1809 or later and the .NET 8 SDK.

```powershell
cd windows
dotnet test tests/Aproid.Core.Tests
dotnet run --project src/Aproid -r win-x64 -p:Platform=x64
```

CI publishes a self-contained build as the `Aproid-windows-x64` artifact (unzip it and run `Aproid.exe`) and the installer as `Aproid-windows-setup`.

## Releases

Push a tag like `1.2.3` (all apps) or `windows-1.2.3` and the release workflow publishes `Aproid-Setup-1.2.3.exe` on GitHub. Installed copies check those releases twice a day and offer to update. The installer isn't signed, so on first install Windows SmartScreen asks: pick "More info", then "Run anyway".

On first launch Windows Firewall asks whether Aproid may use the network. Allow it on private networks, or the phone can't find this PC.

## What works

Pairing with the verification code, phone notifications with replies, shared clipboard (text, pictures and files), sending and receiving files with resume, links and text, battery level, and ringing the phone with its location on a map.

Texts in the Messages window, calls with a banner to answer, mute and hang up, media controls for what the phone plays, the phone's photos in the Photos window, and several paired phones with a card carousel.

Mirror and control the phone's screen from the panel's Mirror tile. When the phone is off your Wi-Fi but in Bluetooth range, Aproid finds it over Bluetooth and can ask it to turn on its hotspot and join it. Windows only shares the Wi-Fi name with apps when location is allowed for apps, so turn that on if Aproid doesn't remember the hotspot.

Your phone's 2,000 most recent photos show in Explorer under `Phone Photos` in your user folder. They take no space until opened, when Aproid fetches the original from the phone. Turn it off in the panel's settings menu.

Win+Shift+A opens the panel from anywhere. Pin Aproid to the taskbar for jump list shortcuts to Messages, Photos, mirroring and ringing your phone.

Right-click files in Explorer and pick "Send to phone" (on Windows 11 it's under "Show more options"). To call `tel:` links from your phone, pick Aproid for TEL in Settings > Apps > Default apps.

Phone notifications need Windows notifications turned on for Aproid.
