//! Hippie's path engine, called from AStar() for the bots' searches (hippiestation/code/modules/bots_ai/bot_path_engine.dm).
//! The search is in search.rs; this is just the BYOND side of it.
//!
//! Like the lighting engine (tools/lighting_engine) it only reads lists and arguments DM passes, and writes into lists DM
//! passes, and those only ever hold numbers and turfs: neither is reference counted, so it never has a BYOND reference to
//! look after. The two BYOND API functions it uses are looked up in byondcore.dll at first use.

pub mod search;

use search::{Cost, Outcome, Search, Settings};
use std::collections::BTreeMap;
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Mutex, OnceLock};

/// Bumped whenever what DM and the engine pass each other changes. DM won't use a library that says anything else.
pub const ENGINE_VERSION: f32 = 1.0;

/// Searches kept at once: a search DM gave up on (a runtime part way) is dropped when this many newer ones have started
const MAX_SEARCHES: usize = 256;

const TYPE_NULL: u8 = 0x00;
const TYPE_TURF: u8 = 0x01;
const TYPE_NUMBER: u8 = 0x2A;

/// BYOND's CByondValue: a type byte, padding, then a number or a reference
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ByondValue {
	kind: u8,
	junk: [u8; 3],
	data: u32,
}

impl ByondValue {
	fn num(value: f32) -> Self {
		ByondValue {
			kind: TYPE_NUMBER,
			junk: [0; 3],
			data: value.to_bits(),
		}
	}

	fn turf(id: u32) -> Self {
		ByondValue {
			kind: TYPE_TURF,
			junk: [0; 3],
			data: id,
		}
	}

	fn null() -> Self {
		ByondValue {
			kind: TYPE_NULL,
			junk: [0; 3],
			data: 0,
		}
	}

	fn as_f32(&self) -> f32 {
		if self.kind == TYPE_NUMBER {
			f32::from_bits(self.data)
		} else {
			0.0
		}
	}

	fn as_int(&self) -> i32 {
		self.as_f32() as i32
	}
}

type ReadListFn = unsafe extern "C" fn(loc: *const ByondValue, list: *mut ByondValue, len: *mut u32) -> bool;
type WriteListFn = unsafe extern "C" fn(loc: *const ByondValue, list: *const ByondValue, len: u32) -> bool;

struct Api {
	read_list: ReadListFn,
	write_list: WriteListFn,
}

#[cfg(windows)]
mod platform {
	use std::ffi::c_void;
	extern "system" {
		pub fn GetModuleHandleA(name: *const u8) -> *mut c_void;
		pub fn GetProcAddress(module: *mut c_void, name: *const u8) -> *mut c_void;
	}

	pub fn find(name: &[u8]) -> *mut c_void {
		unsafe {
			let module = GetModuleHandleA(b"byondcore.dll\0".as_ptr());
			if module.is_null() {
				return std::ptr::null_mut();
			}
			GetProcAddress(module, name.as_ptr())
		}
	}
}

#[cfg(not(windows))]
mod platform {
	use std::ffi::c_void;
	extern "C" {
		fn dlsym(handle: *mut c_void, name: *const u8) -> *mut c_void;
	}

	pub fn find(name: &[u8]) -> *mut c_void {
		unsafe { dlsym(std::ptr::null_mut(), name.as_ptr()) }
	}
}

fn api() -> Option<&'static Api> {
	static API: OnceLock<Option<Api>> = OnceLock::new();
	API.get_or_init(|| {
		let read = platform::find(b"Byond_ReadList\0");
		let write = platform::find(b"Byond_WriteList\0");
		if read.is_null() || write.is_null() {
			return None;
		}
		unsafe {
			Some(Api {
				read_list: std::mem::transmute::<*mut c_void, ReadListFn>(read),
				write_list: std::mem::transmute::<*mut c_void, WriteListFn>(write),
			})
		}
	})
	.as_ref()
}

fn read_values(api: &Api, list: &ByondValue, into: &mut Vec<ByondValue>) -> Result<(), String> {
	if into.len() < 1024 {
		into.resize(1024, ByondValue::null());
	}
	loop {
		let mut len = into.capacity() as u32;
		into.resize(len as usize, ByondValue::null());
		if unsafe { (api.read_list)(list, into.as_mut_ptr(), &mut len) } {
			into.truncate(len as usize);
			return Ok(());
		}
		if len as usize <= into.len() {
			return Err("couldn't read a list".into());
		}
		into.resize(len as usize, ByondValue::null());
	}
}

