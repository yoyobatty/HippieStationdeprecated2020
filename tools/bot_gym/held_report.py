#!/usr/bin/env python3
"""What bots keep in their hands when they aren't using it: between jobs (wander, no goal), by item, by the goal that took it up,
and for how long, with the player log's own hands (PLAYER_LOG_CKEY) beside it when the round has one.

A player puts a tool back on the belt or in the bag once the job's done and walks about with empty hands; turing.py found the
hands the biggest tell (2026-11-28): something in the active hand in 57% of a bot's calm samples against 22% of the player's,
screwdrivers, handcuffs, gas masks and a desk lamp carried round on wanders.

Usage: python tools/bot_gym/held_report.py [--top N] <run or batch dir>...
Output, per argument: the share of between-jobs time with something in a hand (active, other, either), the median and 90th
percentile of how long a thing stays held once the bot is between jobs, the items held longest in total, and the goals that
picked those up (from the pickup/draw event that put the item in hand). The player's line is all its awake samples with
help intent, since its log has no goal or state. Times are game time (samples' "t"), so timewarp doesn't stretch them.
"""
import argparse
import collections
import glob
import json
import os
import statistics

import logread


def runs_under(path):
    if logread.find(path, 'telemetry'):
        return [path]
    return sorted({os.path.dirname(p) for p in glob.glob(os.path.join(path, '**', 'bot_telemetry.jsonl*'), recursive=True)})


def scan_bots(run, out):
    """Adds this run's bots to out: samples between jobs, held time by item and by taking goal, stretch lengths."""
    took = {}  # (bot, item name) -> goal it was taken up in
    last = {}  # bot -> (t, ah, ih, between)
    stretch = {}  # (bot, item) -> seconds held so far between jobs
    for line in logread.lines(logread.find(run, 'telemetry')):
        i = line.find('{')
        if i < 0:
            continue
        try:
            r = json.loads(line[i:])
        except ValueError:
            continue
        b = r.get('b')
        if r.get('k') == 'e':
            if r.get('ev') in ('pickup', 'draw') and r.get('item'):
                took[(b, r['item'])] = r.get('g') or r.get('step') or '(between jobs)'
            continue
        if r.get('k') != 's' or r.get('hp') is None or r['hp'] <= 0:
            continue
        t = r['t']
        prev = last.get(b)
        dt = (t - prev[0]) / 10.0 if prev and 0 < t - prev[0] <= 20 else 0
        between = r.get('st') == 'wander' and not r.get('g') and not r.get('act') and not r.get('inc')
        last[b] = (t, r.get('ah'), r.get('ih'), between)
        if not dt:
            continue
        held_now = [x for x in (r.get('ah'), r.get('ih')) if x]
        for item in list(stretch):
            if item[0] == b and (item[1] not in held_now or not between):
                out['stretches'].append(stretch.pop(item))
        if not between:
            continue
        out['time'] += dt
        if r.get('ah'):
            out['active'] += dt
        if r.get('ih'):
            out['other'] += dt
        if held_now:
            out['either'] += dt
        for item in held_now:
            out['items'][item] += dt
            out['by_goal'][took.get((b, item), '(held from before the log)')] += dt
            out['goal_items'][(took.get((b, item), '(held from before the log)'), item)] += dt
            stretch[(b, item)] = stretch.get((b, item), 0) + dt
    out['stretches'] += list(stretch.values())


def scan_player(run, out):
    path = logread.find(run, 'player')
    if not path:
        return
    last = None
    for line in logread.lines(path):
        i = line.find('{"k":"s"')
        if i < 0:
            continue
        try:
            r = json.loads(line[i:])
        except ValueError:
            continue
        if r.get('hp') is None or r['hp'] <= 0 or r.get('b') in (None, '?'):
            continue
        t = r['t']
        dt = (t - last) / 10.0 if last is not None and 0 < t - last <= 20 else 0
        last = t
        if not dt or r.get('int') != 'help' or r.get('inc') or r.get('stat'):
            continue
        out['time'] += dt
        out['active'] += dt if r.get('ah') else 0
        out['other'] += dt if r.get('ih') else 0
        out['either'] += dt if (r.get('ah') or r.get('ih')) else 0
        for item in (r.get('ah'), r.get('ih')):
            if item:
                out['items'][item] += dt


def blank():
    return {'time': 0.0, 'active': 0.0, 'other': 0.0, 'either': 0.0, 'items': collections.Counter(),
            'by_goal': collections.Counter(), 'goal_items': collections.Counter(), 'stretches': []}


def pct(a, b):
    return 100.0 * a / b if b else float('nan')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('dirs', nargs='+')
    ap.add_argument('--top', type=int, default=15)
    args = ap.parse_args()
    for target in args.dirs:
        bots, player = blank(), blank()
        runs = runs_under(target)
        for run in runs:
            scan_bots(run, bots)
            scan_player(run, player)
        print('%s (%d runs)' % (target, len(runs)))
        for who, d in (('bots between jobs', bots), ('player, help intent', player)):
            if not d['time']:
                continue
            print('  %-20s %7.0f s: something in the active hand %4.1f%%, the other %4.1f%%, either %4.1f%%' % (
                who, d['time'], pct(d['active'], d['time']), pct(d['other'], d['time']), pct(d['either'], d['time'])))
        st = sorted(bots['stretches'])
        if st:
            print('  held on between jobs: median %.0f s, 90%% %.0f s, longest %.0f s (%d times)' % (
                statistics.median(st), st[int(len(st) * 0.9)], st[-1], len(st)))
        if bots['time']:
            print('  items held longest between jobs (share of between-jobs time):')
            for item, s in bots['items'].most_common(args.top):
                print('    %5.1f%%  %s' % (pct(s, bots['time']), item))
            print('  the goals that took them up:')
            for g, s in bots['by_goal'].most_common(args.top):
                top = [it for (gg, it), _ in bots['goal_items'].most_common() if gg == g][:4]
                print('    %5.1f%%  %-34s %s' % (pct(s, bots['time']), g[:34], ', '.join(top)))
        if player['time']:
            print('  player items: ' + ', '.join('%s %.1f%%' % (it, pct(s, player['time'])) for it, s in player['items'].most_common(8)))
        print()


if __name__ == '__main__':
    main()
