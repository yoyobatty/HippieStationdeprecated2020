#!/usr/bin/env python3
"""Review smoke tests: checks, in a real headless dd.exe, what the 2026-11-28 backend review fixes claim (commit 5b3f2e7f) for the
dashboard, light textures and the lobby build. Builds its own dmb (review_smoke.mdme: hippiestation.dme + review_smoke.dm), so
hippiestation.dmb is left alone. One dd.exe at a time, on the test map unless a check needs Lavaland, on ports 45530-45539, at
below-normal priority; each server is stopped as soon as its step is done.

  tools/review_smoke/run.sh [STEP ...] [--no-build] [--keep-build]       (or python tools/review_smoke/review_smoke.py ...)

Steps (all of them by default, in this order):
  dash           1a bound to 127.0.0.1 by default (netstat), 1b oversized/slow requests turned away and the server still serves,
                 1c a link streams, deadmin (disassociate()/deactivate()) stops the stream and refuses the link, expiry on an
                 open stream, 1d dashboard_alert()/dashboard_revoke() before SSdashboard initializes
  dash_bind      1a DASHBOARD_BIND_ALL in the config: 0.0.0.0, and the plain-HTTP warning in the log; 1b 32 drips from this
                 machine's LAN address: 4 held (the per-address cap), the rest turned away, 127.0.0.1 still served
  dash_local     1a DASHBOARD_BIND_ALL + DASHBOARD_LOCAL_ONLY: 127.0.0.1 again
  sprites        2a pictures in data/lightmaps/<port>/, 2b the 32 MB budget: falls back, logs, won't turn back on
  sprites2       2a a second server on another port leaves the first one's folder alone (run after sprites)
  sprites_old    2c hippie_lighting.dll from 15a5694b (no texture exports; git show into data/review_smoke/): set_sprites falls
                 back with a log line, no runtime
  lobby_powernets, lobby_ruins, lobby_atom, lobby_maploader, lobby_body, lobby_atoms_off
                 3 a runtime injected part way through a real lobby build (Runtime Station with Lavaland and space ruins): in a
                 stage proc (setup_template_powernets), as the ruins start (seed_startup_ruins), in one atom's Initialize, in the
                 map loader as it loads Lavaland, or in the build's own code; atoms_off: SSatoms left at map_loader_begin()

SPRITES_MAP=hippiestation runs the sprites step on the real station (12 levels: the budget fallback's pass over every turf,
from inside SSlighting's fire, is longest there).

Results: data/review_smoke/results.txt (PASS/FAIL lines with their evidence); each server's logs in data/logs/review_smoke_<step>/.
The dash steps load tools/review_smoke/hippie_dashboard_review.dll if it's there (REVIEW_DASHBOARD_LIB=root for the repo-root
hippie_dashboard.dll, or another path). Needs: BYOND (BYOND_BIN), pefile (for sprites_old), the repo-root DLLs.
"""
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.join(ROOT, "tools", "testkit"))
import dash_client as dc  # noqa: E402
from tk import topic  # noqa: E402  (the testkit's BYOND topic packets)

BYOND_BIN = os.environ.get("BYOND_BIN", r"C:\Program Files (x86)\BYOND\bin")
BUILD = "review_smoke.mdme"
OUT = os.path.join(ROOT, "data", "review_smoke")
BUDGET = 32 * 1024 * 1024
# The dashboard library the dash steps load (dashboard-lib=): REVIEW_DASHBOARD_LIB if set ("root": the repo-root one), else a build of
# tools/dashboard copied here as hippie_dashboard_review.dll, if there is one
DASH_LIB = os.environ.get("REVIEW_DASHBOARD_LIB") or ("tools/review_smoke/hippie_dashboard_review.dll"
	if os.path.exists(os.path.join(HERE, "hippie_dashboard_review.dll")) else "root")


def dash_params():
	return "" if DASH_LIB == "root" else "dashboard-lib=" + DASH_LIB
# The lighting engine from 15a5694b, before the light textures' exports: taken out of git into data/ when it isn't there yet
OLD_DLL_COMMIT = "15a5694b"
OLD_DLL = "data/review_smoke/hippie_lighting_old15a.dll"
LOW = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)
STEPS = ["dash", "dash_bind", "dash_local", "sprites", "sprites2", "sprites_old", "lobby_powernets", "lobby_ruins", "lobby_atom",
	"lobby_maploader", "lobby_body", "lobby_atoms_off"]


