#!/usr/bin/env bash
# Runs Cyborgroid on this PC in a window: no Raspberry Pi, no OS image, no virtual
# machine. The core engine reads this PC's real Wi-Fi and traffic. Close the window
# to stop. Needs cargo and the .NET SDK.
set -euo pipefail

ROOT=$(dirname "$(readlink -f "$0")")
cargo build --quiet --release --manifest-path "$ROOT/core/Cargo.toml"
dotnet build -v q --nologo "$ROOT/shell/CyborgroidDashboard.csproj" >/dev/null

RUNTIME=${XDG_RUNTIME_DIR:-/tmp}/cyborgroid-dev
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/cyborgroid-dev
mkdir -p "$RUNTIME" "$STATE"
WIFI=$(ls /sys/class/net | grep -m1 '^wl' || true)

cat > "$RUNTIME/core.toml" <<CONFIG
interface = "${WIFI:-lo}"
tick_secs = 2
scan_secs = 15
ledger_save_secs = 30
socket_path = "$RUNTIME/core.sock"
state_dir = "$STATE"
killswitch_marker = "$RUNTIME/killswitch.active"
CONFIG

"$ROOT/core/target/release/cyborgroid-core" --config "$RUNTIME/core.toml" &
core=$!
trap 'kill "$core" 2>/dev/null' EXIT

CYBORGROID_SOCKET="$RUNTIME/core.sock" "$ROOT/shell/bin/Debug/net10.0/cyborgroid-shell"
