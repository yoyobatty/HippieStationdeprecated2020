"""Sheet and walking GIFs from floor_depth_shots.dm's pictures (data/previews/depth_*.png).

    python tools/keybind_check/floor_depth_sheet.py

Writes data/previews/depth_sheet.png (flat, then each depth smoothed and crisp, cropped round the holes) and
data/previews/depth_walk_<depth>.gif (the pit held still while the viewer walks past it, so only the depth moves).
"""
import os
import numpy as np
from PIL import Image, ImageChops, ImageDraw

D = "data/previews"
SCALE = 2  # enlarged, nearest neighbour


def load(name):
    return Image.open(os.path.join(D, name + ".png")).convert("RGB")


def grey(im):
    return np.asarray(im.convert("L"), dtype=np.float32)


def holes_box(off, on, margin=40):
    """Where the depth changed anything: the holes"""
    diff = np.asarray(ImageChops.difference(off, on).convert("L")) > 24
    diff[:, off.height - 160:] = False  # the map is the square on the left, its right edge the HUD; the panels change too
    diff[:60, :] = False  # title bar
    ys, xs = np.nonzero(diff)
    return (int(xs.min()) - margin, int(ys.min()) - margin, int(xs.max()) + margin, int(ys.max()) + margin)


def best_dx(a, b, lo, hi, band):
    """b's content is a's moved dx pixels across, dx in lo..hi"""
    x0, y0, x1, y1 = band
    ref = grey(a)[y0:y1, x0:x1]
    gb = grey(b)
    best = None
    for dx in range(lo, hi + 1):
        if x0 + dx < 0 or x1 + dx > gb.shape[1]:
            continue
        err = float(np.mean(np.abs(gb[y0:y1, x0 + dx:x1 + dx] - ref)))
        if best is None or err < best[0]:
            best = (err, dx)
    return best[1]


def label(im, text):
    out = Image.new("RGB", (im.width, im.height + 22), (24, 24, 24))
    out.paste(im, (0, 22))
    ImageDraw.Draw(out).text((6, 4), text, fill=(230, 230, 230))
    return out


def enlarge(im):
    return im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST)


def main():
    off = load("depth_0_off")
    box = holes_box(off, load("depth_medium_soft"))
    cells = [[label(enlarge(off.crop(box)), "flat (setting off)")], [None]]
    for depth in ("shallow", "medium", "deep"):
        for row, kind in enumerate(("soft", "crisp")):
            cells[row].append(label(enlarge(load(f"depth_{depth}_{kind}").crop(box)), f"{depth}, {kind}"))
    w, h = cells[0][0].width, cells[0][0].height
    gap = 10
    sheet = Image.new("RGB", (len(cells[0]) * (w + gap) - gap, 2 * (h + gap) - gap), (24, 24, 24))
    for r, row in enumerate(cells):
        for c, cell in enumerate(row):
            if cell:
                sheet.paste(cell, (c * (w + gap), r * (h + gap)))
    sheet.save(os.path.join(D, "depth_sheet.png"))
    print("sheet", sheet.size, "holes at", box)

    # The walk started three tiles west of where the static pictures were taken: find the tile size from that
    band = (box[0] - 400, box[1], box[2], box[3])
    band = (max(band[0], 0), band[1], band[2], band[3])
    for depth in ("shallow", "medium", "deep"):
        if not os.path.exists(os.path.join(D, f"depth_walk_{depth}_0.png")):
            continue
        frames = []
        first = load(f"depth_walk_{depth}_0")
        three = best_dx(load(f"depth_{depth}_soft"), first, 150, 360, band)
        tile = three / 3.0
        start = (box[0] + three, box[1], box[2] + three, box[3])
        prev = first
        offset = 0
        for i in range(9):
            path = os.path.join(D, f"depth_walk_{depth}_{i}.png")
            if not os.path.exists(path):
                break
            im = load(f"depth_walk_{depth}_{i}")
            if i:
                offset += best_dx(prev, im, int(-tile * 1.5), int(-tile * 0.5), (start[0] + offset - 200, start[1], start[2] + offset, start[3]))
            prev = im
            crop = im.crop((start[0] + offset, start[1], start[2] + offset, start[3]))
            frames.append(label(enlarge(crop), f"{depth}: viewer step {i}"))
        out = os.path.join(D, f"depth_walk_{depth}.gif")
        frames[0].save(out, save_all=True, append_images=frames[1:], duration=450, loop=0)
        print(depth, "tile", tile, "px,", len(frames), "frames ->", out)


if __name__ == "__main__":
    main()
