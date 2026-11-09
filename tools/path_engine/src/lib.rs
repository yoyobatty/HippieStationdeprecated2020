//! Hippie's path engine, called from AStar() for the bots' searches (hippiestation/code/modules/bots_ai/bot_path_engine.dm).
//! The search is in search.rs, the station picture it keeps between searches in picture.rs; this is the BYOND side of them.
//!
//! Like the lighting engine (tools/lighting_engine) it only reads lists and arguments DM passes, and writes into lists DM
//! passes, and those only ever hold numbers and turfs: neither is reference counted, so it never has a BYOND reference to
//! look after. The two BYOND API functions it uses are looked up in byondcore.dll at first use.

pub mod flood;
pub mod picture;
pub mod search;

use flood::{Flood, FloodOutcome, FloodSettings, NO_TILE};
use picture::Picture;
use search::{Cost, Outcome, Search, Settings};
use std::collections::BTreeMap;
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Mutex, OnceLock};

/// Bumped whenever what DM and the engine pass each other changes. DM won't use a library that says anything else.
pub const ENGINE_VERSION: f32 = 3.0;

/// Searches kept at once: a search DM gave up on (a runtime part way) is dropped when this many newer ones have started
const MAX_SEARCHES: usize = 256;

/// Regions (the tiles a search that found no route opened) kept at once, and their tiles in all: the oldest go first. DM keeps
/// them for seconds at most (bot_pathing_permissive.dm), and a region asked about after it's gone just answers "not known".
const MAX_REGIONS: usize = 4096;
const MAX_REGION_TILES: usize = 8_000_000;

/// The mode argument of path_begin(), above the cost (bits 0-3) and below the look-ahead (bits 8-15)
const MODE_SIMULATED_ONLY: i32 = 16;
const MODE_PICTURE_OFF: i32 = 32;
const MODE_PICTURE_CHECK: i32 = 64;
const MODE_RETURN_TILES: i32 = 128;
/// path_flood_begin(): a backward flood (bot_sealed_pocket())
const MODE_BACKWARD: i32 = 256;
/// path_flood_begin(): stop at the first hallway tile too (path_hubs())
const MODE_STOP_AT_HUB: i32 = 512;

/// Answers that disagreed with the station picture kept for DM to describe, in the picture check
const MAX_CHECK_SAMPLES: usize = 40;

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
	/// floods finished
	floods: u64,
	found: u64,
	no_route: u64,
	aborted: u64,
	rounds: u64,
	tiles_asked: u64,
	opened: u64,
	/// Tiles the station picture answered instead of DM
	picture_hits: u64,
	/// Tiles DM told it had changed
	dirtied: u64,
	/// The picture check: answers it would have given and DM gave, and how many of them differed
	checked: u64,
	mismatched: u64,
}

/// What a search was started with that the engine needs to know besides the search itself
struct Flags {
	check: bool,
	return_tiles: bool,
	start: u32,
	simulated_only: bool,
}

/// A tile the station picture would have answered differently from DM, in the picture check
struct Mismatch {
	turf: u32,
	predicted: u32,
	actual: u32,
	kind: u8,
}

struct State {
	maxx: i32,
	maxy: i32,
	per_level: u32,
	searches: BTreeMap<u32, (Search, Flags)>,
	floods: BTreeMap<u32, (Flood, Flags)>,
	next_id: u32,
	picture: Picture,
	/// Region number -> its tiles, sorted
	regions: BTreeMap<u32, Vec<u32>>,
	region_tiles: usize,
	next_region: u32,
	samples: Vec<Mismatch>,
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

impl State {
	/// Keeps the tiles a search with no route opened, and returns the region's number
	fn keep_region(&mut self, mut tiles: Vec<u32>) -> u32 {
		tiles.sort_unstable();
		tiles.dedup();
		let id = self.next_region;
		self.next_region = if self.next_region >= 1 << 23 { 1 } else { self.next_region + 1 };
		self.region_tiles += tiles.len();
		if let Some(old) = self.regions.insert(id, tiles) {
			self.region_tiles -= old.len(); // wrapped round onto one still kept
		}
		while self.regions.len() > MAX_REGIONS || (self.region_tiles > MAX_REGION_TILES && self.regions.len() > 1) {
			let oldest = *self.regions.keys().next().unwrap();
			if oldest == id {
				break;
			}
			if let Some(gone) = self.regions.remove(&oldest) {
				self.region_tiles -= gone.len();
			}
		}
		id
	}
}

/// call_ext("hippie_path", "byond:path_setup")(maxx, maxy, maxz, turfs, coordinates): starts afresh for a world this size.
/// `turfs` are a few turfs and `coordinates` their x, y and z, to check turfs are numbered the way the engine thinks.
/// Returns ENGINE_VERSION. The station picture starts empty: every tile is asked about once.
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
			floods: BTreeMap::new(),
			next_id: 1,
			picture: Picture::new(per_level as usize * maxz as usize),
			regions: BTreeMap::new(),
			region_tiles: 0,
			next_region: 1,
			samples: Vec::new(),
			values: Vec::new(),
			out: Vec::new(),
			answers: Vec::new(),
			stats: Stats::default(),
		});
		Ok(ENGINE_VERSION)
	})
}