class Results:
	def __init__(self):
		self.lines = []
		self.failed = 0
		self.passed = 0

	def check(self, name, ok, evidence=""):
		line = "%s %s%s" % ("PASS" if ok else "FAIL", name, (": " + str(evidence)) if evidence != "" else "")
		if ok:
			self.passed += 1
		else:
			self.failed += 1
		self.add(line)

	def add(self, line):
		print(line, flush=True)
		self.lines.append(line)
		os.makedirs(OUT, exist_ok=True)
		with open(os.path.join(OUT, "results.txt"), "w", encoding="utf-8") as f:
			f.write("\n".join(self.lines) + "\n")


def clean_env():
	env = dict(os.environ)
	env.pop("__COMPAT_LAYER", None)  # dm.exe leaks two kernel handles a file with it set
	return env


def gpu_wait(what):
	subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gpu_share.py"), "wait", "review_smoke " + what], cwd=ROOT)


def build():
	gpu_wait("build")
	with open(os.path.join(ROOT, "hippiestation.dme"), "rb") as f:
		dme = f.read()
	if not dme.endswith(b"\n"):
		dme += b"\r\n"
	with open(os.path.join(ROOT, BUILD), "wb") as f:
		f.write(dme + b'#include "tools\\review_smoke\\review_smoke.dm"\r\n')
	dmb = os.path.join(ROOT, BUILD + ".dmb")
	if os.path.exists(dmb):
		os.remove(dmb)
	print("Compiling %s..." % BUILD, flush=True)
	began = time.time()
	p = subprocess.run([os.path.join(BYOND_BIN, "dm.exe"), BUILD], cwd=ROOT, env=clean_env(), capture_output=True, text=True,
		creationflags=LOW)
	for line in p.stdout.splitlines():
		if re.search(r"error|review_smoke\.dm.*warning|dmb -", line):
			print("  " + line)
	if not os.path.exists(dmb):
		raise SystemExit("Build failed")
	print("Built in %d s" % (time.time() - began), flush=True)


def clean_build():
	for name in os.listdir(ROOT):
		if name.startswith(BUILD):
			try:
				os.remove(os.path.join(ROOT, name))
			except OSError:
				pass


def listening(port):
	"""(local address, pid) of every TCP socket listening on `port` (netstat -ano)"""
	out = subprocess.run(["netstat", "-ano", "-p", "TCP"], capture_output=True, text=True).stdout
	found = []
	for line in out.splitlines():
		parts = line.split()
		if len(parts) >= 5 and parts[0] == "TCP" and parts[3] == "LISTENING" and parts[1].endswith(":%d" % port):
			found.append((parts[1], int(parts[4])))
	return found


def runtimes(text, *files):
	"""Runtime errors in a runtime.log, as one line each (the error and its source file), only those in `files` if given"""
	out = []
	lines = text.splitlines()
	for i, line in enumerate(lines):
		if "runtime error:" not in line:
			continue
		block = " | ".join(l.strip() for l in lines[i:i + 4])
		if not files or any(f in block for f in files):
			out.append(re.sub(r"^\[[^\]]*\]\s*", "", block)[:300])
	return out


