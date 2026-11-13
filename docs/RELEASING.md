# Releasing

Push a tag like `1.2.3` to release all three apps, or `android-1.2.3`, `macos-1.2.3` or `windows-1.2.3` for one. Tags have no `v` prefix. Nothing is published unless every app in the release builds.

| App | Files |
| --- | --- |
| Android | `FlyyLink-1.2.3.apk` and the Play Store bundle `.aab` |
| Mac | `FlyyLink-1.2.3.dmg`, signed and notarized, and its update `.zip` |
| Windows | `FlyyLink-Setup-1.2.3.exe` |

The Android build number is the base in `version.json` plus the workflow's run number.

## Where files go

Every file is uploaded to the `aproid-releases` R2 bucket. The website serves it at `/download/<platform>` and `/releases/<file>`, and serves the update feeds: `/updates/mac/appcast.xml` for the Mac and `/updates/windows.json` for Windows, which installed copies check twice a day.

The Windows installer isn't signed, so on first install Windows SmartScreen asks: pick "More info", then "Run anyway".

## Secrets and variables

Set these under GitHub > Settings > Secrets and variables > Actions. `.github/workflows/release.yml` lists them too.

| App | Secrets | Variables |
| --- | --- | --- |
| Android | `ANDROID_KEYSTORE` (base64 `.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` if the key has its own | |
| Mac | `MACOS_CERT_P12` (base64 Developer ID Application `.p12`), `MACOS_CERT_PASSWORD`, `NOTARY_KEY` (`.p8` contents), `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `SPARKLE_PRIVATE_KEY` | `SPARKLE_PUBLIC_KEY` |
| Mac and Windows | | `LICENCE_PUBLIC_KEY` |
| Website upload | `CLOUDFLARE_API_TOKEN` (Workers R2 Storage edit), `CLOUDFLARE_ACCOUNT_ID` | |

Without the Sparkle key and variable, the Mac release works but can't auto-update. Without `LICENCE_PUBLIC_KEY`, the Mac and Windows builds skip the licence check, as local builds do. See [LICENCES.md](LICENCES.md).
