#!/system/bin/sh
# Original Gen5W SmartTube wrapper code, MIT licensed. Never changes other UIDs.
export PATH=/system/bin:/system/xbin:/sbin:/vendor/bin
umask 022
PKG=org.smarttube.stable
DIR=/data/local/smarttube-gen5w-network
CHAIN=ST_G5W_OUT
CHECK=ST_G5W_UID
DNS_CHAIN=ST_G5W_DNS
DOMAIN=stg5wnet
IFACE=wlan0
UID_NUMBER=
read -r CURRENT_BOOT < /proc/sys/kernel/random/boot_id || exit 1
mkdir -p "$DIR" || exit 1
chmod 755 "$DIR" || exit 1

find_uid() {
    RESULT=
    while read -r NAME NUMBER REST; do
        [ "$NAME" = "$PKG" ] || continue
        RESULT="$NUMBER"
        break
    done < /data/system/packages.list
    case "$RESULT" in ''|*[!0-9]*) return 1 ;; esac
    [ "$RESULT" -ge 10000 ] && [ "$RESULT" -le 19999 ] || return 1
    UID_NUMBER="$RESULT"
}

write_state() {
    read -r UP REST < /proc/uptime || return 1
    {
        echo "version=2"
        echo "boot_id=$CURRENT_BOOT"
        echo "uid=$UID_NUMBER"
        echo "interface=$IFACE"
        echo "ready=$1"
        echo "uptime=$UP"
        echo "pid=$$"
    } > "$DIR/state.new" || return 1
    chmod 644 "$DIR/state.new" || return 1
    mv "$DIR/state.new" "$DIR/state"
}

ensure_family() {
    BIN="$1"
    "$BIN" -n -L "$CHAIN" >/dev/null 2>&1 || {
        "$BIN" -N "$CHAIN" || return 1
        # Install deny before allow, including during partial initialization.
        "$BIN" -A "$CHAIN" -j REJECT || return 1
        "$BIN" -I "$CHAIN" 1 -o "$IFACE" -j RETURN || return 1
    }
    "$BIN" -C "$CHAIN" -o "$IFACE" -j RETURN || return 1
    "$BIN" -C "$CHAIN" -j REJECT || return 1
    "$BIN" -n -L "$CHECK" >/dev/null 2>&1 || {
        "$BIN" -N "$CHECK" || return 1
        "$BIN" -A "$CHECK" -j RETURN || return 1
        "$BIN" -I "$CHECK" 1 -m owner --uid-owner "$UID_NUMBER" -j "$CHAIN" || return 1
        "$BIN" -I "$CHECK" 2 -m mark --mark "$DNS_MARK" -j "$CHAIN" || return 1
    }
    "$BIN" -C "$CHECK" -m owner --uid-owner "$UID_NUMBER" -j "$CHAIN" || return 1
    "$BIN" -C "$CHECK" -m mark --mark "$DNS_MARK" -j "$CHAIN" || return 1
    "$BIN" -t mangle -n -L "$DNS_CHAIN" >/dev/null 2>&1 || {
        "$BIN" -t mangle -N "$DNS_CHAIN" || return 1
        "$BIN" -t mangle -A "$DNS_CHAIN" -m mark --mark "$PRIVATE_MARK" -j MARK --set-mark "$DNS_MARK" || return 1
        "$BIN" -t mangle -A "$DNS_CHAIN" -m mark --mark "$DNS_MARK" -j ACCEPT || return 1
        "$BIN" -t mangle -A "$DNS_CHAIN" -j RETURN || return 1
    }
    "$BIN" -t mangle -C "$DNS_CHAIN" -m mark --mark "$PRIVATE_MARK" -j MARK --set-mark "$DNS_MARK" || return 1
    "$BIN" -t mangle -C OUTPUT -j "$DNS_CHAIN" >/dev/null 2>&1 ||
        "$BIN" -t mangle -I OUTPUT 1 -j "$DNS_CHAIN" || return 1
    # Insert ahead of stock ACCEPT rules on first setup. An app-scoped guard
    # such as Jellyfin may later precede us; both return unrelated packets.
    # Do not insert duplicate jumps every poll when both services run.
    "$BIN" -C OUTPUT -j "$CHECK" >/dev/null 2>&1 ||
        "$BIN" -I OUTPUT 1 -j "$CHECK" || return 1
}

bind_dns() {
    # Android 4.4's DNS proxy resolves on behalf of apps as another UID. A socket
    # owner rule alone is insufficient: pin this app's resolver mapping as well.
    read -r BOOT_ID < /proc/sys/kernel/random/boot_id || return 1
    NETD_PID=
    PROCESSES="$(ps)" || return 1
    while IFS= read -r LINE; do
        case "$LINE" in *'/system/bin/netd'|*' netd')
            set -- $LINE
            [ "$1" = root ] || continue
            NETD_PID="$2"; break ;;
        esac
    done <<EOF
