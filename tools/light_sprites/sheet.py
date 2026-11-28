"""Side-by-side sheets of the light bench's pictures: lighting objects, light sprites, and where they differ.
Usage: python tools/light_sprites/sheet.py [prefix]    (default lsp_bench) -> data/previews/<prefix>_sheet_<spot>.png
The map is the left part of the game window: cropped to the square left of the chat.
"""
import glob
import os
import sys

from PIL import Image, ImageChops, ImageDraw

prefix = sys.argv[1] if len(sys.argv) > 1 else "lsp_bench"
spots = sorted({os.path.basename(p)[len(prefix) + 1:].rsplit("_", 1)[0] for p in glob.glob(f"data/previews/{prefix}_*_objects.png")})


def map_crop(im):
	w, h = im.size
	# The map is square, the window's full height less the title bar, on the left
	top = 30
	side = h - top
	return im.crop((0, top, min(side, w), top + side))


for spot in spots:
	a_path = f"data/previews/{prefix}_{spot}_objects.png"
	others = [m for m in ("sprites", "textures", "chunks", "fine") if os.path.exists(f"data/previews/{prefix}_{spot}_{m}.png")]
	if not others:
		continue
	a = map_crop(Image.open(a_path).convert("RGB"))
	size = 640
	panels = [a.resize((size, size))]
	titles = ["lighting objects (now)"]
	for m in others:
		b = map_crop(Image.open(f"data/previews/{prefix}_{spot}_{m}.png").convert("RGB"))
		diff = ImageChops.difference(a, b).convert("L").point(lambda v: min(255, v * 4))
		panels += [b.resize((size, size)), diff.convert("RGB").resize((size, size))]
		titles += [m, f"{m}: difference x4"]
	sheet = Image.new("RGB", (size * len(panels), size + 28), "black")
	draw = ImageDraw.Draw(sheet)
	for i, (panel, title) in enumerate(zip(panels, titles)):
		sheet.paste(panel, (i * size, 28))
		draw.text((i * size + 8, 8), f"{spot}: {title}", fill="white")
	out = f"data/previews/{prefix}_sheet_{spot}.png"
	sheet.save(out)
	print(out)