fn write_values(api: &Api, list: &ByondValue, values: &[ByondValue]) -> Result<(), String> {
	if unsafe { (api.write_list)(list, values.as_ptr(), values.len() as u32) } {
		Ok(())
	} else {
		Err("couldn't write a result list".into())
	}
}

unsafe fn arguments<'a>(argc: u32, argv: *const ByondValue) -> &'a [ByondValue] {
	if argv.is_null() || argc == 0 {
		&[]
	} else {
		std::slice::from_raw_parts(argv, argc as usize)
	}
}

#[derive(Default)]
struct Stats {
	searches: u64,
	found: u64,
	no_route: u64,
	aborted: u64,
	rounds: u64,
	tiles_asked: u64,
	opened: u64,
}

struct State {
	maxx: i32,
	maxy: i32,
	per_level: u32,
	searches: BTreeMap<u32, Search>,
	next_id: u32,
	values: Vec<ByondValue>,
	out: Vec<ByondValue>,
	answers: Vec<u32>,
	stats: Stats,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);

fn guarded(name: &str, call: impl FnOnce() -> Result<f32, String>) -> ByondValue {
	match catch_unwind(AssertUnwindSafe(call)) {
		Ok(Ok(value)) => ByondValue::num(value),
		Ok(Err(error)) => {
			eprintln!("hippie_path {name}: {error}");
			ByondValue::num(-1.0)
		}
		Err(_) => {
			eprintln!("hippie_path {name}: panicked");
			ByondValue::num(-2.0)
		}
	}
}

fn with_state(name: &str, call: impl FnOnce(&Api, &mut State) -> Result<f32, String>) -> ByondValue {
	guarded(name, || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("not set up")?;
		call(api, state)
	})
}

/// call_ext("hippie_path", "byond:path_setup")(maxx, maxy, maxz, turfs, coordinates): starts afresh for a world this size.
/// `turfs` are a few turfs and `coordinates` their x, y and z, to check turfs are numbered the way the engine thinks.
/// Returns ENGINE_VERSION.
#[no_mangle]
pub unsafe extern "C" fn path_setup(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("setup", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 5 {
			return Err(format!("{} arguments, wanted 5", args.len()));
		}
		let (maxx, maxy, maxz) = (args[0].as_int(), args[1].as_int(), args[2].as_int());
		if maxx < 1 || maxy < 1 || maxz < 1 {
			return Err("no world".into());
		}
		let mut turfs = Vec::new();
		read_values(api, &args[3], &mut turfs)?;
		let mut coordinates = Vec::new();
		read_values(api, &args[4], &mut coordinates)?;
		if coordinates.len() != turfs.len() * 3 {
			return Err("turfs and coordinates don't match".into());
		}
		let per_level = (maxx * maxy) as u32;
		for (i, turf) in turfs.iter().enumerate() {
			let (x, y, z) = (
				coordinates[i * 3].as_int(),
				coordinates[i * 3 + 1].as_int(),
				coordinates[i * 3 + 2].as_int(),
			);
			let expected = (z as u32 - 1) * per_level + ((y - 1) * maxx + (x - 1)) as u32;
			if turf.kind != TYPE_TURF || turf.data != expected {
				return Err(format!("turf ({x},{y},{z}) is numbered {} (type {}), not {expected}", turf.data, turf.kind));
			}
		}
		*STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(State {
			maxx,
			maxy,
			per_level,
			searches: BTreeMap::new(),
			next_id: 1,
			values: Vec::new(),
			out: Vec::new(),
			answers: Vec::new(),
			stats: Stats::default(),
		});
		Ok(ENGINE_VERSION)
	})
}

