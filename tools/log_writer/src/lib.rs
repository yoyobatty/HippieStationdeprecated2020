//! Hippie's log writer, used for WRITE_LOG (code/__HELPERS/_logging.dm, hippiestation/code/__HELPERS/log_writer.dm).
//!
//! rust_g's log_write writes each line to the file there and then, on the game's own thread. When the drive stalls, so
//! does the game: in a round on 2026-11-10, with the drive 99% full, single log lines held the server for 3 to 7
//! seconds at a time. Here log_write only takes the time and queues the line; a thread of its own does the writing and
//! flushes each time it has caught up, so the lines are on disk as quickly as before when the drive keeps up.
//!
//! The lines are written exactly as rust_g 7.0.0 writes them: "[YYYY-MM-DD HH:MM:SS.mmm] first line", then " - " before
//! each further line, the time in UTC and taken when log_write is called. With "false" as the third argument the text
//! goes in as it is.
//!
//! BYOND calls these through call_ext's text interface (count, array of C strings), as it calls rust_g.

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{c_char, c_int, CStr, CString};
use std::fs::{self, File, OpenOptions};
use std::io::{BufWriter, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const VERSION: &str = "hippie_log 1";

/// Past this many lines waiting, new ones are dropped (and counted) rather than held: the drive has been gone a while
const MAX_QUEUED: u64 = 2_000_000;
/// How long closing the files waits for the queue to empty
const CLOSE_WAIT: Duration = Duration::from_secs(10);

enum Msg {
	Line(PathBuf, Vec<u8>),
	/// Flush everything written so far and answer
	Flush(Sender<()>),
	/// Flush, close every file, and answer
	CloseAll(Sender<()>),
}

struct Stats {
	queued: AtomicU64,
	written: AtomicU64,
	dropped: AtomicU64,
	failed: AtomicU64,
	/// Test only: the writer waits this many ms before each line it takes (a stalling drive, made to order)
	stall_ms: AtomicU64,
	last_error: Mutex<String>,
}

static STATS: Stats = Stats {
	queued: AtomicU64::new(0),
	written: AtomicU64::new(0),
	dropped: AtomicU64::new(0),
	failed: AtomicU64::new(0),
	stall_ms: AtomicU64::new(0),
	last_error: Mutex::new(String::new()),
};

static QUEUE: OnceLock<Mutex<Sender<Msg>>> = OnceLock::new();

fn queue() -> &'static Mutex<Sender<Msg>> {
	QUEUE.get_or_init(|| {
		pin_self();
		let (tx, rx) = channel();
		thread::Builder::new()
			.name("hippie_log writer".into())
			.spawn(move || writer(rx))
			.expect("hippie_log: no writer thread");
		Mutex::new(tx)
	})
}

fn send(msg: Msg) -> bool {
	match queue().lock() {
		Ok(tx) => tx.send(msg).is_ok(),
		Err(_) => false,
	}
}

fn note_error(text: String) {
	STATS.failed.fetch_add(1, Ordering::Relaxed);
	if let Ok(mut last) = STATS.last_error.lock() {
		*last = text;
	}
}

fn writer(rx: Receiver<Msg>) {
	let mut files: HashMap<PathBuf, BufWriter<File>> = HashMap::new();
	while let Ok(msg) = rx.recv() {
		handle(msg, &mut files);
		while let Ok(msg) = rx.try_recv() {
			handle(msg, &mut files);
		}
		flush_all(&mut files); // caught up: out to the drive
	}
}

fn flush_all(files: &mut HashMap<PathBuf, BufWriter<File>>) {
	for (path, file) in files.iter_mut() {
		if let Err(e) = file.flush() {
			note_error(format!("{}: {e}", path.display()));
		}
	}
}

fn handle(msg: Msg, files: &mut HashMap<PathBuf, BufWriter<File>>) {
	match msg {
		Msg::Line(path, bytes) => {
			let stall = STATS.stall_ms.load(Ordering::Relaxed);
			if stall > 0 {
				thread::sleep(Duration::from_millis(stall));
			}
			STATS.queued.fetch_sub(1, Ordering::Relaxed);
			if !files.contains_key(&path) {
				match open(&path) {
					Ok(file) => {
						files.insert(path.clone(), BufWriter::with_capacity(64 * 1024, file));
					}
					Err(e) => {
						note_error(format!("{}: {e}", path.display()));
						return;
					}
				}
			}
			let file = files.get_mut(&path).unwrap();
			match file.write_all(&bytes) {
				Ok(()) => {
					STATS.written.fetch_add(1, Ordering::Relaxed);
				}
				Err(e) => note_error(format!("{}: {e}", path.display())),
			}
		}
		Msg::Flush(answer) => {
			flush_all(files);
			let _ = answer.send(());
		}
		Msg::CloseAll(answer) => {
			flush_all(files);
			files.clear();
			let _ = answer.send(());
		}
	}
}

