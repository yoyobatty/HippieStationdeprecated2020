"""Bots with a route and an errand that don't take a step: from the twice-a-second telemetry samples, the time each bot spent on one tile
with a pursuit and a path (pk and pl set), not moving, not acting and not down. The pacing and idle scans don't see these: the bot keeps
changing its mind (give up, next goal, give up), so no goal is long and nothing looks frozen until the totals are added up per tile.

It was how the zero-g floaters were found (2026-11-21): in the 7 of 24 shifts where the gravity generator went offline, bots with nothing
to push off stood on one tile for up to 18 minutes with "stuck heading to the floor, rerouting" in the log; 30,000 s in those shifts,
1,000 s in the other 17. A run is marked "zero-g" if its gravity.html says "no gravity for this level".

Usage: python tools/bot_gym/stuck_walks.py [--min SECS] [--top N] <run dir> [run dir...]
  python tools/bot_gym/stuck_walks.py data/logs/shift_batch/night11/run*
Output: the bot-and-tile pairs with the most seconds (at least --min, default 60), then the totals for zero-g runs and the rest. What
stopped the bot is in the run's trace log: `python tools/bot_gym/logread.py <run> trace -b "Name" -g stuck-diagnostic` (mobility flags,
stun, who's pulling it, what it's buckled to; gravity isn't in it).
"""
import argparse
import collections
import json
import os

import logread


def zero_g(run):
    path = os.path.join(run, "gravity.html")
    try:
        with open(path, errors="replace") as f:
            return "no gravity for this level" in f.read()
    except OSError:
        return False


def scan(run, min_secs, rows):
    path = logread.find(run, "telemetry")
    if not path:
        return
    name = run.replace("\\", "/").rstrip("/").split("/")[-1]
    samples = collections.defaultdict(list)
    for line in logread.lines(path):
        i = line.find("{")
        if i < 0 or '"k":"s"' not in line:
            continue
        try:
            j = json.loads(line[i:])
        except ValueError:
            continue
        samples[j["b"]].append(j)
    low_g = zero_g(run)
    for bot, seq in samples.items():
        at = collections.Counter()
        for j in seq:
            if not j.get("mv") and not j.get("act") and not j.get("inc") and j.get("pk") and (j.get("pl") or 0) > 0:
                at[(j["x"], j["y"], j["z"])] += 0.5
        for tile, secs in at.items():
            if secs >= min_secs:
                rows.append((secs, name, bot, tile, low_g))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--min", type=float, default=60.0)
    ap.add_argument("--top", type=int, default=20)
    args = ap.parse_args()
    rows = []
    for run in args.runs:
        scan(run, args.min, rows)
    rows.sort(reverse=True)
    for secs, name, bot, tile, low_g in rows[: args.top]:
        print("%6.0fs  %-8s %-22s %s%s" % (secs, name, bot, tile, "  zero-g" if low_g else ""))
    print("%d bot-and-tile pairs of %.0f s or more: %.0f s in zero-g runs, %.0f s in the rest" % (
        len(rows), args.min, sum(r[0] for r in rows if r[4]), sum(r[0] for r in rows if not r[4])))


if __name__ == "__main__":
    main()
