#!/usr/bin/env bash
# Adds the built ISO to this PC's GRUB menu, booted from a file on an existing
# partition. No partition is changed and the default boot entry stays as it is.
#
#   os/register-boot.sh            register the newest build/cyborgroid-amd64-*.iso
#   os/register-boot.sh --print    show the menu entry and check it, changing nothing
#   os/register-boot.sh --remove   take the entry out of the menu again
#
# Only the live system runs from it: changes are lost at power-off.
set -euo pipefail

ROOT=$(dirname "$(dirname "$(readlink -f "$0")")")
ENTRY=/etc/grub.d/42_cyborgroid
OWNER=${SUDO_USER:-$(id -un)}
ISO_DIR=$(getent passwd "$OWNER" | cut -d: -f6)/iso
ISO_FILE=$ISO_DIR/cyborgroid-amd64.iso
MODE=${1:-register}

case "$MODE" in
  register|--remove) [ "$EUID" -eq 0 ] || exec sudo "$0" "$@" ;;
  --print) ;;
  *) echo "usage: $0 [--print | --remove]" >&2; exit 2 ;;
esac

if [ "$MODE" = --remove ]; then
  rm -f "$ENTRY"
  update-grub
  echo "메뉴에서 뺐습니다. ISO 파일은 $ISO_FILE 에 그대로 있습니다."
  exit 0
fi

SOURCE=$(ls -t "$ROOT"/build/cyborgroid-amd64-*.iso 2>/dev/null | head -1 || true)
[ -n "$SOURCE" ] || { echo "build/ 에 ISO가 없습니다. 먼저 os/build-iso.sh 를 실행하세요." >&2; exit 1; }

# GRUB has to read this partition by itself, before any OS has started.
FSTYPE=$(findmnt -no FSTYPE -T "$(dirname "$ISO_DIR")")
case "$FSTYPE" in
  ext2|ext3|ext4|vfat|exfat|ntfs) ;;
  *) echo "GRUB가 읽기 어려운 파일 시스템입니다: $FSTYPE" >&2; exit 1 ;;
esac
FS_UUID=$(findmnt -no UUID -T "$(dirname "$ISO_DIR")")
MOUNT=$(findmnt -no TARGET -T "$(dirname "$ISO_DIR")")
GRUB_PATH=${ISO_FILE#"${MOUNT%/}"}

# The kernel path and options come from the ISO's own first menu entry.
BOOT_LINE=$(xorriso -osirrox on -indev "$SOURCE" -extract /boot/grub/grub.cfg /dev/stdout 2>/dev/null \
  | grep -m1 -E '^\s*linux\s' || true)
if [ -z "$BOOT_LINE" ]; then
  TMP_CFG=$(mktemp)
  LANG=C isoinfo -R -i "$SOURCE" -x /boot/grub/grub.cfg > "$TMP_CFG"
  BOOT_LINE=$(grep -m1 -E '^\s*linux\s' "$TMP_CFG")
  rm -f "$TMP_CFG"
fi
read -r _ KERNEL OPTIONS <<<"$BOOT_LINE"
INITRD=${KERNEL%/*}/initrd

ENTRY_TEXT=$(cat <<GRUB
menuentry 'Cyborgroid (Live ISO)' {
    insmod part_gpt
    insmod ext2
    insmod loopback
    insmod iso9660
    search --no-floppy --fs-uuid --set=root $FS_UUID
    set isofile=$GRUB_PATH
    loopback loop \$isofile
    linux (loop)$KERNEL iso-scan/filename=\$isofile $OPTIONS
    initrd (loop)$INITRD
}
GRUB
)

CHECK=$(mktemp)
printf '%s\n' "$ENTRY_TEXT" > "$CHECK"
grub-script-check "$CHECK"
rm -f "$CHECK"

if [ "$MODE" = --print ]; then
  printf '%s\n' "$ENTRY_TEXT"
  exit 0
fi

install -d -o "$OWNER" -g "$(id -gn "$OWNER")" "$ISO_DIR"
install -o "$OWNER" -g "$(id -gn "$OWNER")" -m 644 "$SOURCE" "$ISO_FILE"
{
  printf '#!/bin/sh\nexec tail -n +3 $0\n'
  printf '%s\n' "$ENTRY_TEXT"
} > "$ENTRY"
chmod 755 "$ENTRY"
update-grub
echo "등록했습니다. 재부팅 때 GRUB 메뉴에서 'Cyborgroid (Live ISO)'를 고르세요. 기본 부팅은 그대로입니다."
