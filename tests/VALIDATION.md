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

## Head-unit feedback (WiFi-Back-Test1, 2026-11-06)

- User confirms the slow connection issue is fixed on their head unit. This is
  an observed improvement, not an instrumented throughput/latency benchmark.
- The OEM media screen still appears on the first video play. Do not mark this
  issue resolved by the current audio-focus handoff patch.
- User had to uninstall before installing this test package. The local test key
  differs from the official signing key; this does not validate same-key updates.
- No sign-in code/QR was reported in a previous test. Whether that also occurs
  in WiFi-Back-Test1 is awaiting clarification; account sign-in is not validated.

Still unconfirmed: complete audio/Back behavior on hardware, same-key update
and uninstall cleanup, and Android Auto internet sharing. The emulator sign-in
experiment did not establish successful live authentication and is not evidence
of a sign-in fix. The PR remains a draft pending these checks.

Maintainer builds should use the existing signing key and the next downstream
revision. The local test signature cannot update an existing official install.
