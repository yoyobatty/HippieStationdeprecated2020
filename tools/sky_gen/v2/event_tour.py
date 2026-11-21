#!/usr/bin/env python3
"""Real-client tour of the sky's rare events: each one started in turn on a test server, its whole run captured from a
DreamSeeker every few seconds, and a labelled contact sheet made per event.

  python tools/sky_gen/v2/event_tour.py [--events vortex,prism,...] [--every 30] [--seed 5] [--at 110,60,2] [--zoom 0] [--fps 10]
                                        [--crop x0,y0,x1,y1] [--out data/previews/sky_tour] [--nobuild] [--keep]

Builds its own dmb (skyev.mdme, so testkit.mdme stays free), starts testbench (seed 5 is the ember theme, which has a sun,
so the prism can run), connects the testkit client lane (refuses while another DreamSeeker, the user's game, is open) and
puts the view at a fixed deep-space tile (110,60,2 on testbench: no hull, lattice or station tile on screen), the window
maximized and the map stretch-to-fit (zoom 0, what the player sees; --zoom N for a whole zoom), the client capped at 10 fps.
Each sheet's captions carry the window and pane sizes. The map's place in the grab is found from the first frame (map_box). Deterministic: the
same seed, place, zoom and settle wait each run, and rand_seed(seed * 100 + the event's number) right before each event,
so an event lays out the same way every run and before/after sheets line up frame for frame. Then for each event: SSparallax.sky_event(kind), frames by devkit lookkit capture until the
event's length plus its fade has gone by, frames cropped to the map, and devkit lookkit sheet -> OUT/<kind>_sheet.png.
Supernova goes last whatever the order, since its remnant stays for the round. The client is closed (map zoom back to
stretch-to-fit, see client_lane.close) and the server stopped at the end unless --keep.

Sky animations run on the client in real time, so a tour takes the events' real lengths (6-9 minutes each). Run it in the
background. --count N caps the frames per event; --quick 0.3,0.55 takes one frame at each of those points of an event and
runs the rest of it time-warped (spares the PC: ~40 minutes for all eight). Servers start only when gpu_share is clear, and
the client and server close whenever a Last Light timed run waits, starting again after it.
"""
import argparse
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "testkit"))
import tk  # noqa: E402
import client_lane  # noqa: E402

DK = r"C:\Users\Keegan Eaton\devkit\dk.py"
EVENTS = ["vortex", "prism", "giant", "shower", "battle", "breakup", "aurora", "supernova"]
TAIL = 60  # seconds past an event's length: its fade out and the last pieces going
SETTLE = 10  # seconds after the view moves before an event starts


def log(msg):
	print(time.strftime("%H:%M:%S ") + msg, flush=True)


def world_time(server):
	return float(server.call("status")["time"]) / 10


def layout(server, zoom=0, fps=10):
	"""The window maximized (fixed size on this PC), the map at zoom (0: stretch-to-fit, what the player sees) and the
	client capped at fps (stills only: spare the PC). split.splitter can't be reached from winset on this skin, so the map
	keeps its share of the window. Returns the window and pane sizes for the captions. client_lane.close() puts zoom back."""
	server.call("client_winset", control="mainwindow", params="is-maximized=true")
	server.call("client_winset", control=None, params="mapwindow.map.zoom=%d" % zoom)
	client = server.call("get", ref="mob:Testkit Camera", vars=["client"])["vars"]["client"]
	if isinstance(client, dict) and client.get("ref"):
		server.call("set", ref=client["ref"], var="fps", value=fps)
	time.sleep(2)
	return {"window": server.call("client_winget", control="mainwindow", params="size"),
		"pane": server.call("client_winget", control="mapwindow.map", params="size"), "zoom": zoom, "fps": fps}


def map_box(png):
	"""Where the map's picture sits in a PrintWindow grab: DreamSeeker isn't DPI aware and the grab puts the map's surface at
	its own place in the pane, so find it: the bounding box of the sky's pixels (never pure black, unlike the pane round it)."""
	from PIL import Image
	import numpy as np
	a = np.asarray(Image.open(png).convert("RGB")).astype(int)
	h, w = a.shape[:2]
	bg = a[100, 100]  # the empty pane's colour round the map's surface (its top left is always empty)
	same = (np.abs(a - bg).sum(2) <= 12)
	# the pane: the run of background-coloured pixels along row 100, from the left edge in
	x0 = int(np.argmax(same[100]))
	x1 = x0 + int(np.argmin(same[100, x0:]))
	y1 = 100 + int(np.argmin(same[100:, x1 - 3]))  # the pane's bottom, down its right edge (the map sits bottom left)
	lit = ~same
	lit[:, :x0] = False
	lit[:, x1:] = False
	lit[y1:, :] = False
	lit[:60, :] = False  # title bar and menus
	rows = np.where(lit.mean(1) > 0.15)[0]
	rows = rows[rows < h - 40]  # the input bar along the bottom
	cols = np.where(lit[rows.min():rows.max() + 1].mean(0) > 0.5)[0]
	rows = np.where(lit[:, cols.min():cols.max() + 1].mean(1) > 0.5)[0]
	runs = np.split(rows, np.where(np.diff(rows) > 1)[0] + 1)  # the map is the longest run; the input bar is apart
	rows = max(runs, key=len)
	return "%d,%d,%d,%d" % (cols.min(), rows.min(), cols.max() + 1, rows.max() + 1)