/// path_begin(start, end, maxnodedepth, mintargetdist, mode, end_penalty, exclude): a new search, not run yet. `mode` is 1 for
/// Distance_cardinal(), 2 for bot_weighted_distance(); plus 16 for a simulated_only search, 32 to leave the station picture out
/// (ask DM about every tile, as before it was kept), 64 for the picture check (ask DM about every tile and count where the
/// picture would have said something else), 128 to have a search with no route list the tiles it opened; plus 256 times how
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
		let simulated_only = mode & MODE_SIMULATED_ONLY != 0;
		let check = mode & MODE_PICTURE_CHECK != 0;
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
			simulated_only,
			use_picture: mode & (MODE_PICTURE_OFF | MODE_PICTURE_CHECK) == 0,
		});
		let flags = Flags {
			check,
			return_tiles: mode & MODE_RETURN_TILES != 0,
			start: args[0].data,
			simulated_only,
		};
		while state.searches.len() >= MAX_SEARCHES {
			let oldest = *state.searches.keys().next().unwrap();
			state.searches.remove(&oldest);
		}
		let id = state.next_id;
		state.next_id = if state.next_id >= 1 << 23 { 1 } else { state.next_id + 1 };
		state.searches.insert(id, (search, flags));
		state.stats.searches += 1;
		Ok(id as f32)
	})
}

/// path_step(id, answers, out): the answers (numbers, search.rs says what they mean, with the tile's kind for the station picture
/// above them: picture.rs) for the tiles it asked about last, an empty list the first time. Runs the search on and returns:
/// - 1: it wants tiles told about: `out` holds them
/// - 2: found: `out` is how many tiles it opened, then the path, start to end
/// - 3: no route: `out` is how many tiles it opened, 1 if maxnodedepth stopped it expanding any (else 0), the number of the region
///   of tiles it opened (path_region_has()), then every tile it opened if the search was begun with 128 in its mode
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
		let State { searches, picture, stats, samples, .. } = state;
		let (search, flags) = searches.get_mut(&id).ok_or_else(|| format!("no search {id}"))?;
		if answers.len() != search.asked.len() {
			state.answers = answers;
			return Err(format!("{} answers for {} tiles", state.answers.len(), search.asked.len()));
		}
		take_answers(&search.asked, &mut answers, picture, stats, samples, flags);
		let answered = search.answer(&answers);
		state.answers = answers;
		answered?;
		let State { searches, picture, .. } = state;
		let (search, flags) = searches.get_mut(&id).ok_or_else(|| format!("no search {id}"))?;
		let outcome = search.step(picture);
		let return_tiles = flags.return_tiles;
		let mut out = std::mem::take(&mut state.out);
		out.clear();
		let mut finished = None;
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
				state.stats.no_route += 1;
				state.stats.opened += opened.len() as u64;
				out.push(ByondValue::num(opened.len() as f32));
				out.push(ByondValue::num(if depth_cut { 1.0 } else { 0.0 }));
				if return_tiles {
					out.push(ByondValue::num(0.0));
					out.extend(opened.iter().map(|&t| ByondValue::turf(t)));
				} else {
					finished = Some(opened);
				}
				3.0
			}
			Outcome::Abort(why) => {
				eprintln!("hippie_path: search {id} handed back to DM: {why}");
				state.stats.aborted += 1;
				4.0
			}
		};
		if status != 1.0 {
			if let Some((search, _)) = state.searches.remove(&id) {
				state.stats.rounds += search.rounds as u64;
				state.stats.tiles_asked += search.tiles_asked as u64;
				state.stats.picture_hits += search.picture_hits as u64;
			}
		}
		if let Some(opened) = finished {
			let region = state.keep_region(opened);
			out.push(ByondValue::num(region as f32));
		}
		let written = write_values(api, &args[2], &out);
		state.out = out;
		written?;
		Ok(status)
	})
}

