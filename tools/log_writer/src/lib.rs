//! Hippie's log writer, used for WRITE_LOG (code/__HELPERS/_logging.dm, hippiestation/code/__HELPERS/log_writer.dm).
//!
//! rust_g's log_write writes each line to the file there and then, on the game's own thread. When the drive stalls, so
//! does the game: in a round on 2026-11-10, with the drive 99% full, single log lines held the server for 3 to 7
//! seconds at a time. Here log_write only takes the time and adds the line to a queue; a thread of its own picks the queue up
//! every 20 ms (POLL), writes it and flushes, so the lines are on the drive within a tick of rust_g's when the drive keeps up.
//! The game never wakes that thread for a line: with lines a few at a time between game work, a wake for each one (a channel
//! with the writer asleep on it) cost 1.4 us of the game's time a line, more than the rest of log_write (2026-11-10).
//!
//! The lines are written exactly as rust_g 7.0.0 writes them: "[YYYY-MM-DD HH:MM:SS.mmm] first line", then " - " before
//! each further line, the time in UTC and taken when log_write is called. With "false" as the third argument the text
//! goes in as it is.
//!
//! BYOND calls these through call_ext's text interface (count, array of C strings), as it calls rust_g.
//!
//! A path ending in ".zst" is written compressed (zstd, level 6), on the same thread: the bot trace and the telemetry, which were
//! ~170 MB a Bot Shift as plain text, come out ~25 times smaller. The stream is flushed at most once a second, so a server that's
//! killed leaves a file that reads to within a second of the end (python -m zstandard, or tools/bot_gym/logread.py). Closing the
//! files ends the frame; writing to the same file again afterwards adds another frame, which zstd reads as one stream.
//!
//! log_replace(path, text) writes a whole file instead (profiler.json every 5 minutes), also on the writer thread: to path.tmp,
//! then over the old one.

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{c_char, c_int, CStr, CString};
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufWriter, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{channel, Sender};
use std::sync::{Condvar, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// Unchanged from the first version: what it had (log_write, log_flush, log_close_all, log_status) still works the same, so a
/// game built before the rest keeps using it. What came since is in log_features.
pub const VERSION: &str = "hippie_log 1";
/// ".zst" files and log_replace
pub const FEATURES: &str = "zst replace";

/// Past this many lines waiting, new ones are dropped (and counted) rather than held: the drive has been gone a while
const MAX_QUEUED: u64 = 2_000_000;
/// How long closing the files waits for the queue to empty
const CLOSE_WAIT: Duration = Duration::from_secs(10);
/// zstd's level for ".zst" files. 6 was 27x on a shift's trace, 9 only 29x for four times the memory (~20 MB a file, in a 32-bit
/// process); 3 was 23x. The writer compresses a shift's ~170 MB at a few hundred MB/s, on its own thread.
const ZST_LEVEL: i32 = 6;
/// How often a ".zst" file is flushed while lines keep coming. Each flush ends a block, which costs a little of the ratio.
const ZST_FLUSH_EVERY: Duration = Duration::from_secs(1);
/// How often the writer picks up the queue. Asking for a flush or a close wakes it at once.
const POLL: Duration = Duration::from_millis(20);

enum Msg {
	/// A line as log_write was given it, put in rust_g's form by the writer (format_line()), not on the game's time
	Line { path: Vec<u8>, data: Vec<u8>, timestamped: bool, at: SystemTime },
	/// A whole file, written over the old one
	Replace(Vec<u8>, Vec<u8>),
	/// Flush everything written so far and answer
	Flush(Sender<()>),
	/// Flush, close every file, and answer
	CloseAll(Sender<()>),
}

/// An open log: plain text as rust_g writes it, or the same text zstd-compressed
enum Sink {
	Plain(BufWriter<File>),
	Zst {
		encoder: zstd::stream::write::Encoder<'static, BufWriter<File>>,
		/// Written to since the last flush
		dirty: bool,
		flushed: Instant,
	},
}

impl Sink {
	fn open(path: &Path) -> io::Result<Sink> {
		let file = BufWriter::with_capacity(64 * 1024, open(path)?);
		if is_compressed(path) {
			return Ok(Sink::Zst { encoder: zstd::stream::write::Encoder::new(file, ZST_LEVEL)?, dirty: false, flushed: Instant::now() });
		}
		Ok(Sink::Plain(file))
	}

	fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
		match self {
			Sink::Plain(file) => file.write_all(bytes),
			Sink::Zst { encoder, dirty, .. } => {
				*dirty = true;
				encoder.write_all(bytes)
			}
		}
	}

	/// Out to the drive: a plain file every time, a compressed one if it's been ZST_FLUSH_EVERY (or `now`)
	fn flush(&mut self, now: bool) -> io::Result<()> {
		match self {
			Sink::Plain(file) => file.flush(),
			Sink::Zst { encoder, dirty, flushed } => {
				if !*dirty || (!now && flushed.elapsed() < ZST_FLUSH_EVERY) {
					return Ok(());
				}
				*dirty = false;
				*flushed = Instant::now();
				encoder.flush()
			}
		}
	}

	fn close(self) -> io::Result<()> {
		match self {
			Sink::Plain(mut file) => file.flush(),
			Sink::Zst { encoder, .. } => encoder.finish()?.flush(),
		}
	}
}

