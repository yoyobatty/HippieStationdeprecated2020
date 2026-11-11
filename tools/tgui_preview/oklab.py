"""OKLab colour maths and the tgui palette: tg's tgui-core 6.1.1 hues, evened out in OKLab.

Every named colour sits at one OKLab lightness and chroma, so no colour shouts over another and white text passes
4.5:1 on every fill. Sass here is 1.23 (no oklch()), so the colours are worked out here and written as hex.

    python -I tools/tgui_preview/oklab.py      # rewrites the generated block in tgui-next styles/colors.scss
make_themes.py imports this for the department themes.
"""
import colorsys
import math
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
COLORS_SCSS = os.path.join(ROOT, 'tgui-next', 'packages', 'tgui', 'styles', 'colors.scss')


# ---------- OKLab (Ottosson) ----------
def _lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def hex_to_oklch(h):
    h = h.lstrip('#')
    r, g, b = (_lin(int(h[i:i + 2], 16)) for i in (0, 2, 4))
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(x) ** (1 / 3), x) for x in (l, m, s))
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(A, B), math.degrees(math.atan2(B, A)) % 360


def _oklch_lin(L, C, H):
    a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def _out(rgb):
    return any(v < -1e-4 or v > 1 + 1e-4 for v in rgb)


def oklch(L, C, H):
    """Hex for an OKLCH colour; out of sRGB, chroma is pulled in and lightness and hue are kept."""
    rgb = _oklch_lin(L, C, H)
    if _out(rgb):
        lo, hi = 0.0, C
        for _ in range(30):
            mid = (lo + hi) / 2
            if _out(_oklch_lin(L, mid, H)):
                hi = mid
            else:
                lo = mid
        rgb = _oklch_lin(L, lo, H)
    return '#' + ''.join('%02x' % round(max(0, min(1, _gam(max(0, min(1, v))))) * 255) for v in rgb)


