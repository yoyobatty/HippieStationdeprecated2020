#!/usr/bin/env python3
"""Draws the lighting bench's snapshots over the station map, to see what the lighting engine does.

    python tools/lighting_bench/render.py                # every snapshot in data/lighting_bench/, a heat map of where
                                                         # bounce lighting changed things, and close-ups of the 6
                                                         # places it changed most, side by side
    python tools/lighting_bench/render.py --crops 12     # more close-ups

Each lit tile is shaded the way the client shades it: the lighting object's gradient icon, recolored by its corners
(see /atom/movable/lighting_object/proc/update()), multiplied over the map. Only what's in the map file is drawn -
no mobs, items or emissives - and space is left unshaded, as it is in game (with a plain starfield for parallax).

Needs Pillow and numpy. The map is drawn by SpacemanDMM's dmm-tools, which tools/mapviewer/mapviewer.py downloads.
Output goes to data/lighting_preview/.
"""
import argparse
import glob
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "mapviewer"))
import mapviewer  # noqa: E402 - for get_dmm_tools()

BENCH = os.path.join(ROOT, "data", "lighting_bench")
OUT = os.path.join(ROOT, "data", "lighting_preview")  # apart from BENCH, which every bench run wipes
STATION_MAP = os.path.join(ROOT, "_maps", "map_files", "HippieStation", "hippiestation.dmm")
TILE = 32


def render_map(space=True):
    """The station map as players see it (bar lighting), rendered once and cached. Without space, space is left black."""
    path = os.path.join(OUT, "map.png" if space else "map_nospace.png")
    if os.path.exists(path) and os.path.getmtime(path) > os.path.getmtime(STATION_MAP):
        return Image.open(path).convert("RGB")
    print("Rendering the station map with dmm-tools...")
    with tempfile.TemporaryDirectory() as tmp:
        cmd = [mapviewer.get_dmm_tools(), "-e", mapviewer.DME, "minimap", "-o", tmp,
               "--enable", "icon-smoothing-2016", "--disable", "icon-smoothing,hide-space" if space else "icon-smoothing", STATION_MAP]
        subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True)
        rendered = glob.glob(os.path.join(tmp, "*.png"))[0]
        image = Image.open(rendered).convert("RGB")
    image.save(path)
    return image


def gradient_weights():
    """How much each corner (SW, SE, NW, NE) counts at each pixel: the lighting icon's red, green, blue and alpha."""
    dmi = np.asarray(Image.open(os.path.join(ROOT, "icons", "effects", "lighting_object.dmi")).convert("RGBA"))
    return dmi[0:TILE, 0:TILE].astype(np.float32) / 255  # the "" state, first in the sheet


def load_snapshot(path):
    """-> (xs, ys, corner colors as N x 4 corners x 3 channels) for every tile with a lighting object"""
    xs, ys, corners = [], [], []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) < 4:
                continue
            xs.append(int(parts[0]))
            ys.append(int(parts[1]))
            if parts[3] == "L":
                corners.append([1.0] * 12)
            elif parts[3] == "D":
                corners.append([0.0] * 12)
            else:
                corners.append([float(v) for v in parts[3:15]])
    return np.array(xs), np.array(ys), np.array(corners, dtype=np.float32).reshape(-1, 4, 3)


def light_map(snapshot, height, weights):
    """Per-pixel light multiplier over the whole map; 1 where there's no lighting object (space, unlit areas)."""
    xs, ys, corners = snapshot
    width = (xs.max() + 8) * TILE
    light = np.ones((height, max(width, TILE), 3), dtype=np.float32)
    rows = height // TILE
    for start in range(0, len(xs), 4096):
        chunk = slice(start, start + 4096)
        blocks = np.einsum("hwc,ncr->nhwr", weights, corners[chunk])  # N x 32 x 32 x rgb
        for x, y, block in zip(xs[chunk], ys[chunk], blocks):
            top = (rows - y) * TILE
            left = (x - 1) * TILE
            light[top:top + TILE, left:left + TILE] = block
    return light


def shade(base, light):
    width = min(base.shape[1], light.shape[1])
    out = base.astype(np.float32)
    out[:, :width] *= np.clip(light[:, :width], 0, 1)
    return np.clip(out, 0, 255).astype(np.uint8)