pub fn is_compressed(path: &Path) -> bool {
	path.extension().is_some_and(|e| e.eq_ignore_ascii_case("zst"))
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

/// What the game has handed over and the writer hasn't picked up yet
struct Queue {
	items: Mutex<Vec<Msg>>,
	/// Rung for a flush or a close, never for a line
	ring: Condvar,
}

static QUEUE: OnceLock<Queue> = OnceLock::new();

fn queue() -> &'static Queue {
	QUEUE.get_or_init(|| {
		pin_self();
		thread::Builder::new().name("hippie_log writer".into()).spawn(writer).expect("hippie_log: no writer thread");
		Queue { items: Mutex::new(Vec::with_capacity(4096)), ring: Condvar::new() }
	})
}

/// Onto the queue; `now` wakes the writer for it
fn send(msg: Msg, now: bool) -> bool {
	let queue = queue();
	match queue.items.lock() {
		Ok(mut items) => items.push(msg),
		Err(_) => return false,
	}
	if now {
		queue.ring.notify_one();
	}
	true
}

fn path_text(path: &[u8]) -> String {
	String::from_utf8_lossy(path).into_owned()
}

/// The path with the world's folder in front, unless it's already full. BYOND on Linux moves the process's working folder for a
/// moment inside fcopy, text2file, file() and fdel (seen at /, /tmp and folders it was making: Paradise's CI, 2026-11-12), so the
/// writer thread opening "data/logs/..." right then put the file somewhere else, or failed: 1,249 to 1,288 of 1,500 new files in
/// a stress world (tools/log_writer/race_check.dme). Windows BYOND doesn't, 0 of 4,500. So the path is made full here, on the
/// game's thread, which never sees the moved folder, against the folder as it was at the first call.
fn full_path(path: &[u8]) -> Vec<u8> {
	static BASE: OnceLock<Vec<u8>> = OnceLock::new();
	let rooted = matches!(path.first(), Some(b'/') | Some(b'\\')) || path.get(1) == Some(&b':');
	let base = BASE.get_or_init(|| match std::env::current_dir() {
		Ok(dir) => {
			let mut base = dir.to_string_lossy().into_owned().into_bytes();
			if !matches!(base.last(), Some(b'/') | Some(b'\\')) {
				base.push(std::path::MAIN_SEPARATOR as u8);
			}
			base
		}
		Err(_) => Vec::new(),
	});
	if rooted || base.is_empty() {
		return path.to_vec();
	}
	let mut full = Vec::with_capacity(base.len() + path.len());
	full.extend_from_slice(base);
	full.extend_from_slice(path);
	full
}

fn note_error(text: String) {
	STATS.failed.fetch_add(1, Ordering::Relaxed);
	if let Ok(mut last) = STATS.last_error.lock() {
		*last = text;
	}
}

