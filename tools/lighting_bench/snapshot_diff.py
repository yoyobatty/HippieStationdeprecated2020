#!/usr/bin/env python3
"""Lists the tiles two lighting bench snapshots light differently, and how differently.

    python tools/lighting_bench/snapshot_diff.py                       # snapshot_booted.txt against snapshot_relit.txt
    python tools/lighting_bench/snapshot_diff.py --a booted --b toggled
    python tools/lighting_bench/snapshot_diff.py --dir data/lighting_bench_viewdm --list 40

Reads the snapshots lighting_bench_snapshot() writes (hippiestation/code/modules/lighting/lighting_bench.dm): one line
per tile with a lighting object, "x y visible" then twelve corner values (SW, SE, NW, NE; red, green, blue), or "L" for
fully lit, "D" for dark. Prints how many tiles differ, split by what differs (only the visible flag, lit or dark only on
one side, the corner values), the largest corner difference, the differing tiles grouped into clusters of touching
tiles (each with its bounding box, so a missing or extra light shows as one blob), and the first --list tiles in full.
Use --dir for another bench output folder; --a and --b take a snapshot name (snapshot_<name>.txt) or a path.
"""
import argparse
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def snapshot_path(directory, name):
    if os.path.exists(name):
        return name
    return os.path.join(directory, f"snapshot_{name}.txt")


def load(path):
    """-> {(x, y): (visible, values)} where values is 'L', 'D' or a tuple of 12 floats"""
    tiles = {}
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) < 4:
                continue
            x, y, visible = int(parts[0]), int(parts[1]), parts[2]
            rest = parts[3:]
            if rest[0] in ("L", "D"):
                values = rest[0]
            else:
                values = tuple(float(v) for v in rest)
            tiles[(x, y)] = (visible, values)
    return tiles


def as_values(values):
    if values == "L":
        return (1.0,) * 12
    if values == "D":
        return (0.0,) * 12
    return values


def clusters(points):
    """Groups points into sets of 8-way touching ones"""
    left = set(points)
    out = []
    while left:
        start = left.pop()
        group = [start]
        stack = [start]
        while stack:
            x, y = stack.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (x + dx, y + dy)
                    if n in left:
                        left.remove(n)
                        group.append(n)
                        stack.append(n)
        out.append(group)
    return sorted(out, key=len, reverse=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dir", default=os.path.join(ROOT, "data", "lighting_bench"), help="bench output folder")
    parser.add_argument("--a", default="booted", help="first snapshot (name or path), default booted")
    parser.add_argument("--b", default="relit", help="second snapshot (name or path), default relit")
    parser.add_argument("--list", type=int, default=15, help="how many differing tiles to print in full")
    parser.add_argument("--clusters", type=int, default=15, help="how many clusters to print")
    args = parser.parse_args()

    a = load(snapshot_path(args.dir, args.a))
    b = load(snapshot_path(args.dir, args.b))
    only_a = sorted(set(a) - set(b))
    only_b = sorted(set(b) - set(a))
    if only_a or only_b:
        print(f"tiles only in {args.a}: {len(only_a)}, only in {args.b}: {len(only_b)}")
    differing = []
    kinds = {"visible flag only": 0, "dark in a only": 0, "dark in b only": 0, "corner values": 0}
    worst = 0.0
    brighter_a = brighter_b = 0
    for key in sorted(set(a) & set(b)):
        va, vb = a[key], b[key]
        if va == vb:
            continue
        differing.append(key)
        if va[1] == vb[1]:
            kinds["visible flag only"] += 1
            continue
        if va[1] == "D":
            kinds["dark in a only"] += 1
        elif vb[1] == "D":
            kinds["dark in b only"] += 1
        else:
            kinds["corner values"] += 1
        xa, xb = as_values(va[1]), as_values(vb[1])
        delta = max(abs(p - q) for p, q in zip(xa, xb))
        worst = max(worst, delta)
        if sum(xa) > sum(xb):
            brighter_a += 1
        else:
            brighter_b += 1
    print(f"{len(differing)} of {len(a)} tiles differ between {args.a} and {args.b}")
    for kind, count in kinds.items():
        if count:
            print(f"  {kind}: {count}")
    print(f"  brighter in {args.a}: {brighter_a}, brighter in {args.b}: {brighter_b}; largest corner difference {worst:.4f}")
    groups = clusters(differing)
    print(f"{len(groups)} clusters of touching tiles")
    for group in groups[: args.clusters]:
        xs = [p[0] for p in group]
        ys = [p[1] for p in group]
        print(f"  {len(group)} tiles, x {min(xs)}-{max(xs)}, y {min(ys)}-{max(ys)}")
    for key in differing[: args.list]:
        print(f"  {key[0]},{key[1]}: {args.a} {a[key][0]} {a[key][1]}")
        print(f"  {' ' * len(f'{key[0]},{key[1]}')}  {args.b} {b[key][0]} {b[key][1]}")
    return 0 if not differing and not only_a and not only_b else 1


if __name__ == "__main__":
    sys.exit(main())
