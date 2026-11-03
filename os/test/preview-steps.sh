# Sourced inside the running session of preview-inner.sh; has evalshell and shot.
EXT="imports.ui.main.extensionManager.lookup('cyborgroid-touch@cyborgroid')"
evalshell "$EXT.state + ' ' + ($EXT.error || 'no error')"
evalshell "global.backend.get_monitor_manager().get_monitors().map(m => m.get_connector()).join(',')"
evalshell "$EXT.stateObj._touch"

evalshell "$EXT.stateObj._home.setBattery(78, true)"
sleep 1
shot home

gnome-calculator >/dev/null 2>&1 &
sleep 6
shot app
pkill -f gnome-calculator; sleep 2

evalshell "imports.ui.main.overview.showApps()"
sleep 3
shot all-apps
evalshell "imports.ui.main.overview.hide()"
sleep 2

gsettings --schemadir "$HOME/.local/share/gnome-shell/extensions/cyborgroid-touch@cyborgroid/schemas" set org.gnome.shell.extensions.cyborgroid-touch mode-override desktop
sleep 4
evalshell "$EXT.stateObj._touch"
gsettings get org.gnome.desktop.interface color-scheme
shot desktop
