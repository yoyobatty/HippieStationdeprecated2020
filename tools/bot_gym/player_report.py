#!/usr/bin/env python3
"""What the player log (bots_ai/player_log.dm) says about a round.

Usage: tools/bot_gym/player_report.py <round folder> [input|play]

input: what the keyboard did against what the character did. Keys with no step, steps with no key, time from a key to its first step,
stutter while a key is held, releases that never arrived, hotkeys that changed nothing, walking flips nobody asked for.
play: how the player played, for bots to be measured against. Needs attack.log from the same folder.
"""
import json
import re
import statistics
import sys

import logread
from collections import Counter, defaultdict

# Longest a tap or a press can wait for its step before it counts as lost: one step at walking speed, and a tick or two.
STEP_WAIT_MS = 700
# How far past the delay it asked for a step has to be, before it's a stutter a person could feel at 40 ticks a second.
STUTTER_MS = 75


def stamp(line):
    m = re.match(r"\[\d+-\d+-\d+ (\d+):(\d+):(\d+)\.(\d+)\]", line)
    return (int(m[1]) * 3600 + int(m[2]) * 60 + int(m[3])) * 1000 + int(m[4]) if m else None


def clock(ms):
    s = (ms // 1000 - 5 * 3600) % 86400  # the logs are UTC
    return "%02d:%02d:%02d" % (s // 3600, s // 60 % 60, s % 60)


def load(folder):
    rows = []
    for line in logread.lines(logread.find(folder, "player")):
        try:
            r = json.loads(line[line.index("{"):])
        except ValueError:
            continue
        r["ms"] = stamp(line)
        rows.append(r)
    return rows


def spread(values):
    if not values:
        return "none"
    values = sorted(values)
    return "%d: median %d, 90%% %d, worst %d" % (len(values), statistics.median(values), values[int(len(values) * 0.9)], values[-1])


def why_late(rows, a, b):
    """What was going on between two steps too far apart. A stuck step is only logged once a second, so "nothing" can still hide a bump."""
    inside = [r for r in rows if a["ms"] < r["ms"] < b["ms"]]
    if any(r.get("ev") in ("key", "key_up") and r.get("dir") for r in inside):
        return "keys changed in the gap: not a held key"
    fails = [r for r in inside if r.get("ev") == "step" and not r["ok"]]
    if fails:
        return "stunned or held" if any(r["why"] in ("can't move",) or r["why"].startswith("held") for r in fails) else "bumped something"
    if any(r.get("inc") for r in inside if r["k"] == "s"):
        return "stunned or held"
    if any(r.get("ev") == "moved" for r in inside):
        return "moved by something else"
    if (b["ms"] - a["ms"]) - (b["t"] - a["t"]) * 100 > 100:
        return "server stalled: the game clock fell behind"
    return "nothing in the way, and the game clock ran"


def input_report(rows):
    keys = [r for r in rows if r.get("ev") == "key"]
    ups = [r for r in rows if r.get("ev") == "key_up"]
    steps = [r for r in rows if r.get("ev") == "step"]
    good = [r for r in steps if r["ok"]]
    print("%d keys down, %d up, %d step tries, %d of them worked" % (len(keys), len(ups), len(steps), len(good)))
    print("keys:", Counter(r["key"] for r in keys).most_common(24))

    print("\n-- movement keys against steps")
    move_keys = [r for r in keys if r.get("dir") and "Ctrl" not in r["held"].split("+")]
    latency = []
    lost = []
    for r in move_keys:
        first = next((s for s in steps if s["ms"] >= r["ms"] and s["ms"] <= r["ms"] + STEP_WAIT_MS and s["dir"] & r["dir"]), None)
        if first:
            latency.append(first["ms"] - r["ms"])
        else:
            lost.append(r)
    print("key to first step, ms:", spread(latency))
    print("presses with no step tried within %d ms: %d of %d" % (STEP_WAIT_MS, len(lost), len(move_keys)))
    for r in lost[:12]:
        near = [x for x in rows if x["k"] == "s" and abs(x["ms"] - r["ms"]) < 600]
        print("   %s %s held %s hp %s %s" % (clock(r["ms"]), r["key"], r["held"], r.get("hp"), "incapacitated" if near and near[0].get("inc") else ""))
    print("failed steps:", Counter(r["why"] for r in steps if not r["ok"]).most_common(14))

    print("\n-- steps against keys")
    dirs = {}
    for r in keys + ups:
        if r.get("dir"):
            dirs[r["key"]] = r["dir"]
    no_key = []
    wrong = []
    for s in good:
        held = [k for k in s["held"].split("+") if k in dirs]
        if not held:
            recent = [r for r in move_keys if s["ms"] - 500 <= r["ms"] <= s["ms"]]
            if not recent:
                no_key.append(s)
        elif not any(dirs[k] & s["dir"] for k in held):
            wrong.append(s)
    print("steps with no key held or just pressed: %d, against no key at all in the half second before" % len(no_key))
    for s in no_key[:8]:
        print("   %s dir %s at %s,%s" % (clock(s["ms"]), s["dir"], s["x"], s["y"]))
    print("steps the wrong way for the keys held: %d" % len(wrong))
    for s in wrong[:8]:
        print("   %s dir %s held %s" % (clock(s["ms"]), s["dir"], s["held"]))
    moved = [r for r in rows if r.get("ev") == "moved"]
    print("moved with no key: %d, %s" % (len(moved), Counter(r.get("by") or "other" for r in moved).most_common(8)))

    print("\n-- stutter: a key held, and the next step late against the delay the last one asked for")
    gaps = []
    late = []
    for a, b in zip(good, good[1:]):
        held = [k for k in b["held"].split("+") if k in dirs]
        if not held or not any(dirs[k] & a["dir"] and dirs[k] & b["dir"] for k in held):
            continue
        wanted = a["next"] * 100
        real = b["ms"] - a["ms"]
        if real > 1500:
            continue
        gaps.append(real)
        if real - wanted > STUTTER_MS:
            late.append((why_late(rows, a, b), real - wanted, a, b))
    print("steps a held key followed on from:", len(gaps), "gap ms:", spread(gaps))
    print("late by over %d ms: %d (%.1f%%), and most of that isn't lag:" % (STUTTER_MS, len(late), 100.0 * len(late) / max(1, len(gaps))))
    for why, n in Counter(x[0] for x in late).most_common():
        print("   %3d %s, ms over: %s" % (n, why, spread([x[1] for x in late if x[0] == why])))
    print("delays asked for, tenths:", Counter(round(r["next"], 1) for r in good).most_common(8))
    for why, over, a, b in sorted([x for x in late if x[0].startswith(("server", "nothing"))], key=lambda x: -x[1])[:8]:
        print("   %s %d ms over, wanted %d, held %s, at %s,%s: %s" % (clock(b["ms"]), over, a["next"] * 100, b["held"], b["x"], b["y"], why))

    print("\n-- server speed around the input")
    samples = [r for r in rows if r["k"] == "s"]
    if len(samples) > 2:
        spans = []
        for a, b in zip(samples, samples[20:]):
            real = b["ms"] - a["ms"]
            if 0 < real < 60000:
                spans.append((b["t"] - a["t"]) * 100.0 / real)
        print("game seconds a real second: worst %.3f, median %.3f" % (min(spans), statistics.median(spans)))
        print("world.cpu in samples: median %.0f, worst %.0f" % (statistics.median(r["cpu"] for r in samples), max(r["cpu"] for r in samples)))

    print("\n-- keys held and let go")
    lost = [r for r in ups if r.get("lost") or r.get("via") not in (None, "Topic")]
    print("releases the game never got, let go by the server: %d. Older logs can't tell these from a tgui window passing one on" % len(lost))
    for r in lost[:10]:
        print("   %s %s %s" % (clock(r["ms"]), r["key"], r.get("via")))
    print("keys through a tgui window:", sum(1 for r in keys + ups if r.get("via") == "Topic"))
    print("a key down twice with no release:", [(clock(r["ms"]), r["key"]) for r in keys if r["held"].split("+").count(r["key"]) > 1])
    downs = Counter(r["key"] for r in keys)
    released = Counter(r["key"] for r in ups)
    print("pressed more than released:", {k: downs[k] - released[k] for k in downs if downs[k] != released[k]})
    print("to the chat bar instead of the game:", sum(1 for r in keys if r.get("chat")))

    print("\n-- hotkeys against what they changed")
    binds = defaultdict(lambda: [0, 0])
    for r in keys:
        for b in r.get("binds") or []:
            if r.get("dir"):
                continue
            binds[b][0] += 1
            if r.get("chg"):
                binds[b][1] += 1
    for b, (n, changed) in sorted(binds.items(), key=lambda x: -x[1][0]):
        print("   %-26s %3d pressed, %3d changed something the log can see" % (b, n, changed))
    print("modifier and walk keys:", [(r["key"], r.get("chg")) for r in keys + ups if r["key"] in ("Alt", "Shift", "Ctrl") and r.get("chg")][:10])
    flips = [r for r in rows if r.get("ev") == "walk_flip"]
    print("run or walk changed with no key behind it: %d" % len(flips))
    for r in flips[:10]:
        click = [c for c in rows if c.get("ev") == "click" and 0 <= r["ms"] - c["ms"] < 1500]
        print("   %s now %s, held %s, last click %s" % (clock(r["ms"]), "running" if r["run"] else "walking", r["held"], click[-1]["target"] if click else None))

    print("\n-- clicks")
    clicks = [r for r in rows if r.get("ev") == "click"]
    print("%d clicks, %d during a cooldown, %d on the HUD" % (len(clicks), sum(1 for r in clicks if r["cd"]), sum(1 for r in clicks if "dist" not in r)))
    print("gap between clicks in a burst, tenths:", spread([round(r["gap"]) for r in clicks if r["gap"] < 30]))


def attacks(folder):
    """The player's own lines from attack.log: when, who did it, what to whom, with what, and the target's health after."""
    done = []
    pattern = re.compile(r"ATTACK: (.+?)/\((.*?)\) has (.*)$")
    for line in open(folder + "/attack.log", encoding="utf8", errors="replace"):
        m = pattern.search(line)
        if not m or "Yoyobatty" not in line:
            continue
        rest = m[3]
        target = re.search(r"(bot-[a-z0-9-]+|\*no key\*|Yoyobatty)/\(([^)]*)\)", rest)
        hp = re.search(r"\(NEWHP: ([-0-9.]+)\)", rest)
        verb = rest[:target.start()].strip() if target else rest.split(" (")[0].strip()
        weapon = re.search(r" with (?:the )?(.+?)(?: \(| from |$)", rest[target.end():] if target else "")
        done.append({"ms": stamp(line), "by_me": m[1] == "Yoyobatty", "who": m[2], "verb": verb, "target": target[2] if target else None,
            "weapon": weapon[1] if weapon else None, "hp": float(hp[1]) if hp else None})
    return done


def play_report(rows, folder):
    hits = attacks(folder)
    mine = [h for h in hits if h["by_me"]]
    theirs = [h for h in hits if not h["by_me"]]
    samples = [r for r in rows if r["k"] == "s"]
    clicks = [r for r in rows if r.get("ev") == "click"]
    if not samples:
        return
    print("%s to %s, %d minutes" % (clock(samples[0]["ms"]), clock(samples[-1]["ms"]), (samples[-1]["ms"] - samples[0]["ms"]) // 60000))
    for r in rows:
        if r.get("ev") == "role":
            print("role:", r["job"], r["antags"], r["objectives"])

    print("\n-- what they did first")
    for r in rows:
        if r.get("ev") in ("ui_action",) or (r.get("ev") in ("pickup", "equip") and r["ms"] < samples[0]["ms"] + 240000):
            print("  %s %-9s %s" % (clock(r["ms"]), r["ev"], {y: r[y] for y in ("machine", "action", "details", "item", "from", "slot") if y in r}))
    print("\n-- attacks, by verb and weapon")
    print(Counter((h["verb"][:30], h["weapon"]) for h in mine).most_common(24))
    print("done to them:", Counter((h["verb"][:30], h["weapon"]) for h in theirs).most_common(14))

    print("\n-- targets in order")
    order = []
    for h in mine:
        if h["target"] and h["target"] not in order and h["target"] != "Mikayla Collins":
            order.append(h["target"])
    for name in order:
        lines = [h for h in mine if h["target"] == name]
        print("  %s %-18s %3d attacks over %3ds, %s, last hp %s" % (clock(lines[0]["ms"]), name, len(lines), (lines[-1]["ms"] - lines[0]["ms"]) // 1000, Counter(h["weapon"] or h["verb"][:14] for h in lines).most_common(3), lines[-1]["hp"]))

    print("\n-- range: clicks on somebody")
    on_people = [c for c in clicks if c["target_type"].startswith("/mob/living/carbon/human") and c.get("dist") is not None and c["int"] != "help" or (c["target_type"].startswith("/mob/living/carbon/human") and c.get("ah") and c.get("dist", 0) > 1)]
    print("clicks on people:", len(on_people), "with:", Counter(c.get("ah") for c in on_people).most_common(8))
    print("distance:", sorted(Counter(c.get("dist") for c in on_people).items()))
    print("clicks on the floor near people, gun out:", sum(1 for c in clicks if c.get("ah") and "floor" in c["target"] and c.get("dist", 0) > 1))
    print("intent in those clicks:", Counter(c["int"] for c in on_people).most_common())
    print("cooldown clicks:", sum(1 for c in on_people if c["cd"]))

    print("\n-- on the move in a fight: samples with an enemy in view")
    fight = [s for s in samples if any(n[3] == 0 and abs(n[1]) + abs(n[2]) <= 7 for n in s.get("near", []))]
    moving = [s for s in fight if s["mv"]]
    print("%d samples with somebody up and close, %d moving (%d%%)" % (len(fight), len(moving), 100 * len(moving) // max(1, len(fight))))
    near_d = [min(max(abs(n[1]), abs(n[2])) for n in s["near"] if n[3] == 0) for s in fight]
    print("distance to the nearest:", sorted(Counter(near_d).items()))

    print("\n-- reaction: hit, then their next click or key")
    reacts = []
    for h in theirs:
        if h["verb"].startswith(("punched", "attacked", "shot", "kicked", "stunned", "threw", "pushed")):
            nxt = next((r for r in rows if r["ms"] > h["ms"] and r.get("ev") in ("click", "key")), None)
            if nxt and nxt["ms"] - h["ms"] < 3000:
                reacts.append(nxt["ms"] - h["ms"])
    print("ms:", spread(reacts))

    print("\n-- health and leaving a fight")
    low = min(samples, key=lambda s: s["hp"])
    print("lowest %s at %s" % (low["hp"], clock(low["ms"])))
    was = None
    for r in rows:
        if r.get("ev") == "area":
            hp = r.get("hp")
            if "Med" in r["area"] or (hp is not None and hp < 60):
                print("  %s %s hp %s" % (clock(r["ms"]), r["area"], hp))
    print("\n-- suit, hands")
    buttons = Counter(c["target"] for c in clicks if "dist" not in c)
    print("HUD and action buttons:", buttons.most_common(16))
    print("hands while somebody is close:", Counter(s.get("ah") for s in fight).most_common(10))
    print("items picked up:", Counter(r["item"] for r in rows if r.get("ev") == "pickup").most_common(20))
    print("throw mode clicks:", sum(1 for c in clicks if c["thr"]), Counter(c.get("ah") for c in clicks if c["thr"]).most_common(8))
    print("drags:", [(clock(r["ms"]), r["from"], r["over"]) for r in rows if r.get("ev") == "drag"][:10])
    print("pulling:", Counter(s.get("pull") for s in samples if s.get("pull")).most_common(6))


if __name__ == "__main__":
    folder = sys.argv[1]
    part = sys.argv[2] if len(sys.argv) > 2 else "input"
    rows = load(folder)
    (input_report(rows) if part == "input" else play_report(rows, folder))