class Server:
	def __init__(self, step, port, params="", config_lines=(), map_name="testbench", boot_timeout=300):
		self.step, self.port, self.params, self.config_lines = step, port, params, list(config_lines)
		self.map_name, self.boot_timeout = map_name, boot_timeout
		self.key = secrets.token_hex(8)
		self.proc = None
		self.logs = os.path.join(ROOT, "data", "logs", "review_smoke_" + step)

	def start(self):
		config = os.path.join(OUT, "config_%d" % self.port)
		shutil.rmtree(config, ignore_errors=True)
		shutil.copytree(os.path.join(ROOT, "config"), config)
		path = os.path.join(config, "hippiestation_config.txt")
		with open(path, "rb") as f:
			text = f.read().decode("utf-8", "replace")
		text = re.sub(r"(?m)^BOT_CREW_TARGET .*$", "BOT_CREW_TARGET 0", text)
		text += "\r\n" + "\r\n".join(self.config_lines) + "\r\n"
		with open(path, "wb") as f:
			f.write(text.encode("utf-8"))
		shutil.rmtree(self.logs, ignore_errors=True)
		shutil.rmtree(os.path.join(OUT, str(self.port)), ignore_errors=True)
		params = "review-smoke=1&review-smoke-key=%s&log-directory=review_smoke_%s&config=data/review_smoke/config_%d&bot-map=%s" % (
			self.key, self.step, self.port, self.map_name)
		if self.params:
			params += "&" + self.params
		gpu_wait(self.step)
		console = open(os.path.join(OUT, "%s_console.log" % self.step), "w")
		self.began = time.time()
		self.proc = subprocess.Popen([os.path.join(BYOND_BIN, "dd.exe"), BUILD + ".dmb", str(self.port), "-trusted", "-invisible",
			"-params", params], cwd=ROOT, stdout=console, stderr=subprocess.STDOUT, env=clean_env(), creationflags=LOW)
		self.pid = self.proc.pid
		print("[%s] dd.exe %d booting on port %d (%s)" % (self.step, self.pid, self.port, params.split("&", 2)[-1]), flush=True)
		ready = os.path.join(OUT, str(self.port), "ready.txt")
		while not os.path.exists(ready):
			if self.proc.poll() is not None:
				raise RuntimeError("dd.exe exited while booting (see %s)" % self.logs)
			if time.time() - self.began > self.boot_timeout:
				raise RuntimeError("not ready after %d s" % self.boot_timeout)
			time.sleep(1)
		print("[%s] ready after %d s" % (self.step, time.time() - self.began), flush=True)
		return self

	def cmd(self, command, timeout=120, **args):
		query = "review_smoke=%s&key=%s" % (command, self.key)
		if args:
			query += "&" + urllib.parse.urlencode(args)
		answer = topic(self.port, query, 30)
		began = time.time()
		while isinstance(answer, str) and answer.startswith("pending:"):
			if time.time() - began > timeout:
				raise RuntimeError("%s still pending after %d s" % (command, timeout))
			time.sleep(0.5)
			answer = topic(self.port, "review_smoke=job&key=%s&id=%s" % (self.key, answer[8:]), 30)
		return answer

	def status(self):
		return json.loads(self.cmd("status"))

	def wait_for(self, what, test, timeout):
		began = time.time()
		while time.time() - began < timeout:
			st = self.status()
			if test(st):
				return st
			if self.proc.poll() is not None:
				raise RuntimeError("dd.exe exited waiting for %s" % what)
			time.sleep(1)
		return None

	def log(self, name="runtime.log"):
		try:
			with open(os.path.join(self.logs, name), encoding="utf-8", errors="replace") as f:
				return f.read()
		except OSError:
			return ""

	def grep(self, pattern, name="runtime.log"):
		return [re.sub(r"^\[[^\]]*\]\s*", "", l) for l in self.log(name).splitlines() if re.search(pattern, l)]

	def alive(self):
		return self.proc is not None and self.proc.poll() is None

	def stop(self):
		if self.proc and self.proc.poll() is None:
			self.proc.kill()
			try:
				self.proc.wait(15)
			except subprocess.TimeoutExpired:
				pass
		print("[%s] stopped" % self.step, flush=True)


# ---------------------------------------------------------------------------------------------
# 1. The dashboard
# ---------------------------------------------------------------------------------------------

def refused(r):
	"""A bad request turned away: a 400, or the connection closed with nothing served"""
	return (r["status"] or "").startswith("HTTP/1.1 400") or (r["status"] is None and r["ended"] in ("closed", "reset"))


def still_serves(web, token):
	link = dc.get(web, "/?t=" + token)
	page = dc.get(web, "/", token)
	ok = link["code"] == 303 and any(("hd=" + token) in c for c in link["headers"].get("set-cookie", [])) and page["code"] == 200 \
		and len(page["body"]) > 1000
	return ok, "link %s, page %s (%d bytes)" % (link["code"], page["code"], len(page["body"]))


