"""Scratch: a dmm-tools render of a map region with a labelled tile grid (every 5 tiles), for reading coordinates.

    python shot.py <dmm> <out.png> x0 y0 x1 y1 [scale]
    from shot import shot; shot(dmm_path, out_png, (x0, y0, x1, y1), scale=0.75, marks=[(x, y, text)])
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import render  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402


def shot(path, out, region, scale=0.75, marks=(), title=None):
    x0, y0, x1, y1 = region
    render.render(path, out, region=region, scale=scale)
    im = Image.open(out).convert("RGB")
    ts = im.width / float(x1 - x0 + 1)
    d = ImageDraw.Draw(im)
    f = render._font(max(10, int(ts * 0.45)))
    for x in range(x0, x1 + 1):
        if x % 5 == 0:
            px = (x - x0) * ts
            d.line([(px, 0), (px, im.height)], fill=(255, 255, 0), width=1)
            d.text((px + 2, 2), str(x), fill=(255, 255, 0), font=f)
    for y in range(y0, y1 + 1):
        if y % 5 == 0:
            py = (y1 - y + 1) * ts
            d.line([(0, py), (im.width, py)], fill=(0, 255, 255), width=1)
            d.text((2, py - ts * 0.5), str(y), fill=(0, 255, 255), font=f)
    for x, y, text in marks:
        if x0 <= x <= x1 and y0 <= y <= y1:
            px, py = (x - x0) * ts, (y1 - y) * ts
            d.rectangle([px, py, px + ts, py + ts], outline=(255, 40, 40), width=3)
            if text:
                d.text((px + ts + 2, py), text[:40], fill=(255, 80, 80), font=f)
    if title:
        d.rectangle([0, im.height - ts, im.width, im.height], fill=(20, 20, 20))
        d.text((4, im.height - ts), title, fill=(240, 240, 240), font=f)
    im.save(out)
    return out


if __name__ == "__main__":
    a = sys.argv
    shot(a[1], a[2], tuple(int(v) for v in a[3:7]), float(a[7]) if len(a) > 7 else 0.75)
