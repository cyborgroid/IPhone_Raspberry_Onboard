#!/usr/bin/env bash
# Builds the x86-64 Cyborgroid ISO, for VMware and for booting a PC or laptop from USB.
# It is a live system: changes are lost at power-off and nothing is written to the disk.
#
#   os/build-iso.sh     build into build/
#
# Needs cargo, the .NET SDK and a Docker daemon. Docker runs privileged to loop-mount
# the ISO and its layers.
set -euo pipefail

BASE_NAME=ubuntu-26.04.1-desktop-amd64.iso
BASE_URL=https://releases.ubuntu.com/26.04/$BASE_NAME
BASE_SHA256=601e30fbf5d97759367c632e2c33630665039b7e2158fd068403da3ccf1bda1f
BUILDER_IMAGE=ubuntu:26.04

ROOT=$(dirname "$(dirname "$(readlink -f "$0")")")
BUILD=$ROOT/build
CACHE=$BUILD/cache
SHELL_OUT=$BUILD/shell-x64
ISO=cyborgroid-amd64-$(date +%Y%m%d).iso
mkdir -p "$CACHE"

echo "==> base ISO"
if [ ! -f "$CACHE/$BASE_NAME" ]; then
  curl -fL --retry 3 -C - -o "$CACHE/$BASE_NAME.part" "$BASE_URL"
  mv "$CACHE/$BASE_NAME.part" "$CACHE/$BASE_NAME"
fi
echo "$BASE_SHA256  $CACHE/$BASE_NAME" | sha256sum -c -

echo "==> core engine"
(cd "$ROOT/core" && cargo build --release)

echo "==> shell"
rm -rf "$SHELL_OUT"
dotnet publish "$ROOT/shell/CyborgroidDashboard.csproj" -c Release -r linux-x64 \
  --self-contained true -o "$SHELL_OUT" -v q --nologo

echo "==> Cyborgroid layer and ISO (in container)"
docker run --rm --privileged --name cyborgroid-iso-build \
  -v "$ROOT:/src:ro" -v "$BUILD:/build" "$BUILDER_IMAGE" bash -euc "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends squashfs-tools xorriso zstd mount >/dev/null
    /src/os/lib/customize-iso.sh /build/cache/$BASE_NAME /build/$ISO \
      /src/core/target/release/cyborgroid-core /build/shell-x64 /build/iso-work
    chown $(id -u):$(id -g) /build/$ISO
  "

(cd "$BUILD" && sha256sum "$ISO" > "$ISO.sha256")
echo "==> $BUILD/$ISO"
