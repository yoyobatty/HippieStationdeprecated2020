#!/usr/bin/env python3
"""Two profiled Bot Shifts side by side: what a bot change did to the work, in calls and in microseconds a call.

Two shifts never run the same crew for the same game time, so raw seconds can't be compared. This divides each proc's calls by the
calls of a reference proc (default: one bot step, /datum/bot_brain/proc/do_step_next_node), so "calls per step" is comparable between
runs, and puts the self time a call beside it. Counts are exact; microseconds carry the profiler's own cost (~255 ns a proc call,
the same on both sides), so read them as a ratio.

Usage:
  python tools/bot_gym/profile_ab.py <before profile.json> <after profile.json>      # the bot procs that matter, by total time
  python tools/bot_gym/profile_ab.py A B --match log                                 # only procs with "log" in the path
  python tools/bot_gym/profile_ab.py A B --per /datum/bot_brain/process               # calls per brain tick instead of per step
  python tools/bot_gym/profile_ab.py A B --top 40
profile.json comes from a shift booted with PROFILE=1 (tools/bot_gym/run_bot_shift.sh, run_shift_batch.sh): data/logs/shift_batch/<name>/run1/.
"""
import argparse
import json
import os
import sys


def load(path):
    if os.path.isdir(path):
        path = os.path.join(path, 'profile.json')
    with open(path, encoding='utf-8', errors='ignore') as f:
        rows = json.load(f)
    by = {}
    for r in rows:
        # a proc defined at several levels of a type shows once a level: keep the biggest, which is the one that does the work
        old = by.get(r['name'])
        if old is None or r['total'] > old['total']:
            by[r['name']] = r
    return by


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('before')
    ap.add_argument('after')
    ap.add_argument('--per', default='/datum/bot_brain/proc/do_step_next_node', help='the proc whose calls are the unit')
    ap.add_argument('--match', default='bot', help='only procs whose path holds this (default: bot)')
    ap.add_argument('--top', type=int, default=30)
    args = ap.parse_args()
    a = load(args.before)
    b = load(args.after)
    if args.per not in a or args.per not in b:
        sys.exit('the reference proc %s is in neither profile' % args.per)
    unit_a, unit_b = a[args.per]['calls'], b[args.per]['calls']
    print('reference %s: %d calls before, %d after' % (args.per, unit_a, unit_b))
    print('%9s %9s %9s %9s %8s %8s  %s' % ('calls/ref', 'calls/ref', 'self us', 'self us', 'total s', 'total s', 'proc'))
    print('%9s %9s %9s %9s %8s %8s' % ('before', 'after', 'before', 'after', 'before', 'after'))
    names = [n for n in set(a) | set(b) if args.match.lower() in n.lower()]
    names.sort(key=lambda n: -max(a.get(n, {'total': 0})['total'], b.get(n, {'total': 0})['total']))
    for n in names[:args.top]:
        ra, rb = a.get(n), b.get(n)
        def per_ref(r, unit):
            return '%9.2f' % (r['calls'] / unit) if r and unit else '%9s' % '-'
        def self_us(r):
            return '%9.1f' % (1e6 * r['self'] / r['calls']) if r and r['calls'] else '%9s' % '-'
        def total_s(r):
            return '%8.2f' % r['total'] if r else '%8s' % '-'
        print('%s %s %s %s %s %s  %s' % (per_ref(ra, unit_a), per_ref(rb, unit_b), self_us(ra), self_us(rb), total_s(ra), total_s(rb), n[:70]))


if __name__ == '__main__':
    main()
