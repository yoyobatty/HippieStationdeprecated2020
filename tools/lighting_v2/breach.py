"""Opens the breach scene's hull hole (152-153,157 on the Hippie station: a wall between the pool's corridor and space)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "testkit"))
import tk
s = tk.load_server(int(sys.argv[1]))
for x in (152, 153):
	t = s.call("look", at=[x, 157, 2], range=0)[0]["turf"]
	if "closed" in t["type"]:
		s.call("call", ref=t["ref"], proc="ScrapeAway", args=[2])
print([s.call("look", at=[x, 157, 2], range=0)[0]["turf"]["type"] for x in (152, 153)])