def step_dash(R):
	web = 45531
	S = Server("dash", 45530, params=dash_params(), config_lines=["DASHBOARD_PORT %d" % web]).start()
	try:
		st = S.status()
		R.add("-- dash: %s, library %s" % (st["dash_status"], st["dash_lib"]))
		where = listening(web)
		R.check("1a default: listening on 127.0.0.1 only", where == [("127.0.0.1:%d" % web, S.pid)],
			"netstat %s (dd pid %d); status '%s'" % (where, S.pid, st["dash_status"]))

		# 1d: before SSdashboard was up
		early = st["early_calls"]
		R.check("1d dashboard_alert()/dashboard_revoke() before SSdashboard initializes: no runtime",
			len(early) == 3 and all(": ok" in e for e in early) and not runtimes(S.log(), "dashboard.dm"), "; ".join(early))
		snap_token = S.cmd("token", name="reviewsnap", secs="600")
		snap = json.loads(dc.get(web, "/snapshot", snap_token)["body"] or b"{}")
		alerts = [json.loads(a)["m"] if isinstance(a, str) else a.get("m", "") for a in snap.get("alerts", [])]
		early_sent = [a for a in alerts if "review_smoke early alert" in a]
		R.check("1d nothing reached the library before it started (only the call after Initialize is in the feed)",
			early_sent == ["review_smoke early alert: after SSdashboard's Initialize (%s)" % st["dash_status"]], early_sent)

		# 1b: bad requests
		token = S.cmd("token", name="reviewcheck", secs="3600")
		for name, fn in (("request line over 8 KB", dc.long_line), ("one header over 8 KB", dc.long_header),
				("headers over 32 KB in all", dc.many_headers)):
			r = fn(web)
			fav = dc.get(web, "/favicon.ico")
			R.check("1b %s refused, server still answers" % name, refused(r) and fav["code"] == 204 and S.alive(),
				"%s; next request %s" % (r, fav["code"]))
		r = dc.drip(web, 25.0)
		R.check("1b slow drip cut off at 15 s", refused(r) and 14.5 <= r["elapsed"] <= 17.5, r)
		ok, how = still_serves(web, token)
		R.check("1b after all that, a normal request is served", ok and S.alive() and S.status()["dash_status"].startswith("on"), how)

		# 1c: a link streams; deadmin stops it and refuses the link; expiry
		R.add("-- %s" % S.cmd("admin", name="reviewadmin", owner="1"))
		R.add("-- %s" % S.cmd("admin", name="reviewadmin2"))
		R.add("-- %s" % S.cmd("admin", name="reviewadmin3", owner="1"))
		t1 = S.cmd("token", name="reviewadmin", secs="3600")
		t2 = S.cmd("token", name="reviewadmin2", secs="3600")
		t3 = S.cmd("token", name="reviewadmin3", secs="3600")
		link = dc.get(web, "/?t=" + t1)
		s1, s2, s3 = dc.Stream(web, t1), dc.Stream(web, t2), dc.Stream(web, t3)
		for s in (s1, s2, s3):
			s.start()
		time.sleep(5)
		c1 = s1.counts()
		R.check("1c an admin's link streams", link["code"] == 303 and s1.code == 200 and c1.get("hello") == 1 and c1.get("map_live", 0) >= 4
			and s1.ended is None, "link %s, stream %s, 5 s: %s" % (link["code"], s1.code, c1))
		S.cmd("alert", text="review_smoke alert while streaming")
		time.sleep(1.5)
		R.check("1c an alert reaches the open stream", s1.counts().get("alert", 0) > c1.get("alert", 0), s1.counts())

		t_off = time.monotonic() - s1.started
		R.add("-- %s" % S.cmd("disassociate", name="reviewadmin"))
		time.sleep(3)
		after = [dc.get(web, "/?t=" + t1)["code"], dc.get(web, "/", t1)["code"], dc.get(web, "/events", t1)["code"]]
		R.check("1c disassociate(): the open stream stops", s1.ended == "closed" and s1.ended_at - t_off < 2.0,
			"deadminned at %.2f s, stream %s at %s" % (t_off, s1.ended, s1.ended_at))
		R.check("1c disassociate(): the link, page and stream are refused after", after == [403, 403, 403], after)
		taken = S.grep(r"reviewadmin's dashboard links \(\d+\) were taken back", "game.log")
		R.check("1c the revoke is logged", len(taken) >= 1, taken)

		t_off2 = time.monotonic() - s2.started
		R.add("-- %s" % S.cmd("deactivate", name="reviewadmin2"))
		time.sleep(3)
		after2 = [dc.get(web, "/?t=" + t2)["code"], dc.get(web, "/events", t2)["code"]]
		R.check("1c deactivate() of an admin who isn't here: stream stops, link refused",
			s2.ended == "closed" and s2.ended_at - t_off2 < 2.0 and after2 == [403, 403],
			"deadminned at %.2f s, stream %s at %s, after %s" % (t_off2, s2.ended, s2.ended_at, after2))
		R.check("1c another admin's stream carries on", s3.ended is None and s3.counts().get("map_live", 0) > c1.get("map_live", 0),
			s3.counts())
		s3.stop()

		made = time.monotonic()
		t4 = S.cmd("token", name="reviewexpiry", secs="5")
		s4 = dc.Stream(web, t4)
		s4.start()
		s4.join(15)
		closed_after = (s4.started + s4.ended_at - made) if s4.ended_at is not None else None
		c4 = s4.counts()
		R.check("1c expiry is enforced on an open stream (5 s token)", s4.code == 200 and c4.get("map_live", 0) >= 2 and s4.ended == "closed"
			and closed_after is not None and 3.5 <= closed_after <= 7.0,
			"stream %s, %s, closed %s s after the token was made" % (s4.code, c4, closed_after and round(closed_after, 2)))
		R.check("1c an expired link is refused", dc.get(web, "/?t=" + t4)["code"] == 403)
		R.check("1 no runtimes in dashboard.dm", not runtimes(S.log(), "dashboard.dm"), runtimes(S.log(), "dashboard.dm")[:3])
		R.check("1 dd.exe still up after it all", S.alive())
	finally:
		S.stop()


