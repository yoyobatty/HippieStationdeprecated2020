"""Picks this boot's lamp-by-window scene: a wall light within 2 tiles of a hull window (a grille next to space), nearest the
station's middle, and saves it as scene "lampwin" in scenes.json. Shows whether a lamp tints the sky seen past the glass.
python tools/lighting_v2/lamp_window.py PORT"""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "testkit"))
import tk
s = tk.load_server(int(sys.argv[1]))
CX, CY = 128, 128
best = None
for L in s.call("find", type="/obj/machinery/light", near=[CX, CY, 2], range=60, limit=600)["found"]:
	if not isinstance(L, dict):  # "... N more" when past the find cap
		continue
	x, y, z = L["at"]
	if z != 2:
		continue
	d = (x - CX) ** 2 + (y - CY) ** 2
	if best is not None and d >= best[0]:
		continue
	near = s.call("look", at=[x, y, z], range=2)
	if not any("space" in t["turf"]["type"] for t in near):
		continue
	if not any("grille" in o["type"] for t in near for o in t.get("contents", [])):
		continue
	best = (d, [x, y, z])
p = os.path.join(tk.ROOT, "data", "previews", "lighting_v2", "scenes.json")
scenes = json.load(open(p))
scenes["lampwin"] = best[1]
json.dump(scenes, open(p, "w"), indent=1)
print("lamp by window", best)
