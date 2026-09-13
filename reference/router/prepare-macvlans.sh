#!/bin/sh
set -eu
ROOT=/root/router-project
exec 8>/tmp/router-project-macvlan.lock
flock -x 8
[ -e /sys/class/net/wan ]
while read -r n mac; do
 case "$n" in 1|2|3|4|5);; *) exit 2;; esac
 dev=rpwan$n
 if [ ! -e "/sys/class/net/$dev" ]; then
  ip link add link wan name "$dev" address "$mac" type macvlan mode bridge
 fi
 [ "$(cat "/sys/class/net/$dev/address")" = "$mac" ]
 ip -d link show dev "$dev" | grep -q 'macvlan mode bridge'
 [ "$(cat "/sys/class/net/$dev/iflink")" = "$(cat /sys/class/net/wan/ifindex)" ]
 [ ! -w "/proc/sys/net/ipv6/conf/$dev/disable_ipv6" ] || echo 1 > "/proc/sys/net/ipv6/conf/$dev/disable_ipv6"
 if [ -f "$ROOT/policy/core-ready" ]; then
  table=$((100+n)); pref=$((900+n))
  if ! ip -4 rule show | grep -q "^$pref:.*oif $dev lookup $table"; then ip -4 rule add pref "$pref" oif "$dev" lookup "$table"; fi
  if ! ip -4 route show table "$table" | grep -q '^unreachable default.*metric 42760'; then ip -4 route add unreachable default table "$table" metric 42760; fi
 fi
done < "$ROOT/policy/mac-map"
