"""Compares the spritesheets spritesheet_check.dm wrote: the old DM build against iconforge's, sprite by sprite.

Two pixels count as the same when every channel matches, or when both are fully transparent (colour under alpha 0 is never seen).
Usage: python tools/spritesheet_check/compare.py [--show N]   (reads data/spritesheet_check/)
"""
import json
import os
import sys

from PIL import Image

BASE = "data/spritesheet_check"


def load(mode, name):
    path = f"{BASE}/{mode}/{name}.json"
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def sheet_image(cache, mode, name, size_id):
    key = (mode, name, size_id)
    if key not in cache:
        path = f"{BASE}/{mode}/{name}_{size_id}.png"
        cache[key] = Image.open(path).convert("RGBA") if os.path.exists(path) else None
    return cache[key]


def sprite_pixels(cache, mode, name, entry):
    size_id, x, y, w, h = entry
    image = sheet_image(cache, mode, name, size_id)
    if image is None:
        return None
    cropped = image.crop((x, y, x + w, y + h))
    return list(cropped.get_flattened_data() if hasattr(cropped, "get_flattened_data") else cropped.getdata())


def compare(a, b):
    """(pixels that differ, biggest channel difference)"""
    differ = 0
    worst = 0
    for pa, pb in zip(a, b):
        if pa == pb or (pa[3] == 0 and pb[3] == 0):
            continue
        differ += 1
        worst = max(worst, max(abs(ca - cb) for ca, cb in zip(pa, pb)))
    return differ, worst


def main():
    show = 5
    if "--show" in sys.argv:
        show = int(sys.argv[sys.argv.index("--show") + 1])
    with open(f"{BASE}/results.txt", encoding="utf-8") as handle:
        print(handle.read().rstrip())
    print()
    names = sorted(f[:-5] for f in os.listdir(f"{BASE}/dm") if f.endswith(".json"))
    totals = {"same": 0, "differ": 0, "only_dm": 0, "only_forge": 0}
    cache = {}
    for name in names:
        dm = load("dm", name)
        forge = load("forge", name)
        if not forge:
            print(f"{name}: no iconforge sheet")
            continue
        dm_sprites = dm["sprites"]
        forge_sprites = forge["sprites"]
        same = 0
        differing = []
        only_dm = sorted(set(dm_sprites) - set(forge_sprites))
        only_forge = sorted(set(forge_sprites) - set(dm_sprites))
        for sprite in sorted(set(dm_sprites) & set(forge_sprites)):
            a = sprite_pixels(cache, "dm", name, dm_sprites[sprite])
            b = sprite_pixels(cache, "forge", name, forge_sprites[sprite])
            if a is None or b is None or len(a) != len(b):
                differing.append((sprite, -1, -1))
                continue
            differ, worst = compare(a, b)
            if differ:
                differing.append((sprite, differ, worst))
            else:
                same += 1
        totals["same"] += same
        totals["differ"] += len(differing)
        totals["only_dm"] += len(only_dm)
        totals["only_forge"] += len(only_forge)
        print(f"{name} (built by {dm['built_by']} / {forge['built_by']}): {same} same, {len(differing)} differ, {len(only_dm)} only in DM's, {len(only_forge)} only in iconforge's")
        for sprite, differ, worst in sorted(differing, key=lambda d: -d[1])[:show]:
            print(f"    differs: {sprite}: {differ} pixels, biggest channel difference {worst}")
        for sprite in only_dm[:show]:
            print(f"    only in DM's: {sprite} {dm_sprites[sprite][0]}")
        for sprite in only_forge[:show]:
            print(f"    only in iconforge's: {sprite} {forge_sprites[sprite][0]}")
    print()
    print(f"All sheets: {totals['same']} same, {totals['differ']} differ, {totals['only_dm']} only in DM's, {totals['only_forge']} only in iconforge's")


if __name__ == "__main__":
    main()
