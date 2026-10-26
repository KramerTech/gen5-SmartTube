#!/system/bin/sh
# The APK is installed by now. If depwatch had turned the app off (the codec
# fix went missing), the dependency is back, since pre.sh checked it.
. ./scripts/common.sh
log "postinstall $ID $APP_PKG"
app_installed || { log "FAIL: $APP_PKG is not installed"; exit 1; }
enable_app
log "postinstall ok"
exit 0
