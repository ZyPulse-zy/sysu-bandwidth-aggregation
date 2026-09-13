#!/bin/sh
set -eu
n=$1
case "$n" in 1|2|3|4|5);; *) exit 2;; esac
table=$((100+n))
if ! ubus call "network.interface.wan$n" status >/dev/null 2>&1; then
 ubus call network add_dynamic "{\"name\":\"wan$n\",\"proto\":\"dhcp\",\"device\":\"rpwan$n\",\"auto\":false,\"peerdns\":false,\"defaultroute\":true,\"ip4table\":\"$table\",\"metric\":$table,\"delegate\":false,\"iface6rd\":\"0\",\"sendclientid\":\"hardware\"}"
fi
ubus call "network.interface.wan$n" up
