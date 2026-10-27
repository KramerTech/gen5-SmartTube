# SmartTube for Gen5W head units

[SmartTube](https://github.com/yuliskov/SmartTube), patched to run on Hyundai/Kia/Genesis Gen5W head units (Android 4.4.2, Telechips), as a [NEMESIS](https://github.com/xwtk/hmg_nemesis) package.

> **Install [gen5-codec-patch](https://github.com/KramerTech/gen5-codec-patch) first.** This package depends on its `media.codecs` package, version 2.0 or newer. Without it, SmartTube's player can't query the unit's video decoders and nothing plays. The install checks for it and refuses to proceed if it's missing.

## What's different from upstream SmartTube

- **It runs on Gen5W.** Upstream's APK crashes on the splash screen and can't load anything on these units. This build fixes both.
- **Swipe in from the left edge of the screen to go back,** including out of the video player. Gen5W has no Back button for apps like this one.
- **It only works in park.** Outside park, SmartTube shows the head unit's standard "not available while driving" message and closes, the same way the unit's own apps lock down. If it's playing when you shift out of park, it stops and closes.

## Install

1. Install `media.codecs` 2.0+ from [gen5-codec-patch releases](https://github.com/KramerTech/gen5-codec-patch/releases) first.
2. Download SmartTube from [releases](https://github.com/KramerTech/gen5-SmartTube/releases). Each release has two zips:
   - **USB:** extract `smarttube-<version>-usb.zip` onto the root of a FAT32 or exFAT drive, so the drive holds `NEMESIS.data` and `packages/smarttube.zip`. Keep only one NEMESIS package on the drive. With the head unit fully booted, plug the drive in and confirm the install prompt.
   - **ADB:** use `smarttube-<version>.zip`, the package itself. Don't extract this one onto a USB drive: NEMESIS will report "Invalid package descriptor".
     ```sh
     adb push smarttube-<version>.zip /data/local/tmp/
     adb shell '/system/xbin/nemesis install --update /data/local/tmp/smarttube-<version>.zip'
     ```

Launch it from NEMESIS Manager → Packages → SmartTube, or from any launcher.

**Updating:** install the new release the same way. Over ADB with `--update`, your SmartTube settings and sign-in are kept. Over USB, NEMESIS asks you to uninstall the old version first, which resets them. SmartTube may tell you when a new version is out, but install it as a NEMESIS package; updating from inside the app won't work on Gen5W.

If SmartTube was installed before from somewhere else (an upstream APK, or someone else's build), NEMESIS has to uninstall it first, which also resets its settings and sign-in.

## If media.codecs is removed

SmartTube can't play anything without `media.codecs`, so this package keeps an eye on it:

- If `media.codecs` is uninstalled (or downgraded below 2.0), SmartTube is turned off within a minute and a message explains why. Its settings and sign-in are kept.
- SmartTube turns back on by itself as soon as `media.codecs` is reinstalled. If you turned SmartTube off yourself, it's left off.
- Uninstalling this package removes SmartTube completely.

Troubleshooting log: `/data/nemesis/smarttube.log`.

## License

The patch tooling, scripts and tests in this repo are MIT-licensed ([`LICENSE`](LICENSE)). SmartTube itself is MIT-licensed by its author (`notices/SmartTube-LICENSE.txt`). The package ships that license and `notices/NOTICE.txt`, which lists the modifications.
