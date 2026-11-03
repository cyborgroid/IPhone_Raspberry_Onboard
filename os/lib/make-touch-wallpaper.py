#!/usr/bin/env python3
"""Draws the home screen wallpaper of the After design: near-black with a warm glow
towards the bottom right and a violet one behind the fingerprint button.

    make-touch-wallpaper.py OUTPUT.png
"""
import sys

import numpy as np
from PIL import Image

WIDTH, HEIGHT = 1080, 1620
y, x = np.mgrid[0:HEIGHT, 0:WIDTH]
u, v = x / WIDTH, y / HEIGHT


def glow(cx, cy, radius):
    return np.exp(-(((u - cx) ** 2 + ((v - cy) * 1.1) ** 2) / radius**2))[..., None]


base = np.array([24, 24, 28], float)
warm = np.array([86, 40, 34], float) * glow(0.95, 0.92, 0.55)
violet = np.array([52, 34, 86], float) * glow(0.55, 0.88, 0.22)
image = np.clip(base + warm + violet, 0, 255)
# Dither, so the dark gradient does not band on a panel.
noise = np.random.default_rng(1).uniform(-1.2, 1.2, image.shape)
Image.fromarray(np.clip(image + noise, 0, 255).astype("uint8")).save(sys.argv[1])
