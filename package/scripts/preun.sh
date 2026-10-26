#!/system/bin/sh
# Runs on uninstall and before an update. If depwatch had disabled the app,
# enable it again and drop the marker: on uninstall NEMESIS removes the app
# next, and on update the new version's pre.sh checks the dependency right
# after this (and depwatch turns the app off again if it's still missing).
# Either way nothing is left behind.
. ./scripts/common.sh
log "preuninstall $ID"
enable_app
rmdir "$STATE" 2>/dev/null
exit 0
