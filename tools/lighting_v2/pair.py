"""Side-by-side before/after sheets: python tools/lighting_v2/pair.py <before_tag> <after_tag> [scene ...] [--crop x0,y0,x1,y1]"""
import os
import sys

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "previews", "lighting_v2")


def main(args):
	crop = None
	if "--crop" in args:
		i = args.index("--crop")
		crop = tuple(int(v) for v in args[i + 1].split(","))
		del args[i:i + 2]
	before, after, scenes = args[0], args[1], args[2:]
	for scene in scenes:
		a = Image.open(os.path.join(OUT, "%s_%s.png" % (scene, before))).convert("RGB")
		b = Image.open(os.path.join(OUT, "%s_%s.png" % (scene, after))).convert("RGB")
		if crop:
			a, b = a.crop(crop), b.crop(crop)
		w, h = a.size
		sheet = Image.new("RGB", (w * 2 + 8, h), (255, 255, 255))
		sheet.paste(a, (0, 0))
		sheet.paste(b, (w + 8, 0))
		if not crop:
			sheet = sheet.resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS)
		path = os.path.join(OUT, "%s_%s_vs_%s%s.png" % (scene, before, after, "_zoom" if crop else ""))
		sheet.save(path)
		print(path)


if __name__ == "__main__":
	main(sys.argv[1:])