$PROCESSES
EOF
    case "$NETD_PID" in ''|*[!0-9]*) return 1 ;; esac
    read -r NETD_STAT < "/proc/$NETD_PID/stat" || return 1
    set -- $NETD_STAT
    shift 21
    DNS_TOKEN="$BOOT_ID:$NETD_PID:$1:$UID_NUMBER:$IFACE"
    SAVED_TOKEN=
    [ -r "$DIR/dns-owner" ] && read -r SAVED_TOKEN < "$DIR/dns-owner"
    PRIVATE_MARK=
    [ -r "$DIR/private-mark" ] && read -r PRIVATE_MARK < "$DIR/private-mark"
    CURRENT="$(ndc interface fwmark get mark "$UID_NUMBER" 2>&1)" || return 1
    set -- $CURRENT
    CURRENT_MARK="$3"
    if [ "$SAVED_TOKEN" != "$DNS_TOKEN" ] || [ "$PRIVATE_MARK" != "$CURRENT_MARK" ]; then
        write_state 0 || return 1
        # Reserve an app-private logical routing domain. No physical modem or
        # Wi-Fi routes are changed. Netd gives this UID's proxied DNS a unique
        # socket mark so our filter can cover it despite the proxy's system UID.
        ANSWER="$(ndc interface fwmark rule add "$DOMAIN" 2>&1)" || return 1
        case "$ANSWER" in 200\ *) echo "$DNS_TOKEN" > "$DIR/dns-domain" ;; *) return 1 ;; esac
        ANSWER="$(ndc interface fwmark uid add "$DOMAIN" "$UID_NUMBER" "$UID_NUMBER" 2>&1)" || return 1
        case "$ANSWER" in 200\ *) ;; *) return 1 ;; esac
        CURRENT="$(ndc interface fwmark get mark "$UID_NUMBER" 2>&1)" || return 1
        set -- $CURRENT
        PRIVATE_MARK="$3"
        case "$PRIVATE_MARK" in ''|*[!0-9]*) return 1 ;; esac
        [ "$PRIVATE_MARK" -gt 1 ] && [ "$PRIVATE_MARK" -lt 65536 ] || return 1
        echo "$PRIVATE_MARK" > "$DIR/private-mark" || return 1
    fi
    case "$PRIVATE_MARK" in ''|*[!0-9]*) return 1 ;; esac
    DNS_MARK=$((1246101504 + UID_NUMBER))
    ANSWER="$(ndc resolver setifaceforuidrange "$IFACE" "$UID_NUMBER" "$UID_NUMBER" 2>&1)" || return 1
    case "$ANSWER" in
        200\ *) echo "$DNS_TOKEN" > "$DIR/dns-owner"; return $? ;;
        # Android 4.4 rejects even an identical range as an overlap. Only accept
        # that result when this guard installed it in this exact netd instance.
        400\ *'Invalid argument'*) [ "$SAVED_TOKEN" = "$DNS_TOKEN" ]; return $? ;;
        *) echo "SmartTube DNS binding refused: $ANSWER"; return 1 ;;
    esac
}

