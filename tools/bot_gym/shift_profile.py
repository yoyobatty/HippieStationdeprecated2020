#!/usr/bin/env python3
"""Where the server's time went during a profiled Bot Shift (PROFILE=1 tools/bot_gym/run_bot_shift.sh).

A fast-forwarded shift can only skip the time the server spends idle, so the CPU cost of a tick
is what sets how fast a shift runs. This reads data/bot_shift/profile.json and lists the procs
that cost the most, by self time (time in the proc itself, not in what it calls).

Usage:
  python tools/bot_gym/shift_profile.py                 # top 40 procs
  python tools/bot_gym/shift_profile.py --top 80
  python tools/bot_gym/shift_profile.py --match bot     # only procs with "bot" in the path
  python tools/bot_gym/shift_profile.py --by total      # sort by time including callees
"""
import argparse, collections, json, os, re


def group_of(name):
    """A coarse bucket for the totals table."""
    n = name.lower()
    if 'bot_' in n or '/bot' in n or 'astar' in n or 'pathnode' in n:
        return 'bot AI + pathfinding'
    for key, label in (('/subsystem/air', 'atmos'), ('gas_mixture', 'atmos'), ('/turf/open/proc/process_cell', 'atmos'),
                       ('excited_group', 'atmos'), ('atmospherics', 'atmos machinery'), ('lighting', 'lighting'),
                       ('/controller/master', 'master controller'), ('/subsystem/timer', 'timers'), ('timedevent', 'timers'),
                       ('/mob/', 'mobs'), ('/datum/reagent', 'chemistry'), ('/obj/machinery', 'machinery'),
                       ('/datum/controller/subsystem', 'other subsystems')):
        if key in n:
            return label
    return 'everything else'


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('path', nargs='?', default='data/bot_shift/profile.json')
    ap.add_argument('--top', type=int, default=40)
    ap.add_argument('--match', help='only procs whose path contains this')
    ap.add_argument('--by', choices=('self', 'total'), default='self')
    args = ap.parse_args()
    if not os.path.exists(args.path):
        raise SystemExit(f'{args.path} not found - run the shift with PROFILE=1')
    rows = json.load(open(args.path, encoding='utf-8', errors='ignore'))
    self_total = sum(r['self'] for r in rows)
    real = None
    results = os.path.join(os.path.dirname(args.path), 'results.json')
    if os.path.exists(results):
        info = json.load(open(results, encoding='utf-8', errors='ignore'))
        real = info.get('real_seconds')
        print(f"{info.get('minutes')} minute shift in {real:.0f}s of real time ({info.get('speed')}x), "
              f"load {info.get('load_avg')}% of a tick")
    print(f"{self_total:.1f}s of proc time across {len(rows)} procs"
          + (f" = {100 * self_total / real:.0f}% of the run's real time" if real else ''))

    groups = collections.Counter()
    for r in rows:
        groups[group_of(r['name'])] += r['self']
    print('\nBy area (self time):')
    for label, secs in groups.most_common():
        print(f"  {secs:8.2f}s {100 * secs / self_total:5.1f}%  {label}")

    if args.match:
        rows = [r for r in rows if args.match.lower() in r['name'].lower()]
    rows.sort(key=lambda r: -r[args.by])
    print(f"\nTop {min(args.top, len(rows))} procs by {args.by} time:")
    print(f"  {'self s':>8} {'%':>5} {'total s':>8} {'calls':>10} {'us/call':>8}  proc")
    for r in rows[:args.top]:
        per_call = 1e6 * r['self'] / r['calls'] if r['calls'] else 0
        print(f"  {r['self']:8.2f} {100 * r['self'] / self_total:5.1f} {r['total']:8.2f} {r['calls']:10d} {per_call:8.1f}  {r['name']}")


if __name__ == '__main__':
    main()
