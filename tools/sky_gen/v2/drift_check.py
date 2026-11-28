"""Drift check: where the sky's bodies sit on screen as the sky turns over a round, from the real code.

    python tools/sky_gen/v2/drift_check.py probe TAG [rounds]     side build + headless testbench, writes data/sky_drift/TAG.json
    python tools/sky_gen/v2/drift_check.py score TAG [minutes...]  judges TAG.json at those minutes (default 0 30 60 120 240)
    python tools/sky_gen/v2/drift_check.py both TAG [rounds]       probe, then score

`probe` builds skydrift.mdme (hippiestation.dme + the testkit + drift_probe.dm), boots it headless on testbench (no client,
no DreamSeeker), and calls sky_drift_probe(): many round-start sky rolls, each made into the real layers, reporting each
absolute layer's place (place_x/place_y with the eye over the station's middle), its sky_rest() and its core radius, and the
band. It waits on tools/gpu_share.py before building and booting, and stops the server after.

`score` turns those with the sky the way the client draws them. The sky's angle follows the sun, starting at the
angle saved by the probe. update_parallax() lays an absolute layer out afresh only on a forced update (joining,
a new body, a z change). Its holder's screen position at t after a layout at t0 is
    turn(angle(t)) x (rest + turn(-angle(t0)) x (place - rest))
Two viewers are judged at each minute: "stayed", laid out at round start (t0 = 0) and never forced since, and "fresh", laid
out at that minute (t0 = t: a latejoiner, someone back from Lavaland). The band is a tiled layer that never re-lays out: its
line just turns with the sky.

Issues counted (share of rounds), on a 15x15 view (480 px) and a 19x15 one (608 x 480):
  overlap X/Y   two bright cores touch (Lavaland's whole disc counts against the sun and the other world)
  band_sun      the band's middle line within 60 px of the sun's middle
  cut X         under 40% of a thing's core is on screen (Lavaland included)
  dark_side     Lavaland's lit side (its art is lit from the sun's bearing, turned with the sky) points over 45 degrees off
                the sun as seen on screen
Also measures Lavaland's motion in the coordinate frame shared by it and the rare events. Prints one round's sun and
Lavaland screen positions per minute and writes a sheet of the worst rounds to data/previews/sky_drift_TAG.png.
"""
import json
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
OUT = os.path.join(ROOT, 'data', 'sky_drift')
VIEWS = {'15x15': (480, 480), '19x15': (608, 480)}
COLOURS = {'sun': (255, 220, 120), 'planet': (230, 90, 40), 'world': (120, 170, 255), 'galaxy': (220, 200, 255)}


def turn(angle, x, y):
    """BYOND matrix.Turn(angle): clockwise, y up"""
    c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    return x * c + y * s, -x * s + y * c


def probe(tag, rounds):
    sys.path.insert(0, os.path.join(ROOT, 'tools', 'testkit'))
    import tk  # noqa
    subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'gpu_share.py'), 'wait', 'sky drift probe'], check=True)
    dmb = tk.build(checks=['tools/sky_gen/v2/drift_probe.dm'], name='skydrift.mdme', quiet=True)
    s = tk.start('testbench', dmb=dmb, seed=7)
    try:
        rows = json.loads(s.call('call', ref='global', proc='sky_drift_probe', args=[rounds]))
    finally:
        tk.stop(s)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, tag + '.json')
    with open(path, 'w') as f:
        json.dump(rows, f)
    print('wrote', path, len(rows), 'rounds')


def sky_angle(row, minute):
    return row.get('start_angle', 0) + row['turn_per_minute'] * minute


def screen_places(row, t, t0):
    """name -> (x, y, core) on screen at minute t for a viewer laid out at minute t0"""
    out = {}
    for name, thing in row['things'].items():
        (px, py), (rx, ry) = thing['place'], thing['rest']
        dx, dy = turn(-sky_angle(row, t0), px - rx, py - ry)
        x, y = turn(sky_angle(row, t), rx + dx, ry + dy)
        out[name] = (x, y, thing['core'])
    return out


def band_distance(row, t, x, y):
    band = row['band']
    if not band:
        return 1e9
    bx, by = turn(-sky_angle(row, t), x, y)  # back into the sky's frame, where the band's numbers are
    a = math.radians(band['angle'])
    period = band['period']
    d = bx * math.sin(a) + by * math.cos(a) - band['offset']
    d = (d + period / 2) % period - period / 2
    return abs(d)


