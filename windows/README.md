# FlyyLink for Windows

A tray app that pairs with the FlyyLink Android app over the same protocol as the Mac app.

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

CI publishes a self-contained build as the `FlyyLink-windows-x64` artifact (unzip it and run `FlyyLink.exe`) and the installer as `FlyyLink-windows-setup`.

## More

- [docs/WINDOWS.md](../docs/WINDOWS.md): what the app does, shortcuts and command-line options.
- [docs/RELEASING.md](../docs/RELEASING.md): tags, the installer and updates.
- [docs/LICENCES.md](../docs/LICENCES.md): the licence check (`Aproid.Core/Licence.cs`, `Model/LicenceModel.cs`).