fn open(path: &PathBuf) -> std::io::Result<File> {
	if let Some(parent) = path.parent() {
		if !parent.as_os_str().is_empty() {
			fs::create_dir_all(parent)?;
		}
	}
	OpenOptions::new().append(true).create(true).open(path)
}

/// BYOND may unload a library it called; ours has a thread running in it, so it stays loaded for good
#[cfg(windows)]
fn pin_self() {
	#[link(name = "kernel32")]
	extern "system" {
		fn GetModuleHandleExW(flags: u32, name: *const u16, module: *mut *mut std::ffi::c_void) -> i32;
	}
	const PIN: u32 = 0x1;
	const FROM_ADDRESS: u32 = 0x4;
	let mut module = std::ptr::null_mut();
	unsafe {
		GetModuleHandleExW(PIN | FROM_ADDRESS, pin_self as *const u16, &mut module);
	}
}

#[cfg(not(windows))]
fn pin_self() {}

/// A line as rust_g 7.0.0 writes it: "[time] first line\n", then " - line\n" for each further line
pub fn format_line(data: &[u8], timestamped: bool, now: SystemTime) -> Vec<u8> {
	if !timestamped {
		return data.to_vec();
	}
	let mut out = Vec::with_capacity(data.len() + 32);
	let mut lines = data.split(|b| *b == b'\n');
	if let Some(first) = lines.next() {
		out.push(b'[');
		out.extend_from_slice(timestamp(now).as_bytes());
		out.extend_from_slice(b"] ");
		out.extend_from_slice(first);
		out.push(b'\n');
	}
	for line in lines {
		out.extend_from_slice(b" - ");
		out.extend_from_slice(line);
		out.push(b'\n');
	}
	out
}

/// UTC, as chrono's "%F %T%.3f"
pub fn timestamp(now: SystemTime) -> String {
	let since = now.duration_since(UNIX_EPOCH).unwrap_or_default();
	let secs = since.as_secs() as i64;
	let (year, month, day) = civil_from_days(secs.div_euclid(86_400));
	let of_day = secs.rem_euclid(86_400);
	format!(
		"{year:04}-{month:02}-{day:02} {:02}:{:02}:{:02}.{:03}",
		of_day / 3600,
		of_day % 3600 / 60,
		of_day % 60,
		since.subsec_millis()
	)
}

/// The calendar date of a day counted from 1970-01-01 (Howard Hinnant's days_from_civil, backwards)
fn civil_from_days(days: i64) -> (i64, u32, u32) {
	let z = days + 719_468;
	let era = z.div_euclid(146_097);
	let doe = z.rem_euclid(146_097);
	let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
	let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
	let mp = (5 * doy + 2) / 153;
	let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
	let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
	let year = yoe + era * 400 + if month <= 2 { 1 } else { 0 };
	(year, month, day)
}

// ---- what BYOND calls

thread_local! {
	static ANSWER: RefCell<CString> = RefCell::new(CString::default());
}

fn answer(text: &str) -> *const c_char {
	ANSWER.with(|cell| {
		*cell.borrow_mut() = CString::new(text.replace('\0', "")).unwrap_or_default();
		cell.borrow().as_ptr()
	})
}

unsafe fn arg<'a>(argc: c_int, argv: *const *const c_char, i: usize) -> Option<&'a [u8]> {
	if argv.is_null() || i >= argc.max(0) as usize {
		return None;
	}
	let ptr = *argv.add(i);
	if ptr.is_null() {
		return None;
	}
	Some(CStr::from_ptr(ptr).to_bytes())
}

fn guarded(f: impl FnOnce() -> String) -> *const c_char {
	match catch_unwind(AssertUnwindSafe(f)) {
		Ok(text) => answer(&text),
		Err(_) => answer("hippie_log: panicked"),
	}
}

#[no_mangle]
pub extern "C" fn log_version(_argc: c_int, _argv: *const *const c_char) -> *const c_char {
	answer(VERSION)
}

/// log_write(path, text, "true"/"false"): queued, written by the writer thread
#[no_mangle]
pub unsafe extern "C" fn log_write(argc: c_int, argv: *const *const c_char) -> *const c_char {
	let now = SystemTime::now();
	guarded(|| {
		let (Some(path), Some(data)) = (arg(argc, argv, 0), arg(argc, argv, 1)) else {
			return "hippie_log: log_write wants a path and some text".into();
		};
		let timestamped = arg(argc, argv, 2) != Some(b"false".as_slice());
		if STATS.queued.load(Ordering::Relaxed) >= MAX_QUEUED {
			STATS.dropped.fetch_add(1, Ordering::Relaxed);
			return String::new();
		}
		let path = PathBuf::from(String::from_utf8_lossy(path).into_owned());
		STATS.queued.fetch_add(1, Ordering::Relaxed);
		if !send(Msg::Line(path, format_line(data, timestamped, now))) {
			STATS.queued.fetch_sub(1, Ordering::Relaxed);
			return "hippie_log: the writer is gone".into();
		}
		String::new()
	})
}

