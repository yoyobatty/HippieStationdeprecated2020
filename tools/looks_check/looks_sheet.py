#!/usr/bin/env python3
"""Draws the station looks self-test's lighting snapshots over the Hippie map, the same places under every look.

    python tools/looks_check/looks_sheet.py            # after tools/looks_check/run_looks_check.sh

Rows are the places that changed most (two from night lighting, two from Tired wiring); columns are the looks, labelled.
Also a quarter-size overview of the station under each look. Shading is tools/lighting_bench/render.py's.
Output goes to data/previews/looks_*.png. Needs Pillow and numpy.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "lighting_bench"))
import render  # noqa: E402

SNAPSHOTS = os.path.join(ROOT, "data", "looks_check")
OUT = os.path.join(ROOT, "data", "previews")
LOOKS = [("plain", "Day (as now)"), ("morning", "Morning"), ("night", "Night"), ("power_saving", "Power-saving"),
         ("tired_wiring", "Tired wiring")]
SIZE = (22, 15)  # tiles across, down
TILE = render.TILE
GAP = 12
LABEL = 26


def tile_change(a, b, width, rows):
    change = np.abs(a[:, :width] - b[:, :width]).sum(axis=2)
    cols = width // TILE
    tiled = change[:rows * TILE, :cols * TILE].reshape(rows, TILE, cols, TILE).mean(axis=(1, 3))
    return tiled


def main():
    os.makedirs(OUT, exist_ok=True)
    base = np.asarray(render.render_map())
    weights = render.gradient_weights()
    lights, shaded = {}, {}
    for name, _ in LOOKS:
        path = os.path.join(SNAPSHOTS, f"snapshot_{name}.txt")
        if not os.path.exists(path):
            sys.exit(f"missing {path}: run tools/looks_check/run_looks_check.sh first")
        lights[name] = render.light_map(render.load_snapshot(path), base.shape[0], weights)
        shaded[name] = render.shade(base, lights[name])
    width = min(base.shape[1], *(l.shape[1] for l in lights.values()))
    rows = base.shape[0] // TILE
    no_space = np.asarray(render.render_map(space=False))
    cols = width // TILE
    space = no_space[:rows * TILE, :cols * TILE].reshape(rows, TILE, cols, TILE, 3).max(axis=(1, 3, 4)) == 0

    crops = []
    for look in ("night", "tired_wiring"):
        diff = tile_change(lights[look], lights["plain"], width, rows)
        diff[space] = 0
        for row, col in render.pick_crops(diff, 4, SIZE):
            if all(abs(row - r) >= SIZE[1] or abs(col - c) >= SIZE[0] for r, c in crops):
                crops.append((row, col))
            if sum(1 for _ in crops) >= (2 if look == "night" else 4):
                break

    cw, ch = SIZE[0] * TILE, SIZE[1] * TILE
    for i, (row, col) in enumerate(crops, 1):
        sheet = Image.new("RGB", (len(LOOKS) * (cw + GAP) - GAP, ch + LABEL), (24, 24, 28))
        draw = ImageDraw.Draw(sheet)
        for j, (name, label) in enumerate(LOOKS):
            area = shaded[name][row * TILE:(row + SIZE[1]) * TILE, col * TILE:(col + SIZE[0]) * TILE]
            sheet.paste(Image.fromarray(area), (j * (cw + GAP), LABEL))
            draw.text((j * (cw + GAP) + 6, 6), label, fill=(235, 235, 235))
        path = os.path.join(OUT, f"looks_place_{i}.png")
        sheet.save(path)
        x, y = col + 1, rows - row - SIZE[1] + 1
        print(f"place {i}: tiles ({x},{y})-({x + SIZE[0] - 1},{y + SIZE[1] - 1}): {path}")

    for name, label in LOOKS:
        overview = Image.fromarray(shaded[name][:, :width])
        overview = overview.resize((overview.width // 4, overview.height // 4), Image.LANCZOS)
        path = os.path.join(OUT, f"looks_station_{name}.png")
        overview.save(path)
        print(f"{label}: {path}")


if __name__ == "__main__":
    main()
