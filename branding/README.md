# Branding

`aproid-logo.svg` is the source logo. Everything else here, and the app icons in both apps, is built from it:

```sh
python3 branding/generate.py
```

It needs Pillow and Node with Playwright. It writes:

- `aproid-mark.svg`: the mark alone in a square, for docs and the web.
- `app-icon.svg` and `macos/Bundle/AppIcon.icns`: the Mac app icon (also used by the Share extension).
- `play-store-icon.png`: the 512px Play Store icon.
- `macos/Sources/Aproid/AproidMark.swift`: the mark as a SwiftUI shape, used in the menu bar, the panel header and the Share sheet.
- `android/app/src/main/res/drawable/ic_launcher_*.xml`: the adaptive launcher icon layers, including the themed (monochrome) one.
- `android/app/src/main/res/drawable/ic_aproid_logo.xml` and `ic_stat_aproid.xml`: the in-app logo and the notification icon.
