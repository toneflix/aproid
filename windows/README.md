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

CI publishes a self-contained build as the `Aproid-windows-x64` artifact: unzip it and run `Aproid.exe`.

On first launch Windows Firewall asks whether Aproid may use the network. Allow it on private networks, or the phone can't find this PC.

## What works

Pairing with the verification code, phone notifications with replies, shared clipboard (text, pictures and files), sending and receiving files with resume, links and text, battery level, and ringing the phone with its location on a map.

Texts in the Messages window, calls with a banner to answer, mute and hang up, media controls for what the phone plays, the phone's photos in the Photos window, and several paired phones with a card carousel.

Right-click files in Explorer and pick "Send to phone" (on Windows 11 it's under "Show more options"). To call `tel:` links from your phone, pick Aproid for TEL in Settings > Apps > Default apps.

Phone notifications need Windows notifications turned on for Aproid.