def step_dash_bind(R, local_only=False):
	web = 45537
	lines = ["DASHBOARD_PORT %d" % web, "DASHBOARD_BIND_ALL"] + (["DASHBOARD_LOCAL_ONLY"] if local_only else [])
	S = Server("dash_local" if local_only else "dash_bind", 45536, params=dash_params(), config_lines=lines).start()
	try:
		st = S.status()
		where = listening(web)
		warning = S.grep(r"Dashboard WARNING: listening on every address")
		if local_only:
			R.check("1a DASHBOARD_BIND_ALL + DASHBOARD_LOCAL_ONLY: 127.0.0.1 only", where == [("127.0.0.1:%d" % web, S.pid)] and not warning,
				"netstat %s; status '%s'" % (where, st["dash_status"]))
		else:
			R.check("1a DASHBOARD_BIND_ALL: listening on 0.0.0.0", where == [("0.0.0.0:%d" % web, S.pid)],
				"netstat %s; status '%s'" % (where, st["dash_status"]))
			R.check("1a DASHBOARD_BIND_ALL with no https DASHBOARD_URL: warned in the log", len(warning) == 1, warning[:1])
			step_dash_lockout(R, S, web)
	finally:
		S.stop()


def step_dash_lockout(R, S, web):
	"""1b with DASHBOARD_BIND_ALL: 32 unfinished requests from one address that isn't this machine. Past the per-address cap they're
	turned away, and this machine is still served meanwhile; once they're gone, that address gets in again."""
	lan = dc.lan_address()
	if not lan:
		R.check("1b lockout: a non-loopback address of this machine's to test from", False, "none found")
		return
	token = S.cmd("token", name="reviewlockout", secs="600")
	still, closed = dc.hold(web, 32, host=lan, source=lan)
	try:
		fav = dc.get(web, "/favicon.ico")
		ok, how = still_serves(web, token)
		lan_more = dc.get(web, "/favicon.ico", host=lan, source=lan, timeout=3)
	finally:
		for s in still:
			s.close()
	R.check("1b 32 drips from %s: only 4 held, the rest turned away" % lan, len(still) == 4 and closed == 28,
		"held %d, closed %d; one more from there: %s (library %s)" % (len(still), closed, lan_more["code"], S.status()["dash_lib"]))
	R.check("1b during those drips this machine (127.0.0.1) is still served", fav["code"] == 204 and ok, "favicon %s; %s" % (fav["code"], how))
	time.sleep(1)
	after = dc.get(web, "/favicon.ico", host=lan, source=lan)
	R.check("1b once they're gone that address gets in again", after["code"] == 204, after["code"])


