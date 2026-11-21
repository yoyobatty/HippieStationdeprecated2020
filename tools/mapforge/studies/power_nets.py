"""Power nets of a built map, by the game's own cable rules, without booting it.

    python studies/power_nets.py station_v6 [--all]

Rules (code/modules/power/cable.dm, power.dm):
  - a cable links to the cables of the same layer on the four tiles beside it;
  - a cable bridge (/obj/structure/cable_bridge) joins every cable on its own tile, whatever its layer;
  - the cable under an SMES never links to the one under that SMES's terminal (beside it, facing it);
  - a machine sits on the net of the layer-2 cable on its tile, or of any cable there if a bridge is there too.
Prints each net with the machines on it: APCs, SMES (as output), terminals (an SMES's input), generators, emitters,
rad collectors, solars. --all also lists nets with no machine.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
D4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
MACH = (("apc", "/obj/machinery/power/apc"), ("smes", "/obj/machinery/power/smes"),
        ("terminal", "/obj/machinery/power/terminal"), ("pacman", "/obj/machinery/power/port_gen"),
        ("emitter", "/obj/machinery/power/emitter"), ("collector", "/obj/machinery/power/rad_collector"),
        ("solar", "/obj/machinery/power/solar"), ("tracker", "/obj/machinery/power/tracker"))


def layer(o):
    if o.path.startswith("/obj/structure/cable/layer1"):
        return 1
    if o.path.startswith("/obj/structure/cable/layer3"):
        return 3
    return 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args()
    m = dmm.read(os.path.join(ROOT, "data", "mapforge", a.name + ".dmm"))
    nodes = {}      # (x, y, layer) -> True
    bridge, smes, term = set(), set(), {}
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            if o.path == "/obj/structure/cable" or o.path.startswith("/obj/structure/cable/layer"):
                nodes[(x, y, layer(o))] = True
            elif o.path.startswith("/obj/structure/cable_bridge"):
                bridge.add((x, y))
            elif o.path.startswith("/obj/machinery/power/smes"):
                smes.add((x, y))
            elif o.path.startswith("/obj/machinery/power/terminal"):
                term[(x, y)] = o.num("dir", 2)
    # pairs that never link: an SMES's tile and its own terminal's tile
    nolink = set()
    for (x, y), d in term.items():
        dx, dy = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}[d]
        if (x + dx, y + dy) in smes:
            nolink.add(frozenset(((x, y), (x + dx, y + dy))))
    net, n = {}, 0
    for k in nodes:
        if k in net:
            continue
        n += 1
        st = [k]
        net[k] = n
        while st:
            x, y, l = st.pop()
            nb = [(x + dx, y + dy, l) for dx, dy in D4 if frozenset(((x, y), (x + dx, y + dy))) not in nolink]
            if (x, y) in bridge:
                nb += [(x, y, ll) for ll in (1, 2, 3) if ll != l]
            for q in nb:
                if q in nodes and q not in net:
                    net[q] = n
                    st.append(q)
    members = {}
    for (x, y, z), t in m.tiles.items():
        on = net.get((x, y, 2)) or (next((net.get((x, y, l)) for l in (1, 3) if (x, y, l) in net), None)
                                    if (x, y) in bridge else None)
        for kind, pre in MACH:
            if t.has(pre):
                members.setdefault(on, {}).setdefault(kind, []).append((x, y))
    size = {}
    for k, v in net.items():
        size[v] = size.get(v, 0) + 1
    print("%s: %d cable nets" % (a.name, n))
    for nid in sorted(size, key=lambda v: -size[v]):
        mm = members.get(nid, {})
        if not mm and not a.all:
            continue
        print("  net %3d  %4d cables  %s" % (nid, size[nid], "  ".join("%s %d" % (k, len(v)) for k, v in sorted(mm.items()))))
    off = members.get(None, {})
    if off:
        print("  NO NET: %s" % "  ".join("%s %s" % (k, " ".join("%d,%d" % p for p in v[:6])) for k, v in sorted(off.items())))


if __name__ == "__main__":
    main()
