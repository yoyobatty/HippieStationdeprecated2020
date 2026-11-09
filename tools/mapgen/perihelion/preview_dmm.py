"""Tile-level picture of a built .dmm (turfs, doors, furniture; optional pipe/cable overlay).

    python tools/mapgen/perihelion/preview_dmm.py [map.dmm] [out.png] [--wires]
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dmmlib as D  # noqa: E402

S = 4


def colour(atoms):
    turf = next((a for a in atoms if a.startswith("/turf/")), "")
    objs = [a for a in atoms if a.startswith("/obj/") or a.startswith("/mob/")]
    if any("/obj/machinery/door/airlock" in o for o in objs):
        return (240, 200, 60) if "external" not in " ".join(objs) else (90, 230, 230)
    if any("door/window" in o for o in objs):
        return (200, 170, 120)
    if any(o.startswith("/obj/effect/spawner/structure/window") for o in objs):
        return (130, 190, 230)
    if turf.startswith("/turf/closed/wall/r_wall"):
        return (70, 74, 86)
    if turf.startswith("/turf/closed/wall"):
        return (110, 114, 126)
    if turf.startswith("/turf/closed/mineral"):
        return (110, 88, 70)
    if "solarpanel" in turf:
        return (40, 70, 160)
    if turf.startswith("/turf/open/space"):
        if any("catwalk" in o or "lattice" in o for o in objs):
            return (70, 72, 80)
        return (12, 14, 26)
    base = (175, 178, 184)
    if "white" in turf:
        base = (222, 226, 230)
    elif "dark" in turf or "circuit" in turf:
        base = (95, 98, 108)
    elif "wood" in turf:
        base = (150, 110, 70)
    elif "carpet" in turf:
        base = (140, 60, 60)
    elif "plating" in turf:
        base = (120, 112, 104)
    elif "engine" in turf:
        base = (85, 90, 95)
    elif "freezer" in turf or "cafeteria" in turf:
        base = (200, 205, 215)
    furniture = [o for o in objs if not any(k in o for k in ("cable", "atmospherics/pipe", "light", "landmark", "apc", "vent_", "firedoor", "docking_port", "catwalk"))]
    if furniture:
        return tuple(int(v * 0.55) for v in base)
    return base


def main():
    src = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "_maps/map_files/Perihelion/perihelion.dmm"
    out = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else "data/previews/perihelion_tiles.png"
    wires = "--wires" in sys.argv
    m = D.read(src)
    img = Image.new("RGB", (m.maxx * S, m.maxy * S))
    d = ImageDraw.Draw(img)
    for (x, y), atoms in m.tiles.items():
        px, py = (x - 1) * S, (m.maxy - y) * S
        d.rectangle([px, py, px + S - 1, py + S - 1], fill=colour(atoms))
        if wires:
            j = " ".join(atoms)
            if "/obj/structure/cable" in j:
                d.point((px + 1, py + 1), fill=(250, 220, 40))
            if "supply/hidden" in j or "vent_pump" in j or "unary/tank" in j:
                d.point((px + 2, py + 2), fill=(60, 120, 255))
            if "scrubbers/hidden" in j or "vent_scrubber" in j or "outlet_injector" in j:
                d.point((px + 3, py + 3), fill=(240, 60, 60))
            if "/obj/machinery/power/apc" in j:
                d.rectangle([px, py, px + S - 1, py + S - 1], outline=(0, 255, 0))
    img.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
