"""Block plan for the Science redesign: draws the proposed rooms over the original outline.

    python tools/mapforge/studies/science_plan.py   -> data/previews/mapforge/science_plan.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from forge import render  # noqa: E402

ROOT = render.ROOT
X1, Y1, X2, Y2 = 158, 78, 236, 131
T = 32

# (label, x1, y1, x2, y2, colour) in map tiles, inclusive. Public = on the main hall.
BLOCKS = [
    ("MECH BAY\nlaunch shutters to hall", 164, 117, 169, 126, (90, 90, 120)),
    ("ROBOTICS\nfabs > belts > assembly floor\nborg/aug surgery behind glass", 170, 117, 179, 126, (120, 80, 160)),
    ("FOYER\n+ SEC POST", 180, 117, 184, 126, (170, 60, 60)),
    ("R&D\ndesk + chute on hall\nconsole pen", 185, 117, 196, 126, (150, 90, 200)),
    ("RESEARCH SPINE", 164, 114, 197, 116, (200, 200, 210)),
    ("SERVERS\n(cold, RD access)", 164, 106, 169, 113, (60, 110, 160)),
    ("RD OFFICE\nwatches spine + servers", 170, 106, 178, 113, (60, 140, 120)),
    ("NANITES\ndoor on spine", 179, 106, 186, 113, (100, 160, 160)),
    ("EXPERIMENTATION\nexperimentor + blast chamber\n(takes east maint)", 187, 106, 203, 113, (200, 120, 60)),
    ("XENOBIOLOGY\npens, processing,\nkill + cold room", 164, 84, 178, 105, (90, 160, 90)),
    ("SPINE S", 179, 84, 182, 113, (200, 200, 210)),
    ("TOXINS\ncanister bay joined to\nmixing, burn chamber kept", 183, 95, 196, 105, (200, 160, 60)),
    ("LAUNCH\n(kept: driver row 104)", 197, 101, 207, 108, (210, 110, 40)),
    ("TESTING LAB\nmagnets, ignition chamber", 183, 84, 197, 94, (180, 140, 100)),
    ("BOMB RANGE\n(kept)", 224, 100, 232, 108, (210, 110, 40)),
]


def main():
    base = os.path.join(render.PREVIEWS, "sci_full_orig.png")
    if not os.path.exists(base):
        render.render(os.path.join(ROOT, "_maps", "map_files", "HippieStation", "hippiestation.dmm"), base,
                      region=(X1, Y1, X2, Y2))
    img = Image.open(base).convert("RGBA")
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    try:
        font = ImageFont.truetype("arialbd.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    for label, x1, y1, x2, y2, col in BLOCKS:
        left, top = (x1 - X1) * T, (Y2 - y2) * T
        right, bottom = (x2 - X1 + 1) * T, (Y2 - y1 + 1) * T
        d.rectangle([left, top, right, bottom], fill=col + (150,), outline=(255, 255, 255, 230), width=3)
        d.multiline_text((left + 8, top + 6), label, fill=(255, 255, 255, 255), font=font, spacing=3)
    out = Image.alpha_composite(img, over).convert("RGB")
    out = out.resize((out.width // 2, out.height // 2), Image.LANCZOS)
    path = os.path.join(render.PREVIEWS, "science_plan.png")
    out.save(path)
    print(path)


if __name__ == "__main__":
    main()
