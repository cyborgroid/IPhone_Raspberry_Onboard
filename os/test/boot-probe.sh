#!/usr/bin/env bash
# Runs inside the booted test VM; every line goes to the serial log. The markers
# drive os/test/qmp-watch.py, which takes the screenshots.
export LC_ALL=C.UTF-8
sec() { echo; echo "##### $*"; }
sec "probe started"

uid=$(id -u cyborg)
as_cyborg() {
  timeout 60 sudo -u cyborg env XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    SWAYSOCK="$(ls /run/user/"$uid"/sway-ipc.*.sock 2>/dev/null | head -1)" "$@"
}
session_log() { journalctl _UID="$uid" --no-pager | grep -E 'session: ' | tail -"$1"; }
wait_for() { # process-name max-seconds
  local i
  for ((i = 0; i < $2; i += 5)); do
    pgrep -u cyborg -x "$1" >/dev/null && { echo "$1 running after ${i}s"; return 0; }
    sleep 5
  done
  echo "$1 NOT running after $2s"
  return 1
}

wait_for sway 900
for _ in $(seq 1 60); do
  pgrep -u cyborg -f /opt/cyborgroid/shell/cyborgroid-shell >/dev/null && break
  sleep 5
done
sleep 45

sec "system state"
systemctl is-system-running
systemctl --no-pager --failed
sec "cyborgroid units"
for u in cyborgroid-firstboot cyborgroid-killswitch cyborgroid-core cyborgroid-session wg-quick@wg0 ssh gdm3 cloud-init; do
  printf '%-26s active=%s enabled=%s\n' "$u" "$(systemctl is-active "$u")" "$(systemctl is-enabled "$u" 2>/dev/null)"
done
sec "first boot"
df -h / | tail -1
ls -la /home/cyborg/initial-password.txt
test -s /home/cyborg/initial-password.txt && echo "password file non-empty"
passwd --status cyborg
ls /etc/ssh/ssh_host_ed25519_key
wc -c /etc/machine-id
sec "ownership (the auto-login user must not be able to change the system)"
stat -c '%U:%G %a %n' / /etc /usr /etc/sudoers.d /usr/lib/cyborgroid/firstboot.sh /usr/lib/cyborgroid/wireguard-killswitch.sh \
  /etc/systemd/system/cyborgroid-firstboot.service /usr/bin/cyborgroid-core /opt/cyborgroid/shell/cyborgroid-shell
echo "system files owned by cyborg: $(find /etc /usr /opt -xdev -user cyborg 2>/dev/null | wc -l)"
for path in /etc /usr/lib/cyborgroid/firstboot.sh /etc/systemd/system; do
  if sudo -u cyborg test -w "$path"; then echo "WRITABLE by cyborg: $path"; else echo "not writable by cyborg: $path"; fi
done
sudo -u cyborg sudo -n true 2>&1 | head -1
sec "core engine"
ls -la /run/cyborgroid/
sudo -u cyborg cyborgroid-core query mode
sudo -u cyborg cyborgroid-core query status | cut -c1-400
systemctl show cyborgroid-core -p User -p NRestarts -p CapabilityBoundingSet --no-pager
sec "network"
ip -br addr
nmcli -t -f DEVICE,TYPE,STATE device status
if timeout 25 bash -c '</dev/tcp/archive.ubuntu.com/80' 2>/dev/null; then echo "egress: ok"; else echo "egress: blocked"; fi
sec "kill-switch"
ls -la /etc/wireguard/ /boot/firmware/cyborgroid/
systemctl --no-pager --lines=4 status cyborgroid-killswitch wg-quick@wg0 | cut -c1-120
wg show 2>&1 | grep -v 'private key' | cut -c1-80
iptables -S | head -30
ip6tables -S | head -6

sec "touch mode: home screen"
session_log 6
ps -eo user,comm | grep -E 'sway|waybar|wvkbd|cyborgroid' | sort -u
as_cyborg swaymsg -t get_tree | python3 -c '
import json, sys
def walk(n):
    if n.get("pid"):
        print(n.get("app_id"), (n.get("window_properties") or {}).get("class"), "visible=%s" % n.get("visible"), n["rect"]["width"], n["rect"]["height"])
    for c in n.get("nodes", []) + n.get("floating_nodes", []): walk(c)
walk(json.load(sys.stdin))'
as_cyborg swaymsg -t get_outputs | python3 -c 'import json,sys; [print(o["name"], o["current_mode"]) for o in json.load(sys.stdin)]'
echo "@@SHOT touch"; sleep 8

sec "why GTK apps do or do not start under sway"
wl=$(basename "$(ls /run/user/"$uid"/wayland-* 2>/dev/null | grep -v lock | head -1)")
echo "wayland socket: $wl"
as_cyborg env WAYLAND_DISPLAY="$wl" timeout 12 waybar --config /usr/share/cyborgroid/waybar/mobile.jsonc --style /usr/share/cyborgroid/waybar/mobile.css 2>&1 | tail -12 | cut -c1-170
echo "waybar rc=$?"
as_cyborg env WAYLAND_DISPLAY="$wl" timeout 25 gnome-calculator 2>&1 | tail -10 | cut -c1-170
echo "calculator rc=$?"
journalctl _UID="$uid" --no-pager | grep -iE 'waybar|calculator|cannot open display|gtk' | tail -12 | cut -c1-170
free -h | sed -n 1,2p

