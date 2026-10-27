SmartTube @VERSION@, patched for Gen5W head units (Android 4.4), as a NEMESIS package.

**Install [gen5-codec-patch](https://github.com/KramerTech/gen5-codec-patch/releases) (`media.codecs` @CODECS_MIN_VERSION@+) first.** This package won't install without it, and it turns SmartTube off if the codec package is removed later.
@CHANGES@
What's different from upstream SmartTube (details in the README):
- Runs on Gen5W: upstream's APK crashes on the splash screen and can't load anything on these units.
- Swipe in from the left edge of the screen to go back, including out of the video player.
- Only works in park: outside park it shows the head unit's "not available while driving" message and closes.

Install over ADB with `nemesis install --update @ZIP@`, or by USB: extract `@USBZIP@` onto the root of a FAT32/exFAT drive and plug it in (a USB install over an existing SmartTube asks to uninstall it first, which resets its settings; use ADB to keep them). Check downloads against `SHA256SUMS`. If SmartTube was previously installed from another source with a different signing key, it gets reinstalled, which resets its settings and sign-in.

Built by GitHub Actions from upstream's [@UPSTREAM_TAG@](https://github.com/yuliskov/SmartTube/releases/tag/@UPSTREAM_TAG@) release (verified against GitHub's SHA-256 for the APK).
