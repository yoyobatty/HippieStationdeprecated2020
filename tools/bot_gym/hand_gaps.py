"""How fast bots work their hands: the time between one hand event and the next in bot_telemetry, by kind of pair, and where the ones a
player couldn't make come from.

A player's inputs are a click or a key each: letting go of something (drop, put in the bag) and taking the next, drawing a tool and
clicking with it, are each at least a few tenths of a second apart. The audit of 2026-11-21 found 42% of draws less than 0.2 s before the
click they were for, and a drop and a pickup in the same tick about a thousand times a shift (play1114b); bot_human.dm's hand_beat() is the
fix, and this is how to see whether a batch still has it. Event kinds are those bot_telemetry.dm writes: draw (taken out of a bag, belt or
worn slot into a hand), pickup (off the floor or a thing), drop (to the floor), unequip (into a bag), equip, use (a click with an item),
click, ui_action.

Usage: python tools/bot_gym/hand_gaps.py [--fast SECS] [--top N] <run dir> [run dir...]
  python tools/bot_gym/hand_gaps.py data/logs/shift_batch/play1114b/run*
Output: for each pair of one event followed by another by the same bot (the common pairs), how many there are, the median gap in
seconds and the share closer than --fast (default 0.2 s); then the --top (default 15) goals and steps that let go of something and took
another within --fast, with an example (run, bot, game time). Times are game time (the events' "t" is in deciseconds), so timewarp
doesn't stretch them. Runs from before hand_beat() have most of the drop -> pickup and draw -> use pairs under 0.2 s; after it, none
should be (a few remain where code takes things without a pause: strip, handed items, machine output).
"""
import argparse
import collections
import json
import statistics

import logread

KINDS = ("use", "pickup", "draw", "click", "drop", "unequip", "equip", "ui_action")


def scan(run, gaps, sources, examples):
    path = logread.find(run, "telemetry")
    if not path:
        return
    name = run.replace("\\", "/").rstrip("/").split("/")[-1]
    per_bot = collections.defaultdict(list)
    for line in logread.lines(path):
        i = line.find("{")
        if i < 0 or '"k":"e"' not in line:
            continue
        try:
            j = json.loads(line[i:])
        except ValueError:
            continue
        if j.get("ev") in KINDS:
            per_bot[j.get("b", "?")].append(j)
    for bot, events in per_bot.items():
        events.sort(key=lambda e: e["t"])
        for a, b in zip(events, events[1:]):
            gap = (b["t"] - a["t"]) / 10.0
            gaps[(a["ev"], b["ev"])].append(gap)
            if a["ev"] in ("drop", "unequip") and a.get("was") in ("active_hand", "inactive_hand") and b["ev"] in ("pickup", "draw"):
                key = (a.get("g") or "", a.get("step") or "", a["ev"], b["ev"])
                sources[key].append(gap)
                examples.setdefault(key, (name, bot, a["t"] / 10.0, a.get("item"), b.get("item")))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("runs", nargs="+", help="run directories (or telemetry files)")
    parser.add_argument("--fast", type=float, default=0.2, help="a gap shorter than this many seconds is too fast (default 0.2)")
    parser.add_argument("--top", type=int, default=15, help="how many sources to list (default 15)")
    args = parser.parse_args()
    gaps = collections.defaultdict(list)
    sources = collections.defaultdict(list)
    examples = {}
    for run in args.runs:
        scan(run, gaps, sources, examples)
    print("pair                       n   median s   share < %.1f s" % args.fast)
    for pair, values in sorted(gaps.items(), key=lambda kv: -len(kv[1]))[:16]:
        fast = sum(1 for v in values if v < args.fast) / len(values)
        print("%-24s %6d   %6.2f      %3.0f%%" % (pair[0] + " -> " + pair[1], len(values), statistics.median(values), fast * 100))
    print()
    print("let go of in a hand, then taken within %.1f s (goal, step, let go as, taken as):" % args.fast)
    rows = []
    for key, values in sources.items():
        n = sum(1 for v in values if v < args.fast)
        if n:
            rows.append((n, key))
    for n, key in sorted(rows, reverse=True)[: args.top]:
        run, bot, at, first, second = examples[key]
        print("%6d  %-28s %-34s %s -> %s   e.g. %s %s t=%.0fs %s -> %s" % (n, key[0] or "(no goal)", key[1] or "-", key[2], key[3], run, bot, at, first, second))


if __name__ == "__main__":
    main()
