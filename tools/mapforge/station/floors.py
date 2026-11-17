"""Floor styling after the rooms are furnished: the patterns a mapper lays by room type, not one turf wall to wall.

Mined from MetaStation (2026-11-16, user: "stylized floors and correct facing decals ... engineering especially likes
using plating, chevrons"):
- chapel: /turf/open/floor/plasteel/chapel in 2x2 blocks, dir by place in the block (top row 1 4, bottom row 8 2),
  the blocks on one grid across the room; the aisles and the leftover edge stay dark. The templates brought the
  chapel turf over without its dir, so every tile drew the same quarter.
- engineering (workshop, engine room, SMES, gravity, atmos, tech storage): the free floor in front of furniture is
  edged with hazard stripes facing it (stripes/line, an L where two sides meet: 9 5 10 6) with a corner piece where a
  stripe run turns round a piece (stripes/corner, 1 NW 4 NE 2 SE 8 SW); lockers and suit storage stand on a bot box,
  racks and crates on plating. Meta's engineering: 124 plasteel, 77 engine, 74 plating, 67 dark tiles; 180 stripe
  decals over 479 tiles.
"""
from forge import dmm, kit
from forge.kit import CARD, DELTA

CHAPEL = "/turf/open/floor/plasteel/chapel"
DARK = "/turf/open/floor/plasteel/dark"
PLATING = "/turf/open/floor/plating"
STEEL = "/turf/open/floor/plasteel"
ENGINE_FLOOR = "/turf/open/floor/engine"
HEAVY = ("/obj/machinery/power/smes", "/obj/machinery/gravity_generator", "/obj/machinery/power/emitter",
         "/obj/machinery/field/generator", "/obj/machinery/power/rad_collector", "/obj/machinery/power/port_gen",
         "/obj/machinery/the_singularitygen", "/obj/machinery/power/tesla_coil", "/obj/machinery/power/grounding_rod")
LINE = "/obj/effect/turf_decal/stripes/line"
CORNER = "/obj/effect/turf_decal/stripes/corner"
TILE = "/obj/effect/turf_decal/tile/"

ENGINEERING = ("/area/engine/engineering", "/area/engine/engine_room", "/area/engine/engine_smes",
               "/area/engine/gravity_generator", "/area/engine/atmos", "/area/storage/tech")
ON_BOT = ("/obj/structure/closet", "/obj/machinery/suit_storage_unit", "/obj/machinery/vending")
ON_PLATING = ("/obj/structure/rack", "/obj/structure/closet/crate")
# dense but part of the room's shell, or a piece you walk past rather than work at
NOT_FURNITURE = ("/obj/structure/window", "/obj/structure/grille", "/obj/machinery/door", "/obj/structure/plasticflaps",
                 "/obj/effect", "/obj/machinery/atmospherics/pipe", "/obj/structure/cable", "/obj/machinery/holopad",
                 "/obj/item", "/obj/structure/flora", "/obj/machinery/light")
DIAG = {(-1, 1): 1, (1, 1): 4, (1, -1): 2, (-1, -1): 8}     # stripes/corner and tile quarters: NW 1, NE 4, SE 2, SW 8


QUARTERS = {1: (1, 4), 2: (2, 8), 4: (4, 2), 8: (8, 1)}     # tile quarters painting each side's half


def nb(p, d):
    return (p[0] + DELTA[d][0], p[1] + DELTA[d][1])


def biggest_rect(cells, min_side=3):
    """The largest axis-aligned rectangle wholly inside cells with both sides >= min_side, as a set, or None."""
    if not cells:
        return None
    xs = sorted({p[0] for p in cells})
    ys = sorted({p[1] for p in cells})
    x0, x1, y0, y1 = xs[0], xs[-1], ys[0], ys[-1]
    h = {x: 0 for x in range(x0, x1 + 1)}
    best = None
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            h[x] = h[x] + 1 if (x, y) in cells else 0
        # largest rectangle in the histogram, heights >= min_side, width >= min_side
        stack = []
        for i, x in enumerate(list(range(x0, x1 + 1)) + [None]):
            hh = h[x] if x is not None else 0
            start = i
            while stack and stack[-1][1] >= hh:
                si, sh = stack.pop()
                w = i - si
                if sh >= min_side and w >= min_side and (best is None or sh * w > best[0]):
                    best = (sh * w, x0 + si, y - sh + 1, w, sh)
                start = si
                # the popped bar's height cut to hh still spans from si
            stack.append((start, hh))
    if best is None:
        return None
    _, bx, by, w, hh = best
    return {(x, y) for x in range(bx, bx + w) for y in range(by, by + hh)}


