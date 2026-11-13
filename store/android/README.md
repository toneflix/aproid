# Google Play graphics

The feature graphic and phone screenshots for the Play Store listing.

- `feature-graphic.png`: 1024 x 500.
- `screenshots/*.png`: 1080 x 1920 phone screenshots, in listing order.
- `tv/banner.png`: the 1280 x 720 Android TV banner.
- `tv/screenshots/*.png`: 1920 x 1080 Android TV screenshots, in listing order.

The run also writes the TV launcher banner inside the app, `android/app/src/main/res/drawable-xhdpi/tv_banner.png` (320 x 180).

They are drawn as HTML in `page/`: `app.js` and `app.css` rebuild the Android screens from the Compose code in `android/app` (same colors, sizes and strings), and `shots.js` sets the headline and screen for each image. `tv.js` and `tv.css` do the same for the TV screens in `ui/Tv.kt`. The logo, app icon and Lucide icons are read from `branding/` and `android/app/src/main/res/drawable`, so they follow any change there.

To regenerate, with Node and Playwright installed (as for `branding/generate.py`):

```sh
cd store/android
npm install
npm run generate
```

To change a headline or add a screenshot, edit the `SHOTS` list in `page/shots.js`. If the app's home screen changes, update `page/app.js` and `page/app.css` to match.

## Android TV on Google Play

The phone and TV apps are the same build. To offer it on TVs, in Play Console turn on the Android TV form factor (Test and release > Advanced settings > Form factors), then add `tv/banner.png` and the `tv/screenshots` to the store listing's Android TV section. Google reviews TV apps on their own, and the accessibility declaration should mention the "FlyyLink remote" use on TVs.

## Fire TV on the Amazon Appstore

Fire TV runs the same APK as the release. Upload it in the Amazon Developer Console, target Fire TV devices, and reuse `tv/banner.png` (1280 x 720) and the `tv/screenshots` (1920 x 1080). Many Fire TVs have no "Display over other apps" screen, so there pop-ups fall back to a plain toast and things that arrive wait in FlyyLink instead of opening on their own.
