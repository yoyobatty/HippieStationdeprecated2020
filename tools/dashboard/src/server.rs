//! The HTTP side: one thread listening, one for each connection. Four things to ask for: / (the page, once the link's token is
//! in a cookie), /events (the live stream: Server-Sent Events, which every browser takes as it comes), /snapshot (everything kept,
//! once, as one JSON object: for pictures, where an open stream never lets a headless browser finish) and /favicon.ico (nothing).
//! The link an admin gets is /?t=<token>: that sets the cookie and sends them on to /, so the token isn't left in the address bar.

use crate::{frame, lock, now};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc::{channel, RecvTimeoutError};
use std::time::Duration;

const PAGE: &str = include_str!("page.html");
const DENIED: &str = "<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width\"><title>Dashboard</title>\
<body style=\"background:#0f1216;color:#c9d1d9;font:15px system-ui,sans-serif;padding:24px\"><h1 style=\"font-size:18px\">Dashboard</h1>\
<p>This link has run out or isn't valid. Make a new one in game: <b>Admin &gt; Dashboard Link</b>.</p>";
/// More than this many open at once and new ones are turned away
const MAX_CONNECTIONS: usize = 32;
static OPEN: AtomicUsize = AtomicUsize::new(0);

pub fn start(port: u16, all: bool) -> Result<(), String> {
	let address = if all { format!("0.0.0.0:{port}") } else { format!("127.0.0.1:{port}") };
	let listener = TcpListener::bind(&address).map_err(|e| format!("can't listen on {address}: {e}"))?;
	std::thread::Builder::new()
		.name("hippie_dashboard".into())
		.spawn(move || {
			for stream in listener.incoming() {
				let Ok(stream) = stream else {
					continue;
				};
				if OPEN.load(Ordering::Relaxed) >= MAX_CONNECTIONS {
					continue; // dropped: closed
				}
				OPEN.fetch_add(1, Ordering::Relaxed);
				let spawned = std::thread::Builder::new().name("hippie_dashboard_page".into()).spawn(move || {
					let _ = catch_unwind(AssertUnwindSafe(|| handle(stream)));
					OPEN.fetch_sub(1, Ordering::Relaxed);
				});
				if spawned.is_err() {
					OPEN.fetch_sub(1, Ordering::Relaxed);
				}
			}
		})
		.map_err(|e| e.to_string())?;
	Ok(())
}

struct Request {
	path: String,
	query: HashMap<String, String>,
	cookie_token: Option<String>,
}

fn read_request(stream: &TcpStream) -> Option<Request> {
	stream.set_read_timeout(Some(Duration::from_secs(10))).ok()?;
	let mut reader = BufReader::new(stream);
	let mut line = String::new();
	reader.read_line(&mut line).ok()?;
	let mut parts = line.split_whitespace();
	if parts.next()? != "GET" {
		return None;
	}
	let target = parts.next()?.to_string();
	let mut cookie_token = None;
	for _ in 0..100 {
		let mut header = String::new();
		if reader.read_line(&mut header).ok()? == 0 {
			break;
		}
		let header = header.trim_end();
		if header.is_empty() {
			break;
		}
		if let Some((name, value)) = header.split_once(':') {
			if name.trim().eq_ignore_ascii_case("cookie") {
				for cookie in value.split(';') {
					if let Some(("hd", token)) = cookie.trim().split_once('=') {
						cookie_token = Some(token.to_string());
					}
				}
			}
		}
	}
	let (path, query_text) = target.split_once('?').unwrap_or((target.as_str(), ""));
	let query = query_text.split('&').filter_map(|pair| pair.split_once('=')).map(|(k, v)| (k.to_string(), v.to_string())).collect();
	Some(Request { path: path.to_string(), query, cookie_token })
}

/// The admin a token belongs to, and when it runs out, if it's good
fn valid(token: &str) -> Option<(String, u64)> {
	let shared = lock();
	let at = now();
	shared.tokens.get(token).filter(|t| t.expires > at).map(|t| (t.name.clone(), t.expires))
}

fn respond(stream: &mut TcpStream, status: &str, kind: &str, headers: &[&str], body: &str) {
	let mut text = format!(
		"HTTP/1.1 {status}\r\nContent-Type: {kind}\r\nContent-Length: {}\r\nConnection: close\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\n",
		body.len()
	);
	for header in headers {
		text.push_str(header);
		text.push_str("\r\n");
	}
	text.push_str("\r\n");
	text.push_str(body);
	let _ = stream.write_all(text.as_bytes());
}

