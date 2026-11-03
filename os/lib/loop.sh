# Loop-device helpers for the privileged containers. Source this file.
# A container's /dev is a snapshot from when it started, so a loop device the
# kernel creates afterwards has no node yet; `losetup --find --show` then fails.

LOOPS=()

# Sets LOOP_DEV. Not usable through $(...): the subshell would lose LOOPS, and
# with it the cleanup.
loop_attach() { # image offset size
  local free minor
  free=$(losetup --find)
  minor=${free#/dev/loop}
  [ -e "$free" ] || mknod "$free" b 7 "$minor"
  LOOP_DEV=$(losetup --find --show --offset "$2" --sizelimit "$3" "$1")
  LOOPS+=("$LOOP_DEV")
}

loop_detach_all() {
  local dev
  for dev in "${LOOPS[@]:-}"; do
    [ -n "$dev" ] && losetup -d "$dev"
  done
  LOOPS=()
}

part_bytes() { # image partnum -> "offset size"
  sfdisk -J "$1" | python3 -c "import json,sys; p=json.load(sys.stdin)['partitiontable']['partitions'][$2-1]; print(p['start']*512, p['size']*512)"
}
