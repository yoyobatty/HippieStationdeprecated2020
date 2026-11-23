"""Hollow goals: goals a bot "succeeds" at over and over on the same target without doing anything, each one over in a moment.

Found 2026-11-22 in the blob shifts: fighters picked the blob core hundreds of times a shift and every fight_blob goal "succeeded" the
tick it started (hit_blob gave up on a blocked step and a paced step's end is a success), so the next look round picked the same core
again. Nothing flagged it: the batch digest counts give-ups, and a success is no give-up. The core sat at 400/400 every shift.

A goal is hollow here when the same bot succeeds at the same goal type on the same target again and again (--repeat or more in a row,
none of them lasting more than --secs of wall clock, with no more than --gap between the end of one and the start of the next), and
in between it hardly moved (--moves step_next_node lines or fewer per goal, on average). Wall clock: timewarp runs a shift at 6-10x,
so a second of wall is several of game time.

Usage: python tools/bot_gym/hollow_goals.py [--repeat 5] [--secs 1.5] [--gap 3] [--moves 1] [--examples 2] <run or batch dir>...
  python tools/bot_gym/hollow_goals.py data/logs/shift_batch/night1122b_after data/logs/shift_batch/blob1122_night2_after
Output: per goal type, the hollow streaks, the goals in them, how many bots and shifts, and example streaks (bot, target, run, time).
Reads game.log and the bot trace (logread.bot_lines()), so it needs the trace, which Bot Shift and the gym write.
"""
import argparse
import collections
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import logread  # noqa: E402

STAMP = re.compile(r"^\[[0-9-]+ ([0-9:]+\.[0-9]+)\]")
TRYING = re.compile(r"BOT AI: (.+?): trying /datum/bot_strategy/\S+ for (/datum/bot_goal/\S+) \(target: (.*)\)$")
SUCCEEDED = re.compile(r"BOT AI: (.+?): goal (/datum/bot_goal/\S+) succeeded \(target: (.*)\)$")
MOVED = re.compile(r"BOT AI VERBOSE: (.+?): step_next_node")


def secs(stamp):
    h, m, s = stamp.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def runs_of(paths):
    for p in paths:
        if logread.find(p, "game"):
            yield p
        else:
            for r in sorted(glob.glob(os.path.join(p, "run*"))):
                if logread.find(r, "game"):
                    yield r


def scan(run, args, found):
    open_goal = {}   # bot -> (goal, target, start, moves)
    streak = {}      # bot -> dict(goal, target, n, moves, last_end, first)
    for line in logread.bot_lines(run):
        m = STAMP.match(line)
        if not m:
            continue
        t = secs(m.group(1))
        mv = MOVED.search(line)
        if mv:
            g = open_goal.get(mv.group(1))
            if g:
                g[3] += 1
            continue
        tr = TRYING.search(line)
        if tr:
            bot, goal, target = tr.groups()
            g = open_goal.get(bot)
            if not g or g[0] != goal or g[1] != target:
                open_goal[bot] = [goal, target, t, 0]
            continue
        su = SUCCEEDED.search(line)
        if not su:
            continue
        bot, goal, target = su.groups()
        g = open_goal.pop(bot, None)
        if "nonexistent location" in target:  # the target's gone: mopped up, eaten, used. That's work done, not hollow.
            close(bot, streak.get(bot), run, args, found)
            streak[bot] = None
            continue
        start, moves = (g[2], g[3]) if g and g[0] == goal else (t, 0)
        quick = t - start <= args.secs
        s = streak.get(bot)
        if quick and s and s["goal"] == goal and s["target"] == target and start - s["last_end"] <= args.gap:
            s["n"] += 1
            s["moves"] += moves
            s["last_end"] = t
            continue
        close(bot, s, run, args, found)
        streak[bot] = {"goal": goal, "target": target, "n": 1 if quick else 0, "moves": moves, "last_end": t, "first": m.group(1)} if quick else None
    for bot, s in streak.items():
        close(bot, s, run, args, found)


def close(bot, s, run, args, found):
    if not s or s["n"] < args.repeat or s["moves"] / s["n"] > args.moves:
        return
    found[s["goal"]].append((bot, re.sub(r" @ .*", "", s["target"]), os.path.relpath(run), s["first"], s["n"]))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--repeat", type=int, default=5)
    ap.add_argument("--secs", type=float, default=1.5)
    ap.add_argument("--gap", type=float, default=3)
    ap.add_argument("--moves", type=float, default=1)
    ap.add_argument("--examples", type=int, default=2)
    args = ap.parse_args(argv)
    found = collections.defaultdict(list)
    runs = list(runs_of(args.paths))
    for run in runs:
        scan(run, args, found)
    print("%d runs; hollow streaks (same bot, goal and target, %d+ in a row, each <= %.1fs wall, <= %.0f moves each):" % (len(runs), args.repeat, args.secs, args.moves))
    if not found:
        print("  none")
    for goal, streaks in sorted(found.items(), key=lambda kv: -sum(x[4] for x in kv[1])):
        total = sum(x[4] for x in streaks)
        bots = len({x[0] for x in streaks})
        shifts = len({x[2] for x in streaks})
        print("  %-48s %4d streaks  %6d goals  %3d bots  %2d shifts" % (goal.replace("/datum/bot_goal/", ""), len(streaks), total, bots, shifts))
        targets = collections.Counter(x[1] for x in streaks)
        print("      targets: " + ", ".join("%s x%d" % kv for kv in targets.most_common(4)))
        for bot, target, run, first, n in sorted(streaks, key=lambda x: -x[4])[:args.examples]:
            print("      e.g. %s on %s, %d in a row from %s (%s)" % (bot, target, n, first, run))


if __name__ == "__main__":
    main(sys.argv[1:])