/// Each answer's kind goes into the station picture, after the picture check has seen what the picture would have said; the
/// answers are left without their kinds
fn take_answers(asked: &[u32], answers: &mut [u32], picture: &mut Picture, stats: &mut Stats, samples: &mut Vec<Mismatch>, flags: &Flags) {
	for (i, &turf) in asked.iter().enumerate() {
		let kind = (answers[i] >> picture::KIND_SHIFT) as u8;
		answers[i] &= picture::ANSWER_MASK;
		if flags.check {
			if let Some(predicted) = picture.answer(turf, flags.start, flags.simulated_only) {
				stats.checked += 1;
				if predicted != answers[i] {
					stats.mismatched += 1;
					if samples.len() < MAX_CHECK_SAMPLES {
						samples.push(Mismatch { turf, predicted, actual: answers[i], kind: picture.kind(turf) });
					}
				}
			}
		}
		if kind != picture::UNKNOWN {
			picture.set(turf, kind);
		}
	}
}

/// path_flood_begin(start, mode, max_steps, max_tiles, stop_at): a flood (flood.rs), not run yet. `mode` as path_begin()'s (16
/// simulated_only, 32 picture off, 64 picture check, 128 list the tiles even forward), plus 256 for a backward flood. `stop_at` is
/// a turf or null. Returns the flood's number, for path_flood_step().
#[no_mangle]
pub unsafe extern "C" fn path_flood_begin(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("flood_begin", |_api, state| {
		if args.len() < 5 {
			return Err(format!("{} arguments, wanted 5", args.len()));
		}
		if args[0].kind != TYPE_TURF {
			return Err("the start must be a turf".into());
		}
		let mode = args[1].as_int();
		let backward = mode & MODE_BACKWARD != 0;
		let simulated_only = mode & MODE_SIMULATED_ONLY != 0;
		// a backward flood asks "can that tile step onto this" of every tile: none is a search's start to DM
		let start_for_answers = if backward { NO_TILE } else { args[0].data };
		let flood = Flood::new(FloodSettings {
			maxx: state.maxx,
			maxy: state.maxy,
			per_level: state.per_level,
			start: args[0].data,
			backward,
			max_steps: args[2].as_int().max(0) as u32,
			max_tiles: args[3].as_int().max(0) as usize,
			stop_at: if args[4].kind == TYPE_TURF { args[4].data } else { NO_TILE },
			stop_at_hub: mode & MODE_STOP_AT_HUB != 0,
			simulated_only,
			use_picture: mode & (MODE_PICTURE_OFF | MODE_PICTURE_CHECK) == 0,
		});
		let flags = Flags {
			check: mode & MODE_PICTURE_CHECK != 0,
			return_tiles: backward || mode & MODE_RETURN_TILES != 0,
			start: start_for_answers,
			simulated_only,
		};
		while state.floods.len() >= MAX_SEARCHES {
			let oldest = *state.floods.keys().next().unwrap();
			state.floods.remove(&oldest);
		}
		let id = state.next_id;
		state.next_id = if state.next_id >= 1 << 23 { 1 } else { state.next_id + 1 };
		state.floods.insert(id, (flood, flags));
		Ok(id as f32)
	})
}

/// path_flood_step(id, answers, out): like path_step(). Returns 1 with the tiles wanted in `out`, or 2 when done, `out` then being:
/// how many tiles it reached, 1 if it reached stop_at, 1 if it grew past max_tiles, the number of a region of them (forward floods
/// only, else 0), then every tile reached if it lists them (backward floods, or 128 in the mode).
#[no_mangle]
pub unsafe extern "C" fn path_flood_step(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("flood_step", |api, state| {
		if args.len() < 3 {
			return Err(format!("{} arguments, wanted 3", args.len()));
		}
		let id = args[0].as_int() as u32;
		let mut values = std::mem::take(&mut state.values);
		read_values(api, &args[1], &mut values)?;
		let mut answers: Vec<u32> = values.iter().map(|v| v.as_f32() as u32).collect();
		state.values = values;
		let State { floods, picture, stats, samples, .. } = state;
		let (flood, flags) = floods.get_mut(&id).ok_or_else(|| format!("no flood {id}"))?;
		if answers.len() != flood.asked.len() {
			return Err(format!("{} answers for {} tiles", answers.len(), flood.asked.len()));
		}
		take_answers(&flood.asked, &mut answers, picture, stats, samples, flags);
		flood.answer(&answers)?;
		let outcome = flood.step(picture);
		let return_tiles = flags.return_tiles;
		let backward = flags.start == NO_TILE;
		let mut out = Vec::new();
		let status = match outcome {
			FloodOutcome::Need => {
				out.extend(flood.asked.iter().map(|&t| ByondValue::turf(t)));
				1.0
			}
			FloodOutcome::Done(tiles, stopped, big) => {
				if let Some((flood, _)) = state.floods.remove(&id) {
					state.stats.rounds += flood.rounds as u64;
					state.stats.tiles_asked += flood.tiles_asked as u64;
					state.stats.picture_hits += flood.picture_hits as u64;
				}
				state.stats.floods += 1;
				out.push(ByondValue::num(tiles.len() as f32));
				out.push(ByondValue::num(if stopped { 1.0 } else { 0.0 }));
				out.push(ByondValue::num(if big { 1.0 } else { 0.0 }));
				if return_tiles {
					out.push(ByondValue::num(0.0));
					out.extend(tiles.iter().map(|&t| ByondValue::turf(t)));
				} else if !backward {
					let region = state.keep_region(tiles);
					out.push(ByondValue::num(region as f32));
				} else {
					out.push(ByondValue::num(0.0));
				}
				2.0
			}
		};
		write_values(api, &args[2], &out)?;
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
			state.floods.remove(&(id.as_int() as u32));
		}
		Ok(state.searches.len() as f32)
	})
}

