#!/usr/bin/env python3
"""Testkit client: builds the testkit dmb, starts and stops test servers, and sends them commands (tools/testkit/dm/*.dm).

  python tools/testkit/tk.py build [--checks tools/combat_check/combat_check.dm,...]
  python tools/testkit/tk.py start [--map testbench] [--port N] [--seed N] [--speed 0] [--params "a=1&b=2"]
  python tools/testkit/tk.py status | help | stop | servers
  python tools/testkit/tk.py <command> key=value ...      values are JSON when they parse (n=3, at=[10,10,2]), text otherwise
  python tools/testkit/tk.py events [--follow] [--kinds death,bot.] [--since N]
  python tools/testkit/tk.py replay data/testkit/<port>/commands.jsonl [--port N]

The server last started is the default; --port picks another. Each server keeps data/testkit/<port>/ (events.jsonl,
commands.jsonl, ready.txt, dd.log) and data/testkit/servers/<port>.json (port, key, pid).
"""
import json
import os
import secrets
import socket
import struct
import subprocess
import sys
import re
import time
import urllib.parse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BYOND_BIN = os.environ.get("BYOND_BIN", r"C:\Program Files (x86)\BYOND\bin")
DATA = os.path.join(ROOT, "data", "testkit")
SERVERS = os.path.join(DATA, "servers")
DM_FILES = ["testkit_core.dm", "testkit_commands.dm", "testkit_events.dm", "testkit_bots.dm", "testkit_ui.dm", "testkit_client.dm", "testkit_sweep.dm"]
BUILD_NAME = "testkit.mdme"
PORTS = range(45600, 45700)


class TestkitError(Exception):
	pass


def gpu_wait(what):
	"""Waits while a Last Light timed run holds or has reserved this PC's GPU (tools/gpu_share.py, which uses Last Light's
	gpulock): every dd, DreamSeeker and dm.exe the testkit starts comes through here, so no session has to remember."""
	sys.path.insert(0, os.path.join(ROOT, "tools"))
	try:
		import gpu_share
		lock = gpu_share.load()
	except Exception as e:  # never block a run on the helper itself
		print("gpu_share unavailable: %r" % e)
		return
	finally:
		sys.path.pop(0)
	if lock is not None:
		lock.wait("HippieStation testkit: " + what)


# ---------------------------------------------------------------------------------------------
# BYOND topic packets: 00 83, big-endian length, five zero bytes, "?query", a zero byte. The answer: 00 83, length, then a type
# byte (06 text, 2a number) and the value.
# ---------------------------------------------------------------------------------------------

def topic(port, query, timeout=30.0):
	data = ("?" + query).encode("utf-8") + b"\x00"
	if len(data) + 5 > 65535:
		raise TestkitError("command too long for one packet (%d bytes)" % len(data))
	packet = b"\x00\x83" + struct.pack(">H", len(data) + 5) + b"\x00" * 5 + data
	with socket.create_connection(("127.0.0.1", port), timeout=timeout) as s:
		s.sendall(packet)
		head = _read(s, 4)
		if head[:2] != b"\x00\x83":
			raise TestkitError("not a topic answer: %r" % head)
		size = struct.unpack(">H", head[2:4])[0]
		body = _read(s, size)
	kind, value = body[0], body[1:]
	if kind == 0x2A:
		return struct.unpack("<f", value[:4])[0]
	if kind == 0x06:
		return value.rstrip(b"\x00").decode("utf-8", "replace")
	return None


def _read(s, n):
	out = b""
	while len(out) < n:
		chunk = s.recv(n - len(out))
		if not chunk:
			raise TestkitError("server closed the connection")
		out += chunk
	return out


class Server:
	def __init__(self, port, key, pid=None):
		self.port = int(port)
		self.key = key
		self.pid = pid

	def raw(self, cmd, timeout=30.0, **args):
		args["cmd"] = cmd
		query = "testkit=" + urllib.parse.quote(json.dumps(args)) + "&key=" + urllib.parse.quote(self.key)
		text = topic(self.port, query, timeout)
		if text is None:
			raise TestkitError("no answer (the command slept inside the topic call?)")
		answer = json.loads(text)
		if "blob" in answer:
			parts = []
			offset = 0
			while offset < answer["size"]:
				part = self.raw("blob", id=answer["blob"], offset=offset)
				if not part.get("ok"):
					raise TestkitError(part.get("error", "blob failed"))
				parts.append(part["result"])
				offset += answer["part"]
			answer = json.loads("".join(parts))
		return answer

	def call(self, cmd, wait=True, timeout=900.0, **args):
		"""Runs a command; a job is waited for (polled) unless wait=False. Returns the result or raises TestkitError."""
		answer = self.raw(cmd, **args)
		if not answer.get("ok"):
			raise TestkitError(answer.get("error", "failed"))
		if answer.get("pending"):
			if not wait:
				return {"job": answer["job"], "pending": True}
			return self.wait_job(answer["job"], timeout)
		return answer.get("result")

	def wait_job(self, job, timeout=900.0):
		deadline = time.time() + timeout
		delay = 0.05
		while time.time() < deadline:
			answer = self.raw("job", id=job)
			if not answer.get("ok"):
				raise TestkitError(answer.get("error", "failed"))
			result = answer.get("result")
			if not (isinstance(result, dict) and result.get("pending")):
				return result
			time.sleep(delay)
			delay = min(1.0, delay * 1.5)
		raise TestkitError("job %s still running after %d s" % (job, timeout))

	def alive(self):
		try:
			return self.raw("ping", timeout=3).get("result") == "pong"
		except (OSError, TestkitError, ValueError):
			return False


