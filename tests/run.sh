#!/bin/bash
# Tests for the package's dependency handling: the install check for
# media.codecs and the depwatch service that turns SmartTube off/on when
# media.codecs goes away/comes back. Runs the real scripts in a sandbox with
# a fake pm/am/getprop; no car or APK needed.
# Hooks run under mksh (Android's shell) if installed, else zsh in sh emulation.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if command -v mksh >/dev/null; then SH=(mksh); else SH=(zsh --emulate sh); fi
echo "scripts run with: ${SH[*]}"

failures=0
check() { if "${@:2}"; then echo "  ok   $1"; else echo "  FAIL $1"; failures=$((failures + 1)); fi; }
not() { ! "$@"; }

# setup <name>: sandbox with SmartTube installed and enabled, no media.codecs.
setup() {
    local root=$WORK/$1
    mkdir -p "$root/bin" "$root/data/nemesis/apps"
    printf 'installed\n' > "$root/pmstate"
    cat > "$root/bin/pm" <<EOF
#!/bin/sh
st=$root/pmstate
case "\$1 \$2" in
    "path org.smarttube.stable") grep -q installed "\$st" && echo "package:/data/app/org.smarttube.stable-1.apk" ;;
    "list packages") [ "\$3" = -d ] && grep -q disabled "\$st" && echo "package:org.smarttube.stable" ;;
    "disable org.smarttube.stable") grep -q installed "\$st" && { grep -q disabled "\$st" || echo disabled >> "\$st"; echo "Package org.smarttube.stable new state: disabled"; } ;;
    "enable org.smarttube.stable") grep -v disabled "\$st" > "\$st.n"; mv "\$st.n" "\$st"; echo "Package org.smarttube.stable new state: enabled" ;;
esac
echo "pm \$*" >> $root/calls
exit 0
EOF
    cat > "$root/bin/am" <<EOF
#!/bin/sh
echo "am \$*" >> $root/calls
EOF
    cat > "$root/bin/getprop" <<'EOF'
#!/bin/sh
case "$1" in sys.boot_completed) echo 1 ;; ro.build.version.sdk) echo 19 ;; *) echo test ;; esac
EOF
    chmod +x "$root"/bin/*
    echo "export BOOTCLASSPATH=/system/framework/core.jar" > "$root/init.environ.rc"

    local pkg=$root/data/nemesis/apps/smarttube
    cp -R "$REPO/package" "$pkg"
    printf 'CODECS_MIN_VERSION="2.0"\n' > "$pkg/scripts/dep.conf"
    python3 -I - "$root" "$pkg" <<'EOF'
import sys
from pathlib import Path
root, pkg = sys.argv[1], Path(sys.argv[2])
for f in list(pkg.glob("scripts/*.sh")) + list(pkg.glob("svc/*.sh")):
    out = []
    for line in f.read_text().splitlines(keepends=True):
        if line.startswith("export PATH="):
            line = f"export PATH={root}/bin:/usr/bin:/bin\n"
        out.append(line.replace("/data/nemesis", f"{root}/data/nemesis").replace("/init.environ.rc", f"{root}/init.environ.rc"))
    f.write_text("".join(out))
EOF
    echo "$root"
}
codecs() {  # codecs <root> <version>|none
    rm -rf "$1/data/nemesis/apps/media.codecs"
    [ "$2" = none ] && return
    mkdir -p "$1/data/nemesis/apps/media.codecs"
    printf '[nemesis]\nversion=%s\nid=media.codecs\n' "$2" > "$1/data/nemesis/apps/media.codecs/NEMESIS.data"
}
hook() { (cd "$1/data/nemesis/apps/smarttube" && "${SH[@]}" "scripts/$2.sh") >> "$1/log" 2>&1; }
watch() { (export DEPWATCH_INTERVAL=0 DEPWATCH_MAX_CHECKS=$2; "${SH[@]}" "$1/data/nemesis/apps/smarttube/svc/depwatch.sh") >> "$1/log" 2>&1; }
disabled() { grep -q disabled "$1/pmstate"; }
marked() { [ -f "$1/data/nemesis/backup/smarttube/disabled-for-missing-codecs" ]; }
called() { grep -q -F -- "$2" "$1/calls" 2>/dev/null; }

echo "== version comparison"
R=$(setup v)
vge() { (cd "$R/data/nemesis/apps/smarttube" && "${SH[@]}" -c ". scripts/common.sh >/dev/null; version_ge '$1' '$2'"); }
check "2.0 >= 2.0" vge 2.0 2.0
check "2.1 >= 2.0" vge 2.1 2.0
check "10.0 >= 9.9" vge 10.0 9.9
check "2.0.1 >= 2.0" vge 2.0.1 2.0
check "1.1 < 2.0" not vge 1.1 2.0
check "1.99 < 2.0" not vge 1.99 2.0
check "garbage < 2.0" not vge abc 2.0

echo "== install needs media.codecs"
R=$(setup i1)
check "refused without media.codecs" not hook "$R" pre
check "toast explains" called "$R" "Video Codec Fix"
codecs "$R" 1.1
check "refused with media.codecs 1.1" not hook "$R" pre
codecs "$R" 2.0
check "accepted with media.codecs 2.0" hook "$R" pre
check "postinstall ok" hook "$R" post

echo "== depwatch: media.codecs present"
R=$(setup w1); codecs "$R" 2.0
watch "$R" 3
check "app left enabled" not disabled "$R"
check "no force-stop" not called "$R" "force-stop"

echo "== depwatch: media.codecs uninstalled"
R=$(setup w2); codecs "$R" none
watch "$R" 1
check "one miss: nothing yet (update in progress?)" not disabled "$R"
watch "$R" 2
check "two misses: app disabled" disabled "$R"
check "app force-stopped first" called "$R" "am force-stop org.smarttube.stable"
check "marker written" marked "$R"
check "user told why" called "$R" "no longer installed"
check "media.codecs not touched" [ ! -e "$R/data/nemesis/apps/media.codecs" ]
codecs "$R" 2.0
watch "$R" 1
check "media.codecs back: app re-enabled" not disabled "$R"
check "marker cleared" not marked "$R"

echo "== depwatch: media.codecs replaced by a too-old version"
R=$(setup w3); codecs "$R" 1.1
watch "$R" 2
check "app disabled" disabled "$R"

echo "== depwatch: app disabled by the user, not by us"
R=$(setup w4); codecs "$R" none
echo disabled >> "$R/pmstate"
watch "$R" 2
check "no marker (not ours)" not marked "$R"
codecs "$R" 2.0
watch "$R" 1
check "stays disabled (user's choice)" disabled "$R"

echo "== uninstall/update while disabled for missing codecs"
R=$(setup u1); codecs "$R" none
watch "$R" 2
hook "$R" preun
check "preuninstall re-enables" not disabled "$R"
check "no state left behind" [ ! -e "$R/data/nemesis/backup/smarttube" ]

echo "== reinstall clears an old marker"
R=$(setup u2); codecs "$R" none
watch "$R" 2
codecs "$R" 2.0
hook "$R" pre && hook "$R" post
check "postinstall re-enables" not disabled "$R"
check "marker cleared" not marked "$R"

echo
if [ $failures = 0 ]; then echo "all tests passed"; else echo "$failures test(s) failed"; exit 1; fi