fn writer() {
	let queue = queue();
	let mut files: HashMap<Vec<u8>, Sink> = HashMap::new();
	// Swapped with the queue each time round, so neither side allocates once they've grown
	let mut taken: Vec<Msg> = Vec::with_capacity(4096);
	loop {
		{
			let Ok(mut items) = queue.items.lock() else { return };
			if items.is_empty() {
				items = match queue.ring.wait_timeout(items, POLL) {
					Ok((items, _)) => items,
					Err(_) => return,
				};
			}
			std::mem::swap(&mut *items, &mut taken);
		}
		for msg in taken.drain(..) {
			handle(msg, &mut files);
		}
		flush_all(&mut files, false); // caught up: out to the drive (a compressed file once a second)
	}
}

fn flush_all(files: &mut HashMap<Vec<u8>, Sink>, now: bool) {
	for (path, file) in files.iter_mut() {
		if let Err(e) = file.flush(now) {
			note_error(format!("{}: {e}", path_text(path)));
		}
	}
}

fn close_all(files: &mut HashMap<Vec<u8>, Sink>) {
	for (path, file) in files.drain() {
		if let Err(e) = file.close() {
			note_error(format!("{}: {e}", path_text(&path)));
		}
	}
}

fn handle(msg: Msg, files: &mut HashMap<Vec<u8>, Sink>) {
	match msg {
		Msg::Line { path, data, timestamped, at } => {
			let stall = STATS.stall_ms.load(Ordering::Relaxed);
			if stall > 0 {
				thread::sleep(Duration::from_millis(stall));
			}
			STATS.queued.fetch_sub(1, Ordering::Relaxed);
			if !files.contains_key(&path) {
				match Sink::open(&PathBuf::from(path_text(&path))) {
					Ok(file) => {
						files.insert(path.clone(), file);
					}
					Err(e) => {
						note_error(format!("{}: {e}", path_text(&path)));
						return;
					}
				}
			}
			let file = files.get_mut(&path).unwrap();
			match file.write(&format_line(&data, timestamped, at)) {
				Ok(()) => {
					STATS.written.fetch_add(1, Ordering::Relaxed);
				}
				Err(e) => note_error(format!("{}: {e}", path_text(&path))),
			}
		}
		Msg::Replace(path, bytes) => {
			STATS.queued.fetch_sub(1, Ordering::Relaxed);
			if let Some(file) = files.remove(&path) {
				let _ = file.close(); // it was being appended to as well: what was written goes first, then this over it
			}
			match replace(&PathBuf::from(path_text(&path)), &bytes) {
				Ok(()) => {
					STATS.written.fetch_add(1, Ordering::Relaxed);
				}
				Err(e) => note_error(format!("{}: {e}", path_text(&path))),
			}
		}
		Msg::Flush(answer) => {
			flush_all(files, true);
			let _ = answer.send(());
		}
		Msg::CloseAll(answer) => {
			close_all(files);
			let _ = answer.send(());
		}
	}
}

/// The whole file, to path.tmp and then over path, so a reader never sees half of it
fn replace(path: &Path, bytes: &[u8]) -> io::Result<()> {
	if let Some(parent) = path.parent() {
		if !parent.as_os_str().is_empty() {
			fs::create_dir_all(parent)?;
		}
	}
	let mut temp = path.as_os_str().to_owned();
	temp.push(".tmp");
	let temp = PathBuf::from(temp);
	fs::write(&temp, bytes)?;
	fs::rename(&temp, path)
}

fn open(path: &Path) -> io::Result<File> {
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
	if text.is_empty() {
		return c"".as_ptr(); // log_write's answer, nearly always: no allocation for it
	}
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

/// What this build can do beyond log_write: "zst" (paths ending in .zst are compressed) and "replace" (log_replace)
#[no_mangle]
pub extern "C" fn log_features(_argc: c_int, _argv: *const *const c_char) -> *const c_char {
	answer(FEATURES)
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
		STATS.queued.fetch_add(1, Ordering::Relaxed);
		if !send(Msg::Line { path: full_path(path), data: data.to_vec(), timestamped, at: now }, false) {
			STATS.queued.fetch_sub(1, Ordering::Relaxed);
			return "hippie_log: the writer is gone".into();
		}
		String::new()
	})
}

