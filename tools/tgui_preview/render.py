"""Renders each window tgui_dump.dm wrote (data/tgui_preview/*.json) through the built tgui-next bundle in headless Edge.

One picture per window in data/previews/tgui/<interface>__<who>.png, and data/tgui_preview/render.txt: OK, or what the page
threw (the bundle's own error handler) or that nothing rendered. Run by run_tgui_preview.sh; on its own:
    python -I tools/tgui_preview/render.py [regex of interface names]
"""
import concurrent.futures
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DUMP = os.path.join(ROOT, 'data', 'tgui_preview')
HTML = os.path.join(DUMP, 'html')
SHOTS = os.path.join(ROOT, 'data', 'previews', 'tgui')
TGUI = os.path.join(ROOT, 'tgui-next', 'packages', 'tgui', 'public')
FA = os.path.join(ROOT, 'html', 'font-awesome', 'css')
FA_CSS = None
EDGE = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'


def url(path):
    return 'file:///' + path.replace('\\', '/')


PAGE = '''<!DOCTYPE html>
<html><head><meta charset="utf-8">
<link rel="stylesheet" href="{css}">
<link rel="stylesheet" href="{fa}">
<link rel="stylesheet" href="{fa4}">
<script>
window.__ref__ = 'preview';
window.__sendToByond__ = function () {{}};
window.__updateQueue__ = [];
window.update = window.initialize = function (s) {{ window.__updateQueue__.push(s); }};
window.onerror = function (msg, src, line, col, error) {{
  document.title = 'TGUI-ERROR ' + msg + ' @' + line + ':' + col + ' ' + ((error && error.stack) || '').split('\\n').slice(0, 3).join(' | ');
  return true;
}};
window.__updateQueue__.push({state});
setTimeout(function () {{
  if (document.title.indexOf('TGUI-ERROR') === 0) return;
  var root = document.getElementById('react-root');
  document.title = (root && root.innerText.trim().length > 0) ? 'TGUI-OK' : 'TGUI-EMPTY';
}}, 1500);
</script>
</head><body>
<div id="react-root"></div>
<div id="FatalError" style="display: none"><div id="FatalError__stack"></div></div>
<script src="{js}"></script>
</body></html>
'''


def render(name):
    path = os.path.join(DUMP, name)
    try:
        state = json.load(open(path, encoding='utf-8', errors='replace'))
    except Exception as e:
        return name, 'BADJSON ' + str(e)[:120]
    cfg = state.get('config', {})
    w = cfg.get('width') or 500
    h = cfg.get('height') or 560
    page = os.path.join(HTML, name.replace('.json', '.html'))
    with open(page, 'w', encoding='utf-8') as f:
        f.write(PAGE.format(css=url(os.path.join(TGUI, 'tgui.bundle.css')), js=url(os.path.join(TGUI, 'tgui.bundle.js')),
            fa=url(FA_CSS), fa4=url(os.path.join(FA, 'v4-shims.min.css')),
            state=json.dumps(json.dumps(state))))
    shot = os.path.join(SHOTS, name.replace('.json', '.png'))
    common = [EDGE, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
              '--virtual-time-budget=2500', f'--window-size={w},{h}']
    try:
        dom = subprocess.run(common + ['--dump-dom', url(page)], capture_output=True, text=True, timeout=60,
                             encoding='utf-8', errors='replace').stdout
        subprocess.run(common + [f'--screenshot={shot}', url(page)], capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        return name, 'TIMEOUT'
    m = re.search(r'<title>(.*?)</title>', dom, re.S)
    title = m.group(1) if m else 'NO-TITLE'
    if title == 'TGUI-OK':
        return name, 'OK'
    return name, title.replace('\n', ' ')[:400]


def inline_fonts():
    """BYOND serves the font files flat beside the css; here they're in ../webfonts, and a file:// page won't load them anyway."""
    import base64
    css = open(os.path.join(FA, 'all.min.css'), encoding='utf-8').read()
    for font in ('fa-solid-900', 'fa-regular-400'):
        data = base64.b64encode(open(os.path.join(FA, '..', 'webfonts', font + '.woff'), 'rb').read()).decode()
        css = css.replace(f'url({font}.woff)', f'url(data:font/woff;base64,{data})')
        css = re.sub(r'url\(' + font + r'\.eot[^)]*\)(\s*format\([^)]*\))?,?', '', css)
    out = os.path.join(HTML, 'fa_inline.css')
    open(out, 'w', encoding='utf-8').write(css)
    return out


def main():
    only = re.compile(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] else None
    os.makedirs(HTML, exist_ok=True)
    os.makedirs(SHOTS, exist_ok=True)
    global FA_CSS
    FA_CSS = inline_fonts()
    names = sorted(n for n in os.listdir(DUMP) if n.endswith('.json') and (not only or only.search(n)))
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for name, verdict in pool.map(render, names):
            results[name] = verdict
    lines = [f'{"OK  " if v == "OK" else "FAIL"} {n[:-5]}: {v}' for n, v in sorted(results.items())]
    open(os.path.join(DUMP, 'render.txt'), 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
    bad = [l for l in lines if l.startswith('FAIL')]
    print(f'rendered {len(lines)}, {len(lines) - len(bad)} OK, {len(bad)} failed; pictures in data/previews/tgui/')
    for l in bad[:60]:
        print(l[:300])


if __name__ == '__main__':
    main()
