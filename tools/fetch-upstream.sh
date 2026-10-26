#!/bin/bash
# Download an official SmartTube armeabi-v7a APK and verify it against the
# SHA-256 digest GitHub records for the release asset.
# usage: tools/fetch-upstream.sh [tag]     (default: latest release)
# Prints the path of the verified APK (under .cache/upstream/).
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/smarttube.conf"
TAG=${1:-}
OUT=$HERE/.cache/upstream
mkdir -p "$OUT"

if [ -n "$TAG" ]; then api="https://api.github.com/repos/$UPSTREAM_REPO/releases/tags/$TAG"
else api="https://api.github.com/repos/$UPSTREAM_REPO/releases/latest"; fi

read -r name url digest < <(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "$api" | python3 -I -c '
import json, sys
r = json.load(sys.stdin)
assets = [a for a in r["assets"] if a["name"].endswith("_armeabi-v7a.apk") and "stable" in a["name"].lower()]
if len(assets) != 1:
    sys.exit("expected one stable armeabi-v7a asset in %s, found %d" % (r["tag_name"], len(assets)))
a = assets[0]
if not (a.get("digest") or "").startswith("sha256:"):
    sys.exit("release asset has no sha256 digest to check against")
print(a["name"], a["browser_download_url"], a["digest"][7:])
')

apk=$OUT/$name
if [ ! -f "$apk" ] || [ "$(shasum -a 256 "$apk" | cut -d' ' -f1)" != "$digest" ]; then
    echo "downloading $url" >&2
    curl -fL --progress-bar -o "$apk.part" "$url"
    mv "$apk.part" "$apk"
fi
got=$(shasum -a 256 "$apk" | cut -d' ' -f1)
[ "$got" = "$digest" ] || { echo "SHA-256 mismatch for $name: got $got, GitHub says $digest" >&2; rm -f "$apk"; exit 1; }
echo "verified $name (sha256 $digest)" >&2
echo "$apk"
