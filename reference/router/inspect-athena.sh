#!/bin/sh
# Read-only check. Report interfaces, rules and rates without printing addresses.
set -eu

routes=$(ip -4 rule show)
buckets=$(nft list map inet rp_pbr buckets)
printf '%-6s %-8s %-7s %-9s %-10s %-10s\n' WAN Carrier Rule Buckets Upload Download

cake_rate() {
    tc qdisc show dev "$1" 2>/dev/null | awk '
        $2 == "cake" && / root / {
            for (i = 1; i < NF; i++) if ($i == "bandwidth") { print $(i + 1); exit }
        }'
}

for n in 1 2 3 4 5 6; do
    carrier=$(cat "/sys/class/net/rpwan$n/carrier" 2>/dev/null || true)
    mark=$(printf '0x%x/0xff0000' "$((n * 65536))")
    table=$((100 + n))
    rule=$(printf '%s\n' "$routes" | awk -v mark="$mark" -v table="$table" '
        $0 ~ "fwmark " mark " " && $0 ~ "lookup " table "$" { print "yes"; exit }')
    count=$(printf '%s\n' "$buckets" | awk -v n="$n" '
        { total += gsub("jump mark_w" n "([^0-9]|$)", "") }
        END { print total + 0 }')
    up=$(cake_rate "rpwan$n")
    down=$(cake_rate "rpifb$n")
    printf '%-6s %-8s %-7s %-9s %-10s %-10s\n' \
        "$n" "${carrier:-missing}" "${rule:-missing}" "$count" "${up:-missing}" "${down:-missing}"
done

for spec in 'inet athena_bulk_forward' 'inet athena_game_fallback' \
            'ip6 athena_lan6_return' 'inet rp_singbox' \
            'bridge rp_wifi_qos' 'bridge rp_wifi_steer_guard'; do
    set -- $spec
    if nft list table "$1" "$2" >/dev/null 2>&1; then
        printf '%s present\n' "$2"
    else
        printf '%s absent\n' "$2"
    fi
done
