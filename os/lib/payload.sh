# Sourced by the image builders: copies Cyborgroid into a mounted root filesystem.
#   copy_payload <root> <os dir> <core binary> <shell publish dir>
copy_payload() {
  local root=$1 os_dir=$2 core=$3 shell_dir=$4 lib
  lib=$os_dir/lib
  # Everything is root-owned whoever ran the build, and directories that already
  # exist in the image keep their metadata. The builder's uid is also the uid of the
  # device's auto-login user, so keeping it would let that user rewrite /etc and
  # the scripts that run as root.
  tar -C "$os_dir/overlay" --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w' -cf - . \
    | tar -C "$root" --no-overwrite-dir -xf -
  install -m 755 "$core" "$root/usr/bin/cyborgroid-core"
  mkdir -p "$root/opt/cyborgroid/shell"
  tar -C "$shell_dir" --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w' -cf - . \
    | tar -C "$root/opt/cyborgroid/shell" -xf -
  ln -sf /opt/cyborgroid/shell/cyborgroid-shell "$root/usr/bin/cyborgroid-shell"
  mkdir -p "$root/tmp/cyborgroid"
  cp "$os_dir/packages.list" "$root/tmp/cyborgroid/"
  cp "$lib/chroot-setup.sh" "$root/tmp/cyborgroid/"
  cp "$os_dir/wvkbd/hangul.patch" "$root/tmp/cyborgroid/"
}