def luminance(h):
    h = h.lstrip('#')
    r, g, b = (_lin(int(h[i:i + 2], 16)) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    x, y = sorted((luminance(a), luminance(b)), reverse=True)
    return (x + 0.05) / (y + 0.05)


def ink(bg):
    """The text colour (near-black or white) with more contrast on bg."""
    return '#111111' if contrast(bg, '#000000') > contrast(bg, '#ffffff') else '#ffffff'


def rgba(h, a):
    h = h.lstrip('#')
    return 'rgba(%d, %d, %d, %s)' % (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def hsl(h, s, l):
    r, g, b = colorsys.hls_to_rgb(h / 360, l / 100, s / 100)
    return '#%02x%02x%02x' % (round(r * 255), round(g * 255), round(b * 255))


# ---------- tg's palette (tgui-core 6.1.1 styles/colors.scss); only the hue is kept ----------
TG = {
    'red': hsl(0, 70, 50), 'orange': hsl(25, 90, 50), 'yellow': hsl(50, 97.5, 50), 'olive': hsl(70, 75, 45),
    'green': hsl(140, 70, 40), 'teal': hsl(180, 100, 35), 'blue': hsl(210, 65, 47.5), 'violet': hsl(260, 60, 50),
    'purple': hsl(290, 60, 50), 'pink': hsl(325, 70, 50), 'brown': hsl(25, 47.5, 45),
    'good': hsl(95, 62.5, 40), 'average': hsl(32.5, 90, 50), 'bad': hsl(0, 72.5, 50), 'primary': hsl(210, 37.5, 45),
}
HUE = {k: hex_to_oklch(v)[2] for k, v in TG.items()}

TEXT_L, TEXT_C = 0.72, 0.17  # text and icons on the dark base
FILL_L, FILL_C = 0.53, 0.14  # fills under white text
HOVER_DL = 0.07              # a hovered fill is this much lighter
LIGHT = {'yellow': (0.86, 0.80), 'olive': (0.80, 0.70)}  # (text L, fill L): a dark yellow reads as mud


def named():
    """name: (text, fill, hover)."""
    out = {}
    for k in ['red', 'orange', 'yellow', 'olive', 'green', 'teal', 'blue', 'violet', 'purple', 'pink', 'brown',
              'good', 'average', 'bad']:
        tl, fl = LIGHT.get(k, (TEXT_L, FILL_L))
        tc, fc = (0.09, 0.08) if k == 'brown' else (TEXT_C, FILL_C)
        out[k] = (oklch(tl, tc, HUE[k]), oklch(fl, fc, HUE[k]), oklch(fl + HOVER_DL, fc, HUE[k]))
    out['grey'] = (oklch(0.72, 0, 0), oklch(0.45, 0, 0), oklch(0.52, 0, 0))
    out['label'] = (oklch(0.72, 0.03, HUE['primary']), oklch(0.45, 0.03, HUE['primary']),
                    oklch(0.52, 0.03, HUE['primary']))
    out['white'] = ('#ffffff', '#ffffff', '#ffffff')
    out['black'] = ('#000000', '#000000', '#000000')
    return out


PRIMARY = oklch(0.50, 0.075, HUE['primary'])   # default buttons, tg's blue-grey
PRIMARY_HOVER = oklch(0.57, 0.08, HUE['primary'])
CAUTION = oklch(0.80, 0.15, HUE['yellow'])


def colors_block():
    n = named()
    lines = ['// oklab:begin -- written by tools/tgui_preview/oklab.py, do not edit by hand',
             '// Fills: one OKLab lightness and chroma for every hue (tg tgui-core 6.1.1 hues), so white text passes',
             '// 4.5:1 on all of them. bg() of a fill is the fill itself; fg() gives its text colour.']
    for k in ['red', 'orange', 'yellow', 'olive', 'green', 'teal', 'blue', 'violet', 'purple', 'pink', 'brown', 'grey']:
        lines.append(f'${k}: {n[k][1]} !default;')
    lines.append('$black: #000000 !default;')
    lines.append('$white: #ffffff !default;')
    lines.append('')
    lines.append(f'$primary: {PRIMARY} !default;')
    lines.append(f"$primary-line: {oklch(0.66, 0.09, HUE['primary'])} !default;")
    for k in ['good', 'average', 'bad']:
        lines.append(f'${k}: {n[k][1]} !default;')
    lines.append(f"$label: {n['label'][0]} !default;")
    lines.append(f"$label-fill: {n['label'][1]} !default;")
    lines.append('')
    lines.append('// Text colour of each fill (fg), and the fill a hovered button takes.')
    lines.append('$text-of: (')
    seen = set()
    for k, (t, f, _) in n.items():
        if k not in ('white', 'black') and f not in seen:  # bad and red share a fill
            seen.add(f)
            lines.append(f'  {f}: {t},')
    lines.append(');')
    lines.append('$hover-of: (')
    seen = set()
    for k, (_, f, hv) in list(n.items()) + [('primary', (None, PRIMARY, PRIMARY_HOVER))]:
        if k not in ('white', 'black') and f not in seen:
            seen.add(f)
            lines.append(f'  {f}: {hv},')
    lines.append(');')
    lines.append(f'$caution: {CAUTION} !default;')
    lines.append('// NoticeBox: tg\'s tan stripes, darkened to take white text, with an amber edge.')
    lines.append(f"$notice: {oklch(0.42, 0.05, HUE['average'])} !default;")
    lines.append(f"$notice-alt: {oklch(0.38, 0.05, HUE['average'])} !default;")
    lines.append(f"$notice-edge: {n['average'][0]} !default;")
    lines.append('// oklab:end')
    return '\n'.join(lines)


# ---------- department themes: Deep glass body + Signage title bar, headers and card edges (user ruling) ----------
GOLD_H = hex_to_oklch('#e3bd4f')[2]
DEPT_HUE = {
    'medical': hex_to_oklch('#3498db')[2],      # tg medbay (tgui constants COLORS.department)
    'security': hex_to_oklch('#e74c3c')[2],     # tg security
    'science': hex_to_oklch('#9b59b6')[2],      # tg science
    'engineering': hex_to_oklch('#f1c40f')[2],  # tg engineering
    'cargo': hex_to_oklch('#f39c12')[2],        # tg cargo
    'atmos': HUE['teal'],
    'service': HUE['green'],
    'silicon': hex_to_oklch('#35d0a0')[2],      # Hippie's circuit mint
    'command': hex_to_oklch('#2c3e7a')[2],      # navy, with gold signage
}


def yellowish(h):
    return 70 < h < 115


def dark_hue(h):
    """Dark shades of yellow read as olive; lean them toward amber."""
    return h - 10 if 75 < h < 115 else h


def dept_tokens(name):
    H = DEPT_HUE[name]
    Hd = dark_hue(H)
    sh = GOLD_H if name == 'command' else H   # sign hue
    yel = yellowish(sh)
    sign = oklch(0.84, 0.15, sh) if yel else oklch(0.72, 0.13, sh)
    accent = oklch(0.84 if yel else 0.74, 0.14, sh)
    glow = oklch(0.44, 0.12, Hd)
    data = oklch(0.58, 0.13, dark_hue(sh) - (8 if yel else 0))
    t = {
        'sign': sign, 'sign_ink': '#111111', 'sign_hover': oklch(0.88 if yel else 0.80, 0.13, sh),
        'accent': accent,
        'bg': oklch(0.17, 0.035, Hd), 'bg_top': oklch(0.19, 0.035, Hd), 'bg_end': oklch(0.13, 0.03, Hd),
        'glow': glow, 'glow_clear': rgba(glow, 0),
        'title_text': oklch(0.95, 0.03, H),
        'label': oklch(0.74, 0.045, H),
        'btn': rgba(oklch(0.55, 0.11, Hd), 0.32), 'btn_solid': oklch(0.32, 0.07, Hd),
        'btn_hover': rgba(oklch(0.60, 0.12, Hd), 0.5), 'btn_edge': rgba(accent, 0.35),
        'input': oklch(0.52, 0.07, H), 'input_bg': rgba(oklch(0.08, 0.03, Hd), 0.6),
        'notice': oklch(0.30, 0.06, Hd),
        'track': rgba(oklch(0.08, 0.03, Hd), 0.6),
        'data': data, 'data_glow': rgba(data, 0.6),
        'card_edge': rgba(accent, 0.18), 'card_rule': rgba(accent, 0.25),
        'sign_glow': rgba(sign, 0.4), 'sign_text_glow': rgba(sign, 0.45), 'sel_glow': rgba(sign, 0.5),
        'tooltip': oklch(0.22, 0.05, Hd), 'scroll': rgba(accent, 0.3),
        'emblem': accent,
    }
    return t


def write_colors_scss(path=COLORS_SCSS):
    src = open(path, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in src else '\n'
    block = colors_block().replace('\n', nl)
    new, count = re.subn(r'// oklab:begin.*?// oklab:end', lambda m: block, src, flags=re.S)
    if count != 1:
        raise SystemExit('colors.scss has no oklab:begin/oklab:end block')
    open(path, 'w', encoding='utf-8', newline='').write(new)
    print('wrote', path)


if __name__ == '__main__':
    write_colors_scss()
