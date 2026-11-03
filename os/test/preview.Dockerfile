FROM ubuntu:26.04
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    gnome-shell ubuntu-session gnome-shell-extension-ubuntu-dock gnome-shell-extension-appindicator \
    yaru-theme-gnome-shell yaru-theme-gtk yaru-theme-icon fonts-ubuntu fonts-noto-cjk fonts-noto-color-emoji \
    dbus dbus-x11 ibus ibus-hangul libgl1-mesa-dri gnome-settings-daemon nautilus gnome-calculator \
    gnome-text-editor gnome-clocks gnome-control-center ptyxis libglib2.0-bin python3 upower >/dev/null