/// path_begin(start, end, maxnodedepth, mintargetdist, cost, end_penalty, exclude): a new search, not run yet. `cost` is 1 for
/// Distance_cardinal(), 2 for bot_weighted_distance(); add 256 times how
/// many of the next nodes on the open list to ask about the tiles of as well when it has to ask (search.rs). `exclude` is a
/// turf or null. Returns the search's number, for path_step().
#[no_mangle]
pub unsafe extern "C" fn path_begin(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("begin", |_api, state| {
		if args.len() < 7 {
			return Err(format!("{} arguments, wanted 7", args.len()));
		}
		if args[0].kind != TYPE_TURF || args[1].kind != TYPE_TURF {
			return Err("start and end must be turfs".into());
		}
		let mode = args[4].as_int();
		let cost = match mode & 15 {
			1 => Cost::Cardinal,
			2 => Cost::Weighted,
			_ => return Err(format!("no cost {mode}")),
		};
		let exclude = if args[6].kind == TYPE_TURF { Some(args[6].data) } else { None };
		let search = Search::new(Settings {
			maxx: state.maxx,
			maxy: state.maxy,
			per_level: state.per_level,
			start: args[0].data,
			end: args[1].data,
			maxnodedepth: args[2].as_int(),
			mintargetdist: args[3].as_f32(),
			cost,
			end_penalty: args[5].as_f32(),
			exclude,
			ahead: ((mode >> 8) & 255) as usize,
		});
		while state.searches.len() >= MAX_SEARCHES {
			let oldest = *state.searches.keys().next().unwrap();
			state.searches.remove(&oldest);
		}
		let id = state.next_id;
		state.next_id = if state.next_id >= 1 << 23 { 1 } else { state.next_id + 1 };
		state.searches.insert(id, search);
		state.stats.searches += 1;
		Ok(id as f32)
	})
}

/// path_step(id, answers, out): the answers (numbers, search.rs says what they mean) for the tiles it asked about last, an
/// empty list the first time. Runs the search on and returns:
/// - 1: it wants tiles told about: `out` holds them
/// - 2: found: `out` is how many tiles it opened, then the path, start to end
/// - 3: no route: `out` is how many tiles it opened, 1 if maxnodedepth stopped it expanding any (else 0), then every tile it opened
/// - 4: AStar() would have had a runtime error: run DM's own search
/// The search is forgotten once it returns anything but 1.
#[no_mangle]
pub unsafe extern "C" fn path_step(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("step", |api, state| {
		if args.len() < 3 {
			return Err(format!("{} arguments, wanted 3", args.len()));
		}
		let id = args[0].as_int() as u32;
		let mut values = std::mem::take(&mut state.values);
		read_values(api, &args[1], &mut values)?;
		let mut answers = std::mem::take(&mut state.answers);
		answers.clear();
		answers.extend(values.iter().map(|v| v.as_f32() as u32));
		state.values = values;
		let search = state.searches.get_mut(&id).ok_or_else(|| format!("no search {id}"))?;
		let answered = search.answer(&answers);
		state.answers = answers;
		answered?;
		let outcome = search.step();
		let mut out = std::mem::take(&mut state.out);
		out.clear();
		let status = match outcome {
			Outcome::Need => {
				out.extend(search.asked.iter().map(|&t| ByondValue::turf(t)));
				1.0
			}
			Outcome::Found(path, opened) => {
				out.push(ByondValue::num(opened as f32));
				out.extend(path.iter().map(|&t| ByondValue::turf(t)));
				state.stats.found += 1;
				state.stats.opened += opened as u64;
				2.0
			}
			Outcome::NoRoute(opened, depth_cut) => {
				out.push(ByondValue::num(opened.len() as f32));
				out.push(ByondValue::num(if depth_cut { 1.0 } else { 0.0 }));
				out.extend(opened.iter().map(|&t| ByondValue::turf(t)));
				state.stats.no_route += 1;
				state.stats.opened += opened.len() as u64;
				3.0
			}
			Outcome::Abort(why) => {
				eprintln!("hippie_path: search {id} handed back to DM: {why}");
				state.stats.aborted += 1;
				4.0
			}
		};
		if status != 1.0 {
			state.stats.rounds += search.rounds as u64;
			state.stats.tiles_asked += search.tiles_asked as u64;
			state.searches.remove(&id);
		}
		let written = write_values(api, &args[2], &out);
		state.out = out;
		written?;
		Ok(status)
	})
}

/// path_forget(id): drops a search DM is giving up on
#[no_mangle]
pub unsafe extern "C" fn path_forget(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("forget", |_api, state| {
		if let Some(id) = args.first() {
			state.searches.remove(&(id.as_int() as u32));
		}
		Ok(state.searches.len() as f32)
	})
}

/// path_stats(out): searches begun, found, no route, handed back, rounds, tiles asked about, tiles opened, searches open now
#[no_mangle]
pub unsafe extern "C" fn path_stats(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("stats", |api, state| {
		let s = &state.stats;
		let values: Vec<ByondValue> = [s.searches, s.found, s.no_route, s.aborted, s.rounds, s.tiles_asked, s.opened, state.searches.len() as u64]
			.iter()
			.map(|&n| ByondValue::num(n as f32))
			.collect();
		if let Some(out) = args.first() {
			write_values(api, out, &values)?;
		}
		Ok(ENGINE_VERSION)
	})
}
