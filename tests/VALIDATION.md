# Wi-Fi/audio patch validation

Validated locally on 2026-11-06 against the official SmartTube **32.71s** ARM APK
(versionName 32.71, versionCode 2461).

Input SHA-256:
`288e8caaa11417f6b64d2a7f906cead85c0b8a9bb5904753d7cb4f79d117d023`

- The full `build.sh` path completed: decode, patch, compile helper, dex,
  assemble, align, sign, verify API 19 signature and version/resources, package
  inner NEMESIS ZIP and outer USB installer, generate checksums.
- Used apktool 2.12.0, JDK 11 and disposable **test-only** signing credentials.
  The helper also compiled against the API 19 Android jar. This was a Windows
  Git Bash build with local wrappers for Windows Android tools and checksum/Python
  commands; the production Linux release job has not been executed here.
- `python3 -m unittest discover -s tests -v`: three test groups passed. Covers
  internal audio handoff, actual exit, stopped listeners, interruption, failed
  focus request, no automatic reacquisition, stale/wrong-UID/wrong-boot network
  state, malformed timestamps, and changed/duplicate smali hooks.
- Installed the test APK successfully on an owned **ARM API 19 emulator**.
- Real emulator netfilter/netd checks under SmartTube's installed UID passed:
  unapproved default-interface IPv4, IPv6 and DNS blocked; unrelated UID DNS
  stayed online; approved-interface simulation allowed IPv4 and DNS; repeated
  binding stayed ready; state file root-owned and read-only to the app; cleanup
  restored connectivity and preserved a pre-existing foreign resolver mapping.
  Both Jellyfin and SmartTube guards also ran together with stable IPv4/IPv6
  OUTPUT rules (no repeated jump growth).
  Approved-interface simulation uses `lab-eth0`, which refuses to run unless
  `ro.kernel.qemu=1`; production policy remains `wlan0` only.

**Not yet validated:** Gen5W playback/audio, real Wi-Fi throughput or latency,
the OEM media popup, NEMESIS install/update/uninstall on hardware, and Android
Auto internet sharing. This is a candidate for hardware testing, not a claim
that SmartTube has already been confirmed working in a car. The DNS change
addresses a routing gap; no speed improvement has been measured.

Maintainer builds should use the existing signing key and the next downstream
revision. The local test signature cannot update an existing official install.
