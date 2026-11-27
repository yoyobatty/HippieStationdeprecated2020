"""Engineering function numbers over the stock maps (and ours): one line per question, one column per map. Feeds the
checkable rules of studies/dept_specs/engineering.md.

    python tools/mapforge/studies/dept_specs/engineering_work/aggregate.py [extra.dmm ...]

Questions: the safety vestibule ("Engine Room" doors with showers and radiation/fire closets between the front and
the engine), where showers/closets/extinguishers stand and how far they are from the crystal's door, the lockers,
suits, vendors, SMES and consoles and which room holds them, the CE office's doors and shutters, the checkpoint,
tech storage and the break room/foyer and how each joins the hall, Atmospherics' front desk and gear, and walking
distances from the department's front to the engine, solars, telecomms and the gravity generator.
"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import engstudy as ES  # noqa: E402

ST = ES.ST


def grp(a):
    if a.startswith("/area/security/checkpoint/engineering"):
        return "engineering"
    return ST.group_of(a) if a else None


def airlocks(r):
    return [d for d in r["doors"] if d["path"].startswith("/obj/machinery/door/airlock")]


def analyse(name, path):
    m, rooms = ES.study(path)
    eng = [r for r in rooms if grp(r["area"]) == "engineering"]
    atm = [r for r in rooms if grp(r["area"]) == "atmos"]
    out = {}

    def tot(rs, f):
        return sum(r["kit"][f] for r in rs)

    # the crystal's door
    sm_doors = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and any(
        o.path.startswith("/obj/machinery/door/airlock") and o.path.endswith("/critical") for o in t.objs)]
    if not sm_doors:
        sm_doors = [(d["x"], d["y"]) for r in rooms if "supermatter" in r["area"] for d in airlocks(r)]
    dist = ES.walk_dist(m, sm_doors, limit=200) if sm_doors else {}

    def nearest(fam, rs=None):
        best = None
        for (x, y, z), t in m.tiles.items():
            if z != 1 or not any(ES.fam(o.path) == fam for o in t.objs):
                continue
            if rs is not None and not any((x, y) in r["tiles"] for r in rs):
                continue
            d = dist.get((x, y))
            if d is not None and (best is None or d < best):
                best = d
        return best

    # the vestibule: a small room of 2+ airlocks with radiation or fire closets / showers, between the front and works
    vest = [r for r in eng if r["n"] <= 16 and len(airlocks(r)) >= 2 and "supermatter" not in r["area"]
            and "gravity" not in r["area"] and (r["kit"]["rad_closet"] or r["kit"]["shower"])]
    out["vestibule (rad/shower room, 2+ airlocks, <=16 tiles)"] = "; ".join(
        "%d t %s [%s]" % (r["n"], ",".join("%s%d" % (k, v) for k, v in r["kit"].items() if k in (
            "shower", "rad_closet", "fire_closet", "tool_closet", "em_closet", "extinguisher", "sign_rad")),
            "/".join(sorted({d["name"] for d in airlocks(r)}))) for r in vest) or "-"
    out["showers eng / atmos"] = "%d / %d" % (tot(eng, "shower"), tot(atm, "shower"))
    out["shower rooms"] = ", ".join(sorted("%s(%d)" % (r["area"].split("/")[-1], r["n"]) for r in eng + atm if r["kit"]["shower"])) or "-"
    out["sinks eng"] = str(tot(eng, "sink"))
    out["rad closets eng (vest/grav/other) atmos"] = "%d (%d/%d/%d) %d" % (
        tot(eng, "rad_closet"), tot(vest, "rad_closet"), tot([r for r in eng if "gravity" in r["area"]], "rad_closet"),
        tot([r for r in eng if r not in vest and "gravity" not in r["area"]], "rad_closet"), tot(atm, "rad_closet"))
    out["fire closets eng / atmos"] = "%d / %d" % (tot(eng, "fire_closet"), tot(atm, "fire_closet"))
    out["emergency closets eng"] = str(tot(eng, "em_closet"))
    out["extinguisher cabinets eng / atmos"] = "%d / %d" % (tot(eng, "extinguisher"), tot(atm, "extinguisher"))
    out["fireaxe eng / atmos"] = "%d / %d" % (tot(eng, "fireaxe"), tot(atm, "fireaxe"))
    out["walk crystal door -> rad closet / shower / fire closet / extinguisher"] = "%s / %s / %s / %s" % (
        nearest("rad_closet"), nearest("shower"), nearest("fire_closet"), nearest("extinguisher"))
    out["rad signs eng"] = str(tot(eng, "sign_rad"))
    out["eng lockers / elec / weld / tool closets"] = "%d / %d / %d / %d" % (
        tot(eng, "eng_locker"), tot(eng, "elec_locker"), tot(eng, "weld_locker"), tot(eng, "tool_closet"))
    lock_rooms = [r for r in eng if r["kit"]["eng_locker"]]
    out["locker rooms (tiles)"] = ", ".join("%d" % r["n"] for r in lock_rooms) or "-"
    out["engivend / toolvend / engi wardrobe"] = "%d / %d / %d" % (tot(eng, "engivend"), tot(eng, "toolvend"), tot(eng, "engi_wardrobe"))
    out["SUS engine (rooms) / SUS ce"] = "%d (%s) / %d" % (tot(eng, "sus_engine"), ",".join(
        "%s%d" % (r["area"].split("/")[-1][:8], r["n"]) for r in eng if r["kit"]["sus_engine"]), tot(eng, "sus_ce"))
    out["tank dispensers eng"] = str(tot(eng, "tank_disp"))
    out["fuel / water tanks eng"] = "%d / %d" % (tot(eng, "fueltank"), tot(eng, "watertank"))
    out["sheet stacks metal/glass/plasteel eng"] = "%d/%d/%d" % (tot(eng, "metal"), tot(eng, "glass"), tot(eng, "plasteel"))
    smes_rooms = [r for r in eng if r["kit"]["smes"] and "gravity" not in r["area"]]
    out["SMES main rooms (count, tiles, door names)"] = "; ".join("%d in %d t %s" % (
        r["kit"]["smes"], r["n"], "/".join(sorted({d["name"] for d in airlocks(r)}))) for r in smes_rooms) or "-"
    out["SMES grav"] = str(tot([r for r in eng if "gravity" in r["area"]], "smes"))
    out["terminals eng (SMES eng)"] = "%d (%d)" % (tot(eng, "terminal"), tot(eng, "smes"))
    out["consoles eng: station_alert/atmos_alert/eng_modcon/power_mon/apc_ctrl"] = "%d/%d/%d/%d/%d" % (
        tot(eng, "station_alert"), tot(eng, "atmos_alert"), tot(eng, "eng_modcon"), tot(eng, "power_mon"), tot(eng, "apc_ctrl"))
    cons_rooms = [r for r in eng if r["kit"]["eng_modcon"] or r["kit"]["station_alert"]]
    out["console rooms"] = ", ".join("%s(%d)" % (r["area"].split("/")[-1][:10], r["n"]) for r in cons_rooms)
    sec = [r for r in eng if (r["kit"]["emitter"] or r["kit"]["field_gen"]) and any(
        d["path"].startswith("/obj/machinery/door/poddoor") and "torage" in d["name"] for d in r["doors"])]
    out["secure storage (blast doors): emitters/fieldgens/shieldgens"] = "; ".join("%d t %d/%d/%d" % (
        r["n"], r["kit"]["emitter"], r["kit"]["field_gen"], r["kit"]["shieldgen"]) for r in sec) or "-"
    laser = [r for r in eng if any(d["name"] == "Laser Room" for d in airlocks(r)) and r["kit"]["emitter"]]
    out["laser room emitters"] = ",".join(str(r["kit"]["emitter"]) for r in laser) or "-"
    ce = [r for r in eng if r["area"].endswith("/chief")]
    out["CE office rooms (tiles: airlocks->beyond [access])"] = "; ".join("%d: %s" % (r["n"], ", ".join(
        "%s[%s]" % ("/".join(b.split("/")[-1] for b in d["beyond"]) or "?", d["access"]) for d in airlocks(r))) for r in ce)
    out["CE office shutters (poddoors) / blast buttons"] = "%d / %d" % (
        sum(1 for r in ce for d in r["doors"] if d["path"].startswith("/obj/machinery/door/poddoor")),
        tot(ce, "blast_btn"))
    out["CE kit: locker/sus_ce/card/keycard/apc_ctrl/st_alert/telescreen/req"] = "/".join(str(tot(ce, f)) for f in (
        "ce_locker", "sus_ce", "card_ce", "keycard", "apc_ctrl", "station_alert", "telescreen", "req_console"))
    cp = [r for r in eng if "checkpoint" in r["area"]]
    out["checkpoint airlocks -> beyond"] = "; ".join(", ".join(
        "/".join(b.replace("/area/", "") for b in d["beyond"]) for d in airlocks(r)) for r in cp) or "-"
    ts = [r for r in eng if "storage/tech" in r["area"]]
    out["tech storage (tiles: airlocks -> beyond [access])"] = "; ".join("%d: %s" % (r["n"], ", ".join(
        "%s[%s]" % ("/".join(b.replace("/area/", "") for b in d["beyond"]), d["access"]) for d in airlocks(r))) for r in ts)
    br = [r for r in eng if "break_room" in r["area"]]
    out["break room/foyer (tiles: airlock names [access])"] = "; ".join("%d: %s" % (r["n"], ", ".join(
        "%s[%s]" % (d["name"], d["access"]) for d in airlocks(r))) for r in br) or "-"
    out["break kit: coffee/microwave/lathe/toolvend/disposal"] = "/".join(str(tot(br, f)) for f in (
        "coffee", "microwave", "lathe_eng", "toolvend", "disposal"))
    out["eng lathe rooms"] = ", ".join("%s(%d)" % (r["area"].split("/")[-1], r["n"]) for r in eng if r["kit"]["lathe_eng"]) or "-"
    hall = []
    for r in eng:
        for d in airlocks(r):
            if any(b.startswith("/area/hallway") for b in d["beyond"]):
                hall.append("%s:%s[%s]" % (r["area"].split("/")[-1][:9], d["name"], d["access"]))
    out["eng airlocks to halls"] = ", ".join(sorted(set(hall)))
    maint = sum(1 for r in eng for d in airlocks(r) if any(b.startswith("/area/maintenance") for b in d["beyond"]))
    out["eng airlocks to maint"] = str(maint)
    ext = sum(1 for r in eng for d in airlocks(r) if "external" in d["path"])
    out["eng external airlocks"] = str(ext)
    to_atm = sorted({"%s[%s]" % (d["name"], d["access"]) for r in eng for d in airlocks(r)
                     if any(grp(b) == "atmos" for b in d["beyond"])} |
                    {"%s[%s]" % (d["name"], d["access"]) for r in atm for d in airlocks(r)
                     if any(grp(b) == "engineering" for b in d["beyond"])})
    out["eng<->atmos airlocks"] = ", ".join(to_atm) or "-"
    deliv = [d["name"] for r in eng + atm for d in r["doors"] if "eliver" in d["name"]]
    out["delivery windoors"] = ", ".join(sorted(set(deliv))) or "-"
    # atmospherics
    desk = [d for r in atm for d in r["doors"] if d["path"].startswith("/obj/machinery/door/window")
            and any(b.startswith("/area/hallway") for b in d["beyond"])]
    out["atmos desk windoors to hall"] = str(len(desk))
    out["atmos hall airlocks [access]"] = ", ".join(sorted({"%s[%s]" % (d["name"], d["access"]) for r in atm for d in airlocks(r)
                                                            if any(b.startswith("/area/hallway") for b in d["beyond"])})) or "-"
    out["atmos kit: lockers/wardrobe/sus/fireaxe/pipe_disp/hazvest/heater/pump/scrub/tank_disp/req/alert"] = "/".join(
        str(tot(atm, f)) for f in ("atmos_locker", "atmos_wardrobe", "sus_atmos", "fireaxe", "pipe_disp", "hazvest", "heater",
                                   "port_pump", "port_scrub", "tank_disp", "req_console", "atmos_alert"))
    # walks from the department's front (its hall airlocks) to places engineers go
    fronts = [(d["x"], d["y"]) for r in eng for d in airlocks(r) if any(b.startswith("/area/hallway") for b in d["beyond"])]
    if fronts:
        fd = ES.walk_dist(m, fronts, limit=600)

        def to_area(pre):
            ds = [v for (x, y), v in fd.items() if m.get(x, y).apath.startswith(pre)]
            return min(ds) if ds else None
        out["walk front -> crystal door / grav / smes room / solars(maint) / tcomms / atmos"] = " / ".join(str(v) for v in (
            min((fd.get(p) for p in sm_doors if p in fd), default=None), to_area("/area/engine/gravity_generator"),
            min((fd[p] for r in smes_rooms for p in r["tiles"] if p in fd), default=None),
            to_area("/area/maintenance/solars") or to_area("/area/solar"), to_area("/area/tcommsat"),
            to_area("/area/engine/atmos")))
    return out


def main():
    maps = [(n, os.path.join(ES.ROOT, "_maps", "map_files", p)) for n, p in ES.STOCK if n != "metalake"]
    maps += [(os.path.splitext(os.path.basename(p))[0][:8], p) for p in sys.argv[1:]]
    res = [(n, analyse(n, p)) for n, p in maps]
    keys = list(res[0][1])
    for k in keys:
        print("## " + k)
        for n, o in res:
            print("   %-8s %s" % (n, o.get(k, "")))


if __name__ == "__main__":
    main()
