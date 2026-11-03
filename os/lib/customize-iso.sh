#!/usr/bin/env bash
# Runs in the privileged builder container. Adds Cyborgroid to the official desktop
# ISO as one more squashfs layer on top of its live layers. The official layers,
# kernel and signed boot chain stay byte-identical.
#   customize-iso.sh <base.iso> <output.iso> <core binary> <shell publish dir> <work dir>
set -euo pipefail
shopt -s inherit_errexit

BASE=$1 OUT=$2 CORE=$3 SHELL_DIR=$4 WORK=$5
HERE=$(dirname "$(readlink -f "$0")")
OS_DIR=$(dirname "$HERE")
# shellcheck source=loop.sh
. "$HERE/loop.sh"
# shellcheck source=payload.sh
. "$HERE/payload.sh"

MNT=$WORK/root UPPER=$WORK/upper OVERLAY_WORK=$WORK/overlay-work ISO=$WORK/iso
LOWER_MOUNTS=()

mount_ro() { # file dir
  loop_attach "$1" 0 "$(stat -c %s "$1")"
  mount -o ro "$LOOP_DEV" "$2"
}

cleanup() {
  set +e
  umount -R "$MNT" 2>/dev/null
  for m in "${LOWER_MOUNTS[@]}"; do umount "$m" 2>/dev/null; done
  # Before the ISO: the layers' loop devices keep files on it open.
  loop_detach_all
  umount "$ISO" 2>/dev/null
  # $MNT binds the real /dev and /sys, so never delete past a mount that is still there.
  if findmnt -rn -o TARGET | grep -q "^$WORK/"; then
    echo "still mounted, leaving $WORK in place:" >&2
    findmnt -rn -o TARGET | grep "^$WORK/" >&2
  else
    rm -rf --one-file-system "$WORK"
  fi
}
trap cleanup EXIT

rm -rf --one-file-system "$WORK"
mkdir -p "$MNT" "$UPPER" "$OVERLAY_WORK" "$ISO"
mount_ro "$BASE" "$ISO"

# The name is the stack: casper mounts minimal.standard.live.cyborgroid on top of the
# parents it finds by dropping one dotted part at a time.
LIVE_LAYER=minimal.standard.live.squashfs
NEW_LAYER=${LIVE_LAYER%.squashfs}.cyborgroid.squashfs
[ -f "$ISO/casper/$LIVE_LAYER" ] || { echo "no $LIVE_LAYER in the ISO" >&2; exit 1; }

LOWER=""
name=${LIVE_LAYER%.squashfs}
while :; do
  m=$WORK/lower-$name
  mkdir -p "$m"
  mount_ro "$ISO/casper/$name.squashfs" "$m"
  LOWER_MOUNTS+=("$m")
  LOWER=${LOWER:+$LOWER:}$m
  [ "$name" = "${name%.*}" ] && break
  name=${name%.*}
done
mount -t overlay overlay -o "lowerdir=$LOWER,upperdir=$UPPER,workdir=$OVERLAY_WORK" "$MNT"
for fs in proc sys dev dev/pts; do mount --rbind "/$fs" "$MNT/$fs"; done

echo "==> copying payload"
copy_payload "$MNT" "$OS_DIR" "$CORE" "$SHELL_DIR"
tar -C "$OS_DIR/iso-overlay" --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w' -cf - . \
  | tar -C "$MNT" --no-overwrite-dir -xf -

# Points at the installer's package pool on the boot medium, absent in this chroot.
rm -f "$MNT/etc/apt/sources.list.d/cdrom.sources"

RESOLV_LINK=$(readlink "$MNT/etc/resolv.conf" || true)
rm -f "$MNT/etc/resolv.conf"
cp /etc/resolv.conf "$MNT/etc/resolv.conf"

echo "==> installing packages"
chroot "$MNT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
  bash /tmp/cyborgroid/chroot-setup.sh

rm -f "$MNT/etc/resolv.conf"
[ -n "$RESOLV_LINK" ] && ln -s "$RESOLV_LINK" "$MNT/etc/resolv.conf"
umount -R "$MNT"

echo "==> packing the layer"
LAYER_FILE=$WORK/$NEW_LAYER
mksquashfs "$UPPER" "$LAYER_FILE" -comp zstd -noappend -quiet

echo "==> writing the ISO"
SUMS=$WORK/md5sum.txt
grep -v -E ' \./(boot/grub/(grub|loopback)\.cfg)$' "$ISO/md5sum.txt" > "$SUMS"
for cfg in grub loopback; do
  sed -E "s#^(\s*linux\s+/casper/vmlinuz)#\1 layerfs-path=$NEW_LAYER#" "$ISO/boot/grub/$cfg.cfg" > "$WORK/$cfg.cfg"
  grep -q "layerfs-path=$NEW_LAYER" "$WORK/$cfg.cfg"
  echo "$(md5sum < "$WORK/$cfg.cfg" | cut -d' ' -f1)  ./boot/grub/$cfg.cfg" >> "$SUMS"
done
echo "$(md5sum < "$LAYER_FILE" | cut -d' ' -f1)  ./casper/$NEW_LAYER" >> "$SUMS"
rm -f "$OUT"
xorriso -indev "$BASE" -outdev "$OUT" -boot_image any replay \
  -volid CYBORGROID \
  -map "$LAYER_FILE" "/casper/$NEW_LAYER" \
  -map "$WORK/grub.cfg" /boot/grub/grub.cfg \
  -map "$WORK/loopback.cfg" /boot/grub/loopback.cfg \
  -map "$SUMS" /md5sum.txt

echo "==> done: $(du -h "$OUT" | cut -f1) $OUT"
