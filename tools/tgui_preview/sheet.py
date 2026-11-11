"""Tiles window pictures into one contact sheet: python -I tools/tgui_preview/sheet.py <out.png> <regex> [columns] [cell width]."""
import os
import re
import sys

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SHOTS = os.path.join(ROOT, 'data', 'previews', 'tgui')

out, pattern = sys.argv[1], re.compile(sys.argv[2])
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
cell_w = int(sys.argv[4]) if len(sys.argv) > 4 else 360
names = sorted(n for n in os.listdir(SHOTS) if n.endswith('.png') and pattern.search(n))
cells = []
for n in names:
    im = Image.open(os.path.join(SHOTS, n)).convert('RGB')
    scale = cell_w / im.width
    im = im.resize((cell_w, int(im.height * scale)))
    cells.append((n[:-4], im))
if not cells:
    sys.exit('nothing matched')
rows = [cells[i:i + cols] for i in range(0, len(cells), cols)]
heights = [max(im.height for _, im in row) + 16 for row in rows]
sheet = Image.new('RGB', (cols * (cell_w + 6), sum(heights)), (10, 10, 10))
d = ImageDraw.Draw(sheet)
y = 0
for row, h in zip(rows, heights):
    for i, (name, im) in enumerate(row):
        x = i * (cell_w + 6)
        d.text((x + 2, y + 2), name, fill=(220, 220, 220))
        sheet.paste(im, (x, y + 16))
    y += h
sheet.save(out)
print(out, len(cells))
