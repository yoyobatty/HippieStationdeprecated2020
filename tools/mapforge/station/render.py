"""Block-plan pictures: department floors in their trim colours, halls, maint, walls, doors by kind, docks, solars."""
import random

SPACE = (11, 13, 22)
WALL, HULL, RWALL = (104, 108, 118), (78, 82, 94), (58, 62, 74)
HALL, MAINT, CATWALK = (214, 214, 208), (84, 76, 66), (96, 96, 74)
DOOR = dict(public=(250, 250, 250), access=(236, 196, 64), secure=(220, 58, 58), maint=(168, 132, 86),
            link=(176, 186, 232), dock=(255, 140, 0), open=HALL)
GLASS = (126, 196, 236)


def tint(c, k):
    return tuple(int(v + (255 - v) * k) for v in c)


def draw(plan, path, T=6, title=None):
    from PIL import Image, ImageDraw, ImageFont
    pts = list(plan.floor) + list(plan.walls) + list(plan.doors)
    for (x, y), side, kind, (a, b) in plan.docks:
        pts.append((x - b, y - b))
        pts.append((x + b, y + b))
    for r, _ in plan.solars:
        pts += [(r[0], r[1]), (r[2], r[3])]
    x0 = min(p[0] for p in pts) - 3
    x1 = max(p[0] for p in pts) + 3
    y0 = min(p[1] for p in pts) - 3
    y1 = max(p[1] for p in pts) + 3
    head = 40
    img = Image.new("RGB", ((x1 - x0 + 1) * T, (y1 - y0 + 1) * T + head), SPACE)
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arialbd.ttf", 15)
        small = ImageFont.truetype("arial.ttf", max(9, T + 3))
        big = ImageFont.truetype("arialbd.ttf", max(12, T * 2 + 2))
    except OSError:
        font = small = big = ImageFont.load_default()
    rnd = random.Random(1)
    for _ in range((x1 - x0) * (y1 - y0) // 40):
        sx, sy = rnd.randrange(img.width), rnd.randrange(head, img.height)
        v = rnd.randrange(60, 160)
        d.point((sx, sy), fill=(v, v, v + 20))

    def box(p, inset=0):
        left, top = (p[0] - x0) * T, (y1 - p[1]) * T + head
        return [left + inset, top + inset, left + T - 1 - inset, top + T - 1 - inset]

    # solars first (under everything)
    for r, name in plan.solars:
        for x in range(r[0], r[2] + 1):
            for y in range(r[1], r[3] + 1):
                if (x - r[0]) % 3 == 2:
                    d.rectangle(box((x, y), T // 3), fill=(70, 70, 60))
                else:
                    d.rectangle(box((x, y), 1), fill=(36, 52, 112), outline=(70, 90, 160))
    for (x, y), side, kind, (a, b) in plan.docks:
        # a shuttle outline docked on the hull, a wide and b long outward
        dx, dy = side
        half = a // 2
        tiles = []
        for k in range(1, b + 1):
            for j in range(-half, half + 1):
                tiles.append((x + dx * k + (j if dy else 0), y + dy * k + (j if dx else 0)))
        for t in tiles:
            d.rectangle(box(t), fill=(150, 156, 170))
        for t in tiles:
            edge = sum(1 for e in ((1, 0), (-1, 0), (0, 1), (0, -1)) if (t[0] + e[0], t[1] + e[1]) not in tiles)
            if edge:
                d.rectangle(box(t), fill=(96, 100, 114))
        cx = sum(t[0] for t in tiles) / len(tiles)
        cy = sum(t[1] for t in tiles) / len(tiles)
        b_ = box((int(cx), int(round(cy))))
        d.text((b_[0], b_[1]), kind, fill=(20, 20, 30), font=small, anchor="mm")
    for p, rid in plan.floor.items():
        m = plan.rooms.get(rid, {})
        k = m.get("kind")
        if rid == "catwalk":
            col = CATWALK
        elif k == "maint":
            col = MAINT
        elif k == "hall":
            col = tint(m["colour"], 0.62) if m.get("colour") and not m.get("public") else HALL
            if m.get("colour") and m.get("public"):
                col = tint(m["colour"], 0.78)
        else:
            col = tint(m.get("colour", (200, 200, 200)), 0.38)
        d.rectangle(box(p), fill=col)
    for p in plan.walls:
        col = RWALL if p in plan.rwall else HULL if p in plan.hull else WALL
        d.rectangle(box(p), fill=col)
    for p in plan.glass:
        d.rectangle(box(p), fill=WALL)
        d.rectangle(box(p, 1), fill=GLASS)
    for p, kind in plan.doors.items():
        if kind == "open":
            d.rectangle(box(p), fill=HALL)
            continue
        d.rectangle(box(p), fill=(40, 40, 46))
        d.rectangle(box(p, 1), fill=DOOR.get(kind, (255, 0, 255)))
    # labels: room names at the room's middle tile
    for rid, m in plan.rooms.items():
        lab = m.get("label")
        if not lab:
            continue
        ts = plan.tiles(rid)
        if not ts:
            continue
        cx = sum(t[0] for t in ts) / float(len(ts))
        cy = sum(t[1] for t in ts) / float(len(ts))
        c = min(ts, key=lambda t: (t[0] - cx) ** 2 + (t[1] - cy) ** 2)
        b = box(c)
        col = (20, 20, 30)
        f = big if lab.isupper() else small
        d.text(((b[0] + b[2]) / 2, (b[1] + b[3]) / 2), lab, fill=col, font=f, anchor="mm")
    d.rectangle([0, 0, img.width, head - 1], fill=(20, 20, 26))
    d.text((8, 4), title or "", fill=(255, 255, 255), font=font)
    sub = "  ".join("%s %s" % (k, v) for k, v in (("sides", plan.sides),))[:220]
    d.text((8, 22), sub, fill=(170, 170, 180), font=small)
    img.save(path)
    return path
