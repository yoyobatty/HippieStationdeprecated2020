"""Snap the colours hard-coded in tgui-next windows onto the OKLab palette (oklab.py).

    python -I tools/tgui_preview/oklab_snap.py            # dry run: what would change, per file
    python -I tools/tgui_preview/oklab_snap.py --write    # rewrite the files
    python -I tools/tgui_preview/oklab_snap.py --write Pda.scss Exosuit.js   # only these files

Rules, per hex colour:
- Greys (OKLCH chroma under 0.035) stay as they are.
- The hue moves to the nearest tg hue, if one is within 30 degrees (a colour further from all of them is a deliberate
  off-palette colour and keeps its hue).
- Lightness says what the colour is doing on a dark window. Bright (L >= 0.62) is text, icons or lines; middle
  (0.42-0.62) is a fill. Either moves toward the palette's lightness for that role and hue, by 0.06 at most, so a
  window's design keeps its light and dark. Dark (< 0.42) is a tint or a panel and keeps its lightness.
- Chroma is kept: a vibrant colour stays vibrant, a dusty one stays dusty (the user's ruling: lean into vibrant).
Game colours are left alone: the files in SKIP hold colour pickers, pipe paints, paper and ink, card suits. The mech
paints (Exosuit.js) belong to the mecha theme and are tuned with the special themes.
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oklab  # noqa: E402

TGUI = os.path.join(oklab.ROOT, 'tgui-next', 'packages', 'tgui')
SKIP = {
    'Preferences.js',        # the colour picker's presets: players pick these for hair, eyes and the like
    'RapidPipeDispenser.js',  # pipe paints, the same colours as the pipes in the game
    'Paper.js', 'Photocopier.js', 'PaperList.js',  # paper and ink
    'ItemsReading.js',        # playing-card suits
    'ReagentBits.js',         # fallback for a reagent's own colour
    'Exosuit.js',             # mech paints: part of the mecha theme
}
NUDGE = 0.06  # most a colour's OKLab lightness moves
HUES = ['red', 'orange', 'average', 'yellow', 'olive', 'good', 'green', 'teal', 'blue', 'violet', 'purple', 'pink']
HEX = re.compile(r'#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b')


def hue_gap(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def snap(hex_colour):
    h = hex_colour.lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    L, C, H = oklab.hex_to_oklch('#' + h)
    if C < 0.035:
        return None
    name = min(HUES, key=lambda k: hue_gap(H, oklab.HUE[k]))
    if hue_gap(H, oklab.HUE[name]) <= 30:
        H2 = oklab.HUE[name]
    else:
        name, H2 = None, H
    text_l, fill_l = oklab.LIGHT.get(name, (oklab.TEXT_L, oklab.FILL_L))
    if L >= 0.62:
        L2 = L + max(-NUDGE, min(NUDGE, text_l - L))
    elif L >= 0.42:
        L2 = L + max(-NUDGE, min(NUDGE, fill_l - L))
    else:
        L2 = L
    out = oklab.oklch(L2, C, H2)
    return None if out.lower() == '#' + h.lower() else out


def targets(only):
    files = glob.glob(os.path.join(TGUI, 'styles', 'components', '*.scss'))
    files += glob.glob(os.path.join(TGUI, 'interfaces', '**', '*.js'), recursive=True)
    out = []
    for f in sorted(files):
        base = os.path.basename(f)
        if base in SKIP or (only and base not in only):
            continue
        out.append(f)
    return out


def main():
    args = sys.argv[1:]
    write = '--write' in args
    only = {a for a in args if not a.startswith('--')}
    total = 0
    for f in targets(only):
        src = open(f, encoding='utf-8', newline='').read()
        changes = []

        def sub(m):
            new = snap(m.group(0))
            if new:
                changes.append((m.group(0), new))
                return new
            return m.group(0)
        out = HEX.sub(sub, src)
        if changes:
            total += len(changes)
            uniq = sorted(set(changes))
            print(f'{len(changes):4d}  {os.path.relpath(f, TGUI)}  ' + ' '.join(f'{a}>{b}' for a, b in uniq[:6])
                  + (' ...' if len(uniq) > 6 else ''))
            if write:
                open(f, 'w', encoding='utf-8', newline='').write(out)
    print(f'{total} colours {"rewritten" if write else "would change"}')


if __name__ == '__main__':
    main()