# ---------------------------------------------------------------------------------------------
# 2. Light textures
# ---------------------------------------------------------------------------------------------

def folder(port):
	path = os.path.join(ROOT, "data", "lightmaps", str(port))
	if not os.path.isdir(path):
		return {}
	return {n: os.path.getmtime(os.path.join(path, n)) for n in os.listdir(path)}


def queued(answer):
	"""Lighting objects queued for a redraw right after a sprites command (its answer says)"""
	m = re.search(r"lighting objects queued (\d+)", answer or "")
	return int(m.group(1)) if m else 10 ** 9


def step_sprites(R):
	port = 45532
	root_before = set(os.listdir(os.path.join(ROOT, "data", "lightmaps"))) if os.path.isdir(os.path.join(ROOT, "data", "lightmaps")) else set()
	S = Server("sprites", port, params="lighting-render=sprites&review-start-round=1", map_name=os.environ.get("SPRITES_MAP", "testbench"),
		boot_timeout=600).start()
	try:
		st = S.wait_for("pictures", lambda s: s["round_started_at"] and s["lightmaps_loaded"] > 0, 180)
		files = folder(port)
		pngs = [n for n in files if n.endswith(".png")]
		root_new = [n for n in os.listdir(os.path.join(ROOT, "data", "lightmaps")) if n not in root_before and n != str(port)]
		on = S.grep(r"Lighting: drawn with light textures")
		R.check("2a pictures go to data/lightmaps/%d/" % port, st is not None and st["sprites"] == 1 and len(pngs) > 0 and not root_new,
			"%d PNGs there, %s loaded, nothing new in data/lightmaps/ itself (%s); %s" % (len(pngs), st and st["lightmaps_loaded"], root_new, on[:1]))

		objects = json.loads(S.cmd("objects"))
		R.add("-- while drawn with light textures: %s" % objects)
		fired = S.status()["lighting_fired"]
		R.add("-- budget: %s" % S.cmd("budget", bytes=str(BUDGET - 2048)))
		R.add("-- %s" % S.cmd("lights", n="6"))
		st = S.wait_for("the budget fallback", lambda s: s["sprites"] == 0, 60)
		spent = S.grep(r"light textures loaded \d+ MB of pictures, their budget for this round")
		objects = json.loads(S.cmd("objects"))
		R.check("2b past the 32 MB budget it falls back to lighting objects and logs it",
			st is not None and st["sprite_kind"] == 0 and spent and objects["on_turf"] == objects["with_object"] > 0,
			"%s; bytes %s; lighting objects on their turfs %s" % (spent[:1], st and st["lightmap_bytes"], objects))
		time.sleep(3) # the fallback's redraw of every lighting object done
		again = S.cmd("sprites", kind="1")
		st = S.status()
		refusal = S.grep(r"Lighting: the light textures' budget for this round is spent")
		objects = json.loads(S.cmd("objects"))
		R.check("2b and refuses to turn back on that round", "budget for this round is spent" in again and st["sprites"] == 0
			and st["sprite_kind"] == 0 and refusal and objects["on_turf"] == objects["with_object"], "set_sprites(1): %s; %s" % (again, refusal[:1]))
		R.check("2b the refusal leaves the lighting objects alone (none requeued)", queued(again) < 50, "%s queued of %d" % (
			queued(again), objects["with_object"]))
		st2 = S.status()
		R.check("2b lighting still fires after the fallback", st2["lighting_fired"] > fired and st2["lighting_can_fire"] == 1,
			"times_fired %d -> %d" % (fired, st2["lighting_fired"]))
		bad = runtimes(S.log(), "light_sprites.dm", "lighting")
		R.check("2 no lighting runtimes", not bad, bad[:3])
		mc = S.grep(r"(?i)^MC[: ].*Lighting|Lighting.*(slept|sleeping|gave up)|MC watchdog")
		R.check("2b the fallback (run from inside SSlighting's fire) doesn't upset the MC", not mc, mc[:3])
	finally:
		S.stop()


