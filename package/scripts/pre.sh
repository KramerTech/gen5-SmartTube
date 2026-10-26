#!/system/bin/sh
# Refuse to install without the codec fix SmartTube needs to play video.
. ./scripts/common.sh
# USB installs run from the usb-handler service, which may lack BOOTCLASSPATH.
load_android_env || log "WARN: no framework environment; pm/am may fail"
log "preinstall $ID"

if ! dep_ok; then
    _have=$(dep_version) || _have="not installed"
    log "FAIL: needs $DEP_ID $CODECS_MIN_VERSION or newer (found: $_have)"
    toast "SmartTube not installed: install the $DEP_NAME package ($DEP_ID $CODECS_MIN_VERSION or newer) first. Found: $_have."
    exit 1
fi
[ "$(getprop ro.build.version.sdk)" = 19 ] || { log "FAIL: needs Android 4.4 (API 19)"; toast "SmartTube not installed: this build is for Android 4.4 head units."; exit 1; }
log "preinstall ok: $DEP_ID $(dep_version)"
exit 0
