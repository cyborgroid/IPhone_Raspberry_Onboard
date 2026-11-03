#!/usr/bin/env bash
# Runs the session for the current form-factor mode and swaps it when
# cyborgroid-core reports a change: the touch home screen on the panel, the standard
# Ubuntu desktop when a monitor is connected.
set -u

export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin

POLL_SECS=2
# Left in the user manager by a session; the next one must not inherit them.
SESSION_ENV="WAYLAND_DISPLAY DISPLAY SWAYSOCK XMODIFIERS XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP GNOME_SHELL_SESSION_MODE"

current_mode() { cyborgroid-core query mode 2>/dev/null || echo mobile; }

start_ubuntu() {
  XDG_CURRENT_DESKTOP=ubuntu:GNOME XDG_SESSION_DESKTOP=ubuntu GNOME_SHELL_SESSION_MODE=ubuntu \
    gnome-session --session=ubuntu &
  pid=$!
}

start_touch() {
  XDG_CURRENT_DESKTOP=sway XDG_SESSION_DESKTOP=sway XMODIFIERS=@im=fcitx \
    sway --config /usr/share/cyborgroid/sway/mobile.conf &
  pid=$!
}

stop_user_session() {
  # The home screen outlives its compositor, and would add itself to the next one.
  pkill -f /usr/lib/cyborgroid/shell-loop.sh
  pkill -f /opt/cyborgroid/shell/cyborgroid-shell
  pkill -x fcitx5
  systemctl --user stop graphical-session.target 2>/dev/null
  # shellcheck disable=SC2086
  systemctl --user unset-environment $SESSION_ENV 2>/dev/null
}

while :; do
  mode=$(current_mode)
  echo "session: starting $mode"
  if [ "$mode" = desktop ]; then start_ubuntu; else start_touch; fi

  while kill -0 "$pid" 2>/dev/null; do
    sleep "$POLL_SECS"
    if [ "$(current_mode)" != "$mode" ]; then
      echo "session: mode changed, restarting"
      kill -TERM "$pid" 2>/dev/null
      break
    fi
  done
  wait "$pid" 2>/dev/null
  stop_user_session
  sleep 2
done