def step_sprites2(R):
	first, second = 45532, 45533
	before = folder(first)
	if not before:
		R.check("2a second server: the first one's folder is there to check", False, "run the sprites step first")
		return
	os.makedirs(os.path.join(ROOT, "data", "lightmaps", str(second)), exist_ok=True)
	sentinel = os.path.join(ROOT, "data", "lightmaps", str(second), "review_sentinel.png")
	with open(sentinel, "wb") as f:
		f.write(b"left from before")
	S = Server("sprites2", second, params="lighting-render=sprites&review-start-round=1").start()
	try:
		st = S.wait_for("pictures", lambda s: s["round_started_at"] and s["lightmaps_loaded"] > 0, 180)
		after = folder(first)
		mine = [n for n in folder(second) if n.endswith(".png")]
		R.check("2a a second server on port %d leaves port %d's folder alone" % (second, first), after == before and st is not None,
			"%d files before and after, unchanged %s" % (len(before), after == before))
		R.check("2a and empties and fills only its own", not os.path.exists(sentinel) and len(mine) > 0,
			"sentinel gone %s, %d PNGs in data/lightmaps/%d" % (not os.path.exists(sentinel), len(mine), second))
	finally:
		S.stop()


def step_sprites_old(R):
	if not os.path.exists(os.path.join(ROOT, OLD_DLL)):
		os.makedirs(os.path.dirname(os.path.join(ROOT, OLD_DLL)), exist_ok=True)
		with open(os.path.join(ROOT, OLD_DLL), "wb") as f:
			f.write(subprocess.run(["git", "show", OLD_DLL_COMMIT + ":hippie_lighting.dll"], cwd=ROOT, capture_output=True, check=True).stdout)
	try:
		import dll_exports
		missing = {"lighting_textures", "lighting_texture_take"} - dll_exports.exports(os.path.join(ROOT, OLD_DLL))
		R.add("-- %s lacks %s" % (OLD_DLL, sorted(missing)))
	except Exception as e:  # pefile missing: the boot still tells
		R.add("-- couldn't read %s's exports: %r" % (OLD_DLL, e))
	S = Server("sprites_old", 45534, params="lighting-lib=%s&lighting-render=sprites&review-start-round=1" % OLD_DLL).start()
	try:
		st = S.wait_for("the round", lambda s: s["round_started_at"], 180)
		fell = S.grep(r"Lighting: the engine can't draw light textures")
		objects = json.loads(S.cmd("objects"))
		bad = runtimes(S.log(), "light_sprites.dm")
		R.check("2c old DLL: set_sprites at startup falls back with a log line, no runtime",
			st is not None and st["lighting_native"] == 1 and st["sprites"] == 0 and fell and not bad
			and objects["on_turf"] == objects["with_object"] > 0,
			"engine '%s' (%s); %s; runtimes %s; objects %s" % (st and st["lighting_status"], st and st["lighting_lib"], fell[:1], bad[:2], objects))
		again = S.cmd("sprites", kind="1")
		bad = runtimes(S.log(), "light_sprites.dm")
		R.check("2c old DLL: set_sprites(1) in the round falls back too, nothing requeued", "can't draw light textures" in again and not bad
			and S.status()["sprites"] == 0 and queued(again) < 50, again)
	finally:
		S.stop()


# ---------------------------------------------------------------------------------------------
# 3. A lobby build that fails part way
# ---------------------------------------------------------------------------------------------

