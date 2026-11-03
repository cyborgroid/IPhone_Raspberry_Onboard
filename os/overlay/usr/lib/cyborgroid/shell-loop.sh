#!/usr/bin/env bash
# Keeps the home screen alive for the lifetime of the touch session. session.sh ends
# this loop when it switches sessions.
#
# The layout is designed in 480x800 units; the 720x1280 panel is 1.5 times that.
export AVALONIA_GLOBAL_SCALE_FACTOR=1.5
while :; do
  /usr/bin/cyborgroid-shell
  sleep 1
done
