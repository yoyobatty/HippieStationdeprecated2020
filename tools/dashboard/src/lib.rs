//! The admins' live dashboard (the user's rulings, 2026-11-09): a web page any browser can open, a phone too, served from inside the
//! game's process on its own port, fed by DM a few times a second; admins only, through a personal link an in-game verb makes; read
//! only. hippiestation/code/modules/admin/dashboard.dm is the DM side.
//!
//! DM talks to it through classic call_ext() calls, every argument and answer a string (it's all JSON):
//!   dashboard_start(port, bind)        -> "ok" or "error: ..."    bind "all" for every address, otherwise this machine only
//!   dashboard_token(name, seconds)     -> a new token for that admin, good for that long
//!   dashboard_push(channel, json)      -> "ok"                    the latest of a kind ("health", "map_static"...): kept, sent on
//!   dashboard_event(json)              -> "ok"                    one for the alerts feed: the last few hundred kept
//!   dashboard_clients()                -> how many pages are open, so DM only builds what somebody's looking at
//! The server runs on its own thread and never calls into BYOND; a world reboot keeps it running (the library stays loaded).

use std::cell::RefCell;
use std::collections::hash_map::RandomState;
use std::collections::{HashMap, VecDeque};
use std::ffi::{CStr, CString};
use std::hash::{BuildHasher, Hasher};
use std::os::raw::{c_char, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

pub mod server;

/// What the alerts feed keeps for a page that opens later
pub const ALERTS_KEPT: usize = 300;

pub struct Token {
	pub name: String,
	pub expires: u64,
}

#[derive(Default)]
pub struct Shared {
	pub tokens: HashMap<String, Token>,
	/// channel -> the latest JSON of it
	pub latest: HashMap<String, String>,
	pub alerts: VecDeque<String>,
	/// one per open page: the event stream frames go down it
	pub clients: Vec<Sender<String>>,
	pub port: u16,
	pub running: bool,
}

/// When somebody last asked for a snapshot (unix seconds): that counts as a page open for half a minute, so DM builds what it shows
pub static LAST_SNAPSHOT: AtomicU64 = AtomicU64::new(0);

pub fn shared() -> &'static Mutex<Shared> {
	static SHARED: OnceLock<Mutex<Shared>> = OnceLock::new();
	SHARED.get_or_init(|| Mutex::new(Shared::default()))
}

pub fn lock() -> std::sync::MutexGuard<'static, Shared> {
	shared().lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

pub fn now() -> u64 {
	SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// One event stream frame
pub fn frame(event: &str, data: &str) -> String {
	let mut out = String::with_capacity(data.len() + event.len() + 16);
	out.push_str("event: ");
	out.push_str(event);
	out.push('\n');
	for line in data.split('\n') {
		out.push_str("data: ");
		out.push_str(line);
		out.push('\n');
	}
	out.push('\n');
	out
}

/// Sends a frame to every open page, and forgets the ones that have closed
pub fn broadcast(shared: &mut Shared, text: String) {
	shared.clients.retain(|client| client.send(text.clone()).is_ok());
}

/// 128 bits from std's hasher seeds, which come from the operating system's randomness, mixed with the time
fn new_token() -> String {
	let mut out = String::with_capacity(32);
	for _ in 0..2 {
		let mut hasher = RandomState::new().build_hasher();
		hasher.write_u128(SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0));
		out.push_str(&format!("{:016x}", hasher.finish()));
	}
	out
}

thread_local! {
	static ANSWER: RefCell<CString> = RefCell::new(CString::default());
}

fn answer(text: String) -> *const c_char {
	ANSWER.with(|cell| {
		*cell.borrow_mut() = CString::new(text.replace('\0', "")).unwrap_or_default();
		cell.borrow().as_ptr()
	})
}

unsafe fn arguments(argc: c_int, argv: *const *const c_char) -> Vec<String> {
	if argv.is_null() || argc <= 0 {
		return Vec::new();
	}
	(0..argc as usize)
		.map(|i| {
			let p = *argv.add(i);
			if p.is_null() {
				String::new()
			} else {
				CStr::from_ptr(p).to_string_lossy().into_owned()
			}
		})
		.collect()
}

