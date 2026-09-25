#!/usr/bin/env python3
"""Believability report for bot telemetry (hippiestation/code/modules/bots_ai/bot_telemetry.dm).

Reads data/logs/<round>/bot_telemetry.jsonl and reports, per bot, the things a watching player
would notice: standing still with nothing going on, using tools that aren't in hand, operating
things it isn't facing, items teleporting or grabbed in bursts, walking rhythm and backtracking,
and how long each goal took.

Usage:
  python tools/bot_gym/analyze_telemetry.py                      # newest round with telemetry
  python tools/bot_gym/analyze_telemetry.py <path to jsonl>      # a specific file
  python tools/bot_gym/analyze_telemetry.py --bot "Jordan"       # one bot only
"""
import argparse, collections, glob, json, os, re, statistics

PREFIX = re.compile(r'^\[[^\]]*\]\s*')
IDLE_SECONDS = 3.0


def load(path):
    bots = collections.defaultdict(lambda: {'s': [], 'e': []})
    for raw in open(path, encoding='utf-8', errors='ignore'):
        raw = PREFIX.sub('', raw.strip())
        if not raw.startswith('{'):
            continue
        try:
            rec = json.loads(raw)
        except ValueError:
            continue
        bots[rec.get('b', '?')][rec.get('k', 'e')].append(rec)
    return bots


def secs(ds):
    return ds / 10.0


def clock(t, t0):
    return f"{secs(t - t0):7.1f}s"


def idle_stretches(samples):
    """Runs of samples with no movement and no action in progress, while conscious."""
    out, start = [], None
    for s in samples:
        still = not s.get('mv') and not s.get('act') and not s.get('inc')
        if still and start is None:
            start = s
        elif not still and start is not None:
            dur = secs(s['t'] - start['t'])
            if dur >= IDLE_SECONDS:
                out.append((dur, start, s))
            start = None
    return out


def classify_idle(s):
    if s.get('g') and s.get('pk') and s.get('pl'):
        return "has a route but isn't walking it"
    if s.get('g') and s.get('pk'):
        return 'pursuing with no route'
    if s.get('g'):
        return 'has a goal, nothing in motion'
    if s.get('pk') == 'wander':
        return 'wandering, not moving'
    return 'no goal at all'


