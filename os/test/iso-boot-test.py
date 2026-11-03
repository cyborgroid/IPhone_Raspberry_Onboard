#!/usr/bin/env python3
"""Boots the ISO with KVM and UEFI and saves a screenshot at intervals. QEMU's
virtio GPU is used because vmwgfx needs more of the SVGA device than QEMU's copy of
it offers, so this does not prove the VMware driver; its connector name, Virtual-1,
is the same.

  os/test/iso-boot-test.py <iso> <out dir> <seconds> [secs:x:y ...]

Each secs:x:y clicks the virtual tablet at pixel x,y of the screen after that many
seconds. Extra QEMU arguments can be passed in QEMU_EXTRA.
"""
import json
import os
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time

SHOT_EVERY = 30
TABLET_MAX = 32767
SCREEN_W, SCREEN_H = 480, 1044
OVMF = "/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS = "/usr/share/OVMF/OVMF_VARS_4M.fd"

iso, out, seconds = sys.argv[1], sys.argv[2], int(sys.argv[3])
taps = sorted((int(a), int(b), int(c)) for a, b, c in (t.split(":") for t in sys.argv[4:]))
os.makedirs(out, exist_ok=True)
run_dir = tempfile.mkdtemp(prefix="cyb-iso-", dir=os.environ.get("XDG_RUNTIME_DIR"))
qmp_path = os.path.join(run_dir, "qmp")
vars_path = os.path.join(run_dir, "vars.fd")
shutil.copy(OVMF_VARS, vars_path)

args = [
    "qemu-system-x86_64", "-name", "cyborgroid-iso", "-accel", "kvm", "-cpu", "host",
    "-smp", "4", "-m", "4096", "-M", "q35",
    "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF}",
    "-drive", f"if=pflash,format=raw,file={vars_path}",
    "-device", f"virtio-vga,xres={SCREEN_W},yres={SCREEN_H}", "-device", "qemu-xhci", "-device", "usb-tablet", "-device", "usb-kbd",
    "-nic", "user,model=e1000", "-display", "none", "-qmp", f"unix:{qmp_path},server,nowait",
    "-serial", f"file:{out}/serial.log",
]
if iso != "-":
    args += ["-cdrom", iso]
args += shlex.split(os.environ.get("QEMU_EXTRA", ""))
vm = subprocess.Popen(args)

for _ in range(60):
    try:
        sock = socket.socket(socket.AF_UNIX)
        sock.connect(qmp_path)
        break
    except OSError:
        time.sleep(0.5)
else:
    raise SystemExit("QMP socket never appeared")
qmp = sock.makefile("rw")
qmp.readline()


def command(name, **arguments):
    qmp.write(json.dumps({"execute": name, "arguments": arguments}) + "\n")
    qmp.flush()
    while True:
        reply = json.loads(qmp.readline())
        if "return" in reply or "error" in reply:
            return reply


def tap(x, y):
    command("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": x * TABLET_MAX // SCREEN_W}},
        {"type": "abs", "data": {"axis": "y", "value": y * TABLET_MAX // SCREEN_H}},
    ])
    time.sleep(0.3)
    for down in (True, False):
        command("input-send-event", events=[{"type": "btn", "data": {"down": down, "button": "left"}}])
        time.sleep(0.15)


command("qmp_capabilities")
start = time.time()
next_shot = 0
try:
    while (elapsed := time.time() - start) < seconds and vm.poll() is None:
        while taps and taps[0][0] <= elapsed:
            _, x, y = taps.pop(0)
            tap(x, y)
            print(f"{elapsed:.0f}s tap {x},{y}", flush=True)
        if elapsed >= next_shot:
            print(f"{elapsed:.0f}s shot", command("screendump", filename=f"{out}/shot-{int(elapsed):04d}.ppm").keys(), flush=True)
            next_shot = elapsed + SHOT_EVERY
        time.sleep(1)
finally:
    vm.terminate()
    vm.wait()
    shutil.rmtree(run_dir, ignore_errors=True)
