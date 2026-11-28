"""Draws hippiestation/icons/effects/contact_shadow.dmi: the soft dark strip a floor tile gets along each wall it touches
(contact_shadow.dm). One state per neighbour mask, named by the mask: N 1, S 2, E 4, W 8, and the diagonals NE 16, NW 32,
SE 64, SW 128, a diagonal only when neither wall beside it is there. Usage: python tools/lighting_v2/contact_shadow.py [check]
"""
import math
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tools", "mapmerge2"))
from dmi import Dmi  # noqa: E402
from PIL import Image  # noqa: E402

OUT = os.path.join(ROOT, "hippiestation", "icons", "effects", "contact_shadow.dmi")
SIZE = 32
COLOUR = (5, 7, 14)
# (strength, width px): the wall above a floor shows its face, so the floor under it is darkest
SIDES = {1: (0.55, 12), 2: (0.25, 6), 4: (0.40, 9), 8: (0.40, 9)}
CORNER = (0.40, 9)
DIAGONALS = {16: (1, 4), 32: (1, 8), 64: (2, 4), 128: (2, 8)}  # diagonal bit -> the two cardinals beside it


def canonical(mask):
	for bit, (a, b) in DIAGONALS.items():
		if mask & bit and (mask & a or mask & b):
			mask &= ~bit
	return mask


def fall(d, width):
	return (1 - d / width) ** 2 if d < width else 0.0


def shade(mask, x, y):
	"""How dark pixel (x, y) is, y down from the top edge"""
	px, py = x + 0.5, y + 0.5
	light = 1.0
	dist = {1: py, 2: SIZE - py, 4: SIZE - px, 8: px}
	for bit, (strength, width) in SIDES.items():
		if mask & bit:
			light *= 1 - strength * fall(dist[bit], width)
	corners = {16: (SIZE, 0), 32: (0, 0), 64: (SIZE, SIZE), 128: (0, SIZE)}
	for bit, (cx, cy) in corners.items():
		if mask & bit:
			light *= 1 - CORNER[0] * fall(math.hypot(px - cx, py - cy), CORNER[1])
	return 1 - light


def picture(mask):
	img = Image.new("RGBA", (SIZE, SIZE))
	for y in range(SIZE):
		for x in range(SIZE):
			img.putpixel((x, y), COLOUR + (round(255 * shade(mask, x, y)),))
	return img


def build(path):
	dmi = Dmi(SIZE, SIZE)
	for mask in sorted({canonical(m) for m in range(1, 256)} - {0}):
		dmi.state(str(mask)).frame(picture(mask))
	dmi.to_file(path)


if __name__ == "__main__":
	if sys.argv[1:] == ["check"]:
		with tempfile.TemporaryDirectory() as tmp:
			build(os.path.join(tmp, "c.dmi"))
			same = open(os.path.join(tmp, "c.dmi"), "rb").read() == open(OUT, "rb").read()
		print("contact_shadow.dmi matches the generator" if same else "stale contact_shadow.dmi (run tools/lighting_v2/contact_shadow.py)")
		sys.exit(0 if same else 1)
	build(OUT)
	print(OUT)