fn handle(mut stream: TcpStream) {
	let _ = stream.set_write_timeout(Some(Duration::from_secs(10)));
	let Some(request) = read_request(&stream) else {
		respond(&mut stream, "400 Bad Request", "text/plain", &[], "Bad request");
		return;
	};
	match request.path.as_str() {
		"/" => {
			if let Some(token) = request.query.get("t") {
				match valid(token) {
					Some((_, expires)) => {
						let cookie = format!("Set-Cookie: hd={token}; Max-Age={}; HttpOnly; SameSite=Strict; Path=/", expires.saturating_sub(now()));
						respond(&mut stream, "303 See Other", "text/plain", &[&cookie, "Location: /"], "");
					}
					None => respond(&mut stream, "403 Forbidden", "text/html; charset=utf-8", &[], DENIED),
				}
				return;
			}
			if request.cookie_token.as_deref().and_then(valid).is_some() {
				respond(&mut stream, "200 OK", "text/html; charset=utf-8", &["Cache-Control: no-store"], PAGE);
			} else {
				respond(&mut stream, "403 Forbidden", "text/html; charset=utf-8", &[], DENIED);
			}
		}
		"/events" => match request.cookie_token.as_deref().and_then(valid) {
			Some((name, expires)) => stream_events(stream, name, expires),
			None => respond(&mut stream, "403 Forbidden", "text/plain", &[], "Not logged in"),
		},
		"/snapshot" => match request.cookie_token.as_deref().and_then(valid) {
			Some((name, expires)) => {
				let body = snapshot(&name, expires);
				respond(&mut stream, "200 OK", "application/json", &["Cache-Control: no-store"], &body);
			}
			None => respond(&mut stream, "403 Forbidden", "text/plain", &[], "Not logged in"),
		},
		"/favicon.ico" => respond(&mut stream, "204 No Content", "text/plain", &[], ""),
		_ => respond(&mut stream, "404 Not Found", "text/plain", &[], "Not found"),
	}
}

pub fn json_string(text: &str) -> String {
	let mut out = String::with_capacity(text.len() + 2);
	out.push('"');
	for c in text.chars() {
		match c {
			'"' => out.push_str("\\\""),
			'\\' => out.push_str("\\\\"),
			'\n' => out.push_str("\\n"),
			c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
			c => out.push(c),
		}
	}
	out.push('"');
	out
}

/// Everything kept, as {"hello": ..., "<channel>": <its JSON>, ..., "alerts": [...]}
fn snapshot(name: &str, expires: u64) -> String {
	crate::LAST_SNAPSHOT.store(now(), std::sync::atomic::Ordering::Relaxed);
	let shared = lock();
	let mut out = format!("{{\"hello\":{{\"name\":{},\"expires\":{expires}}}", json_string(name));
	for (channel, json) in shared.latest.iter() {
		out.push(',');
		out.push_str(&json_string(channel));
		out.push(':');
		out.push_str(json);
	}
	out.push_str(",\"alerts\":[");
	for (i, alert) in shared.alerts.iter().enumerate() {
		if i > 0 {
			out.push(',');
		}
		out.push_str(alert);
	}
	out.push_str("]}");
	out
}

/// The live stream: everything kept so far first (the station's walls before anything that moves on them), then whatever DM sends,
/// with a comment line every 15 seconds so a page that's gone is noticed. Ends when the token runs out.
fn stream_events(mut stream: TcpStream, name: String, expires: u64) {
	let (sender, receiver) = channel::<String>();
	let mut first = frame("hello", &format!("{{\"name\":{},\"expires\":{expires}}}", json_string(&name)));
	{
		let mut shared = lock();
		if let Some(json) = shared.latest.get("map_static") {
			first.push_str(&frame("map_static", json));
		}
		for (channel, json) in shared.latest.iter() {
			if channel != "map_static" {
				first.push_str(&frame(channel, json));
			}
		}
		for alert in shared.alerts.iter() {
			first.push_str(&frame("alert", alert));
		}
		shared.clients.push(sender);
	}
	let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: keep-alive\r\nX-Accel-Buffering: no\r\n\r\n";
	if stream.write_all(headers.as_bytes()).is_err() || stream.write_all(first.as_bytes()).is_err() {
		return;
	}
	loop {
		match receiver.recv_timeout(Duration::from_secs(15)) {
			Ok(text) => {
				if stream.write_all(text.as_bytes()).is_err() {
					return;
				}
			}
			Err(RecvTimeoutError::Timeout) => {
				if now() > expires || stream.write_all(b": ping\n\n").is_err() {
					return;
				}
			}
			Err(RecvTimeoutError::Disconnected) => return,
		}
	}
}
