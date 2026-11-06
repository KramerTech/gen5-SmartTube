#!/system/bin/sh
# Runs on uninstall and before an update, after netguard is stopped: remove its
# firewall rules so the uid, which Android hands out again, isn't left blocked.
# From `nemesis install` over ADB this has no CAP_NET_ADMIN and does nothing;
# an update's netguard rebuilds the chain for the new uid, and after an
# uninstall the rules go at the next reboot.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
for ipt in iptables ip6tables; do
    $ipt -D OUTPUT -j smarttube_net 2>/dev/null
    $ipt -F smarttube_net 2>/dev/null
    $ipt -X smarttube_net 2>/dev/null
done
exit 0