sec "use the touch screen: tap icons and the navigation bar"
workspace() { as_cyborg swaymsg -t get_workspaces | python3 -c 'import json,sys; print([w["name"] for w in json.load(sys.stdin) if w["focused"]])'; }
windows() { as_cyborg swaymsg -t get_tree | grep -oE '"(app_id|class)": "[^"]+"' | sort -u | tr '\n' ' '; echo; }
open_tile() { # name x y seconds
  echo "@@TAP $2 $3"; sleep "$4"
  echo "after tapping $1: workspace $(workspace), windows: $(windows)"
  echo "@@SHOT tap-$1"; sleep 8
}
close_app() {
  echo "@@TAP 174 1246"; sleep 8   # navigation bar: close
  echo "@@TAP 286 1246"; sleep 6   # navigation bar: home
  echo "after closing: workspace $(workspace), windows: $(windows)"
}
open_tile calculator 584 460 45; close_app
open_tile wifi 360 738 30; close_app
open_tile settings 584 1016 60; close_app
open_tile browser 360 180 240; close_app
sec "type Korean with the on-screen keyboard"
pgrep -a -u cyborg -x fcitx5 | cut -c1-80
as_cyborg fcitx5-remote -n; which wvkbd-mobintl
type_key() { echo "@@TAP $1 $2"; sleep 3; }
echo "@@TAP 360 460"; sleep 40     # home screen: notes
echo "@@TAP 360 300"; sleep 4      # into the text area
echo "@@TAP 534 1246"; sleep 8     # navigation bar: on-screen keyboard
echo "@@SHOT typing-latin"; sleep 6
type_key 54 1174                   # layer key: to the Hangul layer
sleep 4
echo "input method on the Hangul layer: $(as_cyborg fcitx5-remote -n)"
echo "@@SHOT typing-hangul-layer"; sleep 6
# ㅎㅏㄴ ㄱㅡㄹ: the keys g k s r m f, which must compose into 한글.
type_key 360 1022; type_key 576 1022; type_key 144 1022
type_key 252 946;  type_key 576 1098; type_key 288 1022
type_key 360 1174                  # space
echo "@@SHOT typing-korean"; sleep 6
type_key 54 1174; type_key 54 1174 # layer key twice: symbols, then back to Latin
sleep 4
echo "input method back on Latin: $(as_cyborg fcitx5-remote -n)"
type_key 72 1022; type_key 684 870 # the keys a and 0 as plain characters
echo "@@SHOT typing-latin-after"; sleep 6
echo "@@TAP 534 1246"; sleep 5
close_app
as_cyborg pkill gnome-text-editor

echo "@@TAP 534 1246"; sleep 10    # navigation bar: on-screen keyboard
echo "@@SHOT tap-keyboard"; sleep 8
echo "@@TAP 534 1246"; sleep 5
echo "keyboard layers: $(wvkbd-mobintl --help 2>&1 | grep -iE 'layer|hangul|korean' | head -4 | tr '\n' ' ' | cut -c1-200)"
echo "@@TAP 600 700"; sleep 2

sec "open apps from the touch session"
as_cyborg swaymsg workspace number 2
as_cyborg swaymsg exec -- gnome-calculator; sleep 60
as_cyborg swaymsg -t get_tree | grep -oE '"app_id": "[^"]+"' | sort -u
echo "@@SHOT app"; sleep 8
as_cyborg swaymsg '[workspace="^2$" con_id=__focused__] kill'; sleep 5
as_cyborg swaymsg workspace number 1

sec "monitor connected: standard Ubuntu desktop (forced, the VM has no HDMI)"
sudo -u cyborg cyborgroid-core set-mode desktop
wait_for gnome-shell 420
sleep 90
session_log 6
ps -eo user,comm | grep -E 'sway|gnome-shell|gnome-session|cyborgroid' | sort -u
journalctl _UID="$uid" --no-pager -n 600 | grep -E 'gnome-shell|gnome-session' | grep -iE 'error|fail|fatal' | tail -10 | cut -c1-190
echo "memory on the Ubuntu desktop:"; free -h | sed -n 2p | sed "s/^Mem:/RAM:/"
echo "crash reports:"; ls -la /var/crash/ 2>/dev/null
for crash in /var/crash/*.crash; do [ -f "$crash" ] && grep -aE '^(ExecutablePath|Signal|Title):' "$crash"; done
echo "@@SHOT ubuntu-desktop"; sleep 8

sec "monitor removed: back to the touch home screen"
sudo -u cyborg cyborgroid-core set-mode mobile
sleep 15
wait_for sway 420
sleep 90
session_log 6
ps -eo user,comm | grep -E 'sway|gnome-shell' | sort -u
echo "home screen windows (must be 1): $(as_cyborg swaymsg -t get_tree | grep -c '"class": "cyborgroid-shell"')"
journalctl -b -p err --no-pager -n 15 | cut -c1-170
echo "@@SHOT touch-again"; sleep 8
echo "@@DONE"