def make_sheet(kind, frames, every, lay, out, crop="", times=None):
	"""OUT/<kind>_sheet.png from the frames in frames/: each cropped to the map and drawn at the pane's height (stretch-to-fit
	fills the pane's height: the size on screen), captioned with the time and the window, pane and zoom. Returns (sheet, crop)."""
	from PIL import Image
	shots = sorted(os.path.join(frames, f) for f in os.listdir(frames) if f.endswith(".png"))
	pane = str(lay["pane"]).strip('"')
	height = int(pane.split("x")[1]) if lay["zoom"] == 0 else 480 * lay["zoom"]
	# each frame cropped on its own: the grab's scale can change mid-run (a DPI switch took it from 1936x1048 to 2576x1408)
	cut = os.path.join(frames, "map")
	os.makedirs(cut, exist_ok=True)
	maps, boxes = [], []
	for shot in shots:
		box = crop or map_box(shot)
		boxes.append(box)
		im = Image.open(shot).crop(tuple(int(v) for v in box.split(",")))
		path = os.path.join(cut, os.path.basename(shot))
		im.resize((height, height), Image.LANCZOS).save(path)
		maps.append(path)
	times = times or [i * every for i in range(len(shots))]
	labels = ["%s %d:%02d   grab %s  pane %s  zoom %s" % (kind, int(times[i]) // 60, int(times[i]) % 60,
		"%dx%d" % Image.open(shots[i]).size, pane, lay["zoom"] or "stretch-to-fit") for i in range(len(shots))]
	sheet = os.path.join(out, kind + "_sheet.png")
	cmd = [sys.executable, DK, "lookkit", "sheet"] + maps + [sheet, "--cols", "3", "--labels", ",".join(labels), "--width", str(height)]
	crop = sorted(set(boxes)) if len(set(boxes)) > 1 else boxes[0]
	subprocess.run(cmd, check=True, capture_output=True)
	return sheet, crop


def gpu_busy():
	"""Whether a Last Light timed run holds or has reserved the GPU now (tools/gpu_share.py's lock), without waiting."""
	sys.path.insert(0, os.path.join(ROOT, "tools"))
	try:
		import gpu_share
		lock = gpu_share.load()
		return bool(lock and lock._must_wait())
	except Exception:
		return False
	finally:
		sys.path.pop(0)


def open_session(args, dmb, at):
	"""A server and its client, started only once the GPU is free and dropped again if a timed run got in while the server
	booted (an idle dd waiting on the client lane is a standoff: Last Light waits for quiet, the client waits for Last Light)."""
	while True:
		tk.gpu_wait("dd.exe + dreamseeker.exe sky event tour")
		server = tk.start("testbench", port=args.port, seed=args.seed, dmb=dmb)
		if not gpu_busy():
			break
		log("a timed run came in while the server booted: stopping it and waiting")
		tk.stop(server)
	log("server on %d" % server.port)
	client_lane.connect(server)
	server.call("client_view", at=at)
	lay = layout(server, args.zoom, args.fps)
	log("layout: %s" % lay)
	time.sleep(SETTLE)
	return server, client_lane.client_pid(server), lay


def close_session(server):
	client_lane.close(server)
	tk.stop(server)