def step_lobby(R, where):
	S = Server("lobby_" + where, 45535, params="review-start-round=1&review-lobby-crash=" + where, map_name="runtimestation",
		boot_timeout=600).start()
	try:
		st = S.wait_for("the round", lambda s: s["round_started_at"], 240)
		if st is None:
			st = S.status()
		fired = st["air_fired"]
		waited = time.time()
		st2 = S.wait_for("SSair to fire", lambda s: s["air_fired"] > fired + 2, 60) or S.status()
		waited = time.time() - waited
		failed_log = S.grep(r"Lobby build failed|Lobby build: \d+ runtime error")
		build_log = S.grep(r"Lobby build: done|REVIEW_SMOKE: lobby_build\(\) returned")
		injected = runtimes(S.log(), "review_smoke")
		msgs = [m for m in st2["admin_msgs"] if "Lobby build" in m]
		spawn = json.loads(S.cmd("spawn_check"))
		R.add("-- lobby_%s: crashed %s, status '%s', escape pod docks still waiting %s; %s; %s" % (where, st2["crashed"], st2["lobby_status"],
			st2["docks_waiting"], build_log, injected[:1]))
		atoms_back = S.grep(r"Lobby build: SSatoms was left at")
		if where == "atoms_off":
			R.check("3 [%s] SSatoms put back, and logged" % where, st2["crashed"] and bool(atoms_back), atoms_back[:1])
		else:
			R.check("3 [%s] the error is logged and admins are messaged" % where, st2["crashed"] and bool(failed_log) and bool(msgs),
				"log %s; admins %s" % (failed_log[:1], msgs[:1]))
		held = json.loads(S.cmd("held_check", timeout=300))
		R.check("3 [%s] Lavaland and the ruin levels still set up: things initialized, open turfs have air" % where,
			held["uninitialized"] <= 1 and held["open_no_air"] == 0, held)
		R.check("3 [%s] air and lighting can fire again, busy/holding/loading cleared, tick limit back" % where,
			st2["air_can_fire"] == 1 and st2["lighting_can_fire"] == 1 and st2["lobby_busy"] == 0 and st2["lobby_loading"] == 0
			and st2["lobby_holding"] == 0 and not st2["lobby_levels_held"] and st2["build_ticklimit"] == 0,
			{k: st2[k] for k in ("air_can_fire", "lighting_can_fire", "lobby_busy", "lobby_loading", "lobby_holding", "lobby_levels_held", "build_ticklimit")})
		R.check("3 [%s] the round starts and SSair fires" % where, st2["ticker_state"] == 3 and st2["air_fired"] > fired + 2 and waited < 30,
			"ticker state %s, SSair times_fired %s -> %s in %.0f s (part %s, %s turfs to rebuild, %s active)" % (st2["ticker_state"], fired,
			st2["air_fired"], waited, st2["air_part"], st2["air_rebuild"], st2["air_active"]))
		R.check("3 [%s] SSatoms is left as a round needs it: new things initialize, not as mapload" % where,
			st2["atoms_initialized"] == 1 and spawn["initialized_flag"] and spawn["atoms_initialized"] == 1,
			"SSatoms.initialized %s (1 = INNEW_REGULAR, 2 = INNEW_MAPLOAD), after the build %s; a crowbar made now: %s" % (
				st2["atoms_initialized"], st2["atoms_state_after_build"], spawn))
		other = [r for r in runtimes(S.log()) if "review_smoke" not in r]
		R.check("3 [%s] no other runtimes (things on the levels left half made, e.g. canisters with no air)" % where, not other,
			"%d, first: %s" % (len(other), other[:1]))
	finally:
		S.stop()


def main():
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	flags = [a for a in sys.argv[1:] if a.startswith("--")]
	steps = args or STEPS
	unknown = [s for s in steps if s not in STEPS]
	if unknown:
		raise SystemExit("unknown steps %s; steps are %s" % (unknown, " ".join(STEPS)))
	os.makedirs(OUT, exist_ok=True)
	if "--no-build" not in flags or not os.path.exists(os.path.join(ROOT, BUILD + ".dmb")):
		build()
	R = Results()
	R.add("review_smoke %s, steps %s" % (time.strftime("%Y-%m-%d %H:%M"), " ".join(steps)))
	try:
		for step in steps:
			began = time.time()
			try:
				if step == "dash":
					step_dash(R)
				elif step == "dash_bind":
					step_dash_bind(R)
				elif step == "dash_local":
					step_dash_bind(R, local_only=True)
				elif step == "sprites":
					step_sprites(R)
				elif step == "sprites2":
					step_sprites2(R)
				elif step == "sprites_old":
					step_sprites_old(R)
				elif step.startswith("lobby_"):
					step_lobby(R, step[6:])
			except Exception as e:
				R.check("%s ran to the end" % step, False, repr(e))
			print("[%s] took %d s" % (step, time.time() - began), flush=True)
	finally:
		if "--keep-build" not in flags:
			clean_build()
	R.add("%d passed, %d failed" % (R.passed, R.failed))
	return 1 if R.failed else 0


if __name__ == "__main__":
	sys.exit(main())
