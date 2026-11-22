"""The discriminator's verdict room by room: which rooms of a map look most generated, worst first, so the fixes go
where the judge sees the most. disc.py heat colours the whole map; this totals its tile logits per room, hall and
maint run and draws the worst ones on the game's own sprites.

    python tools/mapforge/forge/disc_rooms.py data/mapforge/station_v6.dmm [--run data/mapforge/disc/v6] [--top 16]

The network is the fold of the run that held the map out (by file name, as disc.py heat picks it), so it judges a
map it never trained on. It runs on the CPU (one forward pass, a few seconds).

Per place (a room as room_stats.rooms finds it; halls and maint by area): the mean tile logit (above 0 = "looks
generated") and the share of its tiles called generated. Output:
    data/mapforge/disc_rooms/<map>.md                  the ranking
    data/previews/mapforge/disc_rooms/<map>.png        the worst places, each its render crop beside the same crop
                                                       tinted by the logits (red generated, blue human)
"""
import argparse
import glob
import json
import os
import sys
from collections import defaultdict

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, tensor, room_stats as RS, gallery  # noqa: E402

OUT = os.path.join(parse.ROOT, "data", "mapforge", "disc_rooms")
PICS = os.path.join(parse.ROOT, "data", "previews", "mapforge", "disc_rooms")
RUN = os.path.join(parse.ROOT, "data", "mapforge", "disc", "v6")


def logits(run, path):
    """Tile logits [H, W] (row 0 = map y 1) from the fold that held this map out, and whether one did."""
    import torch
    from forge import disc
    pts = sorted(glob.glob(os.path.join(run, "fold*.pt")))
    if not pts:
        sys.exit("no fold*.pt in %s" % run)
    ck = {p: torch.load(p, map_location="cpu") for p in pts}
    base = os.path.basename(path)
    held = [p for p, c in ck.items() if base in map(os.path.basename, c["test"])]
    p = held[0] if held else pts[0]
    model = disc.net(ck[p]["width"])
    model.load_state_dict(ck[p]["state"])
    model.eval()
    planes, mask = tensor.load(path)
    try:
        keep = json.load(open(os.path.join(run, "report.json")))["args"].get("keep") or ""
    except (OSError, ValueError, KeyError):
        keep = ""
    if keep:
        planes = planes.copy()
        planes[[i for i in range(tensor.C) if tensor.CHANNELS[i] not in keep.split(",")]] = 0
    with torch.no_grad():
        _, tiles = model(torch.from_numpy(planes[None]).float(), torch.from_numpy(mask[None]).float())
    return tiles[0].numpy(), mask, bool(held)


def places(sm):
    """(kind, area, tiles, box) for every room, and every hall and maint area."""
    out = []
    for rm in RS.rooms(sm):
        out.append(("room", rm.area, rm.tiles, rm.box))
    by = defaultdict(list)
    for r in sm.regions.values():
        if r.kind in ("hall", "maint"):
            by[(r.kind, r.area)].extend(r.tiles)
    for (k, a), ts in by.items():
        if len(ts) >= 8:
            out.append((k, a, ts, sm.bbox(ts)))
    return out


def tint(crop, L, box, pad, px):
    """The crop with each tile tinted by its logit, as disc.py heat colours it."""
    from PIL import Image
    x0, y0, x1, y1 = box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad
    H, W = L.shape
    ov = np.zeros((y1 - y0 + 1, x1 - x0 + 1, 4), np.uint8)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 1 <= x <= W and 1 <= y <= H:
                v = L[y - 1, x - 1]
                a = int(170 * min(1.0, abs(v) / 4.0))
                ov[y1 - y, x - x0] = (235, 40, 30, a) if v > 0 else (40, 90, 235, a)
    o = Image.fromarray(ov, "RGBA").resize(crop.size, Image.NEAREST)
    return Image.alpha_composite(crop.convert("RGBA"), o).convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("map")
    ap.add_argument("--run", default=RUN)
    ap.add_argument("--top", type=int, default=16, help="places drawn in the picture")
    a = ap.parse_args()
    path = a.map
    if not os.path.exists(path) and os.path.exists(os.path.join(parse.ROOT, "data", "mapforge", path)):
        path = os.path.join(parse.ROOT, "data", "mapforge", path)
    label = os.path.splitext(os.path.basename(path))[0]
    sm = parse.load(path)
    L, mask, held = logits(a.run, path)
    rows = []
    for kind, area, ts, box in places(sm):
        v = np.array([L[y - 1, x - 1] for x, y in ts if mask[y - 1, x - 1] > 0])
        if len(v):
            rows.append((float(v.mean()), float((v > 0).mean()), len(ts), kind, area, box))
    rows.sort(key=lambda r: -r[0])
    on = L[mask > 0]
    head = "%s: %s; whole map mean %+.2f, %.0f%% of tiles called generated" % (
        label, "held out" if held else "SEEN IN TRAINING (verdict is optimistic)", on.mean(), 100 * (on > 0).mean())
    print(head)
    md = ["# Discriminator by room: %s" % label, "", head, "", "run: `%s`" % os.path.relpath(a.run, parse.ROOT), "",
          "| mean logit | generated tiles | tiles | kind | area | box |", "|---:|---:|---:|---|---|---|"]
    for m, g, n, kind, area, box in rows:
        md.append("| %+.2f | %.0f%% | %d | %s | %s | %d,%d-%d,%d |" % ((m, 100 * g, n, kind, area) + box))
    for m, g, n, kind, area, box in rows[:12]:
        print("  %+.2f %4.0f%%  %4d  %-5s %s" % (m, 100 * g, n, kind, area))
    os.makedirs(OUT, exist_ok=True)
    rp = os.path.join(OUT, label + ".md")
    open(rp, "w", encoding="utf-8").write("\n".join(md))

    from PIL import Image
    from forge.room_twin import row_image, stack
    img = Image.open(gallery.full_renders([path], jobs=1)[path]).convert("RGB")
    pics = []
    for m, g, n, kind, area, box in [r for r in rows if r[3] == "room"][:a.top]:
        c = gallery.crop(img, sm.m.maxy, (box[0] - 2, box[1] - 2, box[2] + 2, box[3] + 2))
        h = tint(c, L, box, 2, gallery.PX)
        name = area.rsplit("/", 1)[-1]
        txt = [("logit %+.2f" % m, (255, 140, 120) if m > 0 else (140, 180, 255)), ("gen %.0f%%" % (100 * g), (200, 205, 215))]
        pics.append(row_image([(c, name, txt), (h, "heat", [])]))
    os.makedirs(PICS, exist_ok=True)
    out = os.path.join(PICS, label + ".png")
    # two columns of rows, so the sheet is not one tall strip
    half = (len(pics) + 1) // 2
    cols = [stack(pics[:half], "%s: rooms the discriminator finds most generated" % label, out + ".a.png"),
            stack(pics[half:] or pics[:1], " ", out + ".b.png")]
    A, B = Image.open(cols[0]), Image.open(cols[1])
    sheet = Image.new("RGB", (A.width + B.width, max(A.height, B.height)), (16, 17, 21))
    sheet.paste(A, (0, 0))
    sheet.paste(B, (A.width, 0))
    sheet.save(out)
    for f in cols:
        os.remove(f)
    print("->", os.path.relpath(rp, parse.ROOT), "and", os.path.relpath(out, parse.ROOT))


if __name__ == "__main__":
    main()