/// path_dirty(turfs): these tiles have changed since DM last said what they were (station_picture.dm): the station picture forgets
/// them, so the next search that needs one asks. Returns how many.
#[no_mangle]
pub unsafe extern "C" fn path_dirty(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("dirty", |api, state| {
		let Some(list) = args.first() else {
			return Ok(0.0);
		};
		let mut values = std::mem::take(&mut state.values);
		read_values(api, list, &mut values)?;
		let mut count = 0u64;
		for value in &values {
			if value.kind == TYPE_TURF {
				state.picture.forget(value.data);
				count += 1;
			}
		}
		state.values = values;
		state.stats.dirtied += count;
		Ok(count as f32)
	})
}

/// path_hubs(turfs): the hallway tiles, afresh (backward floods stop at them)
#[no_mangle]
pub unsafe extern "C" fn path_hubs(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("hubs", |api, state| {
		let Some(list) = args.first() else {
			return Ok(0.0);
		};
		let mut values = Vec::new();
		read_values(api, list, &mut values)?;
		let turfs: Vec<u32> = values.iter().filter(|v| v.kind == TYPE_TURF).map(|v| v.data).collect();
		let count = turfs.len();
		state.picture.set_hubs(turfs.into_iter());
		Ok(count as f32)
	})
}

/// path_region_has(region, turf): 1 if the search that found no route opened this tile, 0 if it didn't, 2 if the region isn't
/// kept any more (DM then doesn't know, and searches)
#[no_mangle]
pub unsafe extern "C" fn path_region_has(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("region_has", |_api, state| {
		if args.len() < 2 || args[1].kind != TYPE_TURF {
			return Ok(0.0);
		}
		Ok(match state.regions.get(&(args[0].as_int() as u32)) {
			Some(tiles) => {
				if tiles.binary_search(&args[1].data).is_ok() {
					1.0
				} else {
					0.0
				}
			}
			None => 2.0,
		})
	})
}

/// path_region_forget(region): DM is done with it
#[no_mangle]
pub unsafe extern "C" fn path_region_forget(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("region_forget", |_api, state| {
		if let Some(id) = args.first() {
			if let Some(gone) = state.regions.remove(&(id.as_int() as u32)) {
				state.region_tiles -= gone.len();
			}
		}
		Ok(state.regions.len() as f32)
	})
}

/// path_stats(out): searches begun, found, no route, handed back, rounds, tiles asked about, tiles opened, searches open now, tiles
/// the station picture answered, tiles DM said had changed, the picture's open, solid, open space and asked-every-time tiles,
/// regions kept and their tiles, and the picture check's answers compared and how many differed
#[no_mangle]
pub unsafe extern "C" fn path_stats(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("stats", |api, state| {
		let s = &state.stats;
		let kinds = state.picture.counts();
		let values: Vec<ByondValue> = [
			s.searches,
			s.found,
			s.no_route,
			s.aborted,
			s.rounds,
			s.tiles_asked,
			s.opened,
			state.searches.len() as u64,
			s.picture_hits,
			s.dirtied,
			kinds[0],
			kinds[1],
			kinds[2],
			kinds[3],
			state.regions.len() as u64,
			state.region_tiles as u64,
			s.checked,
			s.mismatched,
		]
		.iter()
		.map(|&n| ByondValue::num(n as f32))
		.collect();
		if let Some(out) = args.first() {
			write_values(api, out, &values)?;
		}
		Ok(ENGINE_VERSION)
	})
}

/// path_check_samples(out): the picture check's disagreements so far, four numbers each: the tile, what the picture would have
/// answered, what DM answered, and the kind the picture had for it. Clears them.
#[no_mangle]
pub unsafe extern "C" fn path_check_samples(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("check_samples", |api, state| {
		let mut values = Vec::new();
		for sample in state.samples.drain(..) {
			values.push(ByondValue::turf(sample.turf));
			values.push(ByondValue::num(sample.predicted as f32));
			values.push(ByondValue::num(sample.actual as f32));
			values.push(ByondValue::num(sample.kind as f32));
		}
		if let Some(out) = args.first() {
			write_values(api, out, &values)?;
		}
		Ok((values.len() / 4) as f32)
	})
}