def issues_at(row, t, t0, view):
    w, h = VIEWS[view]
    places = screen_places(row, t, t0)
    found = []
    names = list(places)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if 'planet' in (a, b) and not ({'sun', 'world'} & {a, b}):
                continue  # Lavaland is drawn over the far things
            xa, ya, ra = places[a]
            xb, yb, rb = places[b]
            if math.hypot(xa - xb, ya - yb) < (ra + rb) * (1.0 if 'planet' in (a, b) else 0.8):
                found.append('overlap %s/%s' % (a, b))
    if 'sun' in places and band_distance(row, t, *places['sun'][:2]) < 60:
        found.append('band_sun')
    for n, (x, y, r) in places.items():
        r = max(r, 1)
        inside = max(0, min(w / 2, x + r) - max(-w / 2, x - r)) * max(0, min(h / 2, y + r) - max(-h / 2, y - r)) / (4 * r * r)
        if inside < 0.4:
            found.append('cut %s' % n)
    if 'planet' in places and 'sun' in places:
        sun = row['things']['sun']['place']
        lit = turn(sky_angle(row, t), *sun)  # the art turned to the sun's bearing in the sky, then with the sky
        px, py, _ = places['planet']
        sx, sy, _ = places['sun']
        off = abs((math.degrees(math.atan2(lit[1], lit[0]) - math.atan2(sy - py, sx - px)) + 540) % 360 - 180)
        if off > 45:
            found.append('dark_side')
    return found


def draw(row, t, t0, label, found):
    w, h = VIEWS['15x15']
    im = Image.new('RGB', (w, h), (6, 6, 14))
    d = ImageDraw.Draw(im)
    if row['band']:
        for yy in range(0, h, 4):
            for xx in range(0, w, 4):
                if band_distance(row, t, xx - w / 2, h / 2 - yy) < 40:
                    d.point((xx, yy), fill=(70, 60, 50))
    for n, (x, y, r) in screen_places(row, t, t0).items():
        cx, cy = w / 2 + x, h / 2 - y
        col = COLOURS.get(n, (180, 120, 220))
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=col, width=3)
        d.text((cx - 12, cy - 6), n, fill=col)
    d.text((6, 4), label, fill=(255, 255, 255))
    for i, s in enumerate(found[:6]):
        d.text((6, 18 + 12 * i), s, fill=(255, 110, 110))
    return im


def score(tag, minutes):
    with open(os.path.join(OUT, tag + '.json')) as f:
        rows = json.load(f)
    print('%s: %d rounds, sky turns %s deg/min' % (tag, len(rows), rows[0]['turn_per_minute']))
    for viewer in ('stayed', 'fresh'):
        max_drift = 0
        for row in rows:
            if 'planet' not in row['things']:
                continue
            first = turn(-sky_angle(row, 0), *screen_places(row, 0, 0)['planet'][:2])
            for t in minutes:
                t0 = 0 if viewer == 'stayed' else t
                current = turn(-sky_angle(row, t), *screen_places(row, t, t0)['planet'][:2])
                max_drift = max(max_drift, math.dist(first, current))
        print('Lavaland drift relative to the event layer, %s viewer: %.2f px max' % (viewer, max_drift))
    worst = []
    for viewer in ('stayed', 'fresh'):
        for view in VIEWS:
            print('\n%s viewer, %s view: share of rounds with each issue' % (viewer, view))
            for t in minutes:
                t0 = 0 if viewer == 'stayed' else t
                counts = {}
                bad = 0
                for i, row in enumerate(rows):
                    found = issues_at(row, t, t0, view)
                    bad += bool(found)
                    for k in {x.split()[0] for x in found}:
                        counts[k] = counts.get(k, 0) + 1
                    if view == '15x15' and found:
                        worst.append((len(found), t, viewer, i, found))
                parts = ', '.join('%s %d%%' % (k, 100 * v // len(rows)) for k, v in sorted(counts.items()))
                print('  %4d min: %3d%% with an issue  %s' % (t, 100 * bad // len(rows), parts))
    row = next((r for r in rows if 'sun' in r['things']), rows[0])
    print('\none round (%s), screen px from the middle (x right, y up):' % row['theme'].split('/')[-1])
    for t in minutes:
        for viewer, t0 in (('stayed', 0), ('fresh', t)):
            p = screen_places(row, t, t0)
            cells = '  '.join('%s %+4.0f,%+4.0f' % (n, p[n][0], p[n][1]) for n in ('sun', 'planet', 'world') if n in p)
            print('  %4d min %-6s %s' % (t, viewer, cells))
    worst.sort(key=lambda w: (-w[0], w[1]))
    picks = worst[:12]
    if picks:
        sheet = Image.new('RGB', (240 * 4, 240 * ((len(picks) + 3) // 4)))
        for k, (_, t, viewer, i, found) in enumerate(picks):
            t0 = 0 if viewer == 'stayed' else t
            tile = draw(rows[i], t, t0, '#%d %d min %s' % (i, t, viewer), found).resize((240, 240))
            sheet.paste(tile, ((k % 4) * 240, (k // 4) * 240))
        path = os.path.join(ROOT, 'data', 'previews', 'sky_drift_%s.png' % tag)
        sheet.save(path)
        print('\n' + path)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    mode, tag = sys.argv[1], sys.argv[2]
    if mode in ('probe', 'both'):
        probe(tag, int(sys.argv[3]) if len(sys.argv) > 3 else 40)
    if mode in ('score', 'both'):
        minutes = [int(m) for m in sys.argv[3:]] if mode == 'score' and len(sys.argv) > 3 else [0, 30, 60, 120, 240]
        score(tag, minutes)


if __name__ == '__main__':
    main()
