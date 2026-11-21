#!/bin/sh
set -eu
ROOT=/root/router-project
count=5
[ ! -f "$ROOT/policy/wan6.enabled" ] || count=6
exec 8>/var/lock/router-project-shaper.lock
baseline_filters() {
 dev=$1;handle=$2
 q=$(tc qdisc show dev "$dev")
 printf '%s\n' "$q" | grep -q "^qdisc cake $handle root " || return 1
 # The classifier's persistent contract is diffserv4. Preserve the current
 # rate and all other CAKE options when repairing the former boot default.
 if printf '%s\n' "$q" | grep -q ' besteffort '; then
  tc qdisc change dev "$dev" root cake diffserv4
 fi
 text=$(tc filter show dev "$dev" parent "$handle")
 first=0;last=0
 printf '%s\n' "$text" | grep -q 'pref 40900 ' && first=1
 printf '%s\n' "$text" | grep -q 'pref 41900 ' && last=1
 [ "$first" = "$last" ] || return 1
 if [ "$first" = 0 ]; then
  printf '%s\n' "$text" | grep -Eq 'pref 41[0-8][0-9][0-9] ' && return 1
  tc filter add dev "$dev" parent "$handle" protocol ip pref 40900 u32 match u8 0x45 0xff at 0 match ip protocol 6 0xff match u16 0x400 0xfc00 at 2 action skbedit priority "${handle}2" pass
  tc filter add dev "$dev" parent "$handle" protocol all pref 41900 matchall action skbedit priority "${handle}2" pass
 fi
}
ensure_ingress() {
 n=$1
 if ! tc qdisc show dev "rpwan$n" | grep -q '^qdisc ingress ffff:'; then tc qdisc add dev "rpwan$n" handle ffff: ingress; fi
 if ! tc filter show dev "rpwan$n" parent ffff: protocol ip | grep -q "rpifb$n"; then
  tc filter add dev "rpwan$n" parent ffff: protocol ip pref 10 matchall action mirred egress redirect dev "rpifb$n"
 fi
 # Native LAN IPv6 uses WAN1 and shares its download budget with IPv4.
 if [ "$n" = 1 ]; then
  ipv6=$(tc filter show dev rpwan1 parent ffff: protocol ipv6 pref 11) || return 1
  case "$ipv6" in
   '') tc filter add dev rpwan1 parent ffff: protocol ipv6 pref 11 handle 0x1 matchall skip_hw action mirred egress redirect dev rpifb1;;
   *'matchall chain 0 handle 0x1'*'mirred (Egress Redirect to device rpifb1)'*) ;;
   *) logger -t rp-shaper 'Refusing unexpected WAN1 IPv6 ingress filter at priority 11'; return 1;;
  esac
 fi
}
ensure_one() {
 n=$1
 ip link show "rpwan$n" >/dev/null 2>&1 || return 0
 if ! ip link show "rpifb$n" >/dev/null 2>&1; then ip link add "rpifb$n" type ifb; fi
 ip -d link show "rpifb$n" | grep -q 'ifb' || return 1
 ip link set "rpifb$n" up
 for dev in "rpwan$n" "rpifb$n"; do
  if [ "$n" = 6 ]; then up=8061:;down=8062:
  else up=$(printf '%x:' $((32768+n*2-1)));down=$(printf '%x:' $((32768+n*2)));fi
  handle=$up;[ "$dev" != "rpifb$n" ] || handle=$down
  if ! tc qdisc show dev "$dev" | grep -q '^qdisc cake .* root '; then
   allowed='^qdisc (noqueue|pfifo_fast) .* root '
   [ "$dev" != "rpifb$n" ] || allowed='^qdisc (noqueue|pfifo_fast|fq_codel) .* root '
   tc qdisc show dev "$dev" | grep -Eq "$allowed" || { logger -t rp-shaper "Refusing unexpected root qdisc on $dev"; return 1; }
   if [ "$dev" = "rpwan$n" ]; then
    if [ "$n" = 6 ]; then
     tc qdisc replace dev "$dev" root handle 8061: cake bandwidth 40mbit diffserv4 dual-srchost nat overhead 38 mpu 84
    else
     tc qdisc replace dev "$dev" root handle "$handle" cake bandwidth 40mbit diffserv4 dual-srchost nat overhead 38 mpu 84
    fi
   else
    if [ "$dev" = rpifb6 ]; then
     tc qdisc replace dev "$dev" root handle 8062: cake bandwidth 70mbit diffserv4 dual-dsthost nat ingress overhead 38 mpu 84
    elif [ "$dev" = rpifb5 ]; then
     tc qdisc replace dev "$dev" root handle "$handle" cake bandwidth 50mbit diffserv4 flows nonat no-split-gso ingress overhead 38 mpu 84
    else
     tc qdisc replace dev "$dev" root handle "$handle" cake bandwidth 50mbit diffserv4 dual-dsthost nat ingress overhead 38 mpu 84
    fi
   fi
  fi
  baseline_filters "$dev" "$handle"
 done
 ensure_ingress "$n"
}
load_module() {
 [ "$(uname -r)" = 6.18.44 ] || { logger -t rp-shaper 'Kernel changed; refusing old CAKE module'; return 1; }
 apk info -v | grep -qx 'kernel-6.18.44~d3af8f5306cb15e0075d8820313a140a-r1' || return 1
 sha256sum -c "$ROOT/manifests/cake-module.sha256" >/dev/null || return 1
 if ! grep -q '^sch_cake ' /proc/modules; then insmod "$ROOT/modules/sch_cake.ko"; fi
}
case ${1:-once} in
 stop)
  flock -x 8
  for n in $(seq 1 "$count"); do
   if tc filter show dev "rpwan$n" parent ffff: 2>/dev/null | grep -q "rpifb$n"; then tc qdisc del dev "rpwan$n" ingress; fi
   if tc qdisc show dev "rpwan$n" 2>/dev/null | grep -q '^qdisc cake .* root '; then tc qdisc del dev "rpwan$n" root; fi
   ip link del "rpifb$n" 2>/dev/null || true
  done;;
 once|watch)
  load_module
  while :; do
   flock -x 8
   for n in $(seq 1 "$count"); do ensure_one "$n"; done
   flock -u 8
   [ "${1:-once}" = watch ] || break
   sleep 5
  done;;
 *) exit 2;;
esac