def main():
	ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
	ap.add_argument("--events", default=",".join(EVENTS))
	ap.add_argument("--every", type=float, default=30)
	ap.add_argument("--count", type=int, default=0)
	ap.add_argument("--seed", type=int, default=5)
	ap.add_argument("--at", default="110,60,2")
	ap.add_argument("--zoom", type=int, default=0)
	ap.add_argument("--fps", type=int, default=10)
	ap.add_argument("--probe", action="store_true")
	ap.add_argument("--crop", default="", help="the map in a grab; found from the first frame when not given")
	ap.add_argument("--out", default=os.path.join(ROOT, "data", "previews", "sky_tour"))
	ap.add_argument("--nobuild", action="store_true")
	ap.add_argument("--keep", action="store_true")
	ap.add_argument("--port", type=int, default=None)
	ap.add_argument("--sheets", action="store_true", help="only remake the sheets from OUT/<kind>/ frames and OUT/tour.json")
	ap.add_argument("--quick", default="", help="fractions of each event's length to take one frame at (0.3,0.55): the rest of the "
		"event runs time-warped (the server unlimited) so the next starts on a clean sky. Spares the PC")
	args = ap.parse_args()
	kinds = [k for k in args.events.split(",") if k]
	if "supernova" in kinds:
		kinds = [k for k in kinds if k != "supernova"] + ["supernova"]
	at = [int(v) for v in args.at.split(",")]
	if args.sheets:
		with open(os.path.join(args.out, "tour.json")) as f:
			summary = json.load(f)
		for kind in kinds:
			if os.path.isdir(os.path.join(args.out, kind)):
				log("%s: %s" % (kind, make_sheet(kind, os.path.join(args.out, kind), args.every, summary["layout"], args.out, args.crop)[0]))
		return
	os.makedirs(args.out, exist_ok=True)
	dmb = os.path.join(ROOT, "skyev.mdme.dmb")
	if not args.nobuild or not os.path.exists(dmb):
		log("building skyev.mdme")
		dmb = tk.build(name="skyev.mdme", quiet=True)
	server, pid, lay = open_session(args, dmb, at)
	summary = {"layout": lay}
	quick = [float(v) for v in args.quick.split(",") if v]
	try:
		if args.probe:
			subprocess.run([sys.executable, DK, "lookkit", "capture", str(pid), os.path.join(args.out, "probe.png")], check=True)
			kinds = []
		for kind in kinds:
			if gpu_busy():  # a timed run is waiting: get out of its way, come back after
				log("a timed run is waiting: closing the client and the server until it's done")
				close_session(server)
				server, pid, lay = open_session(args, dmb, at)
			server.call("seed", seed=args.seed * 100 + EVENTS.index(kind) if kind in EVENTS else args.seed * 100 + 99)
			started = server.call("call", ref="SSparallax", proc="sky_event", args=[kind])
			if not started:
				log("%s: didn't start (doesn't fit this sky)" % kind)
				summary[kind] = None
				continue
			began = world_time(server)
			until = float(server.call("get", ref="SSparallax", vars=["event_until"])["vars"]["event_until"]) / 10
			length = max(30.0, until - began) + TAIL
			frames = os.path.join(args.out, kind)
			if os.path.isdir(frames):
				for f in os.listdir(frames):
					if f.endswith(".png"):
						os.remove(os.path.join(frames, f))
			os.makedirs(frames, exist_ok=True)
			times = None
			if quick:
				times = []
				log("%s: %.0f s, frames at %s of it" % (kind, length, quick))
				for n, f in enumerate(quick):
					wait = began + f * (until - began) - world_time(server)
					if wait > 0:
						time.sleep(wait)
					subprocess.run([sys.executable, DK, "lookkit", "capture", str(pid), os.path.join(frames, "%04d.png" % (n + 1))],
						check=True, capture_output=True)
					times.append(world_time(server) - began)
				server.call("speed", speed=0)  # the rest of it time-warped: its pieces' timers run out, the sky clears
				while world_time(server) < until + TAIL:
					time.sleep(2)
				server.call("speed", speed=1)
				time.sleep(5)
				count = len(quick)
			else:
				count = int(length // args.every) + 1
				if args.count:
					count = min(count, args.count)
				log("%s: %.0f s, %d frames every %.0f s" % (kind, length, count, args.every))
				subprocess.run([sys.executable, DK, "lookkit", "capture", str(pid), frames, "--every", str(args.every), "--count", str(count)],
					check=True, capture_output=True)
				if args.count:  # cut short: wait out the rest so the next event starts on a clean sky
					rest = until + TAIL - world_time(server)
					if rest > 0:
						time.sleep(rest)
			sheet, crop = make_sheet(kind, frames, args.every, lay, args.out, args.crop, times)
			summary[kind] = {"sheet": sheet, "frames": count, "seconds": round(length), "crop": crop}
			log("%s: %s" % (kind, sheet))
		summary["invariants"] = server.call("invariants")
	finally:
		if not args.keep:
			close_session(server)
	with open(os.path.join(args.out, "tour.json"), "w") as f:
		json.dump(summary, f, indent=1)
	log("done: " + os.path.join(args.out, "tour.json"))


if __name__ == "__main__":
	main()
