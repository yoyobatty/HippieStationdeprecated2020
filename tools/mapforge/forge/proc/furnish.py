"""The furnish node: every room is handed to its asset.

An asset is a function of one room (place.Ctx). It reads which wall faces which neighbour, where the doors and lanes
are, and places kits by rule. Rooms without an asset stay empty and are listed, so a missing asset is never silent.
"""
from .place import Ctx


def open_floor(geo, clear=2):
    """Per room, the floor tiles with nothing near them: `clear` or more tiles from every wall and every piece.
    A room with many of these reads as empty. Halls and pens are meant to be open and are left out."""
    dwall = geo.field("dwall")
    out = {}
    for rid, r in geo.rooms.items():
        if r.attrs.get("hall") or r.attrs.get("asset") == "pen" or not r.tiles:
            continue
        pieces = [p for p in r.tiles if geo.taken.get(p) == "obj"]
        out[rid] = [p for p in r.tiles if dwall.get(p, 0) >= clear
                    and all(max(abs(p[0] - q[0]), abs(p[1] - q[1])) > clear for q in pieces)]
    return out


def furnish(geo, P, assets, order=None):
    done, skipped = [], []
    for rid in (order or sorted(geo.rooms)):
        r = geo.rooms.get(rid)
        if r is None:
            continue
        fn = assets.get(r.attrs.get("asset", rid))
        if fn is None:
            skipped.append(rid)
            continue
        before = len(geo.placed)
        fn(Ctx(geo, rid, P))
        done.append("%s %d" % (rid, len(geo.placed) - before))
    geo.notes.append("furnish: kits placed per room: " + ", ".join(done))
    dead = open_floor(geo)
    worst = sorted(((len(v), rid) for rid, v in dead.items() if v), reverse=True)
    geo.notes.append("furnish: empty floor (tiles 2+ from any wall or piece): " +
                     (", ".join("%s %d" % (rid, n) for n, rid in worst) or "none"))
    if skipped:
        geo.notes.append("furnish: no asset yet for " + ", ".join(skipped))
