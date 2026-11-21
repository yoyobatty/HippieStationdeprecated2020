#!/usr/bin/env python3
"""Testkit real-client lane: a DreamSeeker connected to a testkit server, its view put at a place, its window's picture taken.
  python tools/testkit/client_lane.py shot [--at area:Bridge] [--name bridge] [--port N]
  python tools/testkit/client_lane.py close [--port N]
Pictures go to data/previews/testkit_<name>.png. Only one DreamSeeker runs per machine: this refuses while another one (the user's
game) is open. The client may come in as the user's own key; the testkit build saves no preferences.
"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tk  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEWS = os.path.join(tk.ROOT, "data", "previews")


def seeker_pids():
	out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq dreamseeker.exe", "/FO", "CSV", "/NH"], capture_output=True, text=True).stdout
	pids = []
	for line in out.splitlines():
		parts = [p.strip('"') for p in line.split(",")]
		if len(parts) > 1 and parts[1].isdigit():
			pids.append(int(parts[1]))
	return pids


def info_file(server):
	return tk.server_file(server.port)


def client_pid(server):
	with open(info_file(server)) as f:
		return json.load(f).get("client_pid")


def set_client_pid(server, pid):
	path = info_file(server)
	with open(path) as f:
		info = json.load(f)
	info["client_pid"] = pid
	with open(path, "w") as f:
		json.dump(info, f)


def connect(server, timeout=120):
	pid = client_pid(server)
	if pid and tk.pid_alive(pid) and server.call("client_info"):
		return pid
	others = [p for p in seeker_pids() if p != pid]
	if others:
		raise tk.TestkitError("a DreamSeeker is already open (pid %s): close the game first; one runs per machine" % others)
	tk.gpu_wait("dreamseeker.exe port %d" % server.port)
	proc = subprocess.Popen([os.path.join(tk.BYOND_BIN, "dreamseeker.exe"), "byond://127.0.0.1:%d##guest" % server.port],
		env=tk.clean_env(), creationflags=0x00000008)
	set_client_pid(server, proc.pid)
	deadline = time.time() + timeout
	while time.time() < deadline:
		if server.call("client_info"):
			time.sleep(3)  # the map and HUD come in after login
			return proc.pid
		if proc.poll() is not None:
			raise tk.TestkitError("DreamSeeker exited")
		time.sleep(1)
	raise tk.TestkitError("the client didn't connect in %d s" % timeout)


def screenshot(server, at=None, name=None, seconds=8):
	pid = connect(server)
	view = server.call("client_view", at=at) if at else server.call("client_view")
	time.sleep(max(1, float(seconds)))
	os.makedirs(PREVIEWS, exist_ok=True)
	name = name or time.strftime("%H%M%S")
	out = os.path.join(PREVIEWS, "testkit_%s.png" % name)
	res = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", os.path.join(HERE, "shot.ps1"), str(pid), out],
		capture_output=True, text=True)
	if "ok" not in res.stdout:
		raise tk.TestkitError("picture failed: " + (res.stdout + res.stderr).strip())
	return {"png": out, "view": view, "shot": res.stdout.strip(), "client": server.call("client_info")}


def close(server):
	pid = client_pid(server)
	try:
		# the map saves its zoom and the split its splitter per key (skin.dmf saved-params), and this client may be the user's own
		# key: leave the map stretch-to-fit and the split at the skin's 66
		server.call("client_winset", control=None, params="mapwindow.map.zoom=0")
		server.call("client_winset", control=None, params="split.splitter=66")  # saved per key too: the map pane back to its share
		server.call("client_winset", control=None, params="command=.quit")
		time.sleep(1)
	except tk.TestkitError:
		pass
	if pid and tk.pid_alive(pid):
		subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
	set_client_pid(server, None)


if __name__ == "__main__":
	args = sys.argv[1:]
	port = int(args[args.index("--port") + 1]) if "--port" in args else None
	s = tk.load_server(port)
	if args and args[0] == "close":
		close(s)
	else:
		print(json.dumps(screenshot(s, args[args.index("--at") + 1] if "--at" in args else None,
			args[args.index("--name") + 1] if "--name" in args else None), indent=1))