def pick_crops(diff, count, size):
    """The top-left tile of the `count` non-overlapping size[0] x size[1] tile windows where diff adds up to the most."""
    w, h = size
    padded = np.pad(diff, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    window = padded[h:, w:] - padded[:-h, w:] - padded[h:, :-w] + padded[:-h, :-w]
    picks = []
    for _ in range(count):
        row, col = np.unravel_index(np.argmax(window), window.shape)
        if window[row, col] <= 0:
            break
        picks.append((row, col))
        window[max(0, row - h + 1):row + h, max(0, col - w + 1):col + w] = -1
    return picks


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--crops", type=int, default=6, help="how many side by side close-ups to make (default 6)")
    parser.add_argument("--before", default="bounce_off", help="snapshot on the left of the close-ups")
    parser.add_argument("--after", default="bounce_on", help="snapshot on the right of the close-ups")
    args = parser.parse_args()

    snapshots = {os.path.basename(p)[len("snapshot_"):-len(".txt")]: p
                 for p in sorted(glob.glob(os.path.join(BENCH, "snapshot_*.txt")))}
    if not snapshots:
        sys.exit("No snapshots in data/lighting_bench/ - run tools/lighting_bench/run_lighting_bench.sh first")
    os.makedirs(OUT, exist_ok=True)
    base = np.asarray(render_map())
    weights = gradient_weights()

    shaded, lights = {}, {}
    for name, path in snapshots.items():
        lights[name] = light_map(load_snapshot(path), base.shape[0], weights)
        shaded[name] = shade(base, lights[name])
        overview = Image.fromarray(shaded[name])
        overview = overview.resize((overview.width // 4, overview.height // 4), Image.LANCZOS)
        overview.save(os.path.join(OUT, f"{name}_overview.png"))
        print(f"{name}: {os.path.join(OUT, name + '_overview.png')}")

    if args.before in lights and args.after in lights:
        # How much each tile's light changed. Tiles that are space in the map file don't count: things built there at
        # runtime (random rooms and the like) aren't in the map render, so the light on them would be drawn on nothing.
        width = min(base.shape[1], lights[args.after].shape[1])
        change = np.abs(lights[args.after][:, :width] - lights[args.before][:, :width]).sum(axis=2)
        rows, cols = change.shape[0] // TILE, width // TILE
        tiled = (slice(0, rows * TILE), slice(0, cols * TILE))
        tile_change = change[tiled].reshape(rows, TILE, cols, TILE).mean(axis=(1, 3))
        no_space = np.asarray(render_map(space=False))
        tile_change[no_space[tiled].reshape(rows, TILE, cols, TILE, 3).max(axis=(1, 3, 4)) == 0] = 0

        # Where the light changed, over a dimmed grey map: red for brighter, blue for darker
        grey = base[:, :width].astype(np.float32).mean(axis=2, keepdims=True) * 0.35
        delta = (lights[args.after][:, :width] - lights[args.before][:, :width]).mean(axis=2, keepdims=True) * 4
        heat = grey + np.clip(delta, 0, 1) * np.array([255, 60, 0]) + np.clip(-delta, 0, 1) * np.array([0, 90, 255])
        heat = Image.fromarray(np.clip(heat, 0, 255).astype(np.uint8))
        heat = heat.resize((heat.width // 4, heat.height // 4), Image.LANCZOS)
        heat.save(os.path.join(OUT, "change_heatmap.png"))
        print(f"where {args.after} differs from {args.before}: {os.path.join(OUT, 'change_heatmap.png')}")

    if args.crops and args.before in lights and args.after in lights:
        size = (28, 20)
        for i, (row, col) in enumerate(pick_crops(tile_change, args.crops, size), 1):
            area = (slice(row * TILE, (row + size[1]) * TILE), slice(col * TILE, (col + size[0]) * TILE))
            pair = np.concatenate([shaded[args.before][area], np.full((size[1] * TILE, 16, 3), 255, np.uint8),
                                   shaded[args.after][area]], axis=1)
            path = os.path.join(OUT, f"closeup_{i}.png")
            Image.fromarray(pair).save(path)
            x, y = col + 1, rows - row - size[1] + 1
            print(f"close-up {i}: tiles ({x},{y})-({x + size[0] - 1},{y + size[1] - 1}), "
                  f"{args.before} left, {args.after} right: {path}")


if __name__ == "__main__":
    main()