# ---------------------------------------------------------------------------------------------
# Servers on this machine
# ---------------------------------------------------------------------------------------------

def server_file(port):
	return os.path.join(SERVERS, "%d.json" % port)


def load_server(port=None):
	if port is None:
		current = os.path.join(DATA, "current.json")
		if not os.path.exists(current):
			raise TestkitError("no testkit server started (tk.py start)")
		with open(current) as f:
			port = json.load(f)["port"]
	path = server_file(int(port))
	if not os.path.exists(path):
		raise TestkitError("no testkit server on port %s" % port)
	with open(path) as f:
		info = json.load(f)
	return Server(info["port"], info["key"], info.get("pid"))


def list_servers():
	found = []
	if not os.path.isdir(SERVERS):
		return found
	for name in os.listdir(SERVERS):
		if name.endswith(".json"):
			with open(os.path.join(SERVERS, name)) as f:
				info = json.load(f)
			info["alive"] = pid_alive(info.get("pid"))
			found.append(info)
	return found


def pid_alive(pid):
	if not pid:
		return False
	out = subprocess.run(["tasklist", "/FI", "PID eq %d" % pid, "/NH"], capture_output=True, text=True).stdout
	return str(pid) in out


def port_free(port):
	with socket.socket() as s:
		try:
			s.bind(("0.0.0.0", port))
			return True
		except OSError:
			return False


def clean_env():
	env = dict(os.environ)
	env.pop("__COMPAT_LAYER", None)  # dm.exe leaks two kernel handles a file with it set
	return env


def build(checks=(), name=BUILD_NAME, quiet=False):
	"""hippiestation.dme + the testkit files + the checks asked for -> <name>.dmb. Returns the dmb's path."""
	started = time.time()
	with open(os.path.join(ROOT, "hippiestation.dme"), "rb") as f:
		dme = f.read()
	lines = [b'#include "tools\\testkit\\dm\\%s"\r\n' % f.encode() for f in DM_FILES]
	for check in checks:
		check = check.strip().replace("/", "\\")
		if check:
			lines.append(b'#include "%s"\r\n' % check.encode())
	with open(os.path.join(ROOT, name), "wb") as f:
		f.write(dme + b"".join(lines))
	dmb = os.path.join(ROOT, name + ".dmb")
	if os.path.exists(dmb):
		os.remove(dmb)
	gpu_wait("dm.exe " + name)
	proc = subprocess.run([os.path.join(BYOND_BIN, "dm.exe"), name], cwd=ROOT, capture_output=True, text=True, env=clean_env())
	errors = [l for l in proc.stdout.splitlines() if "error" in l or "warning" in l or "dmb -" in l]
	if not quiet:
		for l in errors[:60]:
			print(l)
	if not os.path.exists(dmb):
		raise TestkitError("build failed:\n" + "\n".join(errors[:60]))
	if not quiet:
		print("built %s in %.0f s" % (name + ".dmb", time.time() - started))
	return dmb


def start(map_name="testbench", port=None, seed=None, speed=None, params="", dmb=None, wait=True, timeout=300):
	dmb = dmb or os.path.join(ROOT, BUILD_NAME + ".dmb")
	if not os.path.exists(dmb):
		raise TestkitError("no %s: tk.py build first" % dmb)
	if port is None:
		port = next((p for p in PORTS if port_free(p) and not os.path.exists(server_file(p))), None) or \
			next((p for p in PORTS if port_free(p)), None)
		if port is None:
			raise TestkitError("no free port in %d-%d" % (PORTS[0], PORTS[-1]))
	elif not port_free(port):
		raise TestkitError("port %d is taken" % port)
	key = secrets.token_hex(12)
	folder = os.path.join(DATA, str(port))
	os.makedirs(folder, exist_ok=True)
	for name in ("ready.txt", "events.jsonl", "commands.jsonl"):
		path = os.path.join(folder, name)
		if os.path.exists(path):
			os.remove(path)
	p = {"testkit": "1", "testkit-key": key, "bot-map": map_name, "log-directory": "testkit_%d" % port}
	if seed is not None:
		p["testkit-seed"] = str(seed)
	if speed is not None:
		p["timewarp"] = str(speed)
	query = urllib.parse.urlencode(p)
	if params:
		query += "&" + params
	gpu_wait("dd.exe port %d" % port)
	log = open(os.path.join(folder, "dd.log"), "w")
	flags = 0x00000008 | 0x00000200  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP: lives on after this script
	proc = subprocess.Popen([os.path.join(BYOND_BIN, "dd.exe"), dmb, str(port), "-trusted", "-invisible", "-params", query],
		cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, env=clean_env(), creationflags=flags)
	os.makedirs(SERVERS, exist_ok=True)
	info = {"port": port, "key": key, "pid": proc.pid, "map": map_name, "dmb": dmb, "started": time.time(), "seed": seed}
	with open(server_file(port), "w") as f:
		json.dump(info, f)
	with open(os.path.join(DATA, "current.json"), "w") as f:
		json.dump({"port": port}, f)
	server = Server(port, key, proc.pid)
	if wait:
		wait_ready(server, timeout)
	return server


