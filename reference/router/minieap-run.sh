#!/bin/sh
set -eu
umask 077
n=$1
case "$n" in 1|2|3|4|5);; *) exit 2;; esac
ROOT=/root/router-project
dev=rpwan$n
[ -f "$ROOT/policy/wan$n.enabled" ]
[ -s "/etc/minieap/wan$n.conf" ]
"$ROOT/scripts/prepare-macvlans.sh"
ip link set dev wan up
while [ "$(cat /sys/class/net/wan/carrier 2>/dev/null || echo 0)" != 1 ]; do sleep 5; done
ip link set dev "$dev" up
mkdir -p /tmp/router-project-logs
chmod 700 /tmp/router-project-logs
# Foreground MiniEAP is the procd-tracked process; credentials never appear in argv.
exec /usr/sbin/minieap --conf-file "/etc/minieap/wan$n.conf" --pid-file "/var/run/minieap-wan$n.pid" --daemonize 0 >> "/tmp/router-project-logs/minieap-wan$n.log" 2>&1
