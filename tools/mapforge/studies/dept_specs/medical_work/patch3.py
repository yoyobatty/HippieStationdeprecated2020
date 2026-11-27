"""One-off edit of gen/learn/fn_medical.py after running check() on the stock maps: firelock lines split rooms (Box's
treatment block was one "surgery"), windoors need access, the abandoned medbay and scraps left out, type-level kit
rules, stock-calibrated thresholds. Scratch, kept for the record."""
p = 'tools/mapforge/gen/learn/fn_medical.py'
s = open(p).read()


def rep(old, new, cnt=1):
    global s
    assert s.count(old) == cnt, (old[:80], s.count(old))
    s = s.replace(old, new)


rep('''def _is_med(a):
    return a is not None and a.startswith(MED)''', '''def _is_med(a):
    return a is not None and a.startswith(MED) and not a.startswith("/area/medical/abandoned")''')
rep('''    return t is not None and t.turf is not None and t.tpath.startswith("/turf/open") \\
        and not t.tpath.startswith("/turf/open/space") and not CO.solid(t) and not t.has("/obj/machinery/door/airlock") \\
        and not (t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"))''', '''    return t is not None and t.turf is not None and t.tpath.startswith("/turf/open") \\
        and not t.tpath.startswith("/turf/open/space") and not CO.solid(t) and not t.has("/obj/machinery/door/airlock") \\
        and not t.has("/obj/machinery/door/firedoor") \\
        and not (t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"))''')
# side(): through airlocks and firelock lines
rep('''            if t.has("/obj/machinery/door/airlock") and step:
                p = (p[0] + step[0], p[1] + step[1])
                continue
            if not t.tpath.startswith("/turf/open") or CO.solid(t):
                return ("X", "wall")
            return ("X", _outside(t.apath))''', '''            if (t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/firedoor")) and step \\
                    and not t.has("/obj/structure/table") and t.tpath.startswith("/turf/open"):
                p = (p[0] + step[0], p[1] + step[1])
                continue
            if not t.tpath.startswith("/turf/open") or CO.solid(t):
                return ("X", "wall")
            return ("X", _outside(t.apath))''')
rep('''                    elif tw.has("/obj/machinery/door/window") and tw.has("/obj/structure/table"):''', '''                    elif tw.has("/obj/machinery/door/firedoor") and not tw.has("/obj/structure/table") \\
                            and tw.tpath.startswith("/turf/open") and not CO.solid(tw):
                        a = self.side((w[0] + dx, w[1] + dy), (dx, dy))
                        if a[1] != "wall" and a != ("P", i) and not any(s == a and k == "open" for s, k, _ in self.links[i]):
                            self.links[i].append((a, "open", w))
                            if a[0] == "P":
                                self.links[a[1]].append((("P", i), "open", w))
                    elif tw.has("/obj/machinery/door/window") and tw.has("/obj/structure/table"):''')
# windoors want access; the chapel is walked too
rep('''            for o in t.objs:
                if o.path.startswith("/obj/machinery/door/airlock"):
                    return _opens(o, acc)
            return not (t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"))''', '''            if t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"):
                return False
            for o in t.objs:
                if o.path.startswith(("/obj/machinery/door/airlock", "/obj/machinery/door/window")) and not _opens(o, acc):
                    return False
            return True''')
rep('''                if not ok(tn) or not (tn.apath.startswith("/area/hallway") or _is_med(tn.apath)
                                      or tn.has("/obj/machinery/door/airlock")):''', '''                if not ok(tn) or not (tn.apath.startswith(("/area/hallway", "/area/chapel")) or _is_med(tn.apath)
                                      or tn.has("/obj/machinery/door/airlock")):''')
# fronts: firelocks too
rep('''        for (x, y, z), t in self.m.tiles.items():
            if z == 1 and t.has("/obj/machinery/door/airlock"):
                for dx, dy in N4:
                    out.add((x + dx, y + dy))
        return out''', '''        for (x, y, z), t in self.m.tiles.items():
            if z == 1 and (t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/firedoor")):
                for dx, dy in N4:
                    out.add((x + dx, y + dy))
        return out''')
# scraps (under 4 tiles) aren't rooms
rep('''        for P in self.pieces:
            P["type"] = classify(P["area"], len(P["tiles"]), P["kit"])''', '''        for P in self.pieces:
            P["type"] = classify(P["area"], len(P["tiles"]), P["kit"]) if len(P["tiles"]) >= 4 or sum(P["kit"].values()) \\
                else "scrap"''')
# surgery: autopsy tables in the morgue aren't operating rooms
rep('''    opt = _tiles_with(m, allm, "/obj/structure/table/optable")''', '''    opt = [p for p in _tiles_with(m, allm, "/obj/structure/table/optable") if not m.get(*p).apath.startswith("/area/medical/morgue")]''')
# chemistry kit over the type, not per piece
rep('''    for P in chem:
        k = P["kit"]
        if (k["chem_dispenser"] or 0) < 1 or (k["chem_master"] or 0) < 1 or (k["chem_heater"] or 0) < 1:
            add(D.center(P), "chem_kit", "chemistry lacks a dispenser, ChemMaster or heater (8/8 have 2, 2, 2)")''', '''    if chem:
        k = Counter()
        for P in chem:
            k.update(P["kit"])
        if not k["chem_dispenser"] or not k["chem_master"] or not k["chem_heater"]:
            add(D.center(chem[0]), "chem_kit", "chemistry lacks a dispenser, ChemMaster or heater (8/8 have 2, 2, 2)")''')
