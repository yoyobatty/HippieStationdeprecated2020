#!/usr/bin/env python3
"""A small raw-socket client for the admins' dashboard (tools/dashboard, hippie_dashboard.dll): the bad requests its server must
turn away, and plain requests and the live stream to show it still works. review_smoke.py uses it; it also runs on its own
against any dashboard on this machine.

  python tools/review_smoke/dash_client.py PORT longline          a request line over 8 KB
  python tools/review_smoke/dash_client.py PORT longheader        one header over 8 KB
  python tools/review_smoke/dash_client.py PORT headers           headers over 32 KB in all, each under 8 KB
  python tools/review_smoke/dash_client.py PORT drip [SECONDS]    a header a byte a second, never finished (default 25 s)
  python tools/review_smoke/dash_client.py PORT get PATH [TOKEN]  one GET, with the hd=TOKEN cookie if given
  python tools/review_smoke/dash_client.py PORT stream TOKEN [S]  the /events stream for S seconds (default 10)
  python tools/review_smoke/dash_client.py PORT hold N [HOST]     N unfinished requests at once (to and from HOST if given): how
                                                                many the server holds open and how many it closes

Each prints what came back: the status line, how long it took, and how the connection ended.
"""
import ipaddress
import select
import socket
import sys
import threading
import time

HOST = "127.0.0.1"


def _status_line(data):
	if not data:
		return None
	return data.split(b"\r\n", 1)[0].decode("latin-1", "replace")


def send_raw(port, data, wait=20.0):
	"""Sends `data` at once, then reads until the server closes or `wait` runs out.
	Returns dict(status, elapsed, ended): ended is 'closed' (the server closed it), 'reset', or 'open' (still open at `wait`)."""
	began = time.monotonic()
	s = socket.create_connection((HOST, port), timeout=5)
	got = b""
	ended = "open"
	try:
		try:
			s.sendall(data)
		except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError):
			ended = "reset"
		s.settimeout(0.5)
		while ended == "open" and time.monotonic() - began < wait:
			try:
				chunk = s.recv(65536)
			except socket.timeout:
				continue
			except (ConnectionResetError, ConnectionAbortedError):
				ended = "reset"
				break
			if not chunk:
				ended = "closed"
				break
			got += chunk
	finally:
		s.close()
	return {"status": _status_line(got), "elapsed": round(time.monotonic() - began, 2), "ended": ended, "bytes": len(got)}


def long_line(port):
	return send_raw(port, b"GET /" + b"a" * 9000 + b" HTTP/1.1\r\nHost: x\r\n\r\n")


def long_header(port):
	return send_raw(port, b"GET / HTTP/1.1\r\nHost: x\r\nX-Pad: " + b"a" * 9000 + b"\r\n\r\n")


def many_headers(port):
	"""Five headers of 7000 bytes: each is under the 8 KB line cap, together they're over the 32 KB cap"""
	pad = b"".join(b"X-Pad-%d: " % i + b"a" * 7000 + b"\r\n" for i in range(5))
	return send_raw(port, b"GET / HTTP/1.1\r\nHost: x\r\n" + pad + b"\r\n")


def drip(port, seconds=25.0, every=1.0):
	"""A request line, then a header a byte at a time, never finished. Returns when the server answers or closes, or at `seconds`."""
	began = time.monotonic()
	s = socket.create_connection((HOST, port), timeout=5)
	got = b""
	ended = "open"
	sent = 0
	try:
		s.sendall(b"GET / HTTP/1.1\r\nX-Drip: ")
		next_byte = began + every
		while time.monotonic() - began < seconds:
			readable, _, _ = select.select([s], [], [], max(0.0, min(0.25, next_byte - time.monotonic())))
			if readable:
				try:
					chunk = s.recv(65536)
				except (ConnectionResetError, ConnectionAbortedError):
					ended = "reset"
					break
				if not chunk:
					ended = "closed"
					break
				got += chunk
				continue
			if time.monotonic() >= next_byte:
				try:
					s.sendall(b"a")
					sent += 1
				except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError):
					ended = "reset"
					break
				next_byte += every
	finally:
		s.close()
	return {"status": _status_line(got), "elapsed": round(time.monotonic() - began, 2), "ended": ended, "bytes_dripped": sent}


def get(port, path, token=None, timeout=10.0, host=HOST, source=None):
	"""One GET (to `host`, from the local address `source` if given). Returns dict(code, headers, body); code None if the server
	closed it unanswered."""
	request = "GET %s HTTP/1.1\r\nHost: %s:%d\r\n" % (path, host, port)
	if token:
		request += "Cookie: hd=%s\r\n" % token
	request += "\r\n"
	s = socket.create_connection((host, port), timeout=timeout, source_address=(source, 0) if source else None)
	got = b""
	try:
		s.sendall(request.encode())
		while True:
			try:
				chunk = s.recv(65536)
			except socket.timeout:
				break
			except (ConnectionResetError, ConnectionAbortedError):
				break
			if not chunk:
				break
			got += chunk
	finally:
		s.close()
	head, _, body = got.partition(b"\r\n\r\n")
	lines = head.decode("latin-1", "replace").split("\r\n")
	code = int(lines[0].split()[1]) if lines and len(lines[0].split()) > 1 else None
	headers = {}
	for line in lines[1:]:
		if ":" in line:
			k, v = line.split(":", 1)
			headers.setdefault(k.strip().lower(), []).append(v.strip())
	return {"code": code, "headers": headers, "body": body}


