"""Glow masks: the lit parts of sprites whose lights are painted into the sprite, cut out at build time.

The game draws a "<state>_glow" state on the emissive planes (lit through the dark, then bloomed in its own colours).
tg draws most screens and indicator lights into the machine's own sprite, so those masks are made here from glow.txt:

  <sheet>: <lit> [<lit> ...] - <off>      each lit state gets <lit>_glow: its pixels that are brighter than in <off>,
                                          the same machine unpowered (vending "snack" against "snack-off")
  <sheet>: <lit> [<lit> ...] bright[=N]   no off state to compare with: the pixels at least N bright (0-255, default 200)
  <sheet>: * - *-off                      a pattern: every state that has an off twin by it (vending "snack", "snack-off")

"colour" at the end of a line keeps only coloured or near-white pixels: for off states that dim the whole sprite
(intercom-p), where the grey casing comes out brighter too. "changed" also keeps coloured pixels that clearly differ from
the off state, brighter or not: for off states that blank the screen with a flat bright panel (some vending machines).

A "<lit>_glow" state already in the merged sheet (drawn by hand in the Hippie twin) wins over the made one, which is how a
bad mask gets fixed. Masks keep the lit sprite's own colours, so the bloom comes out coloured.

  python tools/icon_merge/icon_merge.py glow-review     sheets of every mask in data/previews/glow/
"""
import os
import re

from PIL import Image

import dmi

HERE = os.path.dirname(os.path.abspath(__file__))
GLOW_FILE = os.path.join(HERE, 'glow.txt')
SUFFIX = '_glow'
SOLID = 32          # alpha below this counts as empty
BRIGHTER = 20       # luma a lit pixel must gain over the off one
RECOLOURED = 60     # or this much change in some channel, if it's not dark
RECOLOURED_LUMA = 80
COLOURED = 48       # "colour": channel spread a kept pixel needs, unless it's near white
NEAR_WHITE = 200


def read_rules():
    """{sheet: [(rule line, [lit states], off state or None, brightness cut, {flags})]} from glow.txt."""
    rules = {}
    if not os.path.exists(GLOW_FILE):
        return rules
    for raw in open(GLOW_FILE, encoding='utf-8'):
        line = raw.split('#', 1)[0].strip()
        if not line:
            continue
        sheet, rest = [x.strip() for x in line.split(':', 1)]
        words = rest.split()
        flags = set()
        while words and words[-1] in ('colour', 'changed'):
            flags.add(words.pop())
        off, cut = None, None
        if '-' in words:
            at = len(words) - 1 - words[::-1].index('-')
            lit, off_words = words[:at], words[at + 1:]
            if len(off_words) != 1:
                raise SystemExit(f'glow.txt: one off state after "-" in: {line}')
            off = off_words[0]
        elif words and words[-1].startswith('bright'):
            lit = words[:-1]
            cut = int(words[-1].split('=', 1)[1]) if '=' in words[-1] else 200
        else:
            raise SystemExit(f'glow.txt: no "- <off state>" or "bright" in: {line}')
        if not lit:
            raise SystemExit(f'glow.txt: no lit states in: {line}')
        rules.setdefault(sheet, []).append((' '.join(line.split()), lit, off, cut, flags))
    return rules


def coloured(p):
    return max(p[0], p[1], p[2]) - min(p[0], p[1], p[2]) >= COLOURED or min(p[0], p[1], p[2]) >= NEAR_WHITE


def luma(p):
    return (p[0] * 299 + p[1] * 587 + p[2] * 114) // 1000


def lit_pixel(lit, off, changed=False):
    if lit[3] < SOLID:
        return False
    if off is None or off[3] < SOLID:
        return True
    if changed and coloured(lit) and max(abs(lit[0] - off[0]), abs(lit[1] - off[1]), abs(lit[2] - off[2])) >= RECOLOURED:
        return True
    gain = luma(lit) - luma(off)
    if gain >= BRIGHTER:
        return True
    shift = max(abs(lit[0] - off[0]), abs(lit[1] - off[1]), abs(lit[2] - off[2]))
    return shift >= RECOLOURED and luma(lit) >= RECOLOURED_LUMA and gain > -BRIGHTER