rep('''        disp = [p for P in chem for p in _tiles_with(m, P["tiles"], "/obj/machinery/chem_dispenser")]
        if disp:
            d = _walk_dist(m, disp[0], lambda q: m.get(*q) is not None and m.get(*q).has("/obj/machinery/shower"), 30)
            if d is None or d > 15:
                add(disp[0], "chem_shower", "nearest emergency shower %s tiles from the dispenser (stock 4-27, "
                    "median 13; Hippie and Endo keep one in chemistry)" % (d if d is not None else "30+"))''', '''        disp = [p for P in chem for p in _tiles_with(m, P["tiles"], "/obj/machinery/chem_dispenser")]
        if disp:
            ds = [_walk_dist(m, q0, lambda q: m.get(*q) is not None and m.get(*q).has("/obj/machinery/shower"), 30)
                  for q0 in disp[:2]]
            d = min([x for x in ds if x is not None] or [None]) if any(x is not None for x in ds) else None
            if d is None or d > CHEM_SHOWER:
                add(disp[0], "chem_shower", "nearest emergency shower %s tiles from the dispensers (stock 4-26, "
                    "median 13, 7/8 within %d; Hippie and Endo keep one in chemistry)" % (d if d is not None else "30+", CHEM_SHOWER))''')
rep('''        if d is None or d > 15:
            fronts = D.fronts()''', '''        if d is None or d > CHEM_SHOWER:
            fronts = D.fronts()''')
rep('''WALKWAY = ("medhall", "lobby", "reception")''', '''WALKWAY = ("medhall", "lobby", "reception")
CHEM_SHOWER = 20    # walking tiles from the nearer chem dispenser to a shower (stock min 4-26: 7 of 8 within 20)''')
# morgue rules over the type
rep('''    for P in morg:
        n = P["kit"]["morgue"] or 0
        if n < 8:
            add(D.center(P), "morgue_trays", "%d morgue trays (stock 8-13)" % n)
        if not any(D.name(s) in ("MAINT", "HALL", "CHAPEL") for s, _, _ in D.links[P["i"]]):
            add(D.center(P), "morgue_exit", "no door to maintenance or the hall: bodies leave through medbay "
                "(stock 8/8: maintenance 7, hall 6)")
        if P["i"] in pub:
            add(D.center(P), "morgue_public", "the public walks into the morgue (stock 0/8: morgue access 6)")''', '''    if morg:
        n = sum(P["kit"]["morgue"] or 0 for P in morg)
        big = max(morg, key=lambda P: (P["kit"]["morgue"] or 0, len(P["tiles"])))
        if n < 8:
            add(D.center(big), "morgue_trays", "%d morgue trays (stock 8-13)" % n)
        if not any(D.name(s) in ("MAINT", "HALL", "CHAPEL") for P in morg for s, _, _ in D.links[P["i"]]):
            add(D.center(big), "morgue_exit", "no door to maintenance or the hall: bodies leave through medbay "
                "(stock 8/8: maintenance 7, hall 6)")
        if any(P["i"] in pub for P in morg):
            add(D.center(big), "morgue_public", "the public walks into the morgue (stock 0/8: morgue access 6)")''')
# through: open wards count as walkway, the morgue may be served from the hall or the chapel
rep('''    for t in ("lobby", "chemistry", "storage", "checkpoint", "cmo", "morgue", "treatment"):
        ps = D.of(t)
        if ps and not any(D.name(s) in WALKWAY + ("HALL",) for P in ps for s, _, _ in D.links[P["i"]]):''', '''    for t in ("lobby", "chemistry", "storage", "checkpoint", "cmo", "morgue", "treatment"):
        ps = D.of(t)
        ok_ = WALKWAY + ("HALL", "treatment", "cryo") + (("CHAPEL",) if t == "morgue" else ())
        if ps and not any(D.name(s) in ok_ for P in ps for s, _, _ in D.links[P["i"]]):''')
# public: only rooms the stock maps keep shut
rep('''    for P in D.pieces:
        if P["i"] in pub and P["type"] not in WALKWAY + ("patient_room", "treatment", "cryo", "surgery_obs", "surgery_prep",
                                                         "morgue"):''', '''    for P in D.pieces:
        if P["i"] in pub and P["type"] in ("surgery", "storage", "chemistry", "cmo", "genetics", "cloning", "viro_lab",
                                           "viro_airlock", "viro_cell", "viro_pen", "other") and len(P["tiles"]) >= 6:''')
# door names: "... Access" corridors lead toward the room
rep('''        nm = (o.get("name") or "").strip('"').lower()
        sides = {D.name(a), D.name(b)}
        for key, types in NAME_TYPES:''', '''        nm = (o.get("name") or "").strip('"').lower()
        sides = {D.name(a), D.name(b)}
        if "access" in nm:
            continue
        for key, types in NAME_TYPES:''')
open(p, 'w', newline='').write(s)
print("patched")
