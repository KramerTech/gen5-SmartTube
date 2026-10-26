SmartTube @VERSION@, patched for Gen5W head units (Android 4.4), as a NEMESIS package.

**Install [gen5-codec-patch](https://github.com/KramerTech/gen5-codec-patch/releases) (`media.codecs` @CODECS_MIN_VERSION@+) first.** This package won't install without it, and it turns SmartTube off if the codec package is removed later.
@CHANGES@
What's patched (details in the README):
- Swipe in from the left edge of the screen to go back. This is SmartTube's own gesture, which upstream only enables on Android 5+.
- Starts and loads on Gen5W: adds the `GET_TASKS` permission Hyundai's firmware requires, and uses SmartTube's bundled TLS (Conscrypt) instead of KitKat's, which crashes.
- The in-app update check points at this repo.

Install over ADB with `nemesis install --update @ZIP@`, or by USB: extract `@USBZIP@` onto the root of a FAT32/exFAT drive and plug it in (a USB install over an existing SmartTube asks to uninstall it first, which resets its settings; use ADB to keep them). Check downloads against `SHA256SUMS`. If SmartTube was previously installed from another source with a different signing key, it gets reinstalled, which resets its settings and sign-in.

Built by GitHub Actions from upstream's [@UPSTREAM_TAG@](https://github.com/yuliskov/SmartTube/releases/tag/@UPSTREAM_TAG@) release (verified against GitHub's SHA-256 for the APK).
