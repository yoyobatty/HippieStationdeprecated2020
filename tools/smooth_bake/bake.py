"""Bakes bitmask smoothing states ("<prefix>-<junction>") from the old corner states (1-i .. 4-f) of a .dmi.

The old smoothing drew four corner overlays over the atom; the new one picks a single icon_state by junction
(tg's bits: N 1, S 2, E 4, W 8, NE 16, SE 32, SW 64, NW 128; a diagonal bit only with both its cardinals, so 47 shapes).
Each baked state is the four corners composited in the order the old code added them (1, 2, 3, 4), over an optional
base state for turfs whose own icon showed through. Diagonal walls also get "<prefix>-<junction>-diagonal" for the
8 diagonal shapes, from the old "d-" states. Animated corners are merged into one timeline.

The corner states stay in the file as the source: edit them and re-run this to rebake.

    python tools/smooth_bake/bake.py            bake every sheet in sheets.txt
    python tools/smooth_bake/bake.py --check    only compare; exit 1 if any baked state is missing or differs
    python tools/smooth_bake/bake.py <dmi> ...  just these sheets (as written in sheets.txt)
"""
import math
import os
import sys
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'mapmerge2'))
import dmi  # noqa: E402
from PIL import Image  # noqa: E402

N, S, E, W, NE, SE, SW, NW = 1, 2, 4, 8, 16, 32, 64, 128

DIAGONAL = {  # junction -> the two old "d-" states, drawn in this order
    N | W: ('d-se', 'd-se-0'), N | E: ('d-sw', 'd-sw-0'), S | W: ('d-ne', 'd-ne-0'), S | E: ('d-nw', 'd-nw-0'),
    N | W | NW: ('d-se', 'd-se-1'), N | E | NE: ('d-sw', 'd-sw-1'), S | W | SW: ('d-ne', 'd-ne-1'), S | E | SE: ('d-nw', 'd-nw-1'),
}


def junctions():
    out = []
    for j in range(256):
        if j & NE and not (j & N and j & E):
            continue
        if j & SE and not (j & S and j & E):
            continue
        if j & SW and not (j & S and j & W):
            continue
        if j & NW and not (j & N and j & W):
            continue
        out.append(j)
    return out


def corner_states(j):
    def pick(prefix, a, b, diag, a_name, b_name, both_name):
        if j & a and j & b:
            return f'{prefix}-f' if j & diag else f'{prefix}-{both_name}'
        if j & a:
            return f'{prefix}-{a_name}'
        if j & b:
            return f'{prefix}-{b_name}'
        return f'{prefix}-i'
    return [pick('1', N, W, NW, 'n', 'w', 'nw'), pick('2', N, E, NE, 'n', 'e', 'ne'),
            pick('3', S, W, SW, 's', 'w', 'sw'), pick('4', S, E, SE, 's', 'e', 'se')]


