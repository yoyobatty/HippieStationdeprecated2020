"""Bots standing frozen: the "idle" events in bot_telemetry (3 s or more with no step taken and no action in progress, while awake),
counted by what the bot was supposedly doing (state, goal, pursuit kind) over whole batches. A player who freezes for 8 s is AFK; the
user flagged 5-10 s freezes as the thing that gives a bot away (2026-09-25), and analyze_telemetry.py only lists them per bot.

Usage: python tools/bot_gym/idle_scan.py [--min SECS] [--top N] <run dir> [run dir...]
  python tools/bot_gym/idle_scan.py --min 8 data/logs/shift_batch/night11/run*
Output: one line per (state, goal, pursuit, sat/why/stood) with the number of stretches over --min seconds (default 8), the total seconds in them and
the longest, then three example places. Times are game time (world.time), so timewarp doesn't stretch them. "sat" is buckled to a chair (a break), "why" a duty or request
it was holding for, "stood" nothing. Runs from before 2026-11-21 also count time spent knocked down or in crit as idle: ignore those.
"""
import argparse
import collections
import json

import logread


def scan(run, min_secs, found):
    path = logread.find(run, "telemetry")
    if not path:
        return
    name = run.replace("\\", "/").rstrip("/").split("/")[-1]
    for line in logread.lines(path):
        i = line.find("{")
        if i < 0 or '"ev":"idle"' not in line:
            continue
        try:
            j = json.loads(line[i:])
        except ValueError:
            continue
        dur = j.get("dur", 0) / 10.0
        if dur < min_secs:
            continue
        key = (j.get("st"), j.get("g") or "-", j.get("pk") or "-", "sat" if j.get("sit") else (j.get("why") or "stood"))
        found[key].append((dur, "%s %s t=%.0f (%s,%s,%s)" % (name, j.get("b", "?"), j.get("t", 0) / 10.0, j.get("x"), j.get("y"), j.get("z"))))


def scan_samples(run, min_secs, found):
    """The same from the twice-a-second "s" samples, for runs from before the idle events knew about being down: a stretch is a run of
    samples with no step, no action and not incapacitated. Chair-sat time can't be told apart here (no buckled flag), so it's "stood"."""
    path = logread.find(run, "telemetry")
    if not path:
        return
    name = run.replace("\\", "/").rstrip("/").split("/")[-1]
    last = {}  # bot -> (start t, first sample)
    prev_t = {}
    for line in logread.lines(path):
        i = line.find("{")
        if i < 0 or '"k":"s"' not in line:
            continue
        try:
            j = json.loads(line[i:])
        except ValueError:
            continue
        b = j.get("b")
        t = j.get("t", 0)
        still = not j.get("mv") and not j.get("act") and not j.get("inc")
        if still and b not in last:
            last[b] = (t, j)
        elif not still and b in last:
            t0, first = last.pop(b)
            dur = (prev_t.get(b, t) - t0) / 10.0
            if dur >= min_secs:
                key = (first.get("st"), first.get("g") or "-", first.get("pk") or "-", first.get("step") or "stood")
                found[key].append((dur, "%s %s t=%.0f (%s,%s,%s)" % (name, b, t0 / 10.0, first.get("x"), first.get("y"), first.get("z"))))
        prev_t[b] = t


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--min", type=float, default=8.0)
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--samples", action="store_true", help="work from the samples instead of the idle events (older runs)")
    args = ap.parse_args()
    found = collections.defaultdict(list)
    for run in args.runs:
        (scan_samples if args.samples else scan)(run, args.min, found)
    rows = sorted(found.items(), key=lambda kv: -sum(d for d, _ in kv[1]))
    total = sum(len(v) for v in found.values())
    print("%d idle stretches of %.0f s or more" % (total, args.min))
    for key, hits in rows[: args.top]:
        hits.sort(reverse=True)
        print("%4d x  total %6.0fs  longest %5.1fs  state=%s goal=%s pursuit=%s %s" % (len(hits), sum(d for d, _ in hits), hits[0][0], key[0], key[1], key[2], key[3]))
        for d, where in hits[:3]:
            print("          %5.1fs %s" % (d, where))


if __name__ == "__main__":
    main()
