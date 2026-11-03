#!/usr/bin/env bash
# Runs the built image in a window on this PC, to try it without a Raspberry Pi.
#
#   os/run-vm.sh           keep what you did last time
#   os/run-vm.sh --reset   start again as on a freshly flashed card
#
# This emulates an arm64 machine (QEMU's generic board) on an x86 PC, so it is slow:
# expect several minutes for the first boot. Mouse clicks stand in for touch. There is
# no Wi-Fi chip or Pi hardware inside; the network is a virtual Ethernet cable.
#
# Inside it, plugging in a monitor is simulated from the Terminal icon:
#   cyborgroid-core set-mode desktop   switch to the standard Ubuntu desktop
#   cyborgroid-core set-mode mobile    back to the touch home screen
set -euo pipefail

ROOT=$(dirname "$(dirname "$(readlink -f "$0")")")
BUILD=$ROOT/build
DISK=$BUILD/vm-disk.img
TOOLS_IMAGE=cyborgroid-vm-tools

IMG=$(ls -t "$BUILD"/cyborgroid-pi5-*.img 2>/dev/null | head -1 || true)
if [ -z "$IMG" ]; then
  echo "build/ 에 이미지가 없습니다. 먼저 SKIP_COMPRESS=1 os/build-image.sh 를 실행하세요." >&2
  exit 1
fi
if [ -z "${DISPLAY:-}" ]; then
  echo "화면(DISPLAY)을 찾을 수 없습니다. 데스크톱의 터미널에서 실행하세요." >&2
  exit 1
fi

docker build -q -t "$TOOLS_IMAGE" - >/dev/null <<'DOCKERFILE'
FROM ubuntu:26.04
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    --no-install-recommends qemu-system-arm qemu-system-gui ipxe-qemu e2fsprogs fdisk python3
DOCKERFILE

if [ "${1:-}" = "--reset" ] || [ ! -f "$DISK" ] || [ "$IMG" -nt "$DISK" ]; then
  echo "==> 가상 디스크를 새로 만듭니다"
  cp --sparse=always "$IMG" "$DISK"
  # Room for first boot to grow into, as on a real card.
  truncate -s +6G "$DISK"
fi

XAUTH_ARGS=()
if [ -n "${XAUTHORITY:-}" ] && [ -f "$XAUTHORITY" ]; then
  XAUTH_ARGS=(-v "$XAUTHORITY:/tmp/xauthority:ro" -e XAUTHORITY=/tmp/xauthority)
fi

echo "==> 가상 기기를 시작합니다. 첫 부팅은 몇 분 걸립니다. 끝내려면 창을 닫으세요."
# Runs as this user, so the disk stays writable by you and needs no extra privileges.
# The display's access cookie is tied to the hostname, so the container must share it.
docker run --rm --name cyborgroid-vm --user "$(id -u):$(id -g)" --hostname "$(hostname)" \
  -e HOME=/tmp -e DISPLAY -e DISK=/build/vm-disk.img "${XAUTH_ARGS[@]}" \
  -e IMAGE="/build/$(basename "$IMG")" -v /tmp/.X11-unix:/tmp/.X11-unix -v "$BUILD:/build" \
  "$TOOLS_IMAGE" bash -euc '
    # From the pristine image: the working disk may not have been shut down cleanly.
    offset=$(sfdisk -J "$IMAGE" | python3 -c "import json,sys; print(json.load(sys.stdin)[\"partitiontable\"][\"partitions\"][1][\"start\"]*512)")
    version=$(debugfs -R "ls -p /boot" "$IMAGE?offset=$offset" 2>/dev/null | tr "/" "\n" | grep -m1 "^vmlinuz-" | sed s/vmlinuz-//)
    debugfs -R "dump /boot/vmlinuz-$version /tmp/vmlinuz" "$IMAGE?offset=$offset" 2>/dev/null
    debugfs -R "dump /boot/initrd.img-$version /tmp/initrd" "$IMAGE?offset=$offset" 2>/dev/null
    [ -s /tmp/vmlinuz ] && [ -s /tmp/initrd ] || { echo "이미지에서 부팅 파일을 읽지 못했습니다." >&2; exit 1; }
    exec qemu-system-aarch64 -name Cyborgroid -M virt -cpu max -smp 8 -m 4096 -accel tcg,thread=multi \
      -kernel /tmp/vmlinuz -initrd /tmp/initrd \
      -append "root=LABEL=writable rootfstype=ext4 rootwait console=ttyAMA0" \
      -drive "file=$DISK,format=raw,if=none,id=d0" -device virtio-blk-pci,drive=d0 \
      -device virtio-gpu-pci,xres=720,yres=1280 -device qemu-xhci -device usb-tablet -device usb-kbd \
      -nic user,model=virtio-net-pci -display gtk,zoom-to-fit=on,show-menubar=off \
      -serial file:/build/vm-serial.log
  '
