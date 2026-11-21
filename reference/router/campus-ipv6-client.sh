#!/bin/sh
set -eu
dev=${1:-}
case "$dev" in rpwan1|rpwan2|rpwan3|rpwan4|rpwan5);; *) exit 2;; esac
exec 9>/tmp/campus-ipv6-client.lock
flock -x 9
# A helper queued before rollback must not re-enable IPv6 after removal.
[ -f /root/router-project/scripts/campus-ipv6-client.sh ] || exit 0
[ -d "/sys/class/net/$dev" ]
[ "$(cat "/sys/class/net/$dev/iflink")" = "$(cat /sys/class/net/wan/ifindex)" ]
put() {
 p="/proc/sys/net/ipv6/conf/$dev/$1"
 [ -w "$p" ]
 [ "$(cat "$p")" = "$2" ] || printf '%s\n' "$2" > "$p"
}
put accept_ra 2
put autoconf 1
put accept_ra_pinfo 1
put accept_ra_defrtr 1
put disable_ipv6 0