/// log_replace(path, text): the whole file, queued like a line and written over the old one by the writer thread
#[no_mangle]
pub unsafe extern "C" fn log_replace(argc: c_int, argv: *const *const c_char) -> *const c_char {
	guarded(|| {
		let (Some(path), Some(data)) = (arg(argc, argv, 0), arg(argc, argv, 1)) else {
			return "hippie_log: log_replace wants a path and some text".into();
		};
		STATS.queued.fetch_add(1, Ordering::Relaxed);
		if !send(Msg::Replace(full_path(path), data.to_vec()), false) {
			STATS.queued.fetch_sub(1, Ordering::Relaxed);
			return "hippie_log: the writer is gone".into();
		}
		String::new()
	})
}

fn wait_for(make: fn(Sender<()>) -> Msg, wait: Duration) -> String {
	let (tx, rx) = channel();
	if !send(make(tx), true) {
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
	fn paths_are_made_full() {
		let base = std::env::current_dir().unwrap().to_string_lossy().into_owned();
		let full = String::from_utf8(full_path(b"data/logs/game.log")).unwrap();
		assert!(full.starts_with(&base) && full.ends_with("data/logs/game.log"), "{full}");
		assert_eq!(full_path(b"/srv/data/game.log"), b"/srv/data/game.log".to_vec());
		assert_eq!(full_path(b"C:/data/game.log"), b"C:/data/game.log".to_vec());
		assert_eq!(full_path(b"\\\\server\\share\\game.log"), b"\\\\server\\share\\game.log".to_vec());
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

	fn write_line(path: &CString, text: &str) {
		let text = CString::new(text).unwrap();
		let flag = CString::new("false").unwrap();
		let argv = [path.as_ptr(), text.as_ptr(), flag.as_ptr()];
		unsafe { log_write(3, argv.as_ptr()) };
	}

	#[test]
	fn compressed_files_read_back_whole_across_flushes_and_reopens() {
		let dir = std::env::temp_dir().join(format!("hippie_log_zst_{}", std::process::id()));
		let path = dir.join("trace.log.zst");
		let path_text = CString::new(path.to_string_lossy().into_owned()).unwrap();
		let mut expected = String::new();
		for i in 0..5000 {
			let line = format!("Nico Faulkner: step_next_node: the floor -> the floor ({i},34,2), 12 nodes left\n");
			write_line(&path_text, &line);
			expected += &line;
		}
		// flushed but not closed: what a killed server leaves, readable to the flush
		let flush_answer = unsafe { CStr::from_ptr(log_flush(0, std::ptr::null())) }.to_string_lossy().into_owned();
		assert_eq!(flush_answer, "");
		let flushed = fs::read(&path).unwrap();
		let mut partial = Vec::new();
		let mut decoder = zstd::stream::read::Decoder::new(&flushed[..]).unwrap();
		let _ = std::io::Read::read_to_end(&mut decoder, &mut partial); // no end of frame yet: reads what's there, then errors
		assert_eq!(String::from_utf8(partial).unwrap(), expected);
		log_close_all(0, std::ptr::null());
		// written again after closing: a second frame, the same stream
		write_line(&path_text, "after closing\n");
		expected += "after closing\n";
		log_close_all(0, std::ptr::null());
		let bytes = fs::read(&path).unwrap();
		assert!(bytes.len() * 20 < expected.len(), "{} bytes for {}", bytes.len(), expected.len());
		assert_eq!(String::from_utf8(zstd::stream::decode_all(&bytes[..]).unwrap()).unwrap(), expected);
		let _ = fs::remove_dir_all(&dir);
	}

	#[test]
	fn replace_writes_the_whole_file_over_the_old_one() {
		let dir = std::env::temp_dir().join(format!("hippie_log_replace_{}", std::process::id()));
		let path = dir.join("profiler.json");
		let path_text = CString::new(path.to_string_lossy().into_owned()).unwrap();
		for text in ["[{\"name\":\"first, and longer\"}]", "[{\"name\":\"second\"}]"] {
			let text = CString::new(text).unwrap();
			let argv = [path_text.as_ptr(), text.as_ptr()];
			unsafe { log_replace(2, argv.as_ptr()) };
		}
		log_close_all(0, std::ptr::null());
		assert_eq!(fs::read_to_string(&path).unwrap(), "[{\"name\":\"second\"}]");
		assert!(!dir.join("profiler.json.tmp").exists());
		let _ = fs::remove_dir_all(&dir);
	}
}
