"""A map crop with a coordinate grid (every 5 tiles labelled) and optional marks, for reading coordinates off a
picture while reviewing a department.

    python tools/mapforge/studies/dept_specs/engineering_work/shot.py <dmm> x0 y0 x1 y1 out.png [--scale 0.75]
        [--mark x,y,label ...]
    from shot import shot; shot(dmm_path, (x0, y0, x1, y1), out_png, scale=0.75, marks=[(x, y, "text")])

Rendered with forge/render.py (dmm-tools, the game's own sprites). Marks are red boxes with a label.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import render  # noqa: E402


def shot(dmm_path, region, out_png, scale=0.75, marks=(), title=None):
    from PIL import Image, ImageDraw
    x0, y0, x1, y1 = region
    tmp = out_png + ".raw.png"
    render.render(dmm_path, tmp, region=region, scale=scale)
    img = Image.open(tmp).convert("RGB")
    os.remove(tmp)
    px = img.width / float(x1 - x0 + 1)
    top = 24 if title else 0
    out = Image.new("RGB", (img.width + 28, img.height + 20 + top), (16, 16, 20))
    out.paste(img, (28, 20 + top))
    d = ImageDraw.Draw(out)
    f = render._font(12)
    if title:
        d.text((4, 2), title, fill=(255, 220, 120), font=render._font(16))
    for x in range(x0, x1 + 1):
        X = 28 + (x - x0) * px
        if x % 5 == 0:
            d.line((X, 20 + top, X, out.height), fill=(70, 200, 220), width=1)
            d.text((X + 2, 4 + top), str(x), fill=(120, 255, 255), font=f)
    for y in range(y0, y1 + 1):
        Y = 20 + top + (y1 - y) * px
        if y % 5 == 0:
            d.line((28, Y + px, out.width, Y + px), fill=(70, 200, 220), width=1)
            d.text((2, Y + 2), str(y), fill=(120, 255, 255), font=f)
    for (x, y, lab) in marks:
        X, Y = 28 + (x - x0) * px, 20 + top + (y1 - y) * px
        d.rectangle((X, Y, X + px, Y + px), outline=(255, 40, 40), width=2)
        if lab:
            d.text((X + px + 1, Y), str(lab), fill=(255, 90, 90), font=f)
    out.save(out_png)
    return out_png


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dmm")
    ap.add_argument("box", nargs=4, type=int)
    ap.add_argument("out")
    ap.add_argument("--scale", type=float, default=0.75)
    ap.add_argument("--mark", action="append", default=[])
    ap.add_argument("--title")
    a = ap.parse_args()
    marks = []
    for s in a.mark:
        p = s.split(",", 2)
        marks.append((int(p[0]), int(p[1]), p[2] if len(p) > 2 else ""))
    print(shot(a.dmm, tuple(a.box), a.out, a.scale, marks, a.title))


if __name__ == "__main__":
    main()
