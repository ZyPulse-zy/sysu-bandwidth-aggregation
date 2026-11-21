#!/bin/sh
set -eu
umask 077
n=$1
case "$n" in 1|2|3|4|5|6);; *) exit 2;; esac
ROOT=/root/router-project
dev=rpwan$n
[ -f "$ROOT/policy/wan$n.enabled" ]
[ -s "/etc/minieap/wan$n.conf" ]
if [ "$n" = 6 ]; then
 [ ! -L /etc/minieap/wan6.conf ]
 /usr/bin/lua - <<'ATHENA_PRIVATE_AUTH_FILE'
local fs=require('nixio.fs')
local a=assert(fs.lstat('/etc/minieap/wan6.conf'))
assert(a.type=='reg' and a.uid==0 and a.gid==0 and a.modedec==600 and a.nlink==1,'Unsafe private authentication file')
ATHENA_PRIVATE_AUTH_FILE
fi
if [ "$n" = 6 ]; then
 "$ROOT/scripts/prepare-macvlans.sh" 6
else
 "$ROOT/scripts/prepare-macvlans.sh"
fi
ip link set dev wan up
while [ "$(cat /sys/class/net/wan/carrier 2>/dev/null || echo 0)" != 1 ]; do sleep 5; done
ip link set dev "$dev" up
mkdir -p /tmp/router-project-logs
chmod 700 /tmp/router-project-logs
# Foreground MiniEAP is the procd-tracked process; credentials never appear in argv.
# Suppress account6 daemon output as well: upstream diagnostics may reveal identifiers.
if [ "$n" = 6 ]; then
 exec /usr/sbin/minieap --conf-file /etc/minieap/wan6.conf --pid-file /var/run/minieap-wan6.pid --daemonize 0 >/dev/null 2>&1
fi
exec /usr/sbin/minieap --conf-file "/etc/minieap/wan$n.conf" --pid-file "/var/run/minieap-wan$n.pid" --daemonize 0 >> "/tmp/router-project-logs/minieap-wan$n.log" 2>&1
