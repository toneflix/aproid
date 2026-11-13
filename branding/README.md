# Branding

`flyylink-logo.svg` is the source logo. Everything else here, and the app icons in both apps, is built from it:

```sh
python3 branding/generate.py
```

It needs Pillow and Node with Playwright. It writes:

- `flyylink-mark.svg`: the mark alone in a square, for docs and the web.
- `app-icon.svg` and `macos/Bundle/AppIcon.icns`: the Mac app icon (also used by the Share extension).
- `play-store-icon.png`: the 512px Play Store icon.
- `macos/Sources/FlyyLink/FlyyLinkMark.swift`: the mark as a SwiftUI shape, used in the menu bar, the panel header and the Share sheet.
- `windows/src/FlyyLink/Assets/FlyyLink.ico`, `FlyyLink.png` and `Tray.ico`: the Windows app, notification and tray icons.
- `windows/src/FlyyLink/Icons/FlyyLinkMark.cs`: the mark as XAML path data, used in the Windows panel header.
- `android/app/src/main/res/drawable/ic_launcher_*.xml`: the adaptive launcher icon layers, including the themed (monochrome) one.
- `android/app/src/main/res/drawable/ic_flyylink_logo.xml` and `ic_stat_flyylink.xml`: the in-app logo and the notification icon.

## Icons

Both apps use [Lucide](https://lucide.dev) icons (ISC, see `LUCIDE-LICENSE.txt`). `python3 branding/lucide.py` fetches them with npm and writes:

- `macos/Sources/FlyyLink/Lucide.swift`: the Mac icons as paths, drawn with `Image(lucide:size:weight:)`.
- `android/app/src/main/res/drawable/lucide_*.xml`: the Android icons as vector drawables.
- `windows/src/FlyyLink/Icons/Lucide.cs`: the Windows icons as XAML path data, drawn with `LucideIcon`.

To add an icon, put its Lucide name in the `MAC`, `ANDROID` or `WINDOWS` list in that script and run it again.