def mask_frame(lit_im, off_im, cut, flags=frozenset()):
    out = Image.new('RGBA', lit_im.size, (0, 0, 0, 0))
    lp = lit_im.load()
    op = off_im.load() if off_im is not None else None
    dst = out.load()
    w, h = lit_im.size
    kept = 0
    for y in range(h):
        for x in range(w):
            p = lp[x, y]
            if cut is not None:
                keep = p[3] >= SOLID and max(p[0], p[1], p[2]) >= cut
            else:
                keep = lit_pixel(p, op[x, y], 'changed' in flags)
            if keep and 'colour' in flags:
                keep = coloured(p)
            if keep:
                dst[x, y] = p
                kept += 1
    return out, kept


def off_frame(off, lit_index, lit_dirs):
    """The off state's frame for the same direction (its first frame: off states don't animate)."""
    dir_ofs = lit_index % lit_dirs
    return off.frames[dir_ofs if dir_ofs < off.dirs else 0]


def make_mask(lit, off, cut, flags, sheet):
    state = dmi.State(sheet, lit.name + SUFFIX, loop=lit.loop, rewind=lit.rewind, movement=lit.movement, dirs=lit.dirs)
    state.delays = list(lit.delays)
    state.hotspots = list(lit.hotspots) if lit.hotspots else None
    kept = 0
    for i, frame in enumerate(lit.frames):
        im, n = mask_frame(frame, off_frame(off, i, lit.dirs) if off is not None else None, cut, flags)
        state.frames.append(im)
        kept += n
    return state, kept


def expand(rule, names):
    """[(lit state, off state or None)] for a rule. A "*" pattern ("* - *-off") pairs every state with its off twin;
    "sword* - sword0" pairs every match with the one off state."""
    _, lits, off_name, _, _ = rule
    if len(lits) == 1 and '*' in lits[0] and off_name:
        pattern = re.compile('^' + re.escape(lits[0]).replace(r'\*', '(.+)') + '$')
        found = []
        for name in names:
            match = pattern.match(name)
            if match and not name.endswith(SUFFIX):
                off = off_name.replace('*', match.group(1))
                if off in names and off != name:
                    found.append((name, off))
        return found
    return [(name, off_name) for name in lits]


def colour(state):
    """[colour, size] of the light a mask would cast: the average of its lit pixels, weighted by alpha, brightened so its
    strongest channel is full, and how many pixels a frame lights on average (the game scales the light by it). None if the
    mask is empty."""
    total = [0, 0, 0]
    weight = 0
    for frame in state.frames:
        for r, g, b, a in frame.getdata():
            if a:
                total[0] += r * a
                total[1] += g * a
                total[2] += b * a
                weight += a
    if not weight:
        return None
    avg = [t / weight for t in total]
    top = max(avg)
    if top <= 0:
        return None
    hex_colour = '#%02X%02X%02X' % tuple(min(255, round(c * 255 / top)) for c in avg)
    return [hex_colour, round(weight / 255 / len(state.frames))]


DM_COLOURS = 'hippiestation/code/modules/lighting/emissive_glow_colours.dm'


def render_colours(manifest):
    """The DM list of every mask's colour, from the merge manifest (so check can compare it without loading sheets)."""
    lines = ["// Made by tools/icon_merge/icon_merge.py build from the glow masks; don't edit by hand.",
             "// The faint light each mask casts (\"<icon>|<mask state>\" = list(colour, lit pixels per frame)): its pixels'",
             "// average colour at full strength, and how much of the sprite glows, which sets how strong (see emissive_glow.dm).",
             'GLOBAL_LIST_INIT(emissive_glow_lights, list(']
    entries = []
    for tg in sorted(manifest):
        for state, (hex_colour, pixels) in sorted(manifest[tg].get('glow_colours', {}).items()):
            entries.append(f'\t"{tg}|{state}" = list("{hex_colour}", {pixels}),')
    if entries:
        entries[-1] = entries[-1].rstrip(',')
    return '\n'.join(lines + entries + ['))', ''])