def load_rgba(path):
    """mapmerge2's Dmi with every frame cut from an RGBA copy of the sheet (it cuts palette sheets in palette mode)"""
    sheet = dmi.Dmi.from_file(path)
    full = Image.open(path).convert('RGBA')
    grid = full.width // sheet.width
    i = 0
    for st in sheet.states:
        for k in range(len(st.frames)):
            x = sheet.width * (i % grid)
            y = sheet.height * (i // grid)
            st.frames[k] = full.crop((x, y, x + sheet.width, y + sheet.height))
            i += 1
    return sheet


def layer(state):
    """(images, delays) of a state's first direction, delays as Fractions (BYOND counts a missing delay as 1)"""
    frames = state.framecount
    images = [state.frames[f * state.dirs] for f in range(frames)]
    delays = [Fraction(str(state.delays[f])) if f < len(state.delays) else Fraction(1) for f in range(frames)]
    if frames == 1:
        delays = [Fraction(1)]
    if state.rewind and frames > 2:
        images = images + images[-2:0:-1]
        delays = delays + delays[-2:0:-1]
    return images, delays, state.loop


def compose(sheet, names):
    """The states drawn bottom to top, as one animation: (images, delays, loop)"""
    layers = [layer(sheet.get_state(n)) for n in names]
    loops = {lp for imgs, dl, lp in layers if len(imgs) > 1}
    if len(loops) > 1:
        raise ValueError(f'{names}: animated layers loop differently ({loops})')
    loop = loops.pop() if loops else 0
    animated = [(imgs, dl) for imgs, dl, lp in layers if len(imgs) > 1]
    if not animated:
        out = layers[0][0][0].copy()
        for imgs, dl, lp in layers[1:]:
            out = Image.alpha_composite(out, imgs[0])
        return [out], [], loop
    period = sum(animated[0][1])
    for imgs, dl in animated[1:]:
        period = _lcm(period, sum(dl))
    if loop and any(sum(dl) != period for imgs, dl in animated):
        raise ValueError(f'{names}: finite loops of different lengths')
    cuts = {Fraction(0)}
    for imgs, dl in animated:
        t = Fraction(0)
        while t < period:
            for d in dl:
                cuts.add(t)
                t += d
    cuts = sorted(c for c in cuts if c < period)
    images, delays = [], []
    for i, c in enumerate(cuts):
        end = cuts[i + 1] if i + 1 < len(cuts) else period
        out = None
        for imgs, dl, lp in layers:
            idx = 0
            if len(imgs) > 1:
                t = c % sum(dl)
                acc = Fraction(0)
                for k, d in enumerate(dl):
                    if t < acc + d:
                        idx = k
                        break
                    acc += d
            out = imgs[idx].copy() if out is None else Image.alpha_composite(out, imgs[idx])
        images.append(out)
        delays.append(end - c)
    return images, [_num(d) for d in delays], loop


def _lcm(a, b):
    # least common multiple of two positive Fractions
    num = a.numerator * b.denominator
    den = b.numerator * a.denominator
    g = math.gcd(num, den)
    return a * (den // g)


def _num(f):
    return int(f) if f.denominator == 1 else float(f)


def parse_sheets(path):
    sheets = []
    for line in open(path, encoding='utf-8'):
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        entry = {'dmi': parts[0], 'prefix': parts[1], 'base': None, 'diagonal': False}
        for p in parts[2:]:
            if p.startswith('base='):
                entry['base'] = p[5:]
            elif p == 'diagonal':
                entry['diagonal'] = True
            else:
                raise ValueError(f'{path}: unknown option {p}')
        sheets.append(entry)
    return sheets


def wanted_states(sheet, entry):
    """{state name: (images, delays, loop)} this entry should have"""
    out = {}
    base = [entry['base']] if entry['base'] else []
    for j in junctions():
        out[f"{entry['prefix']}-{j}"] = compose(sheet, base + corner_states(j))
    if entry['diagonal']:
        for j, pair in DIAGONAL.items():
            out[f"{entry['prefix']}-{j}-diagonal"] = compose(sheet, list(pair))
    return out


def same(state, images, delays, loop):
    if state.dirs != 1 or state.framecount != len(images) or state.loop != loop:
        return False
    if len(images) > 1 and [_num(Fraction(str(d))) for d in state.delays[:len(images)]] != delays:
        return False
    return all(a.tobytes() == b.tobytes() for a, b in zip(state.frames, images))


def main(argv):
    check = '--check' in argv
    only = [a for a in argv if not a.startswith('--')]
    entries = parse_sheets(os.path.join(HERE, 'sheets.txt'))
    if only:
        entries = [e for e in entries if e['dmi'] in only]
    by_file = {}
    for e in entries:
        by_file.setdefault(e['dmi'], []).append(e)
    problems = 0
    for path, file_entries in by_file.items():
        full = os.path.join(ROOT, path)
        sheet = load_rgba(full)
        existing = {s.name: s for s in sheet.states}
        want = {}
        for e in file_entries:
            for name, value in wanted_states(sheet, e).items():
                want[name] = value
        prefixes = {e['prefix'] for e in file_entries}
        # a state named like ours that we wouldn't make (a decon stage "r_wall-1" under prefix "r_wall") would be clobbered
        for name in existing:
            for p in prefixes:
                rest = name[len(p) + 1:] if name.startswith(p + '-') else None
                if rest is not None and name not in want and rest.split('-')[0].isdigit():
                    raise ValueError(f'{path}: existing state {name} clashes with prefix {p}')
        changed = [n for n, (imgs, dl, lp) in want.items() if n not in existing or not same(existing[n], imgs, dl, lp)]
        if check:
            if changed:
                problems += len(changed)
                print(f'{path}: {len(changed)} baked states missing or stale, e.g. {changed[:3]}')
            continue
        if not changed:
            print(f'{path}: up to date ({len(want)} states)')
            continue
        kept = [s for s in sheet.states if s.name not in want]
        sheet.states = kept
        for name, (imgs, dl, lp) in want.items():
            st = sheet.state(name, loop=lp)
            for k, im in enumerate(imgs):
                st.frame(im, delay=dl[k] if dl else 1)
            if not dl:
                st.delays = []
        sheet.to_file(full)
        print(f'{path}: baked {len(changed)} of {len(want)} states')
    if check:
        print('bake check:', 'OK' if not problems else f'{problems} problems')
        return 1 if problems else 0
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
