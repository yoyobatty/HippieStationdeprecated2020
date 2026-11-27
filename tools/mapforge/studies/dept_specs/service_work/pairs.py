"""Before/after pictures of the rooms fn_service changes: one PNG a region, before on the left, after on the right.

    python tools/mapforge/studies/dept_specs/service_work/pairs.py <before.dmm> <after.dmm> <out_dir> [name x0 y0 x1 y1]...
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from shots import shot  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

REGIONS = [("service_block", 87, 62, 117, 89), ("dorms_restroom", 74, 109, 99, 132),
           ("chapel_office", 44, 111, 58, 126), ("law_office", 126, 70, 150, 92)]


def pair(before, after, out, x0, y0, x1, y1, scale=0.75):
    a = shot(before, out + ".a.png", x0, y0, x1, y1, scale)
    b = shot(after, out + ".b.png", x0, y0, x1, y1, scale)
    ia, ib = Image.open(a), Image.open(b)
    w, h = ia.size
    img = Image.new("RGB", (w * 2 + 12, h + 22), (20, 20, 20))
    img.paste(ia, (0, 22))
    img.paste(ib, (w + 12, 22))
    d = ImageDraw.Draw(img)
    d.text((4, 4), "before", fill=(255, 255, 255))
    d.text((w + 16, 4), "after fn_service", fill=(255, 255, 255))
    img.save(out)
    os.remove(a)
    os.remove(b)
    return out


if __name__ == "__main__":
    before, after, out_dir = sys.argv[1:4]
    rest = sys.argv[4:]
    regs = [(rest[i], *[int(v) for v in rest[i + 1:i + 5]]) for i in range(0, len(rest), 5)] if rest else REGIONS
    os.makedirs(out_dir, exist_ok=True)
    for name, x0, y0, x1, y1 in regs:
        print(pair(before, after, os.path.join(out_dir, name + ".png"), x0, y0, x1, y1))
