#!/bin/sh
# Native LAN IPv6 only. Existing IPv4 FakeIP/DNS/proxy paths stay unchanged.
# Called by the existing core guard. No network/firewall reload.
set -eu
IP=${IP:-/sbin/ip}
NFT=${NFT:-nft}
LAN=br-lan
WAN=rpwan1
NATIVE_TABLE=16666
PROTO=static
WAN_METRIC=42051
BLOCK_METRIC=42052

rules=$($IP -6 rule show)
rule_at() { printf '%s\n' "$rules" | awk -v p="$1:" '$1==p {$1=$1;print}'; }
check_rule() {
 current=$(rule_at "$1")
 [ -z "$current" ] || [ "$current" = "$2" ] || {
  echo "LAN6 rule priority $1 already has a different rule" >&2
  exit 1
 }
}
# Validate all priorities before writing any of them. The main lookup accepts
# only /128 peer routes, so the campus on-link /64 cannot divert LAN clients.
check_rule 860 '860: from all iif br-lan lookup main suppress_prefixlength 127'
check_rule 870 '870: from all iif br-lan lookup 16666'

native=$($IP -6 route show table "$NATIVE_TABLE" 2>/dev/null || true)
# Refuse to change a table with entries not owned by this helper.
printf '%s\n' "$native" | awk '
 NF==0 {next}
 $0=="unreachable default dev lo proto static metric 42052 pref medium" || $0=="unreachable default proto static metric 42052 pref medium" {next}
 $1=="default" && $2=="via" && $3~/^fe80:/ && $4=="dev" && $5=="rpwan1" && $6=="proto" && $7=="static" && $8=="metric" && $9=="42051" && $10=="pref" && $11=="medium" && NF==11 {next}
 {exit 1}' || { echo 'LAN6 native table contains an unexpected route' >&2; exit 1; }


# Preserve the existing IPv4-first guard and add only this one scoped exception.
# Validate an existing comment's complete rule so a duplicate or altered comment
# cannot silently authorize a different path.
comment='router-project native LAN IPv6 WAN1'
core=$($NFT -a list chain inet rp_core ipv6_forward_guard)
owned=$(printf '%s\n' "$core" | grep -F "comment \"$comment\"" || true)
if [ -n "$owned" ]; then
 normalized=$(printf '%s\n' "$owned" | sed -E 's/counter packets [0-9]+ bytes [0-9]+/counter/; s/[[:space:]]*# handle [0-9]+$//' | awk '{$1=$1;print}')
 [ "$normalized" = 'meta nfproto ipv6 iifname "br-lan" oifname "rpwan1" counter return comment "router-project native LAN IPv6 WAN1"' ] || {
  echo 'LAN6 core guard exception is duplicated or differs' >&2; exit 1
 }
 printf '%s\n' "$core" | awk '
 /comment "router-project native LAN IPv6 WAN1"/ {seen=1}
 /comment "router-project IPv4-first"/ {if(!seen)exit 1}' || {
  echo 'LAN6 core guard exception is after the original reject' >&2; exit 1
 }
fi

# A terminal route is installed before the LAN policy, including at boot.
if ! printf '%s\n' "$native" | grep -Eq '^unreachable default( dev lo)? proto static metric 42052 pref medium$'; then
 $IP -6 route add unreachable default proto "$PROTO" metric "$BLOCK_METRIC" table "$NATIVE_TABLE"
fi
if [ -z "$(rule_at 860)" ]; then
 $IP -6 rule add pref 860 iif "$LAN" lookup main suppress_prefixlength 127
fi
if [ -z "$(rule_at 870)" ]; then
 $IP -6 rule add pref 870 iif "$LAN" lookup "$NATIVE_TABLE"
fi

# Read only the live RA default on WAN1. Never borrow a different WAN gateway.
gateway=$($IP -6 route show table main default dev "$WAN" proto ra 2>/dev/null | awk '$1=="default" && $2=="via" && $3~/^fe80:/ {print $3;exit}')
ready=$($IP -6 address show dev "$WAN" scope global 2>/dev/null | awk '/inet6 / && /scope global/ && !/tentative|dadfailed|deprecated/ {print "yes";exit}')
if [ -n "$gateway" ] && [ "$ready" = yes ]; then
 expected="default via $gateway dev $WAN proto $PROTO metric $WAN_METRIC pref medium"
 if ! printf '%s\n' "$native" | grep -Fqx "$expected"; then
  $IP -6 route replace default via "$gateway" dev "$WAN" proto "$PROTO" metric "$WAN_METRIC" table "$NATIVE_TABLE"
 fi
