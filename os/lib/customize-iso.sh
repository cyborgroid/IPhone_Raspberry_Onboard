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
  umount "$ISO" 2>/dev/null
  loop_detach_all
  rm -rf "$WORK"
}
trap cleanup EXIT

rm -rf "$WORK"
mkdir -p "$MNT" "$UPPER" "$OVERLAY_WORK" "$ISO"
mount_ro "$BASE" "$ISO"

echo "==> finding the live layers"
GRUB_CFG=$ISO/boot/grub/grub.cfg
LIVE_LAYER=$(grep -oE 'layerfs-path=[^ ]+' "$GRUB_CFG" | head -1 | cut -d= -f2)
[ -n "$LIVE_LAYER" ] || { echo "no layerfs-path in grub.cfg" >&2; exit 1; }
NEW_LAYER=${LIVE_LAYER%.squashfs}.cyborgroid.squashfs
echo "live layer: $LIVE_LAYER, new layer: $NEW_LAYER"

# minimal.standard.live is stacked on minimal.standard, which is on minimal.
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
sed "s/layerfs-path=$LIVE_LAYER/layerfs-path=$NEW_LAYER/g" "$GRUB_CFG" > "$WORK/grub.cfg"
grep -q "layerfs-path=$NEW_LAYER" "$WORK/grub.cfg"
SUMS=$WORK/md5sum.txt
grep -v -E ' \./(boot/grub/grub\.cfg|casper/'"$NEW_LAYER"')$' "$ISO/md5sum.txt" > "$SUMS"
echo "$(md5sum < "$WORK/grub.cfg" | cut -d' ' -f1)  ./boot/grub/grub.cfg" >> "$SUMS"
echo "$(md5sum < "$LAYER_FILE" | cut -d' ' -f1)  ./casper/$NEW_LAYER" >> "$SUMS"
rm -f "$OUT"
xorriso -indev "$BASE" -outdev "$OUT" -boot_image any replay \
  -volid CYBORGROID \
  -map "$LAYER_FILE" "/casper/$NEW_LAYER" \
  -map "$WORK/grub.cfg" /boot/grub/grub.cfg \
  -map "$SUMS" /md5sum.txt

echo "==> done: $(du -h "$OUT" | cut -f1) $OUT"
