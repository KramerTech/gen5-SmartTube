#!/bin/bash
# Build a Gen5W SmartTube release from an official upstream APK.
#
# usage: ./build.sh <SmartTube_stable_X_armeabi-v7a.apk> <revision 1-99> [release notes file]
#        ./build.sh "$(tools/fetch-upstream.sh)" 1
#
# Outputs in dist/:
#   smarttube-<ver>-gen5w.<rev>.zip   NEMESIS package (needs media.codecs installed)
#   $APK_ASSET                        the patched, signed APK
#   $MANIFEST_ASSET                   in-app update manifest (only if UPDATE_REPO is set)
#   SHA256SUMS
#
# Needs: python3, apktool (2.9+), Java, and Android build-tools (aapt, zipalign,
# apksigner) under $ANDROID_HOME (default ~/Library/Android/sdk).
# Settings: smarttube.conf, then $SMARTTUBE_CONF if set.
# Signing: $SMARTTUBE_KEYSTORE (default ../smarttube-signing/smarttube.jks),
# alias $SMARTTUBE_KEY_ALIAS (default smarttube), password in pass.txt beside
# the keystore. Every release must use the same key, or installs over an
# older one fail and NEMESIS reinstalls (wiping SmartTube's data and sign-in).
set -euo pipefail

SRC_APK=${1:?usage: build.sh <upstream apk> <revision> [notes file]}
REV=${2:?usage: build.sh <upstream apk> <revision> [notes file]}
NOTES=${3:-}

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/smarttube.conf"
# Optional overrides (e.g. CI, or a test build pointed at another repo).
[ -n "${SMARTTUBE_CONF:-}" ] && . "$SMARTTUBE_CONF"
ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
BT=$(ls -d "$ANDROID_HOME"/build-tools/* 2>/dev/null | tail -1)
APKTOOL=${APKTOOL:-$(command -v apktool || echo "$HOME/.local/bin/apktool")}
KEYSTORE=${SMARTTUBE_KEYSTORE:-$HERE/../smarttube-signing/smarttube.jks}
KEY_ALIAS=${SMARTTUBE_KEY_ALIAS:-smarttube}
KEYPASS=$(dirname "$KEYSTORE")/pass.txt
DIST=$HERE/dist

die() { echo "build: $*" >&2; exit 1; }
[[ $REV =~ ^[0-9]+$ ]] && [ "$REV" -ge 1 ] && [ "$REV" -le 99 ] || die "revision must be 1-99"
[ -f "$SRC_APK" ] || die "no such APK: $SRC_APK"
[ -x "$BT/aapt" ] && [ -x "$BT/zipalign" ] && [ -x "$BT/apksigner" ] || die "Android build-tools not found under $ANDROID_HOME"
[ -x "$APKTOOL" ] || die "apktool not found (set APKTOOL)"
[ -f "$KEYSTORE" ] && [ -f "$KEYPASS" ] || die "keystore or pass.txt not found: $KEYSTORE"

# Upstream identity
badging=$("$BT/aapt" dump badging "$SRC_APK")
pkg=$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<< "$badging")
up_code=$(sed -n "s/^package: .*versionCode='\([0-9]*\)'.*/\1/p" <<< "$badging")
up_name=$(sed -n "s/^package: .*versionName='\([^']*\)'.*/\1/p" <<< "$badging")
[ "$pkg" = org.smarttube.stable ] || die "not SmartTube stable: $pkg"
grep -q "^native-code: .*'armeabi-v7a'" <<< "$badging" || die "not an armeabi-v7a build"
code=$((up_code * 100 + REV))
label=$up_name-gen5w.$REV
url=
[ -n "$UPDATE_REPO" ] && url="https://github.com/$UPDATE_REPO/releases/latest/download/$MANIFEST_ASSET"
echo "SmartTube $up_name ($up_code) -> $label, versionCode $code"
[ -n "$url" ] || echo "note: UPDATE_REPO is empty in smarttube.conf - the in-app update check will be off"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Patch
"$APKTOOL" d -f -o "$work/src" "$SRC_APK" >/dev/null
python3 -I "$HERE/tools/patch.py" "$work/src" "$code" "$url"
"$APKTOOL" b -o "$work/unsigned.apk" "$work/src" >/dev/null
"$BT/zipalign" -f -p 4 "$work/unsigned.apk" "$work/aligned.apk"
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-key-alias "$KEY_ALIAS" --ks-pass "file:$KEYPASS" \
    --min-sdk-version 19 --out "$work/SmartTube.apk" "$work/aligned.apk" 2>/dev/null
rm -f "$work/SmartTube.apk.idsig"

# Check the result, not just that the patch script ran
"$BT/apksigner" verify --min-sdk-version 19 "$work/SmartTube.apk" >/dev/null 2>&1 || die "signature doesn't verify for API 19"
out_badging=$("$BT/aapt" dump badging "$work/SmartTube.apk")
grep -q "versionCode='$code'" <<< "$out_badging" || die "versionCode not $code"
grep -q "uses-permission: name='android.permission.GET_TASKS'" <<< "$out_badging" || die "GET_TASKS missing"
urls=$("$BT/aapt" dump --values resources "$work/SmartTube.apk" | python3 -I "$HERE/tools/resource_array.py" update_urls) \
    || die "update_urls missing from the built APK"
[ "$urls" = "$url" ] || die "update_urls is '$urls', expected '$url'"

# Package
stage=$work/package
cp -R "$HERE/package" "$stage"
mkdir -p "$stage/app" "$stage/notices"
cp "$work/SmartTube.apk" "$stage/app/SmartTube.apk"
printf 'CODECS_MIN_VERSION="%s"\n' "$CODECS_MIN_VERSION" > "$stage/scripts/dep.conf"
cp "$HERE"/notices/* "$stage/notices/"
python3 -I - "$stage/NEMESIS.data" "$label" <<'EOF'
import sys
p, v = sys.argv[1], sys.argv[2]
s = open(p).read()
assert "@VERSION@" in s
open(p, "w").write(s.replace("@VERSION@", v))
EOF

rm -rf "$DIST" && mkdir -p "$DIST"
zipname=smarttube-$label.zip
python3 -I - "$stage" "$DIST/$zipname" <<'EOF'
import sys, zipfile
from pathlib import Path
src, out = Path(sys.argv[1]), Path(sys.argv[2])
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for p in sorted(src.rglob("*")):
        if p.is_file() and not p.name.startswith((".", "._")):
            z.write(p, p.relative_to(src).as_posix())
EOF
cp "$work/SmartTube.apk" "$DIST/$APK_ASSET"

if [ -n "$url" ]; then
    python3 -I - "$DIST/$MANIFEST_ASSET" "$up_name" "$code" "$REV" "https://github.com/$UPDATE_REPO/releases/latest/download/$APK_ASSET" "$NOTES" <<'EOF'
import json, sys
out, name, code, rev, apk_url, notes = sys.argv[1:7]
changelog = [l.strip() for l in open(notes)] if notes else []
changelog = [l for l in changelog if l] or [f"SmartTube {name} for Gen5W head units (build {rev})"]
# Same shape as upstream's smarttube_stable2.json.
manifest = {"package": {"downloadUrlList": [apk_url]}, name: {"versionCode": int(code), "changelog": changelog}}
json.dump(manifest, open(out, "w"), indent=2)
EOF
fi

(cd "$DIST" && shasum -a 256 * > SHA256SUMS)
echo "built:"
ls -l "$DIST" | tail -n +2