else
 # Delete only our single preferred default; keep the terminal route and rules.
 if printf '%s\n' "$native" | grep -q '^default via '; then
  $IP -6 route del default dev "$WAN" proto "$PROTO" metric "$WAN_METRIC" table "$NATIVE_TABLE"
 fi
fi

if [ -z "$owned" ]; then
 printf 'insert rule inet rp_core ipv6_forward_guard meta nfproto ipv6 iifname "%s" oifname "%s" counter return comment "%s"\n' "$LAN" "$WAN" "$comment" | $NFT -f -
fi

# A client can keep its SLAAC address through a router reboot. Until odhcpd
# learns its /128, a campus /64 on another WAN can win the return lookup.
# Learn only accepted LAN senders within WAN1's on-link prefix. An established
# reply on WAN1 can then trigger normal neighbor discovery on the LAN.
RETURN_TABLE=16667
RETURN_PREF=881
RETURN_MARK=0x40000000
return_rule=$(rule_at "$RETURN_PREF")
case "$return_rule" in
 ''|'881: from all fwmark 0x40000000/0x40000000 iif rpwan1 lookup 16667'|'881: from all iif rpwan1 fwmark 0x40000000/0x40000000 lookup 16667') ;;
 *) echo 'LAN6 return policy priority conflict' >&2; exit 1;;
esac
return_route=$($IP -6 route show table "$RETURN_TABLE" 2>/dev/null || true)
case "$return_route" in
 ''|'default dev br-lan proto static metric 42053 pref medium') ;;
 *) echo 'LAN6 return table conflict' >&2; exit 1;;
esac
[ -n "$return_route" ] || $IP -6 route add default dev "$LAN" proto static metric 42053 table "$RETURN_TABLE"
[ -n "$return_rule" ] || $IP -6 rule add pref "$RETURN_PREF" iif "$WAN" fwmark "$RETURN_MARK/$RETURN_MARK" lookup "$RETURN_TABLE"

prefixes=$($IP -6 route show dev "$WAN" proto kernel | awk '$1 ~ /^[23][[:xdigit:]:]*\/[0-9]+$/ {print $1}' | sort -u | awk 'BEGIN{s=""}{printf "%s%s",s,$1;s=", "}')
# Keep the learned hosts during a routine core-guard pass. Compare with the
# active prefix list each time so a change of campus prefix also takes effect.
cache=/var/run/athena-lan6-return-prefixes
if $NFT list set ip6 athena_lan6_return campus >/dev/null 2>&1; then
 if [ ! -f "$cache" ] || [ "$(cat "$cache")" != "$prefixes" ]; then
  {
   echo 'flush set ip6 athena_lan6_return campus'
   if [ -n "$prefixes" ]; then echo "add element ip6 athena_lan6_return campus { $prefixes }"; fi
  } | $NFT -f -
 fi
else
 {
  echo 'table ip6 athena_lan6_return {'
  echo ' set campus { type ipv6_addr; flags interval;'
  if [ -n "$prefixes" ]; then echo " elements = { $prefixes };"; fi
  echo ' }'
  echo ' set clients { type ipv6_addr; flags dynamic,timeout; timeout 20m; size 256; }'
  echo ' chain remember { type filter hook forward priority 10; policy accept;'
  echo '  iifname "br-lan" oifname "rpwan1" ip6 saddr @campus ip6 saddr != @clients add @clients { ip6 saddr }'
  echo ' }'
  echo ' chain return_to_lan { type filter hook prerouting priority mangle; policy accept;'
  echo '  iifname "rpwan1" ct state established ct direction reply ip6 daddr @campus ip6 daddr @clients counter meta mark set meta mark | 0x40000000'
  echo ' }'
  echo '}'
 } | $NFT -f -
fi
if [ ! -f "$cache" ] || [ "$(cat "$cache")" != "$prefixes" ]; then
 printf '%s\n' "$prefixes" > "$cache.new" && mv "$cache.new" "$cache"
fi
