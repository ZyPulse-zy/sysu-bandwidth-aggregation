#!/bin/sh
set -eu
ROOT=/root/router-project
DIR=/tmp/router-project-health
ROUND=${1:?probe round required}
case "$ROUND" in *[!a-zA-Z0-9_.:-]*|'') exit 2;; esac
mkdir -p "$DIR"
chmod 700 "$DIR"
one() {
 n=$1; dev=rpwan$n
 read -r began unused < /proc/uptime
 present=0
 if [ -f "$ROOT/policy/wan$n.enabled" ] && [ "$(cat /sys/class/net/wan/carrier 2>/dev/null)" = 1 ] && ip -4 route show table "$((100+n))" | grep -q '^default via '; then present=1; fi
 rtts=''; good=0
 for host in 223.5.5.5 119.29.29.29 180.76.76.76; do
  rtt=0
  if [ "$present" = 1 ]; then
   rtt=$(ping -I "$dev" -c 1 -W 1 "$host" 2>/dev/null | awk -F= '/round-trip/{split($2,a,"/");print a[2]}')
   if [ -n "$rtt" ]; then good=$((good+1)); else rtt=0; fi
  fi
  rtts="${rtts}${rtts:+,}$rtt"
 done
 fallback=0
 if [ "$present" = 1 ] && [ "$good" -lt 2 ]; then
  code=$(curl --interface "$dev" --noproxy '*' --resolve www.baidu.com:443:157.148.69.186 --connect-timeout 2 --max-time 3 -s -o /dev/null -w '%{http_code}' https://www.baidu.com/ || true)
  [ "$code" != 200 ] || fallback=1
 fi
 read -r finished unused < /proc/uptime
 printf '{"round":"%s","startedAtUptime":%s,"finishedAtUptime":%s,"present":%s,"good":%s,"httpFallback":%s,"rtts":[%s]}\n' "$ROUND" "$began" "$finished" "$present" "$good" "$fallback" "$rtts" > "$DIR/probe$n.new"
 mv "$DIR/probe$n.new" "$DIR/probe$n.json"
}
accounts="1 2 3 4 5"
[ ! -f "$ROOT/policy/wan6.enabled" ] || accounts="$accounts 6"
pids=''
for n in $accounts; do one "$n" & pids="$pids $!"; done
result=0
for pid in $pids; do wait "$pid" || result=1; done
exit "$result"
