"""Lighting v2 server cost with a real client: world.map_cpu (SendMaps) and world.cpu, v2 off / on / off in one boot,
standing in the bar and then panning the view along the station's halls. python tools/lighting_v2/perf_ab.py PORT"""
import json
import os
import statistics
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "testkit"))
import tk  # noqa: E402
import client_lane  # noqa: E402
import shot  # noqa: E402

PAN = [[142, 133, 2], [130, 128, 2], [118, 128, 2], [106, 128, 2], [100, 140, 2], [112, 150, 2], [126, 150, 2], [140, 150, 2]]


def sample(s, seconds, pan):
	cpu, mcpu = [], []
	end = time.time() + seconds
	i = 0
	while time.time() < end:
		if pan:
			s.call("client_view", at=PAN[i % len(PAN)])
			shot.crew_sight(s)
			i += 1
		st = s.call("status")
		cpu.append(st["cpu"])
		mcpu.append(st["map_cpu"])
		time.sleep(1)
	return statistics.mean(cpu), statistics.mean(mcpu)


def main():
	port = int(sys.argv[1])
	s = tk.load_server(port)
	shot.connect(s)
	s.call("client_view", at=PAN[0])
	shot.crew_sight(s)
	time.sleep(8)
	rows = []
	for label, on in (("off", 0), ("on", 1), ("off2", 0), ("on2", 1)):
		s.call("call", ref="global", proc="lighting_v2_set", args=[on])
		time.sleep(20)
		for pan in (False, True):
			c, m = sample(s, 40, pan)
			rows.append((label, "pan" if pan else "stand", round(c, 2), round(m, 2)))
			print(rows[-1], flush=True)
	out = os.path.join(tk.ROOT, "data", "previews", "lighting_v2", "perf_ab.json")
	json.dump(rows, open(out, "w"), indent=1)
	s.call("call", ref="global", proc="lighting_v2_set", args=[0])
	client_lane.close(s)


if __name__ == "__main__":
	main()
