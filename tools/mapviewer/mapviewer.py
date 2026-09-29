#!/usr/bin/env python3
"""Simple map viewer: renders .dmm maps with real sprites and opens them in a browser page where you can zoom,
pan and hover any tile to see what's on it.

    python tools/mapviewer/mapviewer.py                       # every room in _maps/RandomRooms
    python tools/mapviewer/mapviewer.py _maps/map_files/HippieStation/hippiestation.dmm
    python tools/mapviewer/mapviewer.py some/dir other.dmm --no-open

Rendering is done by SpacemanDMM's dmm-tools (downloaded once into tools/mapviewer/.cache, checksum verified),
which reads hippiestation.dme for icons. Output goes to data/mapviewer/ (gitignored). Maps are only re-rendered
when the .dmm is newer than its picture. Standard library only - no pip installs.
"""
import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import webbrowser

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache")
DME = os.path.join(ROOT, "hippiestation.dme")

DMM_TOOLS_VERSION = "suite-1.12"
DMM_TOOLS_SHA256 = {
    "win32": ("dmm-tools.exe", "e3967f7d954567497b297e4671d36baef50755126fea5db8608ba6d94042fb82"),
}
# Render passes (dmm-tools list-passes). This codebase predates tg's 2020 smoothing rewrite (walls use smooth =
# SMOOTH_TRUE), and for mapping we want to see what's actually in the file: space, landmarks and mapping helpers,
# and spawners as themselves rather than a random roll.
ENABLE = ["icon-smoothing-2016"]
DISABLE = ["icon-smoothing", "hide-space", "hide-invisible", "random", "spawners"]
RELEASE_URL = "https://github.com/SpaceManiac/SpacemanDMM/releases/download/%s/%s"


def get_dmm_tools():
    """Path to dmm-tools, downloading it on first use."""
    name, expected = DMM_TOOLS_SHA256.get(sys.platform, ("dmm-tools", None))
    path = os.path.join(CACHE, name)
    if os.path.exists(path):
        return path
    os.makedirs(CACHE, exist_ok=True)
    url = RELEASE_URL % (DMM_TOOLS_VERSION, name)
    print("Downloading %s ..." % url)
    data = urllib.request.urlopen(url).read()
    if expected is None:
        # no pinned hash for this platform: check against the release's own checksum list
        sums = urllib.request.urlopen(RELEASE_URL % (DMM_TOOLS_VERSION, DMM_TOOLS_VERSION + ".sha256")).read().decode()
        match = re.search(r"^([0-9a-f]{64})\s+\S*/%s$" % re.escape(name), sums, re.M)
        expected = match and match.group(1)
    actual = hashlib.sha256(data).hexdigest()
    if actual != expected:
        sys.exit("dmm-tools checksum mismatch (got %s, expected %s) - not using it" % (actual, expected))
    with open(path, "wb") as f:
        f.write(data)
    if not path.endswith(".exe"):
        os.chmod(path, 0o755)
    return path


# ---------------------------------------------------------------- .dmm parsing (standard and TGM formats)

KEY_DEF = re.compile(r'^"([a-zA-Z]+)" = \((.*?)\)\s*$', re.M | re.S)
BLOCK = re.compile(r'^\((\d+),(\d+),(\d+)\) = \{"\n(.*?)\n?"\}', re.M | re.S)


def split_top_level(text, sep=","):
    """Split on sep, ignoring separators inside {...}, (...) and strings."""
    parts, depth, cur, quote = [], 0, [], None
    for ch in text:
        if quote:
            cur.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "{(":
            depth += 1
        elif ch in "})":
            depth -= 1
        elif ch == sep and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
            continue
        cur.append(ch)
    if "".join(cur).strip():
        parts.append("".join(cur).strip())
    return parts


