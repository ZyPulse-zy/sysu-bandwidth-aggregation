#!/bin/sh
set -eu
umask 077
ROOT=/root/router-project
valid() { case "$1" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac; }
uptime_s() { cut -d. -f1 /proc/uptime; }
event() { printf '%s uptime=%s %s\n' "$(date -u +%FT%TZ)" "$(uptime_s)" "$*" >> "$ROOT/logs/transactions.log"; }
rollback_locked() {
 [ -f "$ROOT/active-transaction" ] || return 0
 read -r id boot deadline < "$ROOT/active-transaction"
 valid "$id" || exit 4
 dir="$ROOT/transactions/$id"
 event "ROLLBACK_START $id"
 if (cd "$dir"; sha256sum -c undo.sha256 >/dev/null) && timeout 90 sh "$dir/undo.sh" > "$dir/rollback.log" 2>&1; then
  printf 'rolled-back\n' > "$dir/result"
  rm -f "$ROOT/active-transaction"
  event "ROLLBACK_OK $id"
 else
  printf 'rollback-failed\n' > "$dir/result"
  event "ROLLBACK_FAILED $id; will retry"
  return 1
 fi
 sync
}
cmd=${1:-status}
if [ "$cmd" = watch ]; then
 while :; do "$0" tick || true; sleep 2; done
fi
exec 9>/tmp/router-project-transaction.lock
flock -x 9
case "$cmd" in
 arm)
  id=$2; cp_id=$3; seconds=$4; undo=$5
  valid "$id" && valid "$cp_id" || exit 2
  case "$seconds" in ''|*[!0-9]*) exit 2;; esac
  [ "$seconds" -ge 8 ] && [ "$seconds" -le 1800 ] || exit 2
  [ ! -e "$ROOT/active-transaction" ] || { echo 'Another transaction is active' >&2; exit 3; }
  [ -f "$ROOT/backups/$cp_id/config.tar.gz" ]
  (cd "$ROOT/backups/$cp_id"; sha256sum -c SHA256SUMS >/dev/null)
  [ -r "$undo" ]; sh -n "$undo"
  ubus call service list '{"name":"router-project-guard"}' | jsonfilter -e '@["router-project-guard"].instances.guard.running' | grep -qx true
  dir="$ROOT/transactions/$id"
  mkdir "$dir"
  cp "$undo" "$dir/undo.sh"
  chmod 700 "$dir/undo.sh"
  (cd "$dir"; sha256sum undo.sh > undo.sha256)
  printf '%s\n' "$cp_id" > "$dir/checkpoint"
  printf 'armed\n' > "$dir/result"
  boot=$(cat /proc/sys/kernel/random/boot_id)
  deadline=$(( $(uptime_s) + seconds ))
  printf '%s %s %s\n' "$id" "$boot" "$deadline" > "$ROOT/active-transaction.new"
  mv "$ROOT/active-transaction.new" "$ROOT/active-transaction"
  event "ARMED $id checkpoint=$cp_id timeout=$seconds"
  sync
  echo "ARMED=$id"
  ;;
 commit)
  id=$2; valid "$id" || exit 2
  read -r active boot deadline < "$ROOT/active-transaction"
  [ "$active" = "$id" ]
  [ "$boot" = "$(cat /proc/sys/kernel/random/boot_id)" ]
  [ "$(uptime_s)" -lt "$deadline" ]
  # Only the deploying controller may commit after separate PC-to-LAN/SSH and stage-specific tests.
  [ -s "$ROOT/transactions/$id/verification.txt" ]
  printf 'committed\n' > "$ROOT/transactions/$id/result"
  rm -f "$ROOT/active-transaction"
  event "COMMIT $id"
  sync
  echo "COMMITTED=$id"
  ;;
 tick)
  if [ -f "$ROOT/active-transaction" ]; then
   read -r id boot deadline < "$ROOT/active-transaction"
   if [ "$boot" != "$(cat /proc/sys/kernel/random/boot_id)" ] || [ "$(uptime_s)" -ge "$deadline" ]; then rollback_locked; fi
  fi
  ;;
 rollback) rollback_locked;;
 status)
  if [ -f "$ROOT/active-transaction" ]; then cat "$ROOT/active-transaction"; else echo 'NO_ACTIVE_TRANSACTION'; fi
  ;;
 *) echo 'Usage: arm ID CHECKPOINT TIMEOUT UNDO_SCRIPT | commit ID | rollback | status | watch' >&2; exit 2;;
esac
