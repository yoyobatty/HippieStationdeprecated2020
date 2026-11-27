"""One-off edit of gen/learn/fn_medical.py after the first picture review: machines only on bare floor, mobs kept,
mounted pieces never carried with furniture, two surgery tool tables, the morgue's things follow it, cryo beakers off
the pipes, seats in one run, the monkey pen in the cell with no machines. Scratch, kept for the record."""
p = 'tools/mapforge/gen/learn/fn_medical.py'
s = open(p).read()


def rep(old, new, cnt=1):
    global s
    assert s.count(old) == cnt, (old[:80], s.count(old))
    s = s.replace(old, new)


# mobs stay when a room is cleared
rep('''        "/obj/machinery/navbeacon", "/obj/machinery/power/terminal", "/obj/structure/lattice")
''', '''        "/obj/machinery/navbeacon", "/obj/machinery/power/terminal", "/obj/structure/lattice", "/mob/living/simple_animal")
# what may share a tile with a placed piece: wiring, pipes, vents, decals, landmarks (and wall-mounted pieces)
BARE_OK = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/machinery/atmospherics/components/unary/vent",
           "/obj/structure/disposalpipe", "/obj/effect/turf_decal", "/obj/effect/landmark", "/obj/machinery/navbeacon")
''')
rep('''def _free(t):
    return _room_floor(t) and not _dense(t)
''', '''def _free(t):
    return _room_floor(t) and not _dense(t)


def _bare(t):
    """Free floor with nothing on it but wiring, pipes, vents, decals and wall-mounted pieces."""
    return _free(t) and all(o.path.startswith(BARE_OK) or CO.mounted(o) for o in t.objs)
''')
rep('''    cands = [p for p in room if _free(m.get(*p)) and p not in fronts and p not in avoid and (want is None or want(p))]''',
    '''    cands = [p for p in room if _bare(m.get(*p)) and p not in fronts and p not in avoid and (want is None or want(p))]''')
# surgery tools: two tables, the rest on the first
rep('''    tools = list(SURGERY_TOOLS)
    for k in range(3):
        if not tools:
            break
        put = tools[:4] if k < 2 else tools
        tools = tools[len(put):]
        p = _place(m, room, fronts, [dmm.Atom("/obj/structure/table")] + [dmm.Atom(x) for x in put],
                   want=lambda p: _walls(m, p) and max(abs(p[0] - table[0]), abs(p[1] - table[1])) <= 3,
                   prefer=lambda p: abs(p[0] - table[0]) + abs(p[1] - table[1]))
        if p is None:
            p = _place(m, room, fronts, [dmm.Atom("/obj/structure/table")] + [dmm.Atom(x) for x in put],
                       want=lambda p: max(abs(p[0] - table[0]), abs(p[1] - table[1])) <= 3)
        if p is None:
            # no table spot left: the tools on the floor by the table (the bot picks them up)
            q = _stand(m, table, room)
            if q:
                m.get(*q).objs.extend(dmm.Atom(x) for x in put)''', '''    first = None
    for put in (SURGERY_TOOLS[:8], SURGERY_TOOLS[8:]):
        p = _place(m, room, fronts, [dmm.Atom("/obj/structure/table")] + [dmm.Atom(x) for x in put],
                   want=lambda p: _walls(m, p) and max(abs(p[0] - table[0]), abs(p[1] - table[1])) <= 3,
                   prefer=lambda p: abs(p[0] - table[0]) + abs(p[1] - table[1]))
        if p is None:
            p = _place(m, room, fronts, [dmm.Atom("/obj/structure/table")] + [dmm.Atom(x) for x in put],
                       want=lambda p: max(abs(p[0] - table[0]), abs(p[1] - table[1])) <= 3)
        if p is None:
            # no table spot left: on the first tool table, else on the floor by the operating table
            q = first or _stand(m, table, room)
            if q:
                m.get(*q).objs.extend(dmm.Atom(x) for x in put)
        first = first or p''')
# the morgue's things follow it
rep('''    if H is not None:
        gone = _clear(m, H["tiles"])
        _retype(m, H["tiles"], P["area"])
        if old == "morgue":
            n = _furnish_morgue(m, H["tiles"], fronts, 10)
            _place(m, H["tiles"], fronts, [dmm.Atom("/obj/structure/table"), dmm.Atom("/obj/item/storage/box/bodybags")],
                   want=lambda p: len(_walls(m, p)) >= 1)''', '''    if H is not None:
        gone = _clear(m, H["tiles"])
        _retype(m, H["tiles"], P["area"])
        if old == "morgue":
            n = _furnish_morgue(m, H["tiles"], fronts, 10)
            things = [o for p in P["tiles"] for o in m.get(*p).objs if o.path.startswith(
                ("/obj/item/storage/box/bodybags", "/obj/item/bodybag", "/obj/item/clothing/under/burial",
                 "/obj/item/reagent_containers/food/snacks/grown/poppy")) and not CO.mounted(o)]
            things = things or [dmm.Atom("/obj/item/storage/box/bodybags")]
            if not _place(m, H["tiles"], fronts, [dmm.Atom("/obj/structure/table")] + things,
                          want=lambda p: len(_walls(m, p)) >= 1):
                q = next((q for q in sorted(H["tiles"]) if _bare(m.get(*q)) and q not in fronts), None)
                if q:
                    m.get(*q).objs.extend(things)''')
