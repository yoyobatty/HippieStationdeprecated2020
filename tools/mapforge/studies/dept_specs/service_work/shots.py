"""Renders map crops with a coordinate grid (every 5 tiles labelled) for the service review.

    python tools/mapforge/studies/dept_specs/service_work/shots.py <dmm> <out.png> x0 y0 x1 y1 [scale]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import render as R  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402


def shot(dmm_path, out, x0, y0, x1, y1, scale=0.75):
    R.render(dmm_path, out, region=(x0, y0, x1, y1), scale=1.0)
    img = Image.open(out).convert("RGB")
    W, H = img.size
    tw = W / float(x1 - x0 + 1)
    d = ImageDraw.Draw(img)
    for x in range(x0, x1 + 1):
        px = (x - x0) * tw
        if x % 5 == 0:
            d.line([(px, 0), (px, H)], fill=(255, 255, 0), width=1)
            d.text((px + 2, 2), str(x), fill=(255, 255, 0))
    for y in range(y0, y1 + 1):
        py = (y1 - y) * tw          # north is up
        if y % 5 == 0:
            d.line([(0, py + tw), (W, py + tw)], fill=(0, 255, 255), width=1)
            d.text((2, py + 2), str(y), fill=(0, 255, 255))
    if scale != 1.0:
        img = img.resize((int(W * scale), int(H * scale)), Image.LANCZOS)
    img.save(out)
    return out


if __name__ == "__main__":
    a = sys.argv[1:]
    shot(a[0], a[1], *[int(v) for v in a[2:6]], scale=float(a[6]) if len(a) > 6 else 0.75)