cleanup() {
    if [ -r "$DIR/lock/pid" ]; then
        read -r LOCK_PID < "$DIR/lock/pid"
        LOCK_BOOT=
        [ -r "$DIR/lock/boot" ] && read -r LOCK_BOOT < "$DIR/lock/boot"
        case "$LOCK_PID" in ''|*[!0-9]*) return 1 ;; esac
        if { [ -z "$LOCK_BOOT" ] || [ "$LOCK_BOOT" = "$CURRENT_BOOT" ]; } && [ "$LOCK_PID" != "$$" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
            echo "Stop the SmartTube network service before removing its rules."
            return 1
        fi
        rm -f "$DIR/lock/pid" "$DIR/lock/boot"
        rmdir "$DIR/lock" || return 1
    fi
    if [ -r "$DIR/state" ]; then
        while IFS='=' read -r KEY VALUE; do
            [ "$KEY" = uid ] && UID_NUMBER="$VALUE"
        done < "$DIR/state"
    fi
    if [ -z "$UID_NUMBER" ]; then
        find_uid || {
            [ ! -e "$DIR/dns-owner" ] && [ ! -e "$DIR/dns-domain" ] && return 0
            return 1
        }
    fi
    case "$UID_NUMBER" in ''|*[!0-9]*) return 1 ;; esac
    [ "$UID_NUMBER" -ge 10000 ] && [ "$UID_NUMBER" -le 19999 ] || return 1
    write_state 0 || return 1
    for BIN in iptables ip6tables; do
        while "$BIN" -C OUTPUT -j "$CHECK" >/dev/null 2>&1; do
            "$BIN" -D OUTPUT -j "$CHECK" || return 1
        done
        while "$BIN" -t mangle -C OUTPUT -j "$DNS_CHAIN" >/dev/null 2>&1; do
            "$BIN" -t mangle -D OUTPUT -j "$DNS_CHAIN" || return 1
        done
        while "$BIN" -C OUTPUT -m owner --uid-owner "$UID_NUMBER" -j "$CHAIN" >/dev/null 2>&1; do
            "$BIN" -D OUTPUT -m owner --uid-owner "$UID_NUMBER" -j "$CHAIN" || return 1
        done
        for ITEM in "$CHECK" "$CHAIN"; do
            if "$BIN" -n -L "$ITEM" >/dev/null 2>&1; then
                "$BIN" -F "$ITEM" && "$BIN" -X "$ITEM" || return 1
            fi
        done
        if "$BIN" -t mangle -n -L "$DNS_CHAIN" >/dev/null 2>&1; then
            "$BIN" -t mangle -F "$DNS_CHAIN" && "$BIN" -t mangle -X "$DNS_CHAIN" || return 1
        fi
    done
    if [ -r "$DIR/dns-domain" ]; then
        read -r DOMAIN_OWNER < "$DIR/dns-domain"
        if [ "${DOMAIN_OWNER%%:*}" != "$CURRENT_BOOT" ]; then
            # Kernel/netd mappings from an earlier boot no longer exist. Do not
            # clear a new boot's independently-created policy for a reused UID.
            rm -f "$DIR/dns-domain" "$DIR/private-mark" "$DIR/dns-owner"
            return 0
        fi
        # The UID step may never have completed. Removing the private domain
        # below verifies no UID mappings still refer to it; never remove another
        # domain's UID mapping or clear all resolver mappings.
        ndc interface fwmark uid remove "$DOMAIN" "$UID_NUMBER" "$UID_NUMBER" >/dev/null 2>&1
        ANSWER="$(ndc interface fwmark rule remove "$DOMAIN" 2>&1)" || return 1
        case "$ANSWER" in 200\ *) rm -f "$DIR/dns-domain" "$DIR/private-mark" ;; *) return 1 ;; esac
    fi
    if [ -r "$DIR/dns-owner" ]; then
        read -r DNS_OWNER < "$DIR/dns-owner"
        if [ "${DNS_OWNER%%:*}" != "$CURRENT_BOOT" ]; then
            rm -f "$DIR/dns-owner"
            return 0
        fi
        ANSWER="$(ndc resolver clearifaceforuidrange "$UID_NUMBER" "$UID_NUMBER" 2>&1)" || return 1
        case "$ANSWER" in 200\ *) rm -f "$DIR/dns-owner"; return $? ;; *) return 1 ;; esac
    fi
    return 0
}

case "${1:-daemon}" in
    cleanup) cleanup; exit $? ;;
    lab-eth0)
        # Cannot be enabled by the app or on a production head unit.
        [ "$(getprop ro.kernel.qemu)" = 1 ] || exit 1
        IFACE=eth0
        ;;
    daemon) ;;
    *) echo "Use daemon or cleanup"; exit 1 ;;
esac
# NEMESIS over ADB can initially start a root service without NET_ADMIN.
# Exit so its service manager restarts it with the necessary capability.
CAPS=
while read -r KEY VALUE REST; do
    [ "$KEY" = CapEff: ] && { CAPS="$VALUE"; break; }
done < /proc/self/status
case "$CAPS" in ''|*[!0-9a-fA-F]*) exit 1 ;; esac
[ $((0x$CAPS & 4096)) -ne 0 ] || { sleep 3; exit 1; }
find_uid || exit 1
if ! mkdir "$DIR/lock" 2>/dev/null; then
    LOCK_PID=
    LOCK_BOOT=
    [ -r "$DIR/lock/pid" ] && read -r LOCK_PID < "$DIR/lock/pid"
    [ -r "$DIR/lock/boot" ] && read -r LOCK_BOOT < "$DIR/lock/boot"
    case "$LOCK_PID" in ''|*[!0-9]*) exit 1 ;; esac
    if { [ -z "$LOCK_BOOT" ] || [ "$LOCK_BOOT" = "$CURRENT_BOOT" ]; } && kill -0 "$LOCK_PID" 2>/dev/null; then exit 1; fi
    rm -f "$DIR/lock/pid" "$DIR/lock/boot"
    rmdir "$DIR/lock" && mkdir "$DIR/lock" || exit 1
fi
echo $$ > "$DIR/lock/pid" || exit 1
echo "$CURRENT_BOOT" > "$DIR/lock/boot" || exit 1
write_state 0 || exit 1
trap 'write_state 0; rm -f "$DIR/lock/pid" "$DIR/lock/boot"; rmdir "$DIR/lock"; exit 0' TERM INT HUP
while true; do
    PREVIOUS_UID="$UID_NUMBER"
    if ! find_uid || [ "$UID_NUMBER" != "$PREVIOUS_UID" ]; then
        # The package identity changed; never leave an old UID rule running.
        UID_NUMBER="$PREVIOUS_UID"
        cleanup
        exit 1
    fi
    if bind_dns && ensure_family iptables && ensure_family ip6tables; then
        write_state 1 || exit 1
    else
        write_state 0 || exit 1
    fi
    sleep 1
done
