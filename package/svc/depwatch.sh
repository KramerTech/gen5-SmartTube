#!/system/bin/sh
# NEMESIS service: keep SmartTube in step with its dependency.
# If media.codecs disappears (uninstalled, or replaced by a too-old version)
# for two checks in a row, SmartTube is stopped and disabled, keeping its data,
# so it can't be opened into a player that can't decode video. When media.codecs
# is back, SmartTube is enabled again. media.codecs itself is never touched.
# Two misses (about a minute) ride out a `nemesis install --update` of media.codecs.
cd /data/nemesis/apps/smarttube || exit 1
PKGDIR=$PWD
. ./scripts/common.sh

load_android_env || log "WARN: no framework environment; pm/am may fail"
while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 5; done

# Overridable for tests: seconds between checks, and how many checks (0 = forever).
INTERVAL=${DEPWATCH_INTERVAL:-30}
MAX_CHECKS=${DEPWATCH_MAX_CHECKS:-0}
checks=0
misses=0
while [ "$MAX_CHECKS" = 0 ] || [ $checks -lt "$MAX_CHECKS" ]; do
    checks=$((checks + 1))
    if dep_ok; then
        misses=0
        [ -f "$MARK" ] && enable_app && toast "SmartTube is back on: the $DEP_NAME package is installed again."
    else
        misses=$((misses + 1))
        if [ $misses -ge 2 ] && [ ! -f "$MARK" ] && app_installed && ! app_disabled; then
            disable_app
        fi
    fi
    sleep $INTERVAL
done
