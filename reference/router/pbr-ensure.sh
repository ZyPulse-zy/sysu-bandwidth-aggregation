#!/bin/sh
set -eu
ROOT=/root/router-project
exec 7>/tmp/router-project-pbr.lock
flock -x 7
[ -f "$ROOT/policy/pbr-ready" ] || exit 0
if ! ip -4 rule show | grep -q '^800:.*to 192.168.50.0/24 lookup main'; then
 ip -4 rule add pref 800 to 192.168.50.0/24 lookup main
fi
for n in 1 2 3 4 5; do
 table=$((100+n)); pref=$((1000+n)); mark=$((n*65536))
 if ! ip -4 rule show | grep -q "^$pref:.*fwmark .* lookup $table"; then
  ip -4 rule add pref "$pref" fwmark "$mark/16711680" lookup "$table"
 fi
done
if ! nft list table inet rp_pbr >/dev/null 2>&1; then nft -f "$ROOT/policy/pbr.nft"; fi
# Initial local-output route only. The future health controller will own selection.
if ! ip -4 route show table main default | grep -q 'metric 9000'; then
 for n in 1 2 3 4 5; do
  gateway=$(ip -4 route show table "$((100+n))" default | awk '/^default via /{print $3;exit}')
  src=$(ip -4 -o addr show dev "rpwan$n" | awk '{split($4,a,"/");print a[1];exit}')
  if [ -n "$gateway" ] && [ -n "$src" ]; then
   ip -4 route replace default via "$gateway" dev "rpwan$n" onlink src "$src" metric 9000
   break
  fi
 done
fi