def hold(port, n, host=HOST, source=None, settle=1.5):
	"""`n` connections at once, each with a request that never finishes (as drip() starts it), from the local address `source` if
	given. After `settle` seconds, returns (the sockets the server still holds open, how many it closed). Close the open ones after."""
	held = []
	for _ in range(n):
		try:
			s = socket.create_connection((host, port), timeout=3, source_address=(source, 0) if source else None)
			s.sendall(b"GET / HTTP/1.1\r\nX-Drip: ")
			held.append(s)
		except OSError:
			held.append(None)
	time.sleep(settle)
	still, closed = [], 0
	for s in held:
		if s is None:
			closed += 1
			continue
		readable, _, _ = select.select([s], [], [], 0)
		if readable:
			try:
				data = s.recv(1)
			except (ConnectionResetError, ConnectionAbortedError):
				data = b""
			if not data:
				closed += 1
				s.close()
				continue
		still.append(s)
	return still, closed


def lan_address():
	"""An IPv4 address of this machine's that isn't loopback (a connection from it to the dashboard isn't 'this machine'), or None"""
	try:
		found = [a for a in socket.gethostbyname_ex(socket.gethostname())[2] if not a.startswith("127.")]
	except OSError:
		return None
	private = [a for a in found if ipaddress.ip_address(a).is_private]
	return (private or found or [None])[0]


class Stream(threading.Thread):
	"""The /events stream with the hd=TOKEN cookie, read on a thread: `events` is [(seconds since start, event name)], `ended_at`
	when the server closed it (None while open), `code` the status. stop() closes it from this end."""

	def __init__(self, port, token, limit=120.0):
		super().__init__(daemon=True)
		self.port, self.token, self.limit = port, token, limit
		self.events = []
		self.code = None
		self.ended_at = None
		self.ended = None
		self.started = time.monotonic()
		self._halt = threading.Event()

	def run(self):
		s = socket.create_connection((HOST, self.port), timeout=5)
		s.settimeout(0.25)
		buf = b""
		try:
			s.sendall(("GET /events HTTP/1.1\r\nHost: x\r\nCookie: hd=%s\r\n\r\n" % self.token).encode())
			while not self._halt.is_set() and time.monotonic() - self.started < self.limit:
				try:
					chunk = s.recv(65536)
				except socket.timeout:
					continue
				except (ConnectionResetError, ConnectionAbortedError):
					self.ended, self.ended_at = "reset", time.monotonic() - self.started
					return
				if not chunk:
					self.ended, self.ended_at = "closed", time.monotonic() - self.started
					return
				buf += chunk
				if self.code is None and b"\r\n" in buf:
					parts = buf.split(b"\r\n", 1)[0].split()
					self.code = int(parts[1]) if len(parts) > 1 else -1
				while b"\n\n" in buf:
					block, buf = buf.split(b"\n\n", 1)
					for line in block.split(b"\n"):
						if line.startswith(b"event: "):
							self.events.append((round(time.monotonic() - self.started, 2), line[7:].decode("utf-8", "replace")))
		finally:
			s.close()
		if self.ended is None:
			self.ended = "stopped here" if self._halt.is_set() else "open at the limit"

	def stop(self):
		self._halt.set()
		self.join(2)

	def counts(self):
		out = {}
		for _, name in self.events:
			out[name] = out.get(name, 0) + 1
		return out


def main():
	if len(sys.argv) < 3:
		print(__doc__)
		sys.exit(2)
	port, what = int(sys.argv[1]), sys.argv[2]
	if what == "longline":
		print(long_line(port))
	elif what == "longheader":
		print(long_header(port))
	elif what == "headers":
		print(many_headers(port))
	elif what == "drip":
		print(drip(port, float(sys.argv[3]) if len(sys.argv) > 3 else 25.0))
	elif what == "get":
		answer = get(port, sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
		print(answer["code"], answer["headers"], len(answer["body"]), "bytes")
	elif what == "hold":
		host = sys.argv[4] if len(sys.argv) > 4 else HOST
		still, closed = hold(port, int(sys.argv[3]), host=host, source=host if host != HOST else None)
		print("held open %d, closed %d" % (len(still), closed))
		for s in still:
			s.close()
	elif what == "stream":
		stream = Stream(port, sys.argv[3])
		stream.start()
		stream.join(float(sys.argv[4]) if len(sys.argv) > 4 else 10.0)
		print("code", stream.code, "ended", stream.ended, "at", stream.ended_at, stream.counts())
		stream.stop()
	else:
		print(__doc__)
		sys.exit(2)


if __name__ == "__main__":
	main()
