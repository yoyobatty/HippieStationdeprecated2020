"""Picks this boot's window scene: the hull window (a grille next to space) nearest the middle of Lavaland as the station
sees it (SSparallax.planet_x/y_offset), and saves it as scene "window" in scenes.json. python tools/lighting_v2/planet_spot.py PORT"""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "testkit"))
import tk
s = tk.load_server(int(sys.argv[1]))
v = s.call("get", ref="SSparallax", vars=["planet_x_offset", "planet_y_offset"])["vars"]
px, py = v["planet_x_offset"], v["planet_y_offset"]
best = None
for g in s.call("find", type="/obj/structure/grille", near=[px, py, 2], range=30, limit=200)["found"]:
	if not isinstance(g, dict):  # "... N more" when past the find cap
		continue
	x, y, z = g["at"]
	if z != 2:
		continue
	if not any("space" in t["turf"]["type"] for t in s.call("look", at=[x, y, z], range=1)):
		continue
	d = (x - px) ** 2 + ((y - py) * 35 / 19) ** 2
	if best is None or d < best[0]:
		best = (d, [x, y, z])
p = os.path.join(tk.ROOT, "data", "previews", "lighting_v2", "scenes.json")
scenes = json.load(open(p))
scenes["window"] = best[1]
json.dump(scenes, open(p, "w"), indent=1)
print("planet", px, py, "window", best)