fn guarded(call: impl FnOnce() -> String) -> *const c_char {
	match catch_unwind(AssertUnwindSafe(call)) {
		Ok(text) => answer(text),
		Err(_) => answer("error: panicked".into()),
	}
}

/// dashboard_start(port, bind): starts the server if it isn't running. Asked again with it running, says so.
#[no_mangle]
pub unsafe extern "C" fn dashboard_start(argc: c_int, argv: *const *const c_char) -> *const c_char {
	let args = arguments(argc, argv);
	guarded(|| {
		let port: u16 = match args.first().and_then(|p| p.trim().parse().ok()) {
			Some(p) if p > 0 => p,
			_ => return "error: no port".into(),
		};
		let all = args.get(1).map(|b| b == "all").unwrap_or(false);
		{
			let shared = lock();
			if shared.running {
				return if shared.port == port { "ok: already running".into() } else { format!("error: already running on {}", shared.port) };
			}
		}
		match server::start(port, all) {
			Ok(()) => {
				let mut shared = lock();
				shared.running = true;
				shared.port = port;
				"ok".into()
			}
			Err(error) => format!("error: {error}"),
		}
	})
}

/// dashboard_token(name, seconds): a new link token for that admin
#[no_mangle]
pub unsafe extern "C" fn dashboard_token(argc: c_int, argv: *const *const c_char) -> *const c_char {
	let args = arguments(argc, argv);
	guarded(|| {
		let name = args.first().cloned().unwrap_or_default();
		let seconds: u64 = args.get(1).and_then(|s| s.trim().parse().ok()).unwrap_or(12 * 3600);
		let token = new_token();
		let mut shared = lock();
		let at = now();
		shared.tokens.retain(|_, t| t.expires > at);
		shared.tokens.insert(token.clone(), Token { name, expires: at + seconds });
		token
	})
}

/// dashboard_push(channel, json): the latest of that kind, kept for pages that open later and sent to the open ones
#[no_mangle]
pub unsafe extern "C" fn dashboard_push(argc: c_int, argv: *const *const c_char) -> *const c_char {
	let args = arguments(argc, argv);
	guarded(|| {
		let (Some(channel), Some(json)) = (args.first(), args.get(1)) else {
			return "error: wanted a channel and its JSON".into();
		};
		let mut shared = lock();
		let text = frame(channel, json);
		shared.latest.insert(channel.clone(), json.clone());
		broadcast(&mut shared, text);
		"ok".into()
	})
}

/// dashboard_event(json): one more for the alerts feed
#[no_mangle]
pub unsafe extern "C" fn dashboard_event(argc: c_int, argv: *const *const c_char) -> *const c_char {
	let args = arguments(argc, argv);
	guarded(|| {
		let Some(json) = args.first() else {
			return "error: wanted the event's JSON".into();
		};
		let mut shared = lock();
		shared.alerts.push_back(json.clone());
		while shared.alerts.len() > ALERTS_KEPT {
			shared.alerts.pop_front();
		}
		let text = frame("alert", json);
		broadcast(&mut shared, text);
		"ok".into()
	})
}

/// dashboard_clients(): pages open just now
#[no_mangle]
pub unsafe extern "C" fn dashboard_clients(_argc: c_int, _argv: *const *const c_char) -> *const c_char {
	guarded(|| {
		let mut shared = lock();
		// a closed page is only noticed when something's sent to it: a comment line does that without the page seeing anything
		broadcast(&mut shared, ": ping\n\n".into());
		let asked = now().saturating_sub(LAST_SNAPSHOT.load(Ordering::Relaxed)) < 30;
		(shared.clients.len() + asked as usize).to_string()
	})
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn frames_split_lines() {
		assert_eq!(frame("health", "{\"a\":1}"), "event: health\ndata: {\"a\":1}\n\n");
		assert_eq!(frame("x", "a\nb"), "event: x\ndata: a\ndata: b\n\n");
	}

	#[test]
	fn tokens_differ() {
		let a = new_token();
		let b = new_token();
		assert_eq!(a.len(), 32);
		assert_ne!(a, b);
	}
}
