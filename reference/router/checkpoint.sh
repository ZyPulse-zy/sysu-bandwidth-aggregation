#!/bin/sh
set -eu
umask 077
ROOT=/root/router-project
label=${1:-manual}
case "$label" in ''|*[!a-zA-Z0-9_-]*) echo 'Invalid checkpoint label' >&2; exit 2;; esac
id="$(date -u +%Y%m%dT%H%M%SZ)-$(cut -d. -f1 /proc/uptime)-$label"
dest="$ROOT/backups/$id"
mkdir -p "$dest"
capture() {
 name=$1; shift
 if "$@" > "$dest/$name" 2> "$dest/$name.stderr"; then
  printf '%s OK\n' "$name" >> "$dest/capture-status.txt"
 else
  printf '%s UNAVAILABLE_OR_FAILED\n' "$name" >> "$dest/capture-status.txt"
 fi
}
capture board.json ubus call system board
capture addresses.json ip -j address show
capture links.json ip -j -d link show
capture rules4.json ip -j -4 rule show
capture rules6.json ip -j -6 rule show
capture routes4.json ip -j -4 route show table all
capture routes6.json ip -j -6 route show table all
capture nftables.nft nft list ruleset
capture nftables.json nft -j list ruleset
capture qdisc.json tc -j -s qdisc show
capture packages.txt apk info -v
capture package-world.txt cat /etc/apk/world
capture modules.txt lsmod
capture wireless.sha256 sha256sum /etc/config/wireless
capture uptime.txt cat /proc/uptime
capture boot-id.txt cat /proc/sys/kernel/random/boot_id
: > "$dest/paths.txt"
: > "$dest/absent-paths.txt"
for p in etc/config etc/minieap etc/minieap.conf etc/openclash etc/mihomo etc/nftables.d etc/firewall.d etc/iproute2 etc/hotplug.d etc/rc.local etc/init.d etc/rc.d etc/sysctl.d etc/modules.conf root/router-project/STATE.md root/router-project/CHANGELOG.md root/router-project/scripts root/router-project/policy root/router-project/manifests root/router-project/modules root/router-project/vendor; do
 if [ -e "/$p" ]; then printf '%s\n' "$p" >> "$dest/paths.txt"; else printf '%s\n' "$p" >> "$dest/absent-paths.txt"; fi
done
tar -czf "$dest/config.tar.gz" -C / -T "$dest/paths.txt"
gzip -t "$dest/config.tar.gz"
(cd "$dest"; sha256sum config.tar.gz > SHA256SUMS; sha256sum -c SHA256SUMS)
printf '%s\n' "$id" > "$ROOT/latest-checkpoint"
sync
printf 'CHECKPOINT=%s\n' "$id"
printf 'CONFIDENTIAL=yes\n'