def apply(sheet, rules):
    """Adds the masks for one merged sheet. Returns a report: made, hand (kept a hand-drawn one), colours, problems."""
    report = {'made': [], 'hand': [], 'colours': {}, 'problems': []}
    by_name = {}
    for state in sheet.states:
        if not state.movement:
            by_name.setdefault(state.name, state)
    for rule in rules:
        line, _, _, cut, flags = rule
        pairs = expand(rule, list(by_name))
        if not pairs:
            report['problems'].append(f'{line}: matches no states')
        for name, off_name in pairs:
            off = None
            if off_name is not None:
                off = by_name.get(off_name)
                if off is None:
                    report['problems'].append(f'{line}: no off state "{off_name}"')
                    continue
            lit = by_name.get(name)
            if lit is None:
                report['problems'].append(f'{line}: no state "{name}"')
                continue
            if name + SUFFIX in by_name:
                report['hand'].append(name + SUFFIX)
                hex_colour = colour(by_name[name + SUFFIX])
                if hex_colour:
                    report['colours'][name + SUFFIX] = hex_colour
                continue
            mask, kept = make_mask(lit, off, cut, flags, sheet)
            if not kept:
                if len(pairs) == 1 or '*' not in line: # a pattern meets plenty of states with no light (clothing vendors)
                    report['problems'].append(f'{line}: "{name}" has nothing brighter than "{off_name}"')
                continue
            sheet.states.append(mask)
            by_name[mask.name] = mask
            report['made'].append(mask.name)
            hex_colour = colour(mask)
            if hex_colour:
                report['colours'][mask.name] = hex_colour
    return report


def review(root=None, only=None):
    """data/previews/glow/<sheet>.png: per mask, the lit sprite, the off one, the mask, and the mask over a dark room.
    Each shows the frame where the mask lights the most, so a flashing light doesn't come out blank."""
    import icon_merge as m
    from PIL import ImageFilter
    out_dir = m.rel('data', 'previews', 'glow')
    os.makedirs(out_dir, exist_ok=True)
    scale = 3
    for path, rules in sorted(read_rules().items()):
        if only and only not in path:
            continue
        sheet = m.load(os.path.join(root, path) if root else m.rel(path))
        by_name = {s.name: s for s in sheet.states if not s.movement}
        rows = []
        for rule in rules:
            for name, off_name in expand(rule, list(by_name)):
                if name in by_name and name + SUFFIX in by_name:
                    rows.append((by_name[name], by_name.get(off_name) if off_name else None, by_name[name + SUFFIX]))
        if not rows:
            continue
        w, h = sheet.width * scale, sheet.height * scale
        per_row = max(1, min(3, 1200 // (4 * (w + 6) + 18)))
        cell_w = 4 * (w + 6) + 18
        lines = (len(rows) + per_row - 1) // per_row
        page = Image.new('RGBA', (per_row * cell_w + 8, lines * (h + 8) + 8), (40, 40, 48, 255))
        for r, (lit, off, mask) in enumerate(rows):
            best = max(range(len(mask.frames)), key=lambda i: sum(1 for px in mask.frames[i].getdata() if px[3]))
            lit_im = lit.frames[best]
            mask_im = mask.frames[best]
            off_im = off.frames[best % off.dirs if best % lit.dirs < off.dirs else 0] if off else Image.new('RGBA', lit_im.size)
            x0 = 8 + (r % per_row) * cell_w
            y = 8 + (r // per_row) * (h + 8)
            dark = Image.new('RGBA', lit_im.size, (0, 0, 0, 255))
            dark.alpha_composite(lit_im)
            dark = Image.blend(Image.new('RGBA', dark.size, (0, 0, 0, 255)), dark, 0.18)
            dark.alpha_composite(mask_im.filter(ImageFilter.GaussianBlur(1.2)))
            dark.alpha_composite(mask_im)
            for c, tile in enumerate([lit_im, off_im, mask_im, dark]):
                bg = Image.new('RGBA', lit_im.size, (24, 24, 28, 255) if c < 3 else (0, 0, 0, 255))
                bg.alpha_composite(tile)
                page.alpha_composite(bg.resize((w, h), Image.NEAREST), (x0 + c * (w + 6), y))
        name = path.replace('/', '_').replace('.dmi', '')
        page.save(os.path.join(out_dir, f'{name}.png'))
        print(f'{path}: {len(rows)} masks -> data/previews/glow/{name}.png')
