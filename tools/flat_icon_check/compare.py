"""Compares the pictures flat_icon_check.dm wrote: getFlatIcon() against iconforge, pixel by pixel.

Two pixels count as the same when every channel is within 1 (rounding in a blend), or when both are fully transparent (colour
under alpha 0 is never seen). Usage: python tools/flat_icon_check/compare.py [--show N]   (reads data/flat_icon_check/)
"""
import json
import os
import sys
from collections import Counter

from PIL import Image

BASE = "data/flat_icon_check"


def load(path):
	return Image.open(path).convert("RGBA") if os.path.exists(path) else None


def differs(a, b):
	if a[3] == 0 and b[3] == 0:
		return 0
	return max(abs(a[i] - b[i]) for i in range(4))


def main():
	show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 10
	rows = json.load(open(f"{BASE}/rows.json", encoding="utf-8"))
	outcome = Counter()
	worst = []
	by_type = Counter()
	for row in rows:
		n = row["n"]
		if row["forge"] == "fallback":
			outcome["left to DM"] += 1
			by_type[(row.get("why") or "?")[:100]] += 1
			continue
		dm = load(f"{BASE}/dm/{n}.png") if row["dm"] else None
		if dm is not None and row.get("w"):
			dm = dm.crop((0, 0, row["w"], row["h"]))  # fcopy() writes the /icon as a .dmi sheet: the picture is its first cell
		forge = load(f"{BASE}/forge/{n}.png") if row["forge"] == "drawn" else None
		if dm is None and forge is None:
			outcome["both empty"] += 1
			continue
		if dm is None or forge is None:
			outcome["one empty"] += 1
			worst.append((10**9, n, row["type"], row["dir"], "only " + ("DM" if dm else "iconforge") + " drew something"))
			continue
		if dm.size != forge.size:
			outcome["different size"] += 1
			worst.append((10**8, n, row["type"], row["dir"], f"size {dm.size} against {forge.size}"))
			continue
		a = dm.load()
		b = forge.load()
		bad = 0
		most = 0
		for y in range(dm.size[1]):
			for x in range(dm.size[0]):
				d = differs(a[x, y], b[x, y])
				if d > 1:
					bad += 1
				most = max(most, d)
		if bad:
			outcome["different pixels"] += 1
			worst.append((bad, n, row["type"], row["dir"], f"{bad} pixels differ, most by {most}"))
		else:
			outcome["same"] += 1
	print(f"{len(rows)} pictures: " + ", ".join(f"{v} {k}" for k, v in outcome.most_common()))
	drawn = [r for r in rows if r["forge"] == "drawn"]
	if drawn:
		dm_ms = sum(r["dm_ms"] for r in drawn)
		forge_ms = sum(r["forge_ms"] for r in drawn)
		print(f"where iconforge drew them: DM {dm_ms:.1f} ms, iconforge {forge_ms:.1f} ms ({dm_ms / max(forge_ms, 0.001):.1f}x)")
	if by_type:
		print("left to DM, why:")
		for t, c in by_type.most_common(12):
			print(f"  {c} x {t}")
	worst.sort(reverse=True)
	for item in worst[:show]:
		print(f"  #{item[1]} {item[2]} dir {item[3]}: {item[4]}")


main()
