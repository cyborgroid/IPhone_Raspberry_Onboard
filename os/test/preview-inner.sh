#!/usr/bin/env bash
# Container half of preview-touch.sh.
set -uo pipefail

UUID=cyborgroid-touch@cyborgroid
mkdir -p "$HOME/.local/share/gnome-shell/extensions" /tmp/run "$HOME/.config"
chmod 700 /tmp/run
export XDG_RUNTIME_DIR=/tmp/run LC_ALL=C.UTF-8 LANG=ko_KR.UTF-8
# GNOME Shell needs a system bus, which a container does not start by itself.
mkdir -p /run/dbus
dbus-daemon --system --fork
cp -r /ext "$HOME/.local/share/gnome-shell/extensions/$UUID"
glib-compile-schemas "$HOME/.local/share/gnome-shell/extensions/$UUID/schemas"

cat > /tmp/session.sh <<SESSION
#!/usr/bin/env bash
set -uo pipefail
gsettings set org.gnome.shell disable-user-extensions false
gsettings set org.gnome.shell enabled-extensions "['$UUID']"
gsettings set org.gnome.desktop.input-sources sources "[('xkb','us'),('ibus','hangul')]"
XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=ubuntu:GNOME XDG_SESSION_DESKTOP=ubuntu GNOME_SHELL_SESSION_MODE=ubuntu \
  gnome-shell --mode=ubuntu --headless --wayland --unsafe-mode --virtual-monitor $SIZE >/out/shell.log 2>&1 &
shell=\$!
for _ in \$(seq 1 60); do
  gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Eval "1+1" >/dev/null 2>&1 && break
  sleep 1
done
sleep 6
evalshell() { gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Eval "\$1"; }
shot() { gdbus call --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot --method org.gnome.Shell.Screenshot.Screenshot false false "/out/\$1.png" >/dev/null; }
export -f evalshell shot
source /test/preview-steps.sh
kill \$shell
SESSION
chmod +x /tmp/session.sh
dbus-run-session -- /tmp/session.sh
chown -R "$OWNER" /out
