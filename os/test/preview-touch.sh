#!/usr/bin/env bash
# Starts the real GNOME Shell of the target release, with no display and no Raspberry
# Pi, loads the touch extension, and saves screenshots to build/preview/.
#
#   os/test/preview-touch.sh [WIDTHxHEIGHT]
set -euo pipefail

ROOT=$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")
OUT=$ROOT/build/preview
mkdir -p "$OUT"
docker build -q -t cyborgroid-gnome-preview -f "$ROOT/os/test/preview.Dockerfile" "$ROOT/os/test" >/dev/null
docker run --rm --name cyborgroid-preview -e HOME=/tmp/home -e SIZE="${1:-480x640}" -e OWNER="$(id -u):$(id -g)" \
  -v "$ROOT/os/overlay/usr/share/gnome-shell/extensions/cyborgroid-touch@cyborgroid:/ext:ro" \
  -v "$ROOT/os/overlay/usr/share/backgrounds/cyborgroid-touch.png:/usr/share/backgrounds/cyborgroid-touch.png:ro" \
  -v "$ROOT/os/test:/test:ro" -v "$OUT:/out" cyborgroid-gnome-preview /test/preview-inner.sh
echo "==> $OUT"
