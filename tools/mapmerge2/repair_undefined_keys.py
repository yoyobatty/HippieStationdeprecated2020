#!/usr/bin/env python3
"""Repairs .dmm maps whose grid uses keys the dictionary doesn't define.

The map loader stops dead on the first such key (reader.dm: "Undefined model key in DMM") and the whole map is lost, so
the round starts on an empty z-level. Box, Delta, Meta and Pubby came from upstream like this: a bad merge kept tiles in
the grid and dropped their definitions from the dictionary.

  python tools/mapmerge2/repair_undefined_keys.py [--write] map.dmm [map.dmm ...]

A key stood for one model, so this writes that model back, working out what it most likely was from every cell that
uses it: the turf and area its neighbours agree on, and any cable or pipe running straight through (both neighbours on
opposite sides carry the identical piece). The grid isn't touched. What it can't recover is whatever else was on the
tile, a door or a vent or a light, so each new definition is printed for a person to look over.
Without --write it only reports.

Check its work with a real boot and with find_pipe_gaps.py: a bend or a junction doesn't have the identical piece on both
sides, so those stay cut, and 25 air and engine lines did on the maps above. Pubby's engine lost its whole coolant return
to one such tile. Cables need the same care the other way: a bare one links to everything beside it, so put back where
two grids run alongside each other it can join them.

It also lists models that are defined but have no turf or no area. Those fail one tile at a time: the loader stops on
each and leaves space there, which is how Endo lost a whole shuttle dock and the wall of Research with it. The list is
all it does about them, because what's next to such a tile has usually lost the same thing.
"""
import collections
import re
import sys

COLUMN = re.compile(r'\((\d+),(\d+),(\d+)\) = \{"\n?([a-zA-Z\n]*?)\n?"\}')
MODEL_START = re.compile(r'^"([A-Za-z]+)" = \(', re.M)
# Runs of these carry on from tile to tile, so a gap in one is worth closing.
RUNS = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe/segment", "/obj/structure/lattice")


def split_entries(body):
    """A model's atoms, one string each, keeping any {var edits}."""
    entries = []
    depth = 0
    current = ""
    for char in body:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        if char == "," and depth == 0:
            entries.append(current.strip())
            current = ""
        else:
            current += char
    if current.strip():
        entries.append(current.strip())
    return entries


def read_models(text):
    models = {}
    starts = list(MODEL_START.finditer(text))
    grid_start = COLUMN.search(text).start()
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else grid_start
        body = text[match.end():end].rstrip()
        models[match.group(1)] = split_entries(body[:-1] if body.endswith(")") else body)
    return models


def turf_area(entries):
    turf = next((e for e in entries if e.startswith("/turf")), None)
    area = next((e for e in entries if e.startswith("/area")), None)
    return turf, area


