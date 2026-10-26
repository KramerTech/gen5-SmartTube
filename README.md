# SmartTube for Gen5W head units

[SmartTube](https://github.com/yuliskov/SmartTube), patched to run on Hyundai/Kia/Genesis Gen5W head units (Android 4.4.2, Telechips), as a [NEMESIS](https://github.com/xwtk/hmg_nemesis) package.

> **Install [gen5-codec-patch](https://github.com/KramerTech/gen5-codec-patch) first.** This package depends on its `media.codecs` package, version 2.0 or newer. Without it, SmartTube's player can't query the unit's video decoders and nothing plays. The install checks for it and refuses to proceed if it's missing.

## What's patched

The official armeabi-v7a APK, with five changes ([`tools/patch.py`](tools/patch.py)):

| Change | Why |
|---|---|
| Adds the `GET_TASKS` permission | Hyundai's ActivityManager checks it in `Activity.finish()`. Without it the app dies on the splash screen with `SecurityException: getTasks() requires android.permission.GET_TASKS`. |
| `NetworkData.isConscryptEnabled()` returns `true` | KitKat's system OpenSSL crashes (`SIGSEGV` in `ssl_parse_serverhello_tlsext`), and there are no Play Services to supply a newer TLS stack. This sends all HTTPS through the Conscrypt that SmartTube already bundles. |
| `update_urls` points at this project's releases | The in-app update check would otherwise offer upstream's APK, which isn't patched and is signed with a different key. With `UPDATE_REPO` empty in `smarttube.conf`, the list is empty and the check is off. |
| `versionCode` becomes upstream × 100 + revision | Each revision of ours is an update over the previous one, and over upstream's build of the same version. |
| Swiping in from the left edge goes Back | Gen5W has no Back button for third-party apps, and SmartTube is a TV app. SmartTube already has this gesture (Slidr) but only enables it on Android 5+. Lowering that gate to 4.4 turns it on. |

The result is re-signed with this project's key. Each patch fails the build if a future SmartTube changes the code it targets.

## The dependency on media.codecs

NEMESIS has no dependency mechanism, so this package handles it itself, without touching `media.codecs`:

- **Install:** `pre.sh` refuses unless `/data/nemesis/apps/media.codecs` is installed at version `CODECS_MIN_VERSION` or newer, and a toast explains what's missing.
- **If media.codecs is removed later:** the `depwatch` service checks every 30 s. If the dependency is missing (or too old) in two checks in a row, it stops SmartTube and disables it with `pm disable`, and a toast explains why. Two checks are required so that an `--update` of media.codecs doesn't trigger it. Disabling keeps SmartTube's data and sign-in. SmartTube is enabled again as soon as media.codecs is back.
- **Only reverses its own action:** depwatch re-enables SmartTube only if depwatch was what disabled it (it keeps a marker in `/data/nemesis/backup/smarttube/`). If you disabled the app yourself, it's left alone.
- **Uninstalling this package** re-enables the app first if depwatch had disabled it, then NEMESIS removes it. Nothing is left behind.

Log: `/data/nemesis/smarttube.log`, plus `nemesis log service smarttube/depwatch`.

## Install

1. Install `media.codecs` 2.0+ from [gen5-codec-patch releases](https://github.com/KramerTech/gen5-codec-patch/releases) first.
2. Then install `smarttube-<version>.zip` by USB (`type=install`), or over ADB:
   ```sh
   adb push smarttube-32.68-gen5w.2.zip /data/local/tmp/
   adb shell '/system/xbin/nemesis install --update /data/local/tmp/smarttube-32.68-gen5w.2.zip'
   ```

Launch it from NEMESIS Manager → Packages → SmartTube, or from any launcher.

If the app was installed before with a different signing key (an upstream APK, or someone else's build), NEMESIS has to uninstall it first, which wipes SmartTube's settings and sign-in.

## Build a release

```sh
APK=$(tools/fetch-upstream.sh)        # latest upstream release; or: tools/fetch-upstream.sh 32.68s
./build.sh "$APK" 1 [notes.txt]       # revision 1-99 for this upstream version
tests/run.sh                          # dependency logic, in a sandbox
```

`fetch-upstream.sh` downloads the stable armeabi-v7a APK from upstream's GitHub release and verifies it against the SHA-256 digest GitHub records for that asset.

`build.sh` patches, signs and checks the result: the signature verifies for API 19, `versionCode`, `GET_TASKS`, and the `update_urls` value actually inside the built APK. It writes these to `dist/`:

| File | |
|---|---|
| `smarttube-<ver>-gen5w.<rev>.zip` | the NEMESIS package |
| `smarttube-gen5w-armeabi-v7a.apk` | the patched APK (a fixed name, for the update check's download link) |
| `smarttube-gen5w.json` | the update manifest in upstream's format (only when `UPDATE_REPO` is set) |
| `SHA256SUMS` | checksums |

Needs: python3, Java, [apktool](https://apktool.org) 2.9+, and the Android build-tools (`aapt`, `zipalign`, `apksigner`).

### Signing

`build.sh` uses `$SMARTTUBE_KEYSTORE` (default `../smarttube-signing/smarttube.jks`), alias `$SMARTTUBE_KEY_ALIAS` (default `smarttube`), and the password in `pass.txt` next to the keystore. Every release must use the same key. A different key makes updates fail, and NEMESIS then reinstalls from scratch, which wipes everyone's SmartTube data. Back the key up, and keep it out of the repo.

### The update check

`smarttube.conf` points it at this repo (`UPDATE_REPO="KramerTech/gen5-SmartTube"`). Forks should change it, or leave it empty to turn the check off.

Every GitHub release has to attach `smarttube-gen5w.json` and `smarttube-gen5w-armeabi-v7a.apk`, under exactly those names. The app checks `https://github.com/<repo>/releases/latest/download/smarttube-gen5w.json`. To test against another repo without editing the file, use `SMARTTUBE_CONF=other.conf ./build.sh …`.

The check can tell you about a new version. Installing it from inside the app probably won't work, though: Gen5W's package installer rejects signers that aren't on Hyundai's allowlist, and NEMESIS gets around that only for its own installs. Install updates as NEMESIS packages.

## License

The patch tooling, scripts and tests in this repo are MIT-licensed ([`LICENSE`](LICENSE)). SmartTube itself is MIT-licensed by its author (`notices/SmartTube-LICENSE.txt`). The package ships that license and `notices/NOTICE.txt`, which lists the modifications.