def wait_ready(server, timeout=300):
	ready = os.path.join(DATA, str(server.port), "ready.txt")
	deadline = time.time() + timeout
	while time.time() < deadline:
		if os.path.exists(ready):
			return open(ready).read().strip()
		if server.pid and not pid_alive(server.pid):
			raise TestkitError("server exited during boot: see " + os.path.join(DATA, str(server.port), "dd.log"))
		time.sleep(1)
	raise TestkitError("not ready after %d s" % timeout)


def stop(server):
	try:
		with open(server_file(server.port)) as f:
			client = json.load(f).get("client_pid")
		if client and pid_alive(client):  # DreamSeeker never closes by itself when the world goes
			subprocess.run(["taskkill", "/F", "/PID", str(client)], capture_output=True)
	except (OSError, ValueError):
		pass
	try:
		server.raw("shutdown", timeout=5)
	except (OSError, TestkitError, ValueError):
		pass
	for _ in range(20):
		if not pid_alive(server.pid):
			break
		time.sleep(0.5)
	if pid_alive(server.pid):
		subprocess.run(["taskkill", "/F", "/PID", str(server.pid)], capture_output=True)
	if os.path.exists(server_file(server.port)):
		os.remove(server_file(server.port))


def replay(server, path, speed_up=False):
	"""Runs a commands.jsonl again, waiting out the game time between commands (best effort: the scheduler isn't deterministic)."""
	with open(path) as f:
		entries = [json.loads(l) for l in f if l.strip()]
	if not entries:
		return []
	results = []
	base_then = entries[0]["t"]
	base_now = server.call("status")["time"]
	for e in entries:
		a = dict(e["a"])
		cmd = a.pop("cmd")
		if cmd in ("shutdown",):
			continue
		if not speed_up:
			due = base_now + (e["t"] - base_then)
			while server.call("status")["time"] < due:
				time.sleep(0.05)
		try:
			results.append({"cmd": cmd, "result": server.call(cmd, **a)})
		except TestkitError as err:
			results.append({"cmd": cmd, "error": str(err)})
	return results


# ---------------------------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------------------------

def parse_value(text):
	# Git Bash turns an argument like /obj/item into C:/Program Files/Git/obj/item: undone here
	m = re.match(r"^[A-Za-z]:/Program Files/Git(/(?:obj|mob|datum|turf|area|atom|proc|client).*)$", text)
	if m:
		text = m.group(1)
	try:
		return json.loads(text)
	except ValueError:
		return text


def main(argv):
	if not argv or argv[0] in ("-h", "--help"):
		print(__doc__)
		return 0
	opts = {}
	rest = []
	i = 0
	while i < len(argv):
		a = argv[i]
		if a.startswith("--"):
			if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
				opts[a[2:]] = argv[i + 1]
				i += 2
				continue
			opts[a[2:]] = True
		else:
			rest.append(a)
		i += 1
	cmd = rest[0]
	port = int(opts["port"]) if "port" in opts and cmd != "start" else None
	if cmd == "build":
		build([c for c in str(opts.get("checks", "")).split(",") if c])
		return 0
	if cmd == "start":
		s = start(opts.get("map", "testbench"), int(opts["port"]) if "port" in opts else None, opts.get("seed"), opts.get("speed"),
			opts.get("params", ""), wait="no-wait" not in opts)
		print(json.dumps({"port": s.port, "pid": s.pid}))
		return 0
	if cmd == "servers":
		print(json.dumps(list_servers(), indent=1))
		return 0
	server = load_server(port)
	if cmd == "stop":
		stop(server)
		return 0
	if cmd == "replay":
		print(json.dumps(replay(server, rest[1], "fast" in opts), indent=1))
		return 0
	if cmd == "events" and "follow" in opts:
		since = int(opts.get("since", server.call("status")["event_seq"]))
		kinds = opts.get("kinds")
		while True:
			got = server.call("events", since=since, kinds=kinds, limit=500)
			for e in got["events"]:
				print(json.dumps(e))
				since = e["seq"]
			sys.stdout.flush()
			time.sleep(0.5)
	args = {}
	for r in rest[1:]:
		if "=" in r:
			k, v = r.split("=", 1)
			args[k] = parse_value(v)
	for k, v in opts.items():
		if k not in ("port",):
			args[k] = parse_value(v) if isinstance(v, str) else v
	try:
		result = server.call(cmd, **args)
	except TestkitError as err:
		print("error: %s" % err, file=sys.stderr)
		return 1
	print(json.dumps(result, indent=1))
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
