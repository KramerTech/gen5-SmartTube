#!/bin/bash
# Compile the small API-19 helper, not SmartTube itself. No checked-in binaries.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: compile-helper.sh <decoded apk> <build-tools directory>}
BT=${2:?build-tools directory required}
JAR=${APKTOOL_JAR:-$(dirname "$APKTOOL")/apktool.jar}
[ -f "$JAR" ] || { echo "Set APKTOOL_JAR to apktool 2.12.0's jar" >&2; exit 1; }
ANDROID_JAR=${ANDROID_JAR:-$ANDROID_HOME/platforms/android-30/android.jar}
[ -f "$ANDROID_JAR" ] || { echo "Install platforms;android-30 or set ANDROID_JAR" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/classes" "$TMP/dex"
javac -source 8 -target 8 -bootclasspath "$ANDROID_JAR" -d "$TMP/classes" "$HERE"/helper/org/gen5w/*.java
jar cf "$TMP/helper.jar" -C "$TMP/classes" .
"$BT/d8" --min-api 19 --lib "$ANDROID_JAR" --output "$TMP/dex" "$TMP/helper.jar"
javac -cp "$JAR" -d "$TMP/host" "$HERE/DisassembleHelper.java"
java -cp "$JAR:$TMP/host" DisassembleHelper "$TMP/dex/classes.dex" "$TMP/smali"
# A separate dex avoids overflowing upstream's nearly-full main dex. SmartTube
# installs MultiDex in Application.attachBaseContext before these hooks run.
N=2
while [ -d "$OUT/smali_classes$N" ]; do N=$((N+1)); done
cp -R "$TMP/smali" "$OUT/smali_classes$N"
