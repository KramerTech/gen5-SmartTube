# SmartTube for Gen5W head units

[SmartTube](https://github.com/yuliskov/SmartTube), patched to run on Hyundai/Kia/Genesis Gen5W head units (Android 4.4.2, Telechips), as a [NEMESIS](https://github.com/xwtk/hmg_nemesis) package.

> **Install [gen5-codec-patch](https://github.com/KramerTech/gen5-codec-patch) first.** This package depends on its `media.codecs` package, version 2.1 or newer, which is required for on-device video playback: without it, SmartTube's player can't query the unit's video decoders and nothing plays. NEMESIS 1.16 or newer checks for it and warns before installing SmartTube without it.

## What's different from upstream SmartTube

- **It runs on Gen5W.** Upstream's APK crashes on the splash screen and can't load anything on these units. This build fixes both.
- **Swipe in from the left edge of the screen to go back,** including out of the video player. Gen5W has no Back button for apps like this one.
- **It only uses Wi-Fi, never the car's built-in BlueLink modem.** Connect the head unit to Wi-Fi, such as your phone's hotspot. Android Auto internet sharing is not yet verified for this app. A one-time notice explains this in SmartTube. The NEMESIS package installs a root background service that restricts this app's IPv4/IPv6 connections and its Android 4.4 DNS resolver to `wlan0`. Other apps and the modem's own services are left alone. Install the complete package; an APK alone cannot supply the guard. SmartTube's API and video HTTP paths wait for fresh guard state before connecting. Service log: `/data/nemesis/logs/smarttube/netguard.log`.
- **Going Back from video keeps you in SmartTube without handing audio back to the radio.** Focus is retained across the player-to-browse transition and released when you leave SmartTube. Existing swipe navigation remains unchanged.
- **It only works in park.** Outside park, SmartTube shows the head unit's standard "not available while driving" message and closes, the same way the unit's own apps lock down. If it's playing when you shift out of park, it stops and closes.

## Install

You need NEMESIS 1.16 or newer.

1. Install `media.codecs` 2.1+ from [gen5-codec-patch releases](https://github.com/KramerTech/gen5-codec-patch/releases) first. If you have an older version, update it first; older versions don't tell NEMESIS their version, so SmartTube shows as incompatible until you do. (An older SmartTube may say it was turned off in between; installing this one turns it back on.)
2. Download SmartTube from [releases](https://github.com/KramerTech/gen5-SmartTube/releases). Each release has two zips:
   - **USB:** extract `smarttube-<version>-usb.zip` onto the root of a FAT32 or exFAT drive, so the drive holds `NEMESIS.data` and `packages/smarttube.zip`. Keep only one NEMESIS package on the drive. With the head unit fully booted, plug the drive in and confirm the install prompt.
   - **ADB:** use `smarttube-<version>.zip`, the package itself. Don't extract this one onto a USB drive: NEMESIS will report "Invalid package descriptor".
     ```sh
     adb push smarttube-<version>.zip /data/local/tmp/
     adb shell '/system/xbin/nemesis install --update /data/local/tmp/smarttube-<version>.zip'
     ```

Launch it from NEMESIS Manager → My Packages → SmartTube, or from any launcher.

**Updating:** install the new release the same way. Over ADB with `--update`, your SmartTube settings and sign-in are kept. Over USB, NEMESIS asks you to uninstall the old version first, which resets them. SmartTube may tell you when a new version is out, but install it as a NEMESIS package; updating from inside the app won't work on Gen5W.

If SmartTube was installed before from somewhere else (an upstream APK, or someone else's build), NEMESIS has to uninstall it first, which also resets its settings and sign-in.

## Uninstalling

Manager → My Packages → SmartTube → Uninstall, or `nemesis uninstall smarttube`. This removes SmartTube completely. NEMESIS won't uninstall `media.codecs` while SmartTube is installed, so uninstall SmartTube first if you want to remove both.

## Building and checking the patch

`build.sh` continues to patch the official upstream APK; it does not build a SmartTube fork from source. All changes, including the small Java helper, are applied automatically for each upstream build. Hooks fail the build if the expected upstream methods change.

In addition to the existing tools, install a JDK, Android `platforms;android-30`, and build-tools with `d8`. Set `APKTOOL_JAR` to the apktool **2.12.0** jar (or put `apktool.jar` beside the `APKTOOL` wrapper). `ANDROID_JAR` can override the compile platform. Helpers use API 19 methods and are compiled to API 19 dex. The release workflow installs these dependencies automatically and keeps the existing signing/update process.

Run host regression checks with `python3 -m unittest discover -s tests -v`. These exercise foreground audio handoff and network-state validation. An APK build and host checks do not establish real head-unit playback, popup behavior, or Wi-Fi performance; those require testing on Gen5W hardware.

Current local results and remaining hardware checks: [`tests/VALIDATION.md`](tests/VALIDATION.md).

Uninstall/update cleanup now stops SmartTube before removing its private rules and DNS mapping. Cleanup requires `CAP_NET_ADMIN`; it reports failure instead of silently leaving a reused UID blocked. If an ADB NEMESIS session lacks that capability, use NEMESIS Manager on the head unit for that operation.

The DNS guard adapts the MIT-licensed [Jellyfin on GEN5W](https://github.com/ntwm787/Jellyfin-on-GEN5W) implementation, using separate SmartTube routing/firewall identifiers. On Android 4.4, DNS runs through a shared system resolver: filtering only SmartTube's socket UID does not route those DNS requests to Wi-Fi. The service assigns SmartTube its own resolver mapping and packet mark, then filters those DNS packets too. It does not bind or disable the modem globally.

## License

The patch tooling and scripts in this repo are MIT-licensed ([`LICENSE`](LICENSE)). SmartTube itself is MIT-licensed by its author (`notices/SmartTube-LICENSE.txt`). The package ships that license and `notices/NOTICE.txt`, which lists the modifications.
