#!/usr/bin/env python3
"""Lists pipes on a .dmm that end at nothing: a run with a tile missing from the middle of it, or a vent that was lost.

  python tools/mapmerge2/find_pipe_gaps.py map.dmm [map.dmm ...]

Reads the map, needs no game. A pipe leaves every direction it faces looking for something to join on the next tile, on
the same piping layer. One that finds nothing doesn't leak or complain: whatever is further along just never gets any gas,
so a room's vents go quiet and nothing in the logs says why. Each tile is listed with the directions that are open, and
the map's own runs of pipe are what to go by when closing them. A gap two tiles long shows up as two open ends facing
each other across a tile with no pipe on it.
"""
import collections
import re
import sys

COLUMN = re.compile(r'\((\d+),(\d+),(\d+)\) = \{"\n?([a-zA-Z\n]*?)\n?"\}')
ATOM = re.compile(r"^/obj/machinery/atmospherics/([^\n,{]+)(\{[^}]*\})?", re.M)
N, S, E, W = 1, 2, 4, 8
STEPS = {N: (0, 1), S: (0, -1), E: (1, 0), W: (-1, 0)}
OPPOSITE = {N: S, S: N, E: W, W: E}
NAMES = {N: "N", S: "S", E: "E", W: "W"}
CLOCKWISE = {N: E, E: S, S: W, W: N}


def read_map(path):
    text = open(path, encoding="utf-8", errors="replace", newline="").read().replace("\r\n", "\n")
    grid = COLUMN.search(text).start()
    starts = list(re.finditer(r'^"([A-Za-z]+)" = \(', text, re.M))
    models = {}
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else grid
        # Some maps keep a whole model on one line.
        models[match.group(1)] = re.sub(r",(?=/(?:obj|turf|area)/)", ",\n", text[match.end():end])
    width = len(starts[0].group(1))
    tiles = {}
    for match in COLUMN.finditer(text):
        x0, z = int(match.group(1)), int(match.group(3))
        rows = [row for row in match.group(4).split("\n") if row]
        for dy, row in enumerate(rows):
            for dx in range(0, len(row), width):
                tiles[(x0 + dx // width, len(rows) - dy, z)] = models.get(row[dx:dx + width], "")
    return tiles


def faces(path, attrs):
    """The directions an atom joins pipes in, and its piping layer (None for every layer)."""
    found = re.search(r"\bdir = (\d+)", attrs or "")
    d = int(found.group(1)) if found else S
    layer = 1 if "layer1" in path else 3 if "layer3" in path else 2
    found = re.search(r"piping_layer = (\d)", attrs or "")
    if found:
        layer = int(found.group(1))
    if "layer_manifold" in path:
        return ({N, S} if d in (N, S) else {E, W}), None
    if "/simple" in path:
        return ({N, S} if d in (N, S) else {E, W} if d in (E, W) else {x for x in (N, S, E, W) if d & x}), layer
    if "manifold4w" in path:
        return {N, S, E, W}, layer
    if "/manifold" in path:
        return {N, S, E, W} - {d}, layer
    if d not in OPPOSITE:
        return set(), layer  # a diagonal or a stray dir = 0 on something that only faces straight
    if "heat_exchanging/junction" in path or "binary/" in path:
        return {d, OPPOSITE[d]}, layer
    if "trinary/" in path:
        one, two, three = OPPOSITE[d], CLOCKWISE[d], d
        if "flipped" in path:
            one, three = OPPOSITE[one], OPPOSITE[three]
        return {one, two, three}, layer
    if "unary/" in path:
        return {d}, layer
    return set(), layer


def main():
    for path in sys.argv[1:]:
        tiles = read_map(path)
        pieces = collections.defaultdict(list)
        for place, model in tiles.items():
            for match in ATOM.finditer(model):
                sides, layer = faces(match.group(1), match.group(2))
                if sides:
                    pieces[place].append((match.group(1), sides, layer))
        open_ends = []
        for (x, y, z), here in pieces.items():
            for atom, sides, layer in here:
                if not atom.startswith("pipe/") or "layer_manifold" in atom:
                    continue
                for d in sides:
                    dx, dy = STEPS[d]
                    beside = pieces.get((x + dx, y + dy, z), [])
                    if not any(OPPOSITE[d] in other_sides and (layer is None or other_layer is None or other_layer == layer) for _, other_sides, other_layer in beside):
                        open_ends.append(((x, y, z), NAMES[d], atom))
        print(f"{path}: {len(open_ends)} open pipe ends")
        for (x, y, z), side, atom in sorted(open_ends):
            area = (re.findall(r"/area/[^\s,)]+", tiles[(x, y, z)]) or ["?"])[-1].replace("/area/", "")
            print(f"  ({x},{y},{z}) {side} {atom.replace('pipe/', '')} [{area}]")


if __name__ == "__main__":
    main()
