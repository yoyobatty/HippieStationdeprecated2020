"""Wiring view: the real-sprite render dimmed, with what mapforge laid on top.

supply pipes blue, scrubber pipes red, cables yellow, vents/scrubbers as dots, lights as white ticks on their wall,
APC / air alarm / fire alarm / camera as lettered badges. Zone edge outlined.
"""
from PIL import Image, ImageDraw, ImageEnhance, ImageFont

from forge import kit
from forge.kit import N, S, E, W

TILE = 32
COL = {"supply": (60, 140, 255), "scrubbers": (235, 70, 70), "cable": (250, 210, 40)}
OFF = {"supply": -6, "scrubbers": 6, "cable": 0}


def draw(b, base_png, out_png, region):
    x1, y1, x2, y2 = region
    img = Image.open(base_png).convert("RGB")
    img = ImageEnhance.Brightness(img).enhance(0.45)
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arialbd.ttf", 12)
    except OSError:
        font = ImageFont.load_default()

    def c(x, y, off=0):
        return ((x - x1) * TILE + TILE // 2 + off, (y2 - y) * TILE + TILE // 2 + off)

    m = b.m
    for (x, y) in b.zone:
        t = m.get(x, y)
        cx, cy = c(x, y)
        for cls in ("supply", "scrubbers"):
            mk = 0
            vent = False
            for o in t.objs:
                if kit.pipe_class(o.path) == cls:
                    mk |= kit.pipe_mask(o)
                    vent = vent or "/unary/" in o.path
            if not mk and not vent:
                continue
            o_ = OFF[cls]
            p0 = (cx + o_, cy + o_)
            for dd, (dx, dy) in kit.DELTA.items():
                if mk & dd:
                    d.line([p0, (p0[0] + dx * TILE // 2, p0[1] - dy * TILE // 2)], fill=COL[cls], width=3)
            if vent:
                d.ellipse([p0[0] - 5, p0[1] - 5, p0[0] + 5, p0[1] + 5], fill=COL[cls], outline=(255, 255, 255))
        if t.has(kit.CABLE):
            for dd, (dx, dy) in kit.DELTA.items():
                nb = m.get(x + dx, y + dy)
                if nb is not None and nb.has(kit.CABLE):
                    d.line([(cx, cy), (cx + dx * TILE // 2, cy - dy * TILE // 2)], fill=COL["cable"], width=3)
            d.rectangle([cx - 2, cy - 2, cx + 2, cy + 2], fill=COL["cable"])
        for o in t.objs:
            if o.isa("/obj/machinery/light"):
                side = {1: N, 2: S, 4: E, 8: W}[o.num("dir", 2)]
                dx, dy = kit.DELTA[side]
                px, py = cx + dx * 13, cy - dy * 13
                if dx:
                    d.rectangle([px - 2, py - 8, px + 2, py + 8], fill=(255, 255, 230))
                else:
                    d.rectangle([px - 8, py - 2, px + 8, py + 2], fill=(255, 255, 230))
            for pre, letter, col in (("/obj/machinery/power/apc", "P", (250, 210, 40)), ("/obj/machinery/airalarm", "A", (90, 220, 120)),
                                     ("/obj/machinery/firealarm", "F", (255, 120, 40)), ("/obj/machinery/camera", "C", (200, 200, 255)),
                                     ("/obj/machinery/light_switch", "s", (230, 230, 230))):
                if o.isa(pre):
                    px = cx + int(o.num("pixel_x") * 0.45)
                    py = cy - int(o.num("pixel_y") * 0.45)
                    d.rectangle([px - 7, py - 7, px + 7, py + 7], fill=(20, 20, 24), outline=col)
                    d.text((px - 4, py - 7), letter, fill=col, font=font)
    # zone outline
    for (x, y) in b.zone:
        cx, cy = (x - x1) * TILE, (y2 - y) * TILE
        for dd, (dx, dy) in kit.DELTA.items():
            if (x + dx, y + dy) not in b.zone:
                if dd == N:
                    d.line([(cx, cy), (cx + TILE, cy)], fill=(180, 180, 200), width=1)
                elif dd == S:
                    d.line([(cx, cy + TILE), (cx + TILE, cy + TILE)], fill=(180, 180, 200), width=1)
                elif dd == E:
                    d.line([(cx + TILE, cy), (cx + TILE, cy + TILE)], fill=(180, 180, 200), width=1)
                else:
                    d.line([(cx, cy), (cx, cy + TILE)], fill=(180, 180, 200), width=1)
    img.save(out_png)
    return out_png
