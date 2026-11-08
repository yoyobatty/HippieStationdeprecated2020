"""Keep only Font Awesome 6's own two @font-face rules in tgui6/assets/font-awesome/all.min.css.

The v4/v5 alias rules point at the same fonts again; inlined into the chat's stylesheet each one was a further copy
(2 MB of CSS). The panel only uses the FA6 family. Run after fetching Font Awesome again.
"""
import os
import re

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tgui6', 'assets', 'font-awesome', 'all.min.css')
css = open(path, encoding='utf-8').read()
before = len(css)


def keep(match):
    return match.group(0) if 'Font Awesome 6 Free' in match.group(0) else ''


css = re.sub(r'@font-face\{[^}]*\}', keep, css)
open(path, 'w', encoding='utf-8').write(css)
print('%d -> %d bytes, %d @font-face left' % (before, len(css), css.count('@font-face')))
