#!/usr/bin/env python3
"""Reads CPU stress bench runs (tools/bot_gym/run_stress_bench.sh) and prints what each phase cost, averaged over the runs,
optionally against another build's runs.

Usage:
  python tools/bot_gym/stress_report.py <label>                 # data/logs/shift_batch/stress-<label>/run*/stress.json
  python tools/bot_gym/stress_report.py <label> --vs <label>    # A against B, with the change
  python tools/bot_gym/stress_report.py <dir> ...               # any folders holding run*/stress.json or stress.json
  --subsystems N   how many subsystems to list per phase (default 8)
  --state          what the station was like at the end of each phase (for telling a faster build from one doing less)

Every figure is ms of real server time per second of game time, unless it says otherwise. "outside" is the real time not spent
in any subsystem: procs waking from sleep (mostly bot pathfinding), the MC's own bookkeeping, BYOND's own work. "engine" is the
MC without Timer and Processing, which are mostly the bots. Ranges are the lowest and highest run.
"""
import argparse, glob, json, os, statistics, sys


def load(spec):
    paths = []
    for base in (spec, os.path.join('data', 'logs', 'shift_batch', 'stress-' + spec)):
        if os.path.isdir(base):
            paths = sorted(glob.glob(os.path.join(base, 'run*', 'stress.json'))) or glob.glob(os.path.join(base, 'stress.json'))
            if paths:
                break
    runs = []
    for p in paths:
        try:
            with open(p, encoding='utf-8') as f:
                runs.append(json.load(f))
        except (OSError, ValueError) as e:
            print(f'  skipping {p}: {e}', file=sys.stderr)
    if not runs:
        raise SystemExit(f'no stress.json found for {spec}')
    return runs


def phase_figures(phase):
    s = max(phase['seconds'], 0.1)
    f = {
        'real': phase['real_ms'] / s,
        'MC': phase['mc_ms'] / s,
        # The MC without Timer and Processing, which are mostly the bots walking and thinking (out of scope, and noisy:
        # how much pathfinding a run does swings with where the crew ends up stranded)
        'engine': (phase['mc_ms'] - phase['ss_ms'].get('Timer', 0) - phase['ss_ms'].get('Processing', 0)) / s,
        'outside': (phase['real_ms'] - phase['mc_ms']) / s,
        'worst ms': phase['worst_ms'],
        'p99 ms': phase['p99'],
        '>25ms': phase['over_budget'],
        '>100ms': phase['over_100'],
    }
    for name, ms in phase['ss_ms'].items():
        f['ss:' + name] = ms / s
    for name, fired in phase['ss_fired'].items():
        f['fired:' + name] = fired / s
    for key, value in (phase.get('state') or {}).items():
        f['state:' + key] = value
    return f


def gather(runs):
    """phase name -> figure -> list of values, one per run; plus 'From calm on' over everything after the crew arrived."""
    out = {}
    order = []
    for run in runs:
        total = {'seconds': 0, 'real_ms': 0, 'mc_ms': 0, 'worst_ms': 0, 'p99': 0, 'over_budget': 0, 'over_100': 0, 'ss_ms': {}, 'ss_fired': {}}
        p99s = []
        for phase in run['phases']:
            name = phase['name']
            if name not in order:
                order.append(name)
            for key, value in phase_figures(phase).items():
                out.setdefault(name, {}).setdefault(key, []).append(value)
            if name == 'crew arriving':
                continue
            for key in ('seconds', 'real_ms', 'mc_ms', 'over_budget', 'over_100'):
                total[key] += phase[key]
            total['worst_ms'] = max(total['worst_ms'], phase['worst_ms'])
            p99s.append(phase['p99'])
            for name2, ms in phase['ss_ms'].items():
                total['ss_ms'][name2] = total['ss_ms'].get(name2, 0) + ms
            for name2, fired in phase['ss_fired'].items():
                total['ss_fired'][name2] = total['ss_fired'].get(name2, 0) + fired
        total['p99'] = max(p99s) if p99s else 0
        for key, value in phase_figures(total).items():
            out.setdefault('From calm on', {}).setdefault(key, []).append(value)
    order.append('From calm on')
    return order, out


