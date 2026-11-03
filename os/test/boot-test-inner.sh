#!/usr/bin/env bash
# Container half of boot-test.sh.
set -euo pipefail
shopt -s inherit_errexit

# shellcheck source=../lib/loop.sh
. /os/lib/loop.sh
WORK=$(mktemp -d)
MNT=$(mktemp -d)
cleanup() {
  set +e
  umount -R "$MNT" 2>/dev/null
  loop_detach_all
  pkill qemu-system 2>/dev/null
}
trap cleanup EXIT

echo "==> making a disposable copy"
cp --sparse=always /image.img "$WORK/disk.img"
read -r ROOT_OFF ROOT_SIZE < <(part_bytes "$WORK/disk.img" 2)
loop_attach "$WORK/disk.img" "$ROOT_OFF" "$ROOT_SIZE"
mount "$LOOP_DEV" "$MNT"
cp -L "$MNT/boot/vmlinuz" "$WORK/vmlinuz"
cp -L "$MNT/boot/initrd.img" "$WORK/initrd.img"

# Test-only probe, in the disposable copy: reports over the serial port, because
# the shipped image deliberately has no login that the test could use.
cp /os/test/boot-probe.sh "$MNT/usr/local/sbin/boot-probe.sh"
chmod +x "$MNT/usr/local/sbin/boot-probe.sh"
cat > "$MNT/etc/systemd/system/boot-probe.service" <<'UNIT'
[Unit]
Description=Boot test probe
After=cyborgroid-session.service
[Service]
Type=oneshot
StandardOutput=file:/dev/ttyAMA0
StandardError=file:/dev/ttyAMA0
ExecStart=/usr/local/sbin/boot-probe.sh
[Install]
WantedBy=graphical.target
UNIT
ln -sf /etc/systemd/system/boot-probe.service "$MNT/etc/systemd/system/graphical.target.wants/boot-probe.service"
# A getty on the same port hangs up the probe's open file, losing all its output.
ln -sf /dev/null "$MNT/etc/systemd/system/serial-getty@ttyAMA0.service"
umount "$MNT"
if [ -n "${SEED_WG:-}" ]; then
  # 10.0.2.2 is QEMU's host side: reachable, but no peer answers there.
  read -r BOOT_OFF BOOT_SIZE < <(part_bytes "$WORK/disk.img" 1)
  loop_attach "$WORK/disk.img" "$BOOT_OFF" "$BOOT_SIZE"
  mount "$LOOP_DEV" "$MNT"
  mkdir -p "$MNT/cyborgroid"
  cat > "$MNT/cyborgroid/wg0.conf" <<WG
[Interface]
PrivateKey = $(wg genkey)
Address = 10.200.0.1/24

[Peer]
PublicKey = $(wg genkey | wg pubkey)
Endpoint = 10.0.2.2:51820
AllowedIPs = 0.0.0.0/0, ::/0
WG
  umount "$MNT"
fi
loop_detach_all

# Room for firstboot.sh to grow into, as on a real SD card.
truncate -s +3G "$WORK/disk.img"

echo "==> booting"
qemu-system-aarch64 -M virt -cpu max -smp 8 -m 6144 -accel tcg,thread=multi \
  -kernel "$WORK/vmlinuz" -initrd "$WORK/initrd.img" \
  -append "root=LABEL=writable rootfstype=ext4 rootwait console=ttyAMA0 systemd.show_status=1" \
  -drive "file=$WORK/disk.img,format=raw,if=none,id=d0" -device virtio-blk-pci,drive=d0 \
  -device virtio-gpu-pci,xres=720,yres=1280 -device qemu-xhci -device usb-tablet \
  -nic user,model=virtio-net-pci -display none -monitor none \
  -qmp "unix:$WORK/qmp.sock,server,nowait" -serial "file:/out/serial.log" &
QEMU=$!

python3 /os/test/qmp-watch.py "$WORK/qmp.sock" /out/serial.log /out "${BOOT_TIMEOUT:-2400}"
kill "$QEMU" 2>/dev/null || true
