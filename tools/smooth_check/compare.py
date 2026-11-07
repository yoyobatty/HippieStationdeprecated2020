"""Compares the getFlatIcon() renders the old corner smoothing and the new bitmask smoothing produced for the same
(type, junction): data/smooth_check/old_flat* against new_flat*. Prints any that differ in a visible pixel, and writes
side-by-side sheets of the first differences to data/smooth_check/diffs/.

    python tools/smooth_check/compare.py
"""
import os
import sys
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
D = os.path.join(ROOT, 'data', 'smooth_check')


def index(name):
    out = {}
    for line in open(os.path.join(D, name + '.txt'), encoding='utf-8'):
        p = [x.strip() for x in line.rstrip('\n').split(' | ')]
        if len(p) < 6:
            continue
        num, typ, junction = p[0], p[1], p[2]
        color = p[6] if len(p) > 6 else ''
        out.setdefault((typ, junction, color, p[3]), (num, p[3], p[4], p[5]))
    return out


def visible(im):
    """RGBA with fully transparent pixels zeroed, so hidden colour under alpha 0 doesn't count"""
    im = im.convert('RGBA')
    px = [(0, 0, 0, 0) if a == 0 else (r, g, b, a) for r, g, b, a in im.get_flattened_data()]
    out = Image.new('RGBA', im.size)
    out.putdata(px)
    return out


def main():
    old = index('old_flat')
    new = index('new_flat')
    both = sorted(set(old) & set(new))
    differ = []
    for key in both:
        a = Image.open(os.path.join(D, 'old_flat', old[key][0] + '.png'))
        b = Image.open(os.path.join(D, 'new_flat', new[key][0] + '.png'))
        if a.size != b.size:
            differ.append((key, f'size {a.size} vs {b.size}', a, b))
            continue
        va, vb = visible(a), visible(b)
        if va.tobytes() != vb.tobytes():
            n = sum(1 for x, y in zip(va.get_flattened_data(), vb.get_flattened_data()) if x != y)
            differ.append((key, f'{n} pixels', va, vb))
    only_old = sorted(set(old) - set(new))
    only_new = sorted(set(new) - set(old))
    print(f'{len(both)} (type, junction) pairs in both, {len(differ)} differ; {len(only_old)} only in old, {len(only_new)} only in new')
    for key, why, a, b in differ[:60]:
        print(f'  DIFF {key[0]} junction {key[1]}: {why}  old {old[key][1]} [{old[key][2]}] at {old[key][3]} / new [{new[key][2]}] at {new[key][3]}')
    for key in only_old[:30]:
        print(f'  only old: {key}')
    for key in only_new[:30]:
        print(f'  only new: {key}')
    if differ:
        os.makedirs(os.path.join(D, 'diffs'), exist_ok=True)
        for i, (key, why, a, b) in enumerate(differ[:40]):
            w, h = a.size
            sheet = Image.new('RGBA', (w * 2 * 4 + 8, h * 4), (255, 0, 255, 255))
            sheet.alpha_composite(a.resize((w * 4, h * 4), Image.NEAREST), (0, 0))
            sheet.alpha_composite(b.resize((w * 4, h * 4), Image.NEAREST), (w * 4 + 8, 0))
            sheet.save(os.path.join(D, 'diffs', f'{i:02}.png'))
    return 1 if differ else 0


if __name__ == '__main__':
    sys.exit(main())