# cryo: mounted pieces stay on the front tiles; beakers never on the pipes
rep('''            keep = [o for o in t.objs if (not FN.is_dense(o) or o.path.startswith(KEEP)) and not o.path.startswith(
                ("/obj/item", "/obj/structure/chair"))]''', '''            keep = [o for o in t.objs if CO.mounted(o) or ((not FN.is_dense(o) or o.path.startswith(KEEP))
                                                            and not o.path.startswith(("/obj/item", "/obj/structure/chair")))]''')
rep('''        if items:
            p = _place(m, room, fronts, ([tables[0]] if tables else [dmm.Atom("/obj/structure/table/glass")]) + items[:6],
                       want=lambda p: bool(_walls(m, p)), keep_free=front)
            if p is None:
                q = next((q for q in sorted(room) if _free(m.get(*q)) and q not in fronts), None)
                if q:
                    m.get(*q).objs.extend(items[:6])''', '''        if items:
            p = _place(m, room, fronts, ([tables[0]] if tables else [dmm.Atom("/obj/structure/table/glass")]) + items[:6],
                       want=lambda p: bool(_walls(m, p)), keep_free=front, avoid=set(tiles.values()))
            if p is None:
                q = next((q for q in sorted(room) if _bare(m.get(*q)) and q not in fronts and q not in tiles.values()),
                         None) or next((q for q in sorted(room) if _bare(m.get(*q))), None)
                if q:
                    m.get(*q).objs.extend(items[:6])''')
# chem desk: the table and its loose things move, wall-mounted pieces stay
rep('''                moving = [o for o in t.objs if o.path.startswith(("/obj/structure/table", "/obj/item"))]''',
    '''                moving = [o for o in t.objs if o.path.startswith(("/obj/structure/table", "/obj/item")) and not CO.mounted(o)]''')
# seats: one run along one wall
rep('''        got = 0
        for _ in range(3):
            p = _place(m, P["tiles"], fronts, [dmm.Atom("/obj/structure/chair")],
                       want=lambda p: len(_walls(m, p)) == 1 and 2 <= near(p) <= 8
                       and not m.get(*p).has("/obj/structure/chair"), dir_from_wall=1, prefer=near)
            if p:
                got += 1''', '''        got = []
        for _ in range(3):
            p = _place(m, P["tiles"], fronts, [dmm.Atom("/obj/structure/chair")],
                       want=lambda p: len(_walls(m, p)) == 1 and 2 <= near(p) <= 8 and (not got or (
                           any(abs(p[0] - g[0]) + abs(p[1] - g[1]) == 1 for g in got) and _walls(m, p) == _walls(m, got[0]))),
                       dir_from_wall=1, prefer=near)
            if p:
                got.append(p)
        got = len(got)''')
# monkey pen: the cell with no machines
rep('''        cells = sorted(D.of("viro_cell"), key=lambda P: (-len(P["tiles"]), min(P["tiles"])))''',
    '''        cells = sorted(D.of("viro_cell"), key=lambda P: (sum(1 for p in P["tiles"] for o in m.get(*p).objs
                                                             if o.path.startswith("/obj/machinery/computer")),
                                                         -len(P["tiles"]), min(P["tiles"])))''')
rep('''            spots = [p for p in sorted(P["tiles"]) if _free(m.get(*p)) and p not in fronts]
            for p in spots[:4]:''', '''            spots = [p for p in sorted(P["tiles"]) if _bare(m.get(*p)) and p not in fronts]
            for p in spots[:4]:''')
# cloning re-seat on bare tiles only
rep('''        for c in sorted(room):
            if c in fronts or not _free(m.get(*c)):
                continue
            nbs = [(c[0] + dx, c[1] + dy) for dx, dy in N4]
            nbs = [q for q in nbs if q in room and _free(m.get(*q)) and q not in fronts]''', '''        for c in sorted(room):
            if c in fronts or not _bare(m.get(*c)):
                continue
            nbs = [(c[0] + dx, c[1] + dy) for dx, dy in N4]
            nbs = [q for q in nbs if q in room and _bare(m.get(*q)) and q not in fronts]''')
open(p, 'w', newline='').write(s)
print("patched")
