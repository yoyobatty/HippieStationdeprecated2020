#!/usr/bin/env python3
"""Give-up loops: a bot that gives up on the same goal again and again for minutes, never once getting it done in between.

hollow_goals.py finds goals that "succeed" over and over doing nothing; this is the other half. The Turing judge's most bot-like windows
(turing.py, 2026-11-28) were a Security Officer, Casey Nakamura (round 2026-11-14 01:12), who spent 25 minutes at 40 health going
between the Bridge's emergency toolbox and a locked maintenance door for a pair of security HUD glasses: the tool fetch was given up,
the HUD errand resumed, the door wouldn't open, the tool fetch again, under turret fire the whole time. Each give-up on its own is
ordinary, so the batch digest's give-up counts and giveups.py's reasons don't show a loop; the same goal failing every minute or two for
a quarter of an hour does.

A loop here is one bot giving up on one goal type --min times or more (default 4) with no success of that goal in between, over at
least --span game seconds (default 120) from the first give-up to the last. A success of the goal ends the loop; a gap of more than
--gap game seconds (default 300) between two give-ups ends it too. Goal types and targets come from bot_telemetry's goal_start and
goal_end events, and times are game time ("t"), so timewarp doesn't stretch them.

Usage: python tools/bot_gym/giveup_loops.py [--min 4] [--span 120] [--gap 300] [--top 12] <run or batch dir>...
  python tools/bot_gym/giveup_loops.py data/logs/shift_batch/hands1128_before data/logs/shift_batch/hands1128_after
Output, per argument: how many loops, the game minutes they cover and the share of bot time spent inside one; the goal types that loop
most (loops, give-ups, minutes, bots); then the longest loops, with the targets it kept going for, the share of the loop spent trying
(goal_start to goal_end), where, and the death_story.py line to look at its start.
"""
import argparse
import collections
import glob
import json
import os
import re

import logread

WALL = re.compile(r'^\[(?:\d+-\d+-\d+ )?(\d+:\d+:\d+)')


def runs_under(path):
    if logread.find(path, 'telemetry'):
        return [path]
    return sorted({os.path.dirname(p) for p in glob.glob(os.path.join(path, '**', 'bot_telemetry.jsonl*'), recursive=True)})


def scan(run, args):
    """Loops in one run, and the bots' total sampled time there (for the share), as (loops, bot_seconds)."""
    open_goal = collections.defaultdict(dict)  # bot -> goal -> (goal, target, start t, x, y, z, wall): one each, as goals nest (a tool fetch)
    attempts = collections.defaultdict(list)  # (bot, goal) -> [(start t, end t, result, target, place, wall)]
    first_t, last_t = {}, {}
    for line in logread.lines(logread.find(run, 'telemetry')):
        i = line.find('{')
        if i < 0:
            continue
        if '"goal_start"' not in line and '"goal_end"' not in line and '"k":"s"' not in line:
            continue
        try:
            r = json.loads(line[i:])
        except ValueError:
            continue
        b, t = r.get('b'), r.get('t')
        if b is None or t is None:
            continue
        first_t.setdefault(b, t)
        last_t[b] = t
        ev = r.get('ev')
        if ev == 'goal_start':
            m = WALL.match(line)
            g = r.get('goal') or '?'
            open_goal[b][g] = (g, r.get('target') or '?', t, r.get('x'), r.get('y'), r.get('z'), m.group(1) if m else '')
        elif ev == 'goal_end':
            goal = r.get('goal') or '?'
            m = WALL.match(line)
            end_wall = m.group(1) if m else ''
            started = open_goal[b].pop(goal, None)
            target = started[1] if started else '?'
            start_t = started[2] if started else t
            place = '(%s,%s,%s)' % (started[3], started[4], started[5]) if started else '(%s,%s,%s)' % (r.get('x'), r.get('y'), r.get('z'))
            attempts[(b, goal)].append((start_t, t, r.get('result'), target, place, end_wall))
    loops = []
    for (b, goal), tries in attempts.items():
        streak = []
        for a in tries + [(None, None, 'end', None, None, None)]:
            gap_ok = streak and a[1] is not None and (a[1] - streak[-1][1]) / 10.0 <= args.gap
            if a[2] == 'gave_up' and (not streak or gap_ok):
                streak.append(a)
                continue
            if len(streak) >= args.min and (streak[-1][1] - streak[0][1]) / 10.0 >= args.span:
                loops.append(make_loop(run, b, goal, streak))
            streak = [a] if a[2] == 'gave_up' else []
    bot_seconds = sum((last_t[b] - first_t[b]) / 10.0 for b in last_t)
    return loops, bot_seconds


def make_loop(run, bot, goal, streak):
    span = (streak[-1][1] - streak[0][0]) / 10.0
    trying = sum(max(0, a[1] - a[0]) for a in streak) / 10.0
    targets = collections.Counter(a[3] for a in streak)
    places = collections.Counter(a[4] for a in streak)
    return {'run': run.replace('\\', '/'), 'bot': bot, 'goal': goal, 'tries': len(streak), 'span': span, 'trying': trying,
            'targets': targets, 'places': places, 'start_t': streak[0][0], 'wall': streak[0][5]}  # wall: the first give-up


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('dirs', nargs='+')
    ap.add_argument('--min', type=int, default=4, help='give-ups in a row with no success to count as a loop')
    ap.add_argument('--span', type=float, default=120, help='game seconds from the first give-up to the last, at least')
    ap.add_argument('--gap', type=float, default=300, help='most game seconds between two give-ups in one loop')
    ap.add_argument('--top', type=int, default=12)
    args = ap.parse_args()
    for target in args.dirs:
        runs = runs_under(target)
        loops, bot_seconds = [], 0.0
        for run in runs:
            found, secs = scan(run, args)
            loops += found
            bot_seconds += secs
        minutes = sum(l['span'] for l in loops) / 60.0
        print('%s (%d runs): %d give-up loops, %.0f game minutes in them, %.1f%% of bot time' % (
            target, len(runs), len(loops), minutes, 100.0 * minutes * 60 / bot_seconds if bot_seconds else 0))
        by_goal = collections.defaultdict(lambda: [0, 0, 0.0, set()])
        for l in loops:
            g = by_goal[l['goal']]
            g[0] += 1
            g[1] += l['tries']
            g[2] += l['span'] / 60.0
            g[3].add((l['run'], l['bot']))
        if by_goal:
            print('  goal types that loop:  loops  give-ups  minutes  bots')
            for goal, (n, tries, mins, bots) in sorted(by_goal.items(), key=lambda kv: -kv[1][2])[:args.top]:
                print('    %-34s %4d  %7d  %7.1f  %4d' % (goal[:34], n, tries, mins, len(bots)))
            print('  longest loops:')
            for l in sorted(loops, key=lambda l: -l['span'])[:args.top]:
                print('    %5.1f min  %-20s %-28s gave up %3d times, trying %3.0f%% of it; at %s; for %s' % (
                    l['span'] / 60.0, l['bot'][:20], l['goal'][:28], l['tries'], 100.0 * l['trying'] / l['span'] if l['span'] else 0,
                    ', '.join('%s x%d' % kv for kv in l['places'].most_common(2)),
                    ', '.join('%s x%d' % kv for kv in l['targets'].most_common(2))))
                print('        python tools/bot_gym/death_story.py %s "%s" 30 --at %s   (up to the first give-up)' % (
                    l['run'], l['bot'], l['wall']))
        print()


if __name__ == '__main__':
    main()
