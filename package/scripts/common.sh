#!/system/bin/sh
# Shared helpers for the smarttube package: the media.codecs dependency and
# turning the app off/on when that dependency goes away/comes back.
# Toolbox shell only (no cut/sed/awk/head/tail); mksh builtins instead.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 022

ID=smarttube
HERE=/data/nemesis/apps/$ID
APP_PKG=org.smarttube.stable
LOG=/data/nemesis/$ID.log
STATE=/data/nemesis/backup/$ID
# Present while SmartTube is disabled because media.codecs is missing. Lives
# outside the package tree so it survives a package update.
MARK=$STATE/disabled-for-missing-codecs

DEP_ID=media.codecs
DEP_NAME="Video Codec Fix"
DEP_DATA=/data/nemesis/apps/$DEP_ID/NEMESIS.data
# CODECS_MIN_VERSION, written by build.sh.
DEP_CONF=${PKGDIR:-$PWD}/scripts/dep.conf
[ -f "$DEP_CONF" ] || DEP_CONF=$HERE/scripts/dep.conf
. "$DEP_CONF"

log() { print -r -- "$1"; print -r -- "$(date '+%m-%d %H:%M:%S') $1" >> "$LOG" 2>/dev/null; true; }

toast() {
    am broadcast -a com.hkmc.intent.action.TOAST \
        -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || true
}

# Services may start without init's framework environment, which pm/am need.
load_android_env() {
    [ -n "$BOOTCLASSPATH" ] && return 0
    [ -r /init.environ.rc ] || return 1
    while read _cmd _name _value; do
        [ "$_cmd" = export ] && export "$_name=$_value"
    done < /init.environ.rc
}

# version_ge <a> <b>: a >= b, comparing up to three dot-separated numbers.
# Non-digits in a part are ignored ("2.0-rc1" compares as 2.0.1).
version_ge() {
    _a=$1 _b=$2 _i=0
    while [ $_i -lt 3 ]; do
        _pa=${_a%%.*}; _pb=${_b%%.*}
        case "$_a" in *.*) _a=${_a#*.} ;; *) _a= ;; esac
        case "$_b" in *.*) _b=${_b#*.} ;; *) _b= ;; esac
        _pa=$(digits "$_pa"); _pb=$(digits "$_pb")
        [ "$_pa" -gt "$_pb" ] && return 0
        [ "$_pa" -lt "$_pb" ] && return 1
        _i=$((_i + 1))
    done
    return 0
}
digits() {
    _d=
    _s=$1
    while [ -n "$_s" ]; do
        _ch=${_s%"${_s#?}"}
        _s=${_s#?}
        case "$_ch" in [0-9]) _d=$_d$_ch ;; esac
    done
    print -r -- "${_d:-0}"
}

# Installed media.codecs version, or nothing.
dep_version() {
    [ -f "$DEP_DATA" ] || return 1
    while IFS= read -r _line; do
        case "$_line" in version=*) print -r -- "${_line#version=}"; return 0 ;; esac
    done < "$DEP_DATA"
    print -r -- 0
}

# dep_ok: media.codecs is installed and new enough.
dep_ok() {
    _v=$(dep_version) || return 1
    version_ge "$_v" "$CODECS_MIN_VERSION"
}

app_installed() { pm path "$APP_PKG" 2>/dev/null | grep -q '^package:'; }
app_disabled() { pm list packages -d 2>/dev/null | grep -q -x -F "package:$APP_PKG"; }

# Turn SmartTube off because the dependency is gone (keeps its data).
disable_app() {
    am force-stop "$APP_PKG" >/dev/null 2>&1
    if pm disable "$APP_PKG" >/dev/null 2>&1 && app_disabled; then
        mkdir -p "$STATE" && : > "$MARK"
        log "disabled $APP_PKG: $DEP_ID is missing or older than $CODECS_MIN_VERSION"
        toast "SmartTube was turned off because the $DEP_NAME package ($DEP_ID $CODECS_MIN_VERSION or newer) is no longer installed. Reinstall it and SmartTube comes back on its own."
    else
        log "WARN: could not disable $APP_PKG"
    fi
}

# Turn SmartTube back on, but only if we were the ones who turned it off.
enable_app() {
    [ -f "$MARK" ] || return 0
    if pm enable "$APP_PKG" >/dev/null 2>&1 && ! app_disabled; then
        rm -f "$MARK"
        log "re-enabled $APP_PKG: $DEP_ID is back"
        return 0
    fi
    log "WARN: could not re-enable $APP_PKG"
    return 1
}