def repair(path, write):
    with open(path, "rb") as handle:
        raw = handle.read()
    crlf = b"\r\n" in raw
    text = raw.decode("utf-8", errors="surrogateescape").replace("\r\n", "\n")
    models = read_models(text)
    key_len = len(next(iter(models)))
    columns = {}
    for match in COLUMN.finditer(text):
        rows = [row for row in match.group(4).split("\n") if row]
        if any(len(row) != key_len for row in rows):
            print(f"{path}: not a TGM map, nothing done")
            return
        columns[(int(match.group(1)), int(match.group(3)))] = rows

    def neighbour(x, y, z):
        rows = columns.get((x, z))
        if rows and 0 <= y < len(rows):
            return models.get(rows[y])
        return None

    cells = collections.defaultdict(list)
    for (x, z), rows in columns.items():
        for y, key in enumerate(rows):
            if key not in models:
                cells[key].append((x, y, z))
    print(f"{path}: {sum(len(c) for c in cells.values())} cells use {len(cells)} undefined keys")
    in_use = {key for rows in columns.values() for key in rows}
    incomplete = sorted(key for key in in_use if key in models and None in turf_area(models[key]))
    if incomplete:
        print(f"  {len(incomplete)} models lack a turf or an area, and those tiles will be space: {' '.join(incomplete)}")

    new_models = {}
    for key, places in sorted(cells.items()):
        ground = collections.Counter()
        runs = collections.Counter()
        wired = 0
        for x, y, z in places:
            pairs = [(neighbour(x - 1, y, z), neighbour(x + 1, y, z)), (neighbour(x, y - 1, z), neighbour(x, y + 1, z))]
            # Cables here join up by themselves (a bare /obj/structure/cable links to whatever's beside it), corners
            # and all, so two neighbours with one means this tile was part of the run. Losing one cuts a whole grid:
            # the first go at Box took the SMES room's trunk line out at a single tile, and the station went dark.
            around = [side for pair in pairs for side in pair if side]
            if sum(any(e.startswith("/obj/structure/cable") for e in side) for side in around) >= 2:
                wired += 1
            for first, second in pairs:
                for side in (first, second):
                    if side:
                        ground[turf_area(side)] += 1
                if first and second:
                    if turf_area(first) == turf_area(second):
                        ground[turf_area(first)] += 3 #both sides agree: as good as it gets
                    for entry in first:
                        if entry.startswith(RUNS) and entry in second:
                            runs[entry] += 1
        if not ground:
            print(f"  {key}: nothing around it to go by, left undefined")
            continue
        (turf, area), _ = ground.most_common(1)[0]
        is_wired = wired * 2 >= len(places)
        entries = [entry for entry, count in runs.items() if count * 2 >= len(places) and not entry.startswith("/obj/structure/cable")]
        if is_wired:
            entries.append("/obj/structure/cable")
        # Space with a cable through it was a catwalk: wiring out in the open, between two parts of the station.
        # Space with a floor beside it and nothing through it would be a hole in the hull, and a wrong wall can't vent
        # a room: the nearest kind of wall, then, or failing that a plain one, in the room next door.
        if turf.startswith("/turf/open/space") and entries:
            entries = ["/obj/structure/lattice/catwalk"] + [e for e in entries if not e.startswith("/obj/structure/lattice")]
        elif turf.startswith("/turf/open/space") and any(t and t.startswith("/turf/open/floor") for t, _ in ground):
            walls = [pair for pair in ground if pair[0] and pair[0].startswith("/turf/closed")]
            indoors = [pair for pair in ground if pair[1] and "/area/space" not in pair[1]]
            turf = max(walls, key=lambda pair: ground[pair])[0] if walls else "/turf/closed/wall/r_wall"
            area = max(indoors, key=lambda pair: ground[pair])[1] if indoors else area
        if turf.startswith("/turf/closed") and entries:
            # A wall can't carry a cable or a pipe, and something was carrying it. Bare plating does.
            turf = "/turf/open/floor/plating"
        new_models[key] = entries + [turf, area]
        where = ", ".join(f"({x},{len(columns[(x, z)]) - y},{z})" for x, y, z in places[:3])
        short = " ".join(e.split("{")[0].rsplit("/", 1)[-1] for e in new_models[key])
        print(f"  {key} x{len(places)} at {where}: {short}")

    if not write or not new_models:
        return
    block = "".join(f'"{key}" = (\n' + ",\n".join(entries) + ")\n" for key, entries in sorted(new_models.items()))
    grid_start = COLUMN.search(text).start()
    head = text[:grid_start].rstrip("\n") + "\n"
    text = head + block + "\n" + text[grid_start:]
    if crlf:
        text = text.replace("\n", "\r\n")
    with open(path, "wb") as handle:
        handle.write(text.encode("utf-8", errors="surrogateescape"))
    print(f"  wrote {len(new_models)} definitions")


def main():
    args = sys.argv[1:]
    write = "--write" in args
    paths = [a for a in args if a != "--write"]
    if not paths:
        sys.exit(__doc__)
    for path in paths:
        repair(path, write)


if __name__ == "__main__":
    main()