def parse_dmm(path):
    text = open(path, encoding="utf-8", errors="replace").read().replace("\r\n", "\n")
    body = text.split("\n\n(", 1)[0] if "\n\n(" in text else text
    keys = {}
    for key, contents in KEY_DEF.findall(body):
        atoms = []
        for part in split_top_level(contents.replace("\n", " ").replace("\t", "")):
            if "{" in part:
                typepath, varblock = part.split("{", 1)
                varblock = varblock.rsplit("}", 1)[0]
                atoms.append([typepath.strip(), [v.strip() for v in split_top_level(varblock, ";") if v.strip()]])
            else:
                atoms.append([part.strip(), []])
        keys[key] = atoms
    if not keys:
        raise ValueError("no tile keys found")
    keylen = len(next(iter(keys)))
    tiles = {}  # (x, y, z) -> key
    maxx = maxy = maxz = 0
    for bx, by, bz, grid in BLOCK.findall(text):
        bx, by, bz = int(bx), int(by), int(bz)
        # Standard maps have one block of full-width rows; TGM has one block per column. Rows run top to bottom
        # either way, so both read the same.
        rows = grid.split("\n")
        height = len(rows)
        for row_i, row in enumerate(rows):
            y = by + height - 1 - row_i
            for col in range(len(row) // keylen):
                x = bx + col
                tiles[(x, y, bz)] = row[col * keylen:(col + 1) * keylen]
                maxx, maxy = max(maxx, x), max(maxy, y)
        maxz = max(maxz, bz)
    return keys, tiles, maxx, maxy, maxz


# ---------------------------------------------------------------- rendering

def image_name(rel, zlevel, region):
    """Unique picture name per map, z-level and region (maps in different folders can share a file name)."""
    base = os.path.splitext(rel)[0].replace("/", "__")
    if region:
        base += "_%s_%s" % (region[0].replace(",", "-"), region[1].replace(",", "-"))
    return "%s-%d.png" % (base, zlevel)


def render_all(dmm_tools, jobs, out_dir, region):
    """Render every stale map in one dmm-tools run, so the codebase is only parsed once.

    jobs: list of (dmm_path, rel, maxz). Pictures land in out_dir as image_name(...).
    """
    stale = [j for j in jobs if any(
        not os.path.exists(os.path.join(out_dir, image_name(j[1], z, region)))
        or os.path.getmtime(os.path.join(out_dir, image_name(j[1], z, region))) < os.path.getmtime(j[0])
        for z in range(1, j[2] + 1))]
    if not stale:
        return
    print("rendering %d map(s)..." % len(stale))
    tmpdir = tempfile.mkdtemp()
    try:
        sources = []
        for dmm_path, rel, _ in stale:
            text = open(dmm_path, encoding="utf-8", errors="replace").read()
            # map templates: preview "keep the existing floor" tiles as plain plating rather than the noop marker
            text = text.replace("/turf/template_noop", "/turf/open/floor/plating")
            source = os.path.join(tmpdir, os.path.splitext(rel)[0].replace("/", "__") + ".dmm")
            with open(source, "w", encoding="utf-8", newline="") as f:
                f.write(text)
            sources.append(source)
        cmd = [dmm_tools, "-e", DME, "minimap", "-o", tmpdir, "--enable", ",".join(ENABLE), "--disable", ",".join(DISABLE)]
        if region:
            cmd += ["--min", region[0], "--max", region[1]]
        result = subprocess.run(cmd + sources, cwd=ROOT, capture_output=True, text=True)
        for dmm_path, rel, maxz in stale:
            for z in range(1, maxz + 1):
                produced = os.path.join(tmpdir, image_name(rel, z, None))
                if not os.path.exists(produced):
                    print(result.stdout[-2000:], result.stderr[-2000:])
                    raise RuntimeError("dmm-tools didn't render %s z%d" % (rel, z))
                shutil.move(produced, os.path.join(out_dir, image_name(rel, z, region)))
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def collect(paths):
    found = []
    for p in paths:
        p = os.path.join(ROOT, p) if not os.path.isabs(p) else p
        if os.path.isdir(p):
            found += sorted(glob.glob(os.path.join(p, "**", "*.dmm"), recursive=True))
        else:
            found += sorted(glob.glob(p))
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("maps", nargs="*", default=["_maps/RandomRooms"], help=".dmm files, directories or globs")
    ap.add_argument("--region", nargs=2, metavar=("MIN", "MAX"), help="only render x,y to x,y (e.g. 180,60 220,100)")
    ap.add_argument("--out", default=os.path.join(ROOT, "data", "mapviewer"))
    ap.add_argument("--no-open", action="store_true", help="don't open the browser")
    args = ap.parse_args()

    maps = collect(args.maps)
    if not maps:
        sys.exit("No .dmm files found in: %s" % ", ".join(args.maps))
    os.makedirs(args.out, exist_ok=True)
    dmm_tools = get_dmm_tools()

    parsed = []
    for dmm_path in maps:
        rel = os.path.relpath(dmm_path, ROOT).replace("\\", "/")
        try:
            parsed.append((dmm_path, rel, parse_dmm(dmm_path)))
        except Exception as e:  # noqa: BLE001 - report and keep going
            print("  skipped %s: %s" % (rel, e))
    render_all(dmm_tools, [(p, rel, data[4]) for p, rel, data in parsed], args.out, args.region)

    entries = []
    for dmm_path, rel, (keys, tiles, maxx, maxy, maxz) in parsed:
        minx, miny = 1, 1
        if args.region:
            minx, miny = (int(v) for v in args.region[0].split(","))
            maxx, maxy = (min(int(v), m) for v, m in zip(args.region[1].split(","), (maxx, maxy)))
        for z in range(1, maxz + 1):
            png = image_name(rel, z, args.region)
            grid = [[tiles.get((x, y, z), "") for x in range(minx, maxx + 1)] for y in range(maxy, miny - 1, -1)]
            used = {k for row in grid for k in row if k}
            entries.append({
                "name": rel + (" (z%d)" % z if maxz > 1 else ""),
                "image": png,
                "origin": [minx, miny],
                "width": maxx - minx + 1,
                "height": maxy - miny + 1,
                "grid": ["".join(row) for row in grid],
                "keylen": len(next(iter(keys))),
                "keys": {k: keys[k] for k in used},
            })

    with open(os.path.join(args.out, "maps.js"), "w", encoding="utf-8") as f:
        f.write("window.MAPS = ")
        json.dump(entries, f, separators=(",", ":"))
        f.write(";\n")
    shutil.copy(os.path.join(HERE, "viewer.html"), os.path.join(args.out, "index.html"))
    page = os.path.join(args.out, "index.html")
    print("\n%d map(s) -> %s" % (len(entries), page))
    if not args.no_open:
        webbrowser.open("file:///" + page.replace("\\", "/"))


if __name__ == "__main__":
    main()
