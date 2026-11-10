"""Before/after pictures of explosions from explosion_preview.dm's dumps: the straight line (as before) on the left, shaped on the
right, the room drawn underneath. Usage: python render.py <dump dir> <picture dir>"""
import glob
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

TILE = 14
KIND = {
    "floor": (205, 205, 200),
    "wall": (70, 70, 78),
    "rwall": (35, 35, 42),
    "door_shut": (150, 95, 40),
    "door_open": (225, 185, 120),
    "window": (110, 165, 210),
    "grille": (150, 150, 150),
    "space": (12, 12, 24),
    "none": (0, 0, 0),
}
SEVERITY = {1: (215, 30, 30), 2: (240, 160, 20), 3: (250, 230, 60)}
NAMES = {1: "devastated", 2: "heavy", 3: "light"}


def panel(rows, which, title):
    h = len(rows)
    w = len(rows[0])
    img = Image.new("RGB", (w * TILE, h * TILE + 22), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for y, row in enumerate(rows):
        for x, (kind, line, shaped) in enumerate(row):
            base = KIND.get(kind, (255, 0, 255))
            sev = line if which == "line" else shaped
            colour = base
            if sev:
                s = SEVERITY[sev]
                colour = tuple(int(base[i] * 0.35 + s[i] * 0.65) for i in range(3))
            x0, y0 = x * TILE, y * TILE + 22
            d.rectangle([x0, y0, x0 + TILE - 1, y0 + TILE - 1], fill=colour)
            if kind in ("door_shut", "door_open", "window"):
                d.rectangle([x0 + 3, y0 + 3, x0 + TILE - 4, y0 + TILE - 4], outline=base)
    c = len(rows) // 2
    d.ellipse([c * TILE + 3, c * TILE + 25, c * TILE + TILE - 4, c * TILE + TILE + 18], fill=(0, 0, 0))
    counts = {1: 0, 2: 0, 3: 0}
    for row in rows:
        for kind, line, shaped in row:
            sev = line if which == "line" else shaped
            if sev:
                counts[sev] += 1
    d.text((4, 4), f"{title}: " + ", ".join(f"{counts[k]} {NAMES[k]}" for k in (1, 2, 3)), fill=(0, 0, 0))
    return img


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(src, "*.json"))):
        data = json.load(open(path))
        rows = data["rows"]
        global TILE
        TILE = 14 if len(rows) < 30 else 9
        before = panel(rows, "line", "Before (straight line)")
        after = panel(rows, "shaped", "After (shaped)")
        gap = 16
        img = Image.new("RGB", (before.width + after.width + gap, before.height + 26), (255, 255, 255))
        img.paste(before, (0, 26))
        img.paste(after, (before.width + gap, 26))
        d = ImageDraw.Draw(img)
        s = data["size"]
        d.text((4, 6), f"{data['name']} ({data['area']}, {data['x']},{data['y']}): a ({s[0]}, {s[1]}, {s[2]}) explosion. Red devastated, orange heavy, yellow light; brown shut doors, tan open doors, blue windows.", fill=(0, 0, 0))
        name = os.path.splitext(os.path.basename(path))[0]
        img.save(os.path.join(out, f"{name}.png"))
        print(f"wrote {os.path.join(out, name)}.png")


if __name__ == "__main__":
    main()
