#!/system/bin/sh
# NEMESIS stops netguard before this script. Stop sockets before removing policy.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
am force-stop org.smarttube.stable || exit 1
HERE=${0%/*}
sh "$HERE/../svc/netguard.sh" cleanup || exit 1
# Remove the previous release's owner-filter chain during migration as well.
for ipt in iptables ip6tables; do
    while "$ipt" -C OUTPUT -j smarttube_net >/dev/null 2>&1; do
        "$ipt" -D OUTPUT -j smarttube_net || exit 1
    done
    if "$ipt" -n -L smarttube_net >/dev/null 2>&1; then
        "$ipt" -F smarttube_net && "$ipt" -X smarttube_net || exit 1
    fi
done
