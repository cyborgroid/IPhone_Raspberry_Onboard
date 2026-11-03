#!/usr/bin/env python3
"""Follows the test VM's serial log; acts on its markers through QMP.

@@SHOT name    takes a screenshot
@@TAP x y      clicks with the virtual tablet, in pixels of the 720x1280 screen
"""
import json
import socket
import sys
import time

qmp_path, log_path, out_dir, timeout = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
PERIODIC_SECS = 120
SCREEN_W, SCREEN_H = 720, 1280
TABLET_MAX = 32767


def connect():
    for _ in range(60):
        try:
            s = socket.socket(socket.AF_UNIX)
            s.connect(qmp_path)
            return s.makefile("rw")
        except OSError:
            time.sleep(1)
    raise SystemExit("QMP socket never appeared")


qmp = connect()
qmp.readline()


def command(name, **args):
    qmp.write(json.dumps({"execute": name, "arguments": args}) + "\n")
    qmp.flush()
    while True:
        reply = json.loads(qmp.readline())
        if "return" in reply or "error" in reply:
            return reply


def tap(x, y):
    position = [
        {"type": "abs", "data": {"axis": "x", "value": x * TABLET_MAX // SCREEN_W}},
        {"type": "abs", "data": {"axis": "y", "value": y * TABLET_MAX // SCREEN_H}},
    ]
    command("input-send-event", events=position)
    time.sleep(0.3)
    for down in (True, False):
        command("input-send-event", events=[{"type": "btn", "data": {"down": down, "button": "left"}}])
        time.sleep(0.15)


command("qmp_capabilities")
deadline = time.time() + timeout
offset = 0
next_periodic = time.time() + PERIODIC_SECS
partial = ""
while time.time() < deadline:
    with open(log_path, errors="replace") as f:
        f.seek(offset)
        chunk = f.read()
        offset = f.tell()
    lines = (partial + chunk).split("\n")
    partial = lines.pop()
    for line in lines:
        line = line.strip()
        if line.startswith("@@SHOT "):
            name = line.split()[1]
            print("screenshot:", name, command("screendump", filename=f"{out_dir}/{name}.ppm"), flush=True)
        elif line.startswith("@@TAP "):
            _, x, y = line.split()
            tap(int(x), int(y))
        elif line == "@@DONE":
            print("probe finished", flush=True)
            sys.exit(0)
    if time.time() >= next_periodic:
        # Overwritten each time: what was on screen if the probe never reports.
        command("screendump", filename=f"{out_dir}/latest.ppm")
        next_periodic = time.time() + PERIODIC_SECS
    time.sleep(2)
print("timed out waiting for the probe", flush=True)
sys.exit(1)
