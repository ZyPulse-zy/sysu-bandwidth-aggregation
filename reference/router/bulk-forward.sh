#!/bin/sh
# Data WANs carry ordinary downloads. WAN6 retains CAKE on both directions.
# Flow admission runs after firewall forwarding and requires the actual NAT
# egress and the complete, unmodified direct-routing conntrack mark.
set -eu
root=/root/router-project
state=/var/run/athena-bulk-forward
table=athena_bulk_forward
mkdir -p "$state"
umask 077

# Use an unused priority and a private u32 node. Never delete another owner's
# rule if a device disappears and comes back with a different configuration.
filter() {
    op=$1; dev=$2; parent=$3; pref=$4; direction=$5; port=$6; priority=$7
    rows=$(tc filter show dev "$dev" parent "$parent" protocol ip pref "$pref") || return 1
    own=$(printf '%s\n' "$rows" | awk '/fh [[:xdigit:]]+::a6 /{for(i=1;i<=NF;i++)if($i=="fh")print $(i+1)}')
    if [ "$op" = remove ]; then
        [ -z "$own" ] || tc filter del dev "$dev" parent "$parent" protocol ip pref "$pref" handle "$own" u32
        return
    fi
    [ -z "$own" ] || return 0
    case "$rows" in *terminal*|*'matchall '*|*'flower '*) return 1;; esac
    if [ "$priority" = pass ]; then set -- action pass
    else set -- action skbedit priority "$priority" pass; fi
    tc filter add dev "$dev" parent "$parent" protocol ip pref "$pref" handle ::a6 u32 \
        match u8 0x45 0xff at 0 match u16 0 0x3fff at 6 \
        match ip protocol 6 0xff match ip "$direction" "$port" 0xffff "$@"
}
filters() {
    op=$1
    for n in 1 2 3 4 5; do
        [ -e "/sys/class/net/rpwan$n" ] || continue
        for port in 443 80; do
            pref=6; [ "$port" = 443 ] || pref=7
            filter "$op" "rpwan$n" ffff: "$pref" sport "$port" pass || return 1
        done
    done
    for dev in rpifb6 rpwan6; do
        [ -e "/sys/class/net/$dev" ] || continue
        if [ "$dev" = rpifb6 ]; then parent=8062:; direction=sport; else parent=8061:; direction=dport; fi
        for port in 443 80; do
            pref=40890; [ "$port" = 443 ] || pref=40891
            filter "$op" "$dev" "$parent" "$pref" "$direction" "$port" "${parent}1" || return 1
        done
    done
}
# Older versions lent WAN6 to matching CDN connections. Remove the old
# admission rule before starting the five-WAN policy on an upgraded device.
clear_legacy_loan() {
    handles=$(nft -a list chain inet rp_pbr choose 2>/dev/null |
        awk '/comment "athena-bulk-spare"/ && $(NF-1)=="handle"{print $NF}')
    for handle in $handles; do nft delete rule inet rp_pbr choose handle "$handle" || return 1; done
    if nft list set inet rp_pbr athena_bulk_ready >/dev/null 2>&1; then
        nft delete set inet rp_pbr athena_bulk_ready || return 1
    fi
}
# Traffic on a data WAN only needs download headroom while there is a
# sustained interactive flow on it. Use a separate IFB so the normal
# autorate daemon retains sole ownership of its six production CAKE rates.
fallback_table=athena_game_fallback
fallback_monitor() {
    if nft list set inet "$fallback_table" active >/dev/null 2>&1; then return 0; fi
    nft -f - <<'NFT'
table inet athena_game_fallback {
    set active { type ifname; flags dynamic,timeout; timeout 25s; size 6; }
    chain interactive {
        type filter hook forward priority 9; policy accept;
        iifname != "br-lan" return
        oifname != { "rpwan1","rpwan2","rpwan3","rpwan4","rpwan5","rpwan6" } return
        ct direction != original return
        # A download ACK or brief peer-discovery burst must not cap a whole WAN.
        # Shared web UDP has no first-packet application identity.
        meta l4proto udp ct original avgpkt > 320 return
        meta l4proto udp udp dport 443 ct reply packets < 8 return
        meta l4proto udp udp dport 443 ct reply avgpkt > 300 return
        meta l4proto udp ct reply packets >= 8 ct reply avgpkt > 850 return
        meta l4proto udp udp dport != { 53,67,68,123,137,138,1900,5353,5355 } ct original packets >= 10 meta length <= 768 meter udp_cadence size 4096 { ct id timeout 8s limit rate over 10/second burst 12 packets } update @active { oifname timeout 25s }
        meta l4proto tcp tcp dport != { 22,53,80,443,853 } ct original packets >= 12 ct reply packets >= 3 ct original avgpkt < 600 ct reply avgpkt < 850 meter tcp_cadence size 4096 { ct id timeout 8s limit rate over 4/second burst 8 packets } update @active { oifname timeout 25s }
    }
}
NFT
}
protect_device() {
    pd_name=$1
    if [ ! -d "/sys/class/net/$pd_name" ]; then
        ip link add "$pd_name" type ifb || return 1
        ip link set "$pd_name" alias athena-game-fallback || { ip link del "$pd_name"; return 1; }
    fi
    [ "$(cat "/sys/class/net/$pd_name/ifalias")" = athena-game-fallback ] || return 1
    if ! tc qdisc show dev "$pd_name" | grep -q '^qdisc cake 35a0: .*bandwidth 35Mbit'; then
        tc qdisc replace dev "$pd_name" root handle 35a0: cake bandwidth 35Mbit diffserv4 flows ingress no-split-gso overhead 38 mpu 84 || return 1
    fi
    ip link set "$pd_name" up
}
protect_filter() {
    pf_op=$1; pf_dev=$2; pf_ifb=$3; pf_proto=$4; pf_pref=$5
    pf_rows=$(tc filter show dev "$pf_dev" parent ffff: protocol "$pf_proto" pref "$pf_pref") || return 1
    pf_own=$(printf '%s\n' "$pf_rows" | awk '/fh [[:xdigit:]]+::ad /{for(i=1;i<=NF;i++)if($i=="fh")print $(i+1)}')
    if [ -n "$pf_own" ]; then
        printf '%s\n' "$pf_rows" | grep -Fq "Redirect to device $pf_ifb)" || return 1
        [ "$pf_op" = add ] || tc filter del dev "$pf_dev" parent ffff: protocol "$pf_proto" pref "$pf_pref" handle "$pf_own" u32
    elif [ "$pf_op" = add ]; then
        case "$pf_rows" in *terminal*|*'matchall '*|*'flower '*) return 1;; esac
        tc filter add dev "$pf_dev" parent ffff: protocol "$pf_proto" pref "$pf_pref" handle ::ad u32 match u32 0 0 action mirred egress redirect dev "$pf_ifb"
    fi
}
fallback_sync() {
    fs_entries=$(nft list set inet "$fallback_table" active) || return 1
    fs_gate=$(nft list set inet rp_pbr athena_wan6_generic_ready 2>/dev/null) || fs_gate=''
    # An ongoing game on WAN6 needs a ready backup before its next connection.
    # Follow the same healthy ordering as the first-packet routing rules.
    fs_standby=no
    case "$fs_gate" in
        '') ;;
        *'udp expires'*) case "$fs_entries" in *'"rpwan6"'*) fs_standby=yes;; esac;;
        *) fs_standby=yes;;
    esac
    if [ "$fs_standby" = yes ]; then
        fs_healthy=$(nft list set inet rp_pbr healthy) || return 1
        for fs_i in 5 4 3 2 1; do
            case "$fs_healthy" in *"0x000${fs_i}0000"*) fs_entries="$fs_entries \"rpwan$fs_i\""; break;; esac
        done
    fi
    fs_wanted=''
    for fs_i in 1 2 3 4 5; do
        case "$fs_entries" in *\"rpwan$fs_i\"*) fs_wanted="$fs_wanted $fs_i ";; esac
    done
    if [ "$1" != verify ] && [ "$fs_wanted" = "${last_fallback-unset}" ]; then return 0; fi
    for fs_i in 1 2 3 4 5; do
        fs_dev="rpwan$fs_i"; fs_ifb="agameifb$fs_i"
        [ -e "/sys/class/net/$fs_dev" ] || continue
        case "$fs_wanted" in *" $fs_i "*) fs_op=add; protect_device "$fs_ifb" || return 1;;
            *) fs_op=remove; [ -e "/sys/class/net/$fs_ifb" ] || continue;; esac
        protect_filter "$fs_op" "$fs_dev" "$fs_ifb" ip 4 || return 1
        protect_filter "$fs_op" "$fs_dev" "$fs_ifb" ipv6 5 || return 1
    done
    last_fallback=$fs_wanted
}
fallback_stop() {
    for fd_i in 1 2 3 4 5; do
        fd_ifb="agameifb$fd_i"; fd_dev="rpwan$fd_i"
        [ -d "/sys/class/net/$fd_ifb" ] || continue
        [ "$(cat "/sys/class/net/$fd_ifb/ifalias")" = athena-game-fallback ] || continue
        if [ -e "/sys/class/net/$fd_dev" ]; then
            protect_filter remove "$fd_dev" "$fd_ifb" ip 4 || return 1
            protect_filter remove "$fd_dev" "$fd_ifb" ipv6 5 || return 1
        fi
        ip link del "$fd_ifb" || return 1
    done
    if nft list table inet "$fallback_table" >/dev/null 2>&1; then nft delete table inet "$fallback_table" || return 1; fi
    unset last_fallback
}