fn wait_for(make: fn(Sender<()>) -> Msg, wait: Duration) -> String {
	let (tx, rx) = channel();
	if !send(make(tx)) {
		return "hippie_log: the writer is gone".into();
	}
	match rx.recv_timeout(wait) {
		Ok(()) => String::new(),
		Err(_) => format!("hippie_log: {} lines still waiting after {} s", STATS.queued.load(Ordering::Relaxed), wait.as_secs()),
	}
}

/// Waits (up to 10 s) for everything queued to be written, then closes every file, as rust_g's log_close_all closes them
#[no_mangle]
pub extern "C" fn log_close_all(_argc: c_int, _argv: *const *const c_char) -> *const c_char {
	guarded(|| wait_for(Msg::CloseAll, CLOSE_WAIT))
}

/// log_flush(ms): waits up to ms for everything queued to be on the drive
#[no_mangle]
pub unsafe extern "C" fn log_flush(argc: c_int, argv: *const *const c_char) -> *const c_char {
	guarded(|| {
		let ms = arg(argc, argv, 0).and_then(|a| std::str::from_utf8(a).ok()?.trim().parse::<f64>().ok()).unwrap_or(10_000.0);
		wait_for(Msg::Flush, Duration::from_millis(ms.max(0.0) as u64))
	})
}

/// "queued;written;dropped;failed;last error"
#[no_mangle]
pub extern "C" fn log_status(_argc: c_int, _argv: *const *const c_char) -> *const c_char {
	guarded(|| {
		let last = STATS.last_error.lock().map(|l| l.clone()).unwrap_or_default();
		format!(
			"{};{};{};{};{}",
			STATS.queued.load(Ordering::Relaxed),
			STATS.written.load(Ordering::Relaxed),
			STATS.dropped.load(Ordering::Relaxed),
			STATS.failed.load(Ordering::Relaxed),
			last
		)
	})
}

/// Test only: log_stall(ms) has the writer wait that long before each line, as a stalling drive would
#[no_mangle]
pub unsafe extern "C" fn log_stall(argc: c_int, argv: *const *const c_char) -> *const c_char {
	guarded(|| {
		let ms = arg(argc, argv, 0).and_then(|a| std::str::from_utf8(a).ok()?.trim().parse::<f64>().ok()).unwrap_or(0.0);
		STATS.stall_ms.store(ms.max(0.0) as u64, Ordering::Relaxed);
		String::new()
	})
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn timestamps_match_chrono() {
		// 2026-11-10 18:22:28.200 UTC
		let t = UNIX_EPOCH + Duration::from_millis(1_794_334_948_200);
		assert_eq!(timestamp(t), "2026-11-10 18:22:28.200");
		assert_eq!(timestamp(UNIX_EPOCH), "1970-01-01 00:00:00.000");
		// a leap day and a year's end
		assert_eq!(timestamp(UNIX_EPOCH + Duration::from_secs(951_782_400)), "2000-02-29 00:00:00.000");
		assert_eq!(timestamp(UNIX_EPOCH + Duration::from_millis(1_798_761_599_999)), "2026-12-31 23:59:59.999");
	}

	#[test]
	fn lines_match_rust_g() {
		let t = UNIX_EPOCH + Duration::from_millis(1_794_334_948_200);
		assert_eq!(format_line(b"EMOTE: hi", true, t), b"[2026-11-10 18:22:28.200] EMOTE: hi\n".to_vec());
		assert_eq!(
			format_line(b"Starting up round ID 5.\n-------------------------", true, t),
			b"[2026-11-10 18:22:28.200] Starting up round ID 5.\n - -------------------------\n".to_vec()
		);
		assert_eq!(format_line(b"a\n", true, t), b"[2026-11-10 18:22:28.200] a\n - \n".to_vec());
		assert_eq!(format_line(b"raw", false, t), b"raw".to_vec());
	}

	#[test]
	fn writes_in_order_and_closes() {
		let dir = std::env::temp_dir().join(format!("hippie_log_test_{}", std::process::id()));
		let path = dir.join("sub").join("game.log");
		let path_text = CString::new(path.to_string_lossy().into_owned()).unwrap();
		for i in 0..1000 {
			let text = CString::new(format!("line {i}")).unwrap();
			let flag = CString::new("false").unwrap();
			let argv = [path_text.as_ptr(), text.as_ptr(), flag.as_ptr()];
			unsafe { log_write(3, argv.as_ptr()) };
		}
		log_close_all(0, std::ptr::null());
		let written = fs::read_to_string(&path).unwrap();
		let expected: String = (0..1000).map(|i| format!("line {i}")).collect();
		assert_eq!(written, expected);
		let _ = fs::remove_dir_all(&dir);
	}
}