def mean(values):
    return statistics.fmean(values) if values else 0.0


def fmt(values, digits=1):
    if not values:
        return '-'
    m = mean(values)
    if len(values) == 1:
        return f'{m:.{digits}f}'
    return f'{m:.{digits}f} ({min(values):.{digits}f}-{max(values):.{digits}f})'


def change(a, b):
    ma, mb = mean(a), mean(b)
    if not a or not b:
        return ''
    if ma == 0:
        return '' if mb == 0 else 'new'
    return f'{100 * (mb - ma) / ma:+.0f}%'


MAIN = ('real', 'MC', 'engine', 'outside', 'worst ms', 'p99 ms', '>25ms', '>100ms')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('a')
    ap.add_argument('--vs')
    ap.add_argument('--subsystems', type=int, default=8)
    ap.add_argument('--state', action='store_true')
    args = ap.parse_args()
    runs_a = load(args.a)
    order, fa = gather(runs_a)
    fb = None
    if args.vs:
        runs_b = load(args.vs)
        order_b, fb = gather(runs_b)
        order += [n for n in order_b if n not in order]
        print(f'{args.a}: {len(runs_a)} runs   against   {args.vs}: {len(runs_b)} runs   (mean, then lowest-highest run)')
    else:
        print(f'{args.a}: {len(runs_a)} runs on {runs_a[0].get("map")}, {runs_a[0].get("crew")} crew, {runs_a[0].get("fps")} ticks a second '
              '(mean, then lowest-highest run)')
    for name in order:
        a = fa.get(name, {})
        print()
        print(f'== {name}' + (f'  ({mean(a.get("state:crew alive", [])):.0f} crew alive at the end)' if a.get('state:crew alive') else ''))
        if fb is None:
            print('   ' + '   '.join(f'{k} {fmt(a.get(k, []), 0 if k.startswith(">") else 1)}' for k in MAIN))
        else:
            b = fb.get(name, {})
            for k in MAIN:
                d = 0 if k.startswith('>') else 1
                print(f'   {k:<9} {fmt(a.get(k, []), d):>24}  ->  {fmt(b.get(k, []), d):>24}  {change(a.get(k, []), b.get(k, []))}')
        keys = [k for k in a if k.startswith('ss:')]
        if fb is not None:
            keys += [k for k in fb.get(name, {}) if k.startswith('ss:') and k not in keys]
        keys.sort(key=lambda k: -max(mean(a.get(k, [])), mean((fb or {}).get(name, {}).get(k, [])) if fb else 0))
        keys = keys[:args.subsystems]
        if fb is None:
            print('   ' + ', '.join(f'{k[3:]} {mean(a[k]):.1f}' for k in keys))
        else:
            b = fb.get(name, {})
            for k in keys:
                fired = 'fired:' + k[3:]
                fired_note = ''
                if a.get(fired) and b.get(fired) and mean(a[fired]) > 0 and abs(mean(b[fired]) / mean(a[fired]) - 1) > 0.1:
                    fired_note = f'   fired {mean(a[fired]):.1f} -> {mean(b[fired]):.1f} a second'
                print(f'   {k[3:]:<20} {mean(a.get(k, [])):7.2f} -> {mean(b.get(k, [])):7.2f}  {change(a.get(k, []), b.get(k, []))}{fired_note}')
        if args.state:
            states = [k for k in a if k.startswith('state:')]
            if fb is None:
                print('   at the end: ' + ', '.join(f'{k[6:]} {mean(a[k]):.0f}' for k in states))
            else:
                b = fb.get(name, {})
                print('   at the end: ' + ', '.join(f'{k[6:]} {mean(a[k]):.0f}->{mean(b.get(k, [0])):.0f}' for k in states))


if __name__ == '__main__':
    main()