def style_floors(m, bd, keep=frozenset()):
    rooms = {}
    for p, rc in bd.room.items():
        if p in keep or p not in bd.zone:
            continue
        t = m.get(*p)
        if t is None or not t.tpath.startswith("/turf/open/floor"):
            continue
        rooms.setdefault(rc, []).append(p)
    notes = []
    for rc, tiles in sorted(rooms.items()):
        area = bd.roomdefs[rc]["area"]
        if area == "/area/chapel/main":
            notes.append(chapel(m, tiles))
        elif area.startswith(ENGINEERING):
            notes.append(engineering(m, set(tiles), area))
    return [n for n in notes if n]


def chapel(m, tiles):
    """Chapel tiles in whole 2x2 blocks on one grid; what a whole block doesn't fit goes dark."""
    # plain floor of any template (dark on Meta's, steel on others); carpet, wood and grime stay
    region = {p for p in tiles if m.get(*p).tpath in (DARK, CHAPEL, STEEL)}
    best = None
    for px in (0, 1):
        for py in (0, 1):
            blocks = [(x, y) for (x, y) in region if x % 2 == px and y % 2 == py and
                      all(q in region for q in ((x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)))]
            if best is None or len(blocks) > len(best):
                best = blocks
    done = {}
    for x, y in best or ():
        for q, d in (((x, y + 1), 1), ((x + 1, y + 1), 4), ((x, y), 8), ((x + 1, y), 2)):
            done[q] = d
    for p in region:
        t = m.get(*p)
        if p in done:
            t.turf = dmm.Atom(CHAPEL, [] if done[p] == 2 else [("dir", str(done[p]))])
        elif t.tpath in (CHAPEL, STEEL):
            t.turf = dmm.Atom(DARK)
        if p in done or t.tpath == DARK:
            t.objs = [o for o in t.objs if not o.path.startswith(TILE)]
    return "chapel: %d tiles in %d blocks" % (len(done), len(done) // 4)


def is_piece(o):
    return kit.is_dense_atom(o) and not o.path.startswith(NOT_FURNITURE) and \
        abs(o.num("pixel_x")) < 16 and abs(o.num("pixel_y")) < 16


def engineering(m, tiles, area):
    def piece(p):
        t = m.get(*p)
        return t is not None and any(is_piece(o) for o in t.objs)

    def door(p):
        t = m.get(*p)
        return t is not None and t.has("/obj/machinery/door")
    lines = corners = bots = plating = 0
    for p in tiles:
        t = m.get(*p)
        # the template's stripe fragments go: the edges are drawn again from where things stand now
        t.objs = [o for o in t.objs if not o.path.startswith((LINE, CORNER))]
        an = next((o for o in t.objs if is_piece(o)), None)
        if an is None:
            continue
        if an.path.startswith(ON_PLATING) and t.tpath.startswith("/turf/open/floor/plasteel"):
            t.turf = dmm.Atom(PLATING)
            t.objs = [o for o in t.objs if not o.path.startswith(("/obj/effect/turf_decal",))]
            plating += 1
        elif an.path.startswith(ON_BOT) and not an.path.startswith(ON_PLATING):
            t.objs = [o for o in t.objs if not o.path.startswith(TILE)]
            if not t.has("/obj/effect/turf_decal/bot") and not t.has("/obj/effect/turf_decal/delivery"):
                t.objs.insert(0, dmm.Atom("/obj/effect/turf_decal/bot"))
                bots += 1
    for p in sorted(tiles):
        t = m.get(*p)
        if piece(p) or door(p) or any(door(nb(p, d)) for d in CARD):
            continue
        mask = sum(d for d in CARD if nb(p, d) in tiles and piece(nb(p, d)))
        decals = []
        if mask in (1, 2, 4, 8, 5, 6, 9, 10):
            decals.append(mask)
        elif mask in (3, 12):
            decals += [mask & 5, mask & 10] if mask == 3 else [4, 8]
        # a 3- or 4-sided nook is a stall between pieces: no edge drawn
        for (dx, dy), qd in DIAG.items():
            sx = 4 if dx > 0 else 8
            sy = 1 if dy > 0 else 2
            q = (p[0] + dx, p[1] + dy)
            if q in tiles and piece(q) and not mask & sx and not mask & sy and \
                    not piece((p[0] + dx, p[1])) and not piece((p[0], p[1] + dy)):
                t.objs.insert(0, dmm.Atom(CORNER, [] if qd == 2 else [("dir", str(qd))]))
                corners += 1
        for d in decals:
            t.objs.insert(0, dmm.Atom(LINE, [] if d == 2 else [("dir", str(d))]))
            lines += 1
    # floor zones: a heavy machine stands on an engine-floor pad (its tile and the ring round it), the other work
    # bays (the pieces and the striped floor in front of them) on dark plasteel; the walkway keeps the room's steel
    # and its trim. Only plain steel changes: plating under racks, a template's own floor, stay.
    pads = set()
    for p in tiles:
        if any(o.path.startswith(HEAVY) for o in m.get(*p).objs):
            pads |= {(p[0] + dx, p[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)} & tiles
    dark = engine = 0

    def by_door(p):
        return door(p) or any(door(nb(p, d)) for d in CARD)

    def bay(p):
        t = m.get(*p)
        return piece(p) or any(o.path.startswith((LINE, CORNER)) for o in t.objs)
    steel = {p for p in tiles if m.get(*p).tpath == STEEL}
    # the walkway: open steel in rectangles 3x3 or bigger (biggest first); a pocket between bays narrower than that
    # joins the bays, so the dark floor and the walkway meet in straight lines rather than round every piece
    walk = set()
    open_ = {p for p in steel if not bay(p)}
    if any(bay(p) for p in steel) and biggest_rect(open_):
        while True:
            r = biggest_rect(open_ - walk)
            if r is None:
                break
            walk |= r
    else:
        walk = set(open_)     # too narrow for a walkway (a 2-wide strip): only the bays change
    # the tile inside a door goes with the floor beside it (left steel it was a pale square in a dark bay)
    for p in steel - walk:
        if by_door(p) and not door(p) and not bay(p):
            side = [q for d in CARD for q in (nb(p, d),) if q in steel and not by_door(q)]
            if side and sum(1 for q in side if q in walk) * 2 > len(side):
                walk.add(p)
    for p in steel:
        t = m.get(*p)
        if door(p) or p in walk:
            continue
        if p in pads:
            t.turf = dmm.Atom(ENGINE_FLOOR)
            engine += 1
        else:
            t.turf = dmm.Atom(DARK)
            dark += 1
        t.objs = [o for o in t.objs if not o.path.startswith(TILE)]
    # the walkway's edge toward the bays in the department colour, the half facing out
    trim = 0
    colour = "yellow"
    for p in walk:
        t = m.get(*p)
        for d, qs in QUARTERS.items():
            q = nb(p, d)
            if q in tiles and q not in walk and m.get(*q).tpath in (DARK, ENGINE_FLOOR):
                for qd in qs:
                    a = dmm.Atom(TILE + colour, [] if qd == 2 else [("dir", str(qd))])
                    if not any(o.text() == a.text() for o in t.objs):
                        t.objs.insert(0, a)
                        trim += 1
    if not (lines or corners or bots or plating):
        return None
    return "floors %s: %d stripe edges, %d corners, %d bot boxes, %d racks/crates on plating, %d dark bay, %d engine pad" % (
        area.replace("/area/", ""), lines, corners, bots, plating, dark, engine)
