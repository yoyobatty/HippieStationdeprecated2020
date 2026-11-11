"""The chat (tgui6) and the stat panel on the OKLab palette.

    python -I tools/tgui_preview/oklab_chat.py

1. Chat messages keep tg's colours (tgui6/.../styles/tgchat/chat-dark.scss, tg's own file, re-fetched by
   tools/tgui6_sync), but any coloured text darker than OKLab lightness 0.66 is lifted to it, hue and chroma kept, so
   dark reds and blues read on the dark chat. The overrides go to tgui6/packages/tgui-panel/hippie/chat-oklab.scss,
   dark theme only. Run this again after fetching tg's chat again.
2. The chat's own controls (tgui-core 6 CSS variables) and the stat panel's dark colours (html/statbrowser.css) take
   the tgui-next base, primary and named colours from oklab.py.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oklab  # noqa: E402
from oklab import HUE, PRIMARY, hex_to_oklch, hsl, named, oklch  # noqa: E402

ROOT = oklab.ROOT
CHAT_DARK = os.path.join(ROOT, 'tgui6', 'packages', 'tgui-panel', 'styles', 'tgchat', 'chat-dark.scss')
OUT = os.path.join(ROOT, 'tgui6', 'packages', 'tgui-panel', 'hippie', 'chat-oklab.scss')
STAT_CSS = os.path.join(ROOT, 'html', 'statbrowser.css')
MIN_L = 0.66
HSL = re.compile(r'hsl\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*\)')
H = HUE['primary']


def rules(src):
    """(selector, declarations) for each top-level rule (nested blocks are skipped)."""
    out = []
    depth = 0
    sel_start = 0
    body = []
    selector = None
    i = 0
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    while i < len(src):
        c = src[i]
        if c == '{':
            if depth == 0:
                selector = src[sel_start:i].strip()
                body = []
                body_start = i + 1
            elif depth == 1:
                body.append(src[body_start:i].rsplit(';', 1)[0])
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                if not body:
                    body.append(src[body_start:i])
                else:
                    body.append(src[src.rfind('}', 0, i) + 1:i])
                out.append((selector, ';'.join(body)))
                sel_start = i + 1
            elif depth == 1:
                body_start = i + 1
        elif c == ';' and depth == 0:
            sel_start = i + 1
        i += 1
    return out


def chat_overrides():
    src = open(CHAT_DARK, encoding='utf-8').read()
    lines = ['// hippie -- written by tools/tgui_preview/oklab_chat.py, do not edit by hand. tg\'s chat colours (chat-dark.scss)',
             f'// with every coloured text darker than OKLab lightness {MIN_L} lifted to it, hue and chroma kept, so it reads on',
             '// the dark chat. Dark theme only.', '']
    n = 0
    for selector, decl in rules(src):
        if not selector or selector.startswith('@') or '&' in selector:
            continue
        m = re.search(r'(?<![-\w])color:\s*(hsl\([^)]*\))\s*(!important)?', decl)
        if not m:
            continue
        hm = HSL.match(m.group(1))
        if not hm:
            continue
        hexc = hsl(float(hm.group(1)), float(hm.group(2)), float(hm.group(3)))
        L, C, Hh = hex_to_oklch(hexc)
        if C < 0.035 or L >= MIN_L:
            continue
        new = oklch(MIN_L, C, Hh)
        sels = ',\n'.join('html:not(.theme-light) ' + s.strip() for s in selector.split(','))
        lines.append(f'{sels} {{\n  color: {new}{" !important" if m.group(2) else ""}; // was {m.group(1)}\n}}\n')
        n += 1
    open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
    print(f'{n} chat colours lifted -> {OUT}')


PANEL_VARS = '''// hippie -- the chat's controls on the tgui-next palette (tools/tgui_preview/oklab.py, written by oklab_chat.py)
:root:not(.theme-light) {{
  --color-base: {base};
  --color-primary: {primary};
  --color-label: {label};
  --color-good: {good};
  --color-average: {average};
  --color-bad: {bad};
  --color-red: {red};
  --color-orange: {orange};
  --color-yellow: {yellow};
  --color-olive: {olive};
  --color-green: {green};
  --color-teal: {teal};
  --color-blue: {blue};
  --color-violet: {violet};
  --color-purple: {purple};
  --color-pink: {pink};
  --color-brown: {brown};
}}
'''


def panel_vars():
    n = named()
    v = {k: n[k][1] for k in ['good', 'average', 'bad', 'red', 'orange', 'yellow', 'olive', 'green', 'teal', 'blue',
                               'violet', 'purple', 'pink', 'brown']}
    v.update(base=oklch(0.215, 0.008, H), primary=PRIMARY, label=n['label'][0])
    return PANEL_VARS.format(**v)


STAT_DARK = {
    'bg': oklch(0.20, 0.008, H), 'bar': oklch(0.235, 0.01, H), 'border': oklch(0.31, 0.014, H),
    'text': oklch(0.80, 0.035, H), 'strong': oklch(0.93, 0.015, H), 'muted': oklch(0.62, 0.03, H),
    'hover': oklch(0.28, 0.014, H), 'press': oklch(0.32, 0.016, H), 'accent': oklch(0.62, 0.10, H),
    'link': oklch(0.76, 0.10, H), 'input': oklch(0.16, 0.006, H),
    'scrollbar-base': oklch(0.20, 0.008, H), 'scrollbar-thumb': oklch(0.36, 0.016, H),
}


def stat_panel():
    raw = open(STAT_CSS, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in raw else '\n'
    s = raw.replace('\r\n', '\n')
    m = re.search(r'(\.dark:root\s*\{)(.*?)(\})', s, re.S)
    if not m:
        raise SystemExit('statbrowser.css: no .dark:root block')
    block = m.group(2)
    for k, val in STAT_DARK.items():
        block, c = re.subn(r'(--' + re.escape(k) + r':\s*)#[0-9a-fA-F]{3,6}', lambda mm: mm.group(1) + val, block)
        if c != 1:
            raise SystemExit('statbrowser.css: --' + k + ' not found once')
    s = s[:m.start(2)] + block + s[m.end(2):]
    s = re.sub(r'(\.tab-badge\.hot \{\s*background: )#[0-9a-fA-F]{6}', lambda mm: mm.group(1) + named()['bad'][1], s)
    open(STAT_CSS, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
    print('stat panel dark colours ->', STAT_CSS)


if __name__ == '__main__':
    chat_overrides()
    open(os.path.join(os.path.dirname(OUT), 'panel-oklab.scss'), 'w', encoding='utf-8', newline='\n').write(panel_vars())
    print('panel variables -> hippie/panel-oklab.scss')
    stat_panel()
