#!/usr/bin/env bash
# Builds the flashable Cyborgroid image for Raspberry Pi 5.
#
#   os/build-image.sh            build everything into build/
#   SKIP_COMPRESS=1 os/build-image.sh   leave the raw .img for local testing
#
# Needs cargo with the aarch64-unknown-linux-musl target, the .NET SDK, and a
# Docker daemon. Docker runs privileged to loop-mount the image's partitions, and
# temporarily registers arm64 emulation with the host kernel if it isn't already.
set -euo pipefail

BASE_NAME=ubuntu-26.04.1-preinstalled-desktop-arm64+raspi.img.xz
BASE_URL=https://cdimage.ubuntu.com/ubuntu/releases/26.04/release/$BASE_NAME
BASE_SHA256=8216f54cc1df2fcf7de37530a7edccdd200abd7dcfbc5d4f0407df7513544d6a
BUILDER_IMAGE=ubuntu:26.04

ROOT=$(dirname "$(dirname "$(readlink -f "$0")")")
BUILD=$ROOT/build
CACHE=$BUILD/cache
SHELL_OUT=$BUILD/shell-arm64
IMAGE=cyborgroid-pi5-$(date +%Y%m%d).img
mkdir -p "$CACHE"

echo "==> base image"
if [ ! -f "$CACHE/$BASE_NAME" ]; then
  curl -fL --retry 3 -o "$CACHE/$BASE_NAME.part" "$BASE_URL"
  mv "$CACHE/$BASE_NAME.part" "$CACHE/$BASE_NAME"
fi
echo "$BASE_SHA256  $CACHE/$BASE_NAME" | sha256sum -c -

echo "==> core engine"
# From inside core/, because cargo finds .cargo/config.toml relative to the cwd.
(cd "$ROOT/core" && cargo build --release --target aarch64-unknown-linux-musl)

echo "==> shell"
rm -rf "$SHELL_OUT"
dotnet publish "$ROOT/shell/CyborgroidDashboard.csproj" -c Release -r linux-arm64 \
  --self-contained true -o "$SHELL_OUT" -v q --nologo

echo "==> root filesystem (in container)"
docker run --rm --privileged --name cyborgroid-image-build \
  -v "$ROOT:/src:ro" -v "$BUILD:/build" "$BUILDER_IMAGE" bash -euc "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends qemu-user fdisk e2fsprogs \
      xz-utils mount python3 >/dev/null
    /src/os/lib/customize.sh /build/cache/$BASE_NAME /build/$IMAGE \
      /src/core/target/aarch64-unknown-linux-musl/release/cyborgroid-core /build/shell-arm64
    chown $(id -u):$(id -g) /build/$IMAGE
  "

if [ -z "${SKIP_COMPRESS:-}" ]; then
  echo "==> compressing"
  xz -T0 -6 -f "$BUILD/$IMAGE"
  (cd "$BUILD" && sha256sum "$IMAGE.xz" > "$IMAGE.xz.sha256")
  echo "==> $BUILD/$IMAGE.xz"
else
  echo "==> $BUILD/$IMAGE"
fi
