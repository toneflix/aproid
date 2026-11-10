# Google Play graphics

The feature graphic and phone screenshots for the Play Store listing.

- `feature-graphic.png`: 1024 x 500.
- `screenshots/*.png`: 1080 x 1920 phone screenshots, in listing order.

They are drawn as HTML in `page/`: `app.js` and `app.css` rebuild the Android screens from the Compose code in `android/app` (same colors, sizes and strings), and `shots.js` sets the headline and screen for each image. The logo, app icon and Lucide icons are read from `branding/` and `android/app/src/main/res/drawable`, so they follow any change there.

To regenerate, with Node and Playwright installed (as for `branding/generate.py`):

```sh
cd store/android
npm install
npm run generate
```

To change a headline or add a screenshot, edit the `SHOTS` list in `page/shots.js`. If the app's home screen changes, update `page/app.js` and `page/app.css` to match.
