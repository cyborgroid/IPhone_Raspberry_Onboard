#!/usr/bin/env bash
# Waits for the iPhone to mirror its screen here over AirPlay. One receiver at a time,
# because a second would advertise the same name.
pkill -x uxplay
exec uxplay -n Cyborgroid -nh -fs -vs waylandsink