def report(name, data, verbose):
    S = sorted(data['s'], key=lambda r: r['t'])
    E = sorted(data['e'], key=lambda r: r['t'])
    if not S and not E:
        return
    t0 = min([r['t'] for r in S[:1] + E[:1]])
    t_end = max([r['t'] for r in S[-1:] + E[-1:]])
    span = max(secs(t_end - t0), 0.1)
    print(f"\n{'=' * 78}\n{name}   ({span:.0f}s recorded, {len(S)} samples, {len(E)} events)")

    moving = sum(1 for s in S if s.get('mv'))
    acting = sum(1 for s in S if s.get('act') and not s.get('mv'))
    idle = idle_stretches(S)
    idle_total = sum(d for d, _, _ in idle)
    if S:
        print(f"  time: walking {100 * moving / len(S):.0f}% | acting {100 * acting / len(S):.0f}% | "
              f"idle 3s+ {100 * idle_total / span:.0f}% ({len(idle)} stretches, {idle_total:.0f}s)")

    # --- goals ---
    starts = {}
    goals = []
    for e in E:
        if e['ev'] == 'goal_start':
            starts[e['goal']] = e
        elif e['ev'] == 'goal_end' and e.get('goal') in starts:
            st = starts.pop(e['goal'])
            goals.append((st, e))
    if goals:
        print("  goals:")
        for st, en in goals[-12:]:
            print(f"    {clock(st['t'], t0)} {st['goal']:<38} {en['result']:<8} {secs(en['t'] - st['t']):6.1f}s"
                  f"{'  (fetch for ' + st['nested'] + ')' if st.get('nested') else ''}")

    # --- idle ---
    if idle:
        print("  longest idle stretches:")
        for dur, s, nxt in sorted(idle, key=lambda i: -i[0])[:8]:
            hands = ', '.join(h for h in (s.get('ah'), s.get('ih')) if h) or 'empty hands'
            print(f"    {clock(s['t'], t0)} {dur:5.1f}s  {classify_idle(s):<32} goal={s.get('g')} step={s.get('step')} "
                  f"@({s.get('x')},{s.get('y')},{s.get('z')}) [{hands}]")

    # --- tools used outside the hand / not facing / teleports ---
    bad_tool = [e for e in E if e['ev'] == 'shortcut' and not e.get('legit')]
    if bad_tool:
        print(f"  tools used without holding them: {len(bad_tool)}")
        for e in bad_tool[:8]:
            print(f"    {clock(e['t'], t0)} {e['proc']}: {e['item']} was {e['item_was']} -> {e.get('target')}")
    facing = [e for e in E if e['ev'] in ('use', 'click', 'shortcut') and e.get('facing') is False]
    if facing:
        print(f"  interacted with something it wasn't facing: {len(facing)}")
        for e in facing[:6]:
            print(f"    {clock(e['t'], t0)} {e['ev']} {e.get('item', '')} -> {e.get('target')} (dist {e.get('dist')})")
    unheld_equip = [e for e in E if e['ev'] == 'equip' and (e.get('from') == 'floor' or str(e.get('from', '')).startswith('in:'))]
    if unheld_equip:
        print(f"  equipped straight from the floor/a container, never held: {len(unheld_equip)}")
        for e in unheld_equip[:6]:
            print(f"    {clock(e['t'], t0)} {e['item']} from {e['from']} -> slot {e.get('slot')}")
    tele = [e for e in E if e['ev'] == 'teleport_item']
    if tele:
        print(f"  items moved without being touched (teleports): {len(tele)}")
        for e in tele[:6]:
            print(f"    {clock(e['t'], t0)} {e['item']}: {e['from']} -> {e['to']}")

    # --- pickups ---
    picks = [e for e in E if e['ev'] == 'pickup']
    if picks:
        burst = [e for e in picks if e.get('since_last_pickup', 99) < 3]
        remote = [e for e in picks if (e.get('dist') or 0) > 1]
        print(f"  pickups: {len(picks)} ({len(burst)} within 0.3s of the previous, {len(remote)} from more than a tile away)")
        for e in picks[-10:] if verbose else picks[-6:]:
            flag = ' BURST' if e in burst else ''
            flag += ' REMOTE' if e in remote else ''
            print(f"    {clock(e['t'], t0)} {e['item']:<32} from {e['from']:<12} {e.get('from_type') or '':<22} "
                  f"goal={e.get('g')}{flag}")
    drops = [e for e in E if e['ev'] == 'drop']
    if drops:
        print(f"  dropped on the floor: {len(drops)}  (e.g. {', '.join(d['item'] for d in drops[:5])})")
    both = sum(1 for s in S if s.get('ah') and s.get('ih') and s.get('mv'))
    if S and both:
        print(f"  walking with both hands full: {100 * both / max(moving, 1):.0f}% of walking time")

    # --- movement rhythm and backtracking ---
    in_motion = [s for s in S if s.get('pk') and s.get('pl')]
    if len(in_motion) >= 6:
        rates = [s.get('mv', 0) for s in in_motion]
        stalls = sum(1 for a, b, c in zip(rates, rates[1:], rates[2:]) if a and not b and c)
        print(f"  walking rhythm: {statistics.mean(rates) * 2:.1f} tiles/s on route, "
              f"{stalls} mid-route stops (moving -> stopped -> moving)")
    visits = {}
    backtracks = 0
    for s in S:
        if not s.get('mv') or not s.get('g'):
            continue
        key = (s.get('x'), s.get('y'), s.get('z'), s.get('g'))
        if key in visits and s['t'] - visits[key] > 50:
            backtracks += 1
        visits[key] = s['t']
    if backtracks:
        print(f"  backtracking: revisited {backtracks} tiles 5s+ later during the same goal")

    gave_up = [e for e in E if e['ev'] == 'goal_end' and e['result'] == 'gave_up']
    if gave_up:
        common = collections.Counter(e['goal'] for e in gave_up).most_common(4)
        print(f"  gave up: {len(gave_up)} times ({', '.join(f'{g} x{n}' for g, n in common)})")


def newest_telemetry():
    files = glob.glob('data/logs/**/bot_telemetry.jsonl', recursive=True)
    return max(files, key=os.path.getmtime) if files else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('path', nargs='?')
    ap.add_argument('--bot')
    ap.add_argument('--include-gym', action='store_true', help='include Bot Gym bots (named "Gym ...")')
    ap.add_argument('-v', '--verbose', action='store_true')
    args = ap.parse_args()
    path = args.path or newest_telemetry()
    if not path:
        raise SystemExit('No bot_telemetry.jsonl found under data/logs/')
    print(f"Bot telemetry: {path}")
    for name, data in sorted(load(path).items()):
        if args.bot and args.bot.lower() not in name.lower():
            continue
        if name.startswith('Gym ') and not args.include_gym:
            continue
        report(name, data, args.verbose)


if __name__ == '__main__':
    main()
