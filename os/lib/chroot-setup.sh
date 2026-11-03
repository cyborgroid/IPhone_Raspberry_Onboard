#!/usr/bin/env bash
# Runs inside the arm64 root filesystem under qemu-user.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

# Keep maintainer scripts from starting services in the build chroot.
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

apt-get update
# Deliberately no dist-upgrade: the kernel and firmware stay as shipped in the
# official image, whose boot chain is the part that has been tested on a Pi 5.
grep -vE '^[[:space:]]*(#|$)' /tmp/cyborgroid/packages.list \
  | xargs apt-get install -y --no-install-recommends

# The on-screen keyboard has no Hangul layer, so build it from the archive's source
# with os/wvkbd/hangul.patch. Only packages this step added are removed afterwards.
dpkg-query -W -f '${Package}\n' | sort > /tmp/cyborgroid/before-build
sources=/etc/apt/sources.list.d/ubuntu.sources
cp "$sources" /tmp/cyborgroid/ubuntu.sources
sed -i 's/^Types: deb$/Types: deb deb-src/' "$sources"
apt-get update
apt-get install -y --no-install-recommends dpkg-dev gcc make pkg-config patch \
  libwayland-dev libpango1.0-dev libxkbcommon-dev wayland-protocols
(
  cd /tmp/cyborgroid
  apt-get source wvkbd
  cd wvkbd-*/
  patch -p1 < /tmp/cyborgroid/hangul.patch
  make -j"$(nproc)"
  install -m 755 wvkbd-mobintl /usr/local/bin/wvkbd-mobintl
)
cp /tmp/cyborgroid/ubuntu.sources "$sources"
dpkg-query -W -f '${Package}\n' | sort > /tmp/cyborgroid/after-build
comm -13 /tmp/cyborgroid/before-build /tmp/cyborgroid/after-build | xargs -r apt-get purge -y

# GNOME keeps its own input method; fcitx5 belongs to the touch session only.
rm -f /etc/xdg/autostart/org.fcitx.Fcitx5.desktop

# firstboot.sh replaces cloud-init. Disabled rather than purged, as is GDM below:
# they sit under the ubuntu-desktop metapackage, and removing them would leave the
# rest of the desktop open to autoremove.
touch /etc/cloud/cloud-init.disabled
rm -f /etc/netplan/50-cloud-init.yaml

groupadd --system cyborgroid
for group in netdev bluetooth plugdev; do groupadd --force --system "$group"; done
useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin \
  --gid cyborgroid cyborgroid-core
# Password stays locked until firstboot.sh sets a per-device one.
useradd --create-home --shell /bin/bash \
  --groups cyborgroid,sudo,video,render,input,audio,netdev,plugdev,bluetooth cyborg
passwd --lock cyborg

chmod 600 /etc/netplan/*.yaml
chmod +x /usr/lib/cyborgroid/*.sh /usr/bin/cyborgroid-core

systemctl set-default graphical.target
systemctl enable cyborgroid-firstboot.service cyborgroid-killswitch.service \
  cyborgroid-core.service cyborgroid-session.service NetworkManager.service wg-quick@wg0.service
systemctl disable ssh.service ssh.socket systemd-networkd-wait-online.service getty@tty1.service || true
# cyborgroid-session owns the display and chooses between the touch session and GNOME.
systemctl disable gdm3.service || true
systemctl mask gdm3.service
rm -f /etc/systemd/system/display-manager.service

# The image must not carry identity shared by every device flashed from it.
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
echo cyborgroid > /etc/hostname
sed -i '/127.0.1.1/d' /etc/hosts
echo '127.0.1.1 cyborgroid' >> /etc/hosts

apt-get clean
rm -rf /var/lib/apt/lists/* /var/log/apt/* /var/log/dpkg.log /tmp/cyborgroid
rm -f /usr/sbin/policy-rc.d
