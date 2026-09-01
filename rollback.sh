#!/usr/bin/env bash
# Streamlined rollback of the target to its clean pre-setup btrfs snapshot.
# Run as root (or via sudo). ONE shot: mount -> root swap -> /home reset -> verify -> reboot.
# Usage: rollback.sh                (assumes the clean backup is @.dirty/.snapshots/1/snapshot)
#        ROLLBACK_SRC=DIR rollback.sh   (override the clean snapshot source)
#
# What it does (round 2+ uses fresh names so round-1 artifacts are preserved):
#   1. mount top-level btrfs (subvolid=5) at /mnt/top
#   2. safety snapshot of current dirty root -> @.pre_rollback<N>
#   3. move current root aside                    -> @.dirty<N>
#   4. snapshot the CLEAN backup into a new @     (clean root)
#   5. verify new @ has no setup binaries
#   6. reset /home to pristine (preserving noctalia configs to /tmp/opencode/home-preserve)
#   7. umount, reboot
set -euo pipefail

DEV=/dev/nvme0n1p2
TOP=/mnt/top
DISK_SYS=@
SNAP_SRC="${ROLLBACK_SRC:-/mnt/top/@.dirty/.snapshots/1/snapshot}"
ARCH="x86_64"
SETUP_BINS="labwc mango greetd noctalia-greeter-session agreety"

[ "$(id -u)" -eq 0 ] || { echo "must run as root (sudo)"; exit 1; }
[ -e "$DEV" ] || { echo "device $DEV not found"; exit 1; }

N=1
while btrfs subvolume list "$TOP" 2>/dev/null | grep -qE "@\.pre_rollback$N|@\.dirty$N"; do N=$((N+1)); done
DIRTY="@.dirty$N"
PRE="@.pre_rollback$N"

echo "== round $N: PRE=$PRE DIRTY=$DIRTY =="

mountpoint -q "$TOP" || { mkdir -p "$TOP"; mount -t btrfs -o subvolid=5,compress=zstd:3 "$DEV" "$TOP"; }
trap 'umount "$TOP" 2>/dev/null || true' EXIT

echo "== 1/7 safety snapshot: $PRE =="
btrfs subvolume snapshot -r "$TOP/$DISK_SYS" "$TOP/$PRE"

echo "== 2/7 move current root aside: $DIRTY =="
mv "$TOP/$DISK_SYS" "$TOP/$DIRTY"

echo "== 3/7 restore clean backup -> new $DISK_SYS =="
[ -d "$SNAP_SRC" ] || { echo "clean source missing: $SNAP_SRC"; exit 1; }
btrfs subvolume snapshot "$SNAP_SRC" "$TOP/$DISK_SYS"

echo "== 4/7 verify new root is clean =="
found=""
for b in $SETUP_BINS; do [ -e "$TOP/$DISK_SYS/usr/bin/$b" ] && found="$found $b"; done
[ -z "$found" ] || { echo "new root NOT clean, has:$found — aborting, no reboot"; exit 1; }
[ -e "$TOP/$DISK_SYS/etc/greetd" ] && { echo "new root has /etc/greetd — aborting"; exit 1; }
btrfs subvolume show "$TOP/$DISK_SYS" | grep -E "^	Subvolume ID"

echo "== 5/7 reset /home to pristine (preserving noctalia cfg) =="
PRESERVE=/tmp/opencode/home-preserve
rm -rf "$PRESERVE"; mkdir -p "$PRESERVE"
[ -d /home/salva/.config/noctalia ]      && cp -a /home/salva/.config/noctalia      "$PRESERVE/"
[ -d /home/salva/.local/state/noctalia ] && cp -a /home/salva/.local/state/noctalia "$PRESERVE/"
[ -d /home/salva/Pictures ]              && cp -a /home/salva/Pictures              "$PRESERVE/"
[ -d /home/salva/Videos ]                && cp -a /home/salva/Videos                "$PRESERVE/"
[ -d /home/salva/.config/labwc ]         && cp -a /home/salva/.config/labwc         "$PRESERVE/"
rm -rf /home/salva/.config /home/salva/.local /home/salva/.cache /home/salva/.dotarch-backup-* \
       /home/salva/Desktop /home/salva/Documents /home/salva/Downloads /home/salva/Music \
       /home/salva/Pictures /home/salva/Projects /home/salva/Public /home/salva/Templates \
       /home/salva/Videos /home/salva/.bash_history
[ "$(ls -A /home/salva)" = ".bash_logout .bash_profile .bashrc" ] || echo "WARN: /home not pristine: $(ls -A /home/salva)"

echo "== 6/7 umount =="
umount "$TOP"

echo "== 7/7 rebooting into clean root =="
reboot