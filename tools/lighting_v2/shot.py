"""Lighting v2 scene pictures: a real DreamSeeker on a testkit server, seeing as a crewmember does (lighting on, no ghost
sight), cropped to the map. Usage: python tools/lighting_v2/shot.py --port P --tag before|after [scene ...]

Scenes are named places (SCENES); a scene can also be given as name=x,y,z. Pictures go to data/previews/lighting_v2/<scene>_<tag>.png.
"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "testkit"))
import tk  # noqa: E402
import client_lane  # noqa: E402

OUT = os.path.join(tk.ROOT, "data", "previews", "lighting_v2")
SCENES = {
	"bar": "area:Bar",
	"maint": "area:Aft Maintenance",
	"engine": "area:Supermatter Engine",
	"breach": "area:Arrival Shuttle Hallway",
	"planet": "area:Pool",
}
MAP_BOX = (10, 52, 1286, 1338)  # the map control in a 2576x1408 window grab at 15x15


def crew_sight(server):
	mob = server.call("client_info")["mob"]["ref"]
	for var, value in (("sight", 0), ("see_in_dark", 2), ("lighting_alpha", 255)):
		server.call("set", ref=mob, var=var, value=value)
	server.call("call", ref=mob, proc="sync_lighting_plane_alpha")
	return mob


def connect(server, patience=1800):
	"""client_lane.connect(), waiting while another session's DreamSeeker is open (one runs per machine)"""
	deadline = time.time() + patience
	while True:
		try:
			return client_lane.connect(server)
		except tk.TestkitError as e:
			if "already open" not in str(e) or time.time() > deadline:
				raise
			print("DreamSeeker busy (another session), waiting", flush=True)
			time.sleep(15)


def shoot(server, place, path, seconds=6):
	pid = connect(server)
	view = server.call("client_view", at=place)
	crew_sight(server)
	time.sleep(seconds)
	raw = path + ".raw.png"
	res = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
		os.path.join(client_lane.HERE, "shot.ps1"), str(pid), raw], capture_output=True, text=True)
	if "ok" not in res.stdout:
		raise tk.TestkitError("picture failed: " + res.stdout + res.stderr)
	from PIL import Image
	img = Image.open(raw)
	if img.size == (2576, 1408):
		img = img.crop(MAP_BOX)
	img.save(path)
	os.remove(raw)
	return path, view["at"]["at"]


def main(args):
	opts, names = {}, []
	it = iter(args)
	for a in it:
		if a.startswith("--"):
			opts[a[2:]] = next(it)
		else:
			names.append(a)
	port = int(opts["port"]) if "port" in opts else None
	tag = opts.get("tag", "shot")
	wait = float(opts.get("wait", 6))
	names = names or list(SCENES)
	server = tk.load_server(port)
	os.makedirs(OUT, exist_ok=True)
	fixed_path = os.path.join(OUT, "scenes.json")  # each scene's spot, the first time it's seen: every later picture is the same view
	fixed = json.load(open(fixed_path)) if os.path.exists(fixed_path) else {}
	for name in names:
		if "=" in name:
			name, where = name.split("=", 1)
			fixed[name] = [int(v) for v in where.split(",")]
		place = fixed.get(name) or SCENES[name]
		path, spot = shoot(server, place, os.path.join(OUT, "%s_%s.png" % (name, tag)), wait)
		fixed.setdefault(name, spot)
		json.dump(fixed, open(fixed_path, "w"), indent=1)
		print(path, spot, flush=True)


if __name__ == "__main__":
	main(sys.argv[1:])
