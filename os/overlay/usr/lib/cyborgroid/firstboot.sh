#!/usr/bin/env bash
# Runs on every boot, before networking. Grows the root filesystem once, and
# imports anything left on the FAT boot partition, which the owner can write to
# from any computer. Imported secrets are removed from there, since FAT has no
# permissions.
set -uo pipefail

SEED=/boot/firmware/cyborgroid
STATE=/var/lib/cyborgroid-firstboot
OWNER=cyborg
mkdir -p "$STATE"

if [ ! -e "$STATE/grown" ]; then
  # /boot/firmware may not be mounted yet this early in boot; / always is.
  root_part=$(findmnt -no SOURCE /)
  disk=$(lsblk -no PKNAME "$root_part")
  partnum=$(cat "/sys/class/block/$(basename "$root_part")/partition")
  if [ -n "$disk" ] && [ -n "$partnum" ]; then
    growpart "/dev/$disk" "$partnum" || true
    resize2fs "$root_part" || true
  fi
  touch "$STATE/grown"
fi

if [ ! -e "$STATE/identity" ]; then
  [ -s /etc/machine-id ] || systemd-machine-id-setup
  ssh-keygen -A
  # A per-device password instead of a default shared by every image. Sudo is
  # the only thing it unlocks; SSH stays off unless a key is seeded below.
  password=$(tr -dc 'a-km-np-z2-9' </dev/urandom | head -c 12)
  echo "$OWNER:$password" | chpasswd
  install -m 600 -o "$OWNER" -g "$OWNER" /dev/null "/home/$OWNER/initial-password.txt"
  printf '%s\n' "$password" >"/home/$OWNER/initial-password.txt"
  touch "$STATE/identity"
fi

mountpoint -q /boot/firmware || mount /boot/firmware 2>/dev/null
[ -d "$SEED" ] || exit 0

if [ -f "$SEED/wg0.conf" ]; then
  install -D -m 600 "$SEED/wg0.conf" /etc/wireguard/wg0.conf && rm -f "$SEED/wg0.conf"
fi
for conn in "$SEED"/*.nmconnection; do
  [ -f "$conn" ] || continue
  install -D -m 600 "$conn" "/etc/NetworkManager/system-connections/$(basename "$conn")" && rm -f "$conn"
done
if [ -f "$SEED/authorized_keys" ]; then
  install -d -m 700 -o "$OWNER" -g "$OWNER" "/home/$OWNER/.ssh"
  install -m 600 -o "$OWNER" -g "$OWNER" "$SEED/authorized_keys" "/home/$OWNER/.ssh/authorized_keys"
  rm -f "$SEED/authorized_keys"
  systemctl enable ssh.socket 2>/dev/null || systemctl enable ssh.service
fi
exit 0