withdraw() (
    exec 8>"$state/withdraw.lock"
    flock -x 8 || return 1
    fallback_stop || return 1
    if nft list table inet "$table" >/dev/null 2>&1; then nft delete table inet "$table" || return 1; fi
    filters remove
    rm -f "$state/current" "$state/game-state" "$state/game-next" "$state/lend.nft"
)
ready() {
    [ -f "$root/policy/software-qos.enabled" ] && [ ! -d /sys/module/athena_ecm_gate ] &&
        [ "$(cat /sys/kernel/debug/ecm/front_end_ipv4_stop)" = 1 ] &&
        [ "$(cat /sys/kernel/debug/ecm/front_end_ipv6_stop)" = 1 ]
}
snapshot() {
    [ -d /sys/class/net/br-lan/brif ] || return 1
    network=$(ip -o -4 route show dev br-lan scope link | awk '$1 ~ /\//{print $1;exit}')
    [ "$network" = 192.168.50.0/24 ] || return 1
    printf 'lan %s %s\n' "$network" "$(cat /sys/class/net/br-lan/ifindex)"
    brctl showmacs br-lan | awk '$3=="no"{print "attachment", $1, $2}' | sort -u
    for f in /sys/class/net/br-lan/brif/*; do
        name=${f##*/}; case "$name" in *[!a-zA-Z0-9_-]*|'') return 1;; esac
        [ -e "/sys/class/net/$name/ifindex" ] || continue
        printf 'port %s %s\n' "$name" "$(cat "/sys/class/net/$name/ifindex")"
    done
    for n in 1 2 3 4 5; do
        dev=rpwan$n; [ -e "/sys/class/net/$dev/ifindex" ] || continue
        gateway=$(ip -4 route show table "$((100+n))" default | awk -v d="$dev" '$1=="default" && $2=="via" && $4=="dev" && $5==d {print $3;exit}')
        address=$(ip -o -4 addr show dev "$dev" scope global | awk 'NR==1{print $4}')
        [ -n "$gateway" ] && [ -n "$address" ] || continue
        printf 'wan %s %s %s %s %s\n' "$n" "$(cat "/sys/class/net/$dev/ifindex")" "$gateway" "$address" "$(cat "/sys/class/net/$dev/address")"
    done
}
forwarding() {
    snapshot > "$state/next" || return 1
    grep -q '^wan ' "$state/next" || return 1
    if cmp -s "$state/current" "$state/next" && nft list flowtable inet "$table" bulk >/dev/null 2>&1; then return 0; fi
    {
        if nft list table inet "$table" >/dev/null 2>&1; then echo "delete table inet $table"; fi
        echo "table inet $table {"
        echo 'flowtable bulk { hook ingress priority 0;'
        awk 'BEGIN{printf "devices = { \"br-lan\""} $1=="port"{printf ", \"%s\"",$2} $1=="wan"{printf ", \"rpwan%d\"",$2} END{print " }; counter; }"}' "$state/next"
        # At campus off-peak rates the five macvlans can fill their shared
        # gigabit port. Leave return-path headroom before TCP enters the
        # software flowtable. All data WANs share a single token bucket.
        echo 'counter download_seen { }'
        echo 'counter download_over { }'
        echo 'chain wire_downloads { type filter hook ingress device "wan" priority -500; policy accept;'
        awk '$1=="wan"{printf "%s%s",count++ ? ", " : "ether daddr { ",$6} END{print " } meta l4proto tcp tcp sport { 80, 443 } counter name download_seen limit rate over 70 mbytes/second burst 384 kbytes counter name download_over drop"; print "}"}' "$state/next"
        echo 'counter game_udp { }'
        echo 'chain qualified { type filter hook forward priority 10; policy accept;'
        echo 'meta nfproto ipv4 meta l4proto udp ct mark & 0x00ff0000 == 0x00060000 counter name game_udp'
        awk '$1=="wan"{printf "iifname \"br-lan\" oifname \"rpwan%d\" ip saddr 192.168.50.0/24 tcp dport { 80, 443 } ct direction original ct state established ct status assured ct mark %d counter flow add @bulk\n",$2,65536*$2}' "$state/next"
        echo '}'; echo '}'
    } > "$state/forward.nft"
    nft -f "$state/forward.nft" && mv "$state/next" "$state/current"
}
main() {
    case "$1" in
        stop) clear_legacy_loan && withdraw;;
        once)
            clear_legacy_loan && ready && forwarding && filters install && fallback_monitor && fallback_sync verify;;
        watch)
            clear_legacy_loan || return 1
            trap 'exit 0' TERM INT
            trap 'withdraw' EXIT
            while :; do
                if ! ready || ! forwarding || ! filters install || ! fallback_monitor || ! fallback_sync verify; then
                    withdraw || logger -t athena-bulk 'Inspect fallback cleanup'
                    sleep 4
                    continue
                fi
                for tick in 1 2 3 4; do
                    sleep 1
                    fallback_sync changed || break
                done
            done;;
        *) return 2;;
    esac
}
main "${1:-once}"
