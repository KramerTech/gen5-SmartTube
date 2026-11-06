#!/system/bin/sh
# NEMESIS service: keep SmartTube off the car's built-in modem.
# The telematics SIM isn't a free data service, and streaming video over it
# risks the car's connected services. SmartTube's uid may only send through
# Wi-Fi or a Bluetooth/USB hotspot; anything else (rmnet*, the internal eth0)
# is rejected, so with no Wi-Fi it just reports that it's offline.
# NEMESIS Manager does the same for its own traffic, but in Java, by default
# route (Portal.checkNetwork). This is a per-uid firewall rule instead, so the
# APK needs no patch, and it covers sockets that already exist when the route
# changes. DNS still resolves through netd (another uid), so with no Wi-Fi a
# lookup may go over the modem; nothing else from SmartTube does.
#
# Toolbox shell only (no cut/sed/awk/head/tail); mksh builtins instead.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin

APP_PKG=org.smarttube.stable
CHAIN=smarttube_net
# Interfaces SmartTube may use. Gen5W's modem is rmnet0-3, and eth0 is an
# internal link, so eth isn't allowed the way Manager allows it.
ALLOW="lo wlan+ bnep+ bt-pan+ usb+ rndis+"
INTERVAL=${NETGUARD_INTERVAL:-15}

log() { echo "$(date '+%m-%d %H:%M:%S') $1"; }

# CAP_NET_ADMIN (bit 12) in our effective set. `nemesis install` from ADB
# starts services with adbd's reduced set; svcmgr, started by init, has all.
can_admin() {
    while read _k _v; do
        [ "$_k" = CapEff: ] || continue
        _d=${_v%???}
        _d=${_d#"${_d%?}"}
        case "$_d" in [13579bdfBDF]) return 0 ;; esac
        return 1
    done < /proc/self/status
    return 1
}

# SmartTube's uid from packages.list, or nothing. It changes on every
# reinstall, and NEMESIS reinstalls on every update.
app_uid() {
    while read _p _u _rest; do
        [ "$_p" = "$APP_PKG" ] && { echo "$_u"; return 0; }
    done < /data/system/packages.list
    return 1
}

# The rules for <uid>, in both families: the modem has public IPv6 too.
apply() {
    _ok=0
    for _ipt in iptables ip6tables; do
        $_ipt -N $CHAIN 2>/dev/null
        if ! $_ipt -F $CHAIN; then _ok=1; continue; fi
        $_ipt -A $CHAIN -m owner ! --uid-owner "$1" -j RETURN || _ok=1
        for _i in $ALLOW; do $_ipt -A $CHAIN -o "$_i" -j RETURN || _ok=1; done
        $_ipt -A $CHAIN -j REJECT 2>/dev/null || $_ipt -A $CHAIN -j DROP || _ok=1
        $_ipt -C OUTPUT -j $CHAIN 2>/dev/null || $_ipt -I OUTPUT 1 -j $CHAIN || _ok=1
    done
    return $_ok
}

# The rules are still there for <uid> (netd or an iptables reset can drop them).
applied() {
    for _ipt in iptables ip6tables; do
        $_ipt -C OUTPUT -j $CHAIN 2>/dev/null || return 1
        $_ipt -C $CHAIN -m owner ! --uid-owner "$1" -j RETURN 2>/dev/null || return 1
    done
}

if ! can_admin; then
    # Exit so svcmgr restarts us with the rights to change the firewall.
    log "no CAP_NET_ADMIN (started from ADB?); exiting for svcmgr to restart"
    sleep 3
    exit 1
fi

uid=
last=
while :; do
    if u=$(app_uid); then
        if [ "$u" != "$uid" ] || ! applied "$u"; then
            # On a failure uid stays unset, so the next pass tries again.
            if apply "$u"; then state="blocking non-Wi-Fi for uid $u"; uid=$u
            else state="WARN: rules for uid $u incomplete"; uid=; fi
            [ "$state" = "$last" ] || log "$state"
            last=$state
        fi
    elif [ "$last" != waiting ]; then
        log "$APP_PKG not installed yet"
        last=waiting
    fi
    sleep $INTERVAL
done
