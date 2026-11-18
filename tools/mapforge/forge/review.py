"""Claude crop review pass (plan C5): department crops with map coordinates drawn on, and the rubric a review uses.
Claude reads the crops, answers the rubric per crop and writes findings that name tiles, so each finding can become
a rule check (forge/rules.py) or a tag for the taste model.

    python tools/mapforge/forge/review.py gen_pinwheel_c80_s1 [dept ...]   # crops to data/mapforge/review/<map>/

Each crop is the department's box at 32 px a tile with a coordinate ruler every 5 tiles (x along the top, y down
the left, map coordinates as the game and the .dmm use them).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, gallery  # noqa: E402

OUT = os.path.join(parse.ROOT, "data", "mapforge", "review")

RUBRIC = """Rubric, per crop (answer each; name tiles as x,y):
1 Workflow: can each job here do its loop (fetch, work, hand over) without crossing someone else's work spot?
2 Entry: is the way in obvious, at the public side, with a desk or lobby where the public meets staff?
3 Furniture: does each piece face and serve a spot a person stands on; any piece orphaned, blocking, or doubled?
4 Walls: wall pieces (APC, alarms, lights, signs, buttons) where a mapper puts them; spacing, sides, height order.
5 Room shape: sizes and proportions a mapper would draw; leftover slivers, dead corners, oversized empty floor.
6 Look: floor/decal language like the department's on human maps; tile colour, borders, hazard marks only on hazards.
7 Tell: the single thing that most gives away a generated map, and the rule that would catch it."""


def packet(name, depts=None):
    from PIL import Image, ImageDraw
    from forge.render import _font
    sm = parse.load(name)
    png = gallery.full_renders([parse.map_path(name)], jobs=1)[parse.map_path(name)]
    full = Image.open(png).convert("RGB")
    out = os.path.join(OUT, sm.name)
    os.makedirs(out, exist_ok=True)
    boxes = gallery.dept_boxes(sm)
    ft = _font(13)
    made = []
    for d, box in boxes.items():
        if depts and d not in depts:
            continue
        c = gallery.crop(full, sm.m.maxy, box)
        T = 32
        c = c.resize((c.width * T // gallery.PX, c.height * T // gallery.PX), Image.NEAREST)
        M = 28
        im = Image.new("RGB", (c.width + M, c.height + M), (20, 22, 28))
        im.paste(c, (M, M))
        dr = ImageDraw.Draw(im)
        x0, y0, x1, y1 = box
        for x in range(x0, x1 + 1):
            if x % 5 == 0:
                X = M + (x - x0) * T
                dr.line([(X, M), (X, im.height)], fill=(255, 255, 255), width=1)
                dr.text((X + 2, 6), str(x), fill=(230, 230, 230), font=ft)
        for y in range(y1, y0 - 1, -1):
            if y % 5 == 0:
                Y = M + (y1 - y) * T
                dr.line([(M, Y), (im.width, Y)], fill=(255, 255, 255), width=1)
                dr.text((2, Y + 2), str(y), fill=(230, 230, 230), font=ft)
        p = os.path.join(out, "%s.png" % d)
        im.save(p)
        made.append(p)
    open(os.path.join(out, "rubric.txt"), "w").write(RUBRIC + "\n")
    print("%d crops in %s" % (len(made), out))
    return made


if __name__ == "__main__":
    packet(sys.argv[1] if len(sys.argv) > 1 else "gen_pinwheel_c80_s1", sys.argv[2:] or None)
