//! Hippie's tile atmos engine, called from SSair (hippiestation/code/modules/atmospherics/tile_engine.dm).
//! The maths is in engine.rs; this is just the BYOND side of it.
//!
//! It reads lists DM passes in and writes into lists DM passes in, which mostly hold numbers, gas paths and turfs. None
//! of those are reference counted. The one exception is atmos_engine_write(), which is handed the gas mixtures and gas
//! lists of the turfs whose air changed, to write their new air straight into them, and releases what it read if this
//! BYOND counts reads as references (see atmos_engine_write_setup()). The BYOND API functions it uses (see BYOND's
//! byondapi/byondapi.h) are looked up in byondcore.dll at first use, so the library works with any 516 build that has
//! them.

pub mod engine;

use engine::{NewTile, Tick, KIND_NO_AIR};
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Mutex, OnceLock};

/// Bumped whenever the lists DM and the engine pass each other change shape. DM won't use a library that says
/// anything else and runs LINDA instead.
pub const ENGINE_VERSION: f32 = 11.0;

const TYPE_NULL: u8 = 0x00;
const TYPE_TURF: u8 = 0x01;
const TYPE_NUMBER: u8 = 0x2A;

/// A gas in DM's list that setup wasn't told about
const NO_GAS: u8 = u8::MAX;

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

	fn as_number(&self) -> f64 {
		if self.kind == TYPE_NUMBER {
			f32::from_bits(self.data) as f64
		} else {
			0.0 // nulls (from DM growing a list) count as 0
		}
	}

	fn null() -> Self {
		ByondValue {
			kind: TYPE_NULL,
			junk: [0; 3],
			data: 0,
		}
	}
}

type ReadListFn = unsafe extern "C" fn(loc: *const ByondValue, list: *mut ByondValue, len: *mut u32) -> bool;
type WriteListFn = unsafe extern "C" fn(loc: *const ByondValue, list: *const ByondValue, len: u32) -> bool;
type WriteListIndexFn = unsafe extern "C" fn(loc: *const ByondValue, index: *const ByondValue, value: *const ByondValue) -> bool;
type WriteVarFn = unsafe extern "C" fn(loc: *const ByondValue, name: u32, value: *const ByondValue) -> bool;
type GetStrIdFn = unsafe extern "C" fn(name: *const u8) -> u32;
type DecRefFn = unsafe extern "C" fn(value: *const ByondValue);
type RefcountFn = unsafe extern "C" fn(value: *const ByondValue, count: *mut u32) -> bool;

/// What atmos_engine_write() needs on top of reading and writing lists
struct Writer {
	write_list_index: WriteListIndexFn,
	write_var: WriteVarFn,
	get_str_id: GetStrIdFn,
	dec_ref: DecRefFn,
	refcount: RefcountFn,
}

fn writer() -> Option<&'static Writer> {
	static WRITER: OnceLock<Option<Writer>> = OnceLock::new();
	WRITER
		.get_or_init(|| {
			let index = platform::find(b"Byond_WriteListIndex\0");
			let var = platform::find(b"Byond_WriteVarByStrId\0");
			let str_id = platform::find(b"Byond_GetStrId\0");
			let dec_ref = platform::find(b"ByondValue_DecRef\0");
			let refcount = platform::find(b"Byond_Refcount\0");
			if [index, var, str_id, dec_ref, refcount].iter().any(|f| f.is_null()) {
				return None;
			}
			unsafe {
				Some(Writer {
					write_list_index: std::mem::transmute::<*mut c_void, WriteListIndexFn>(index),
					write_var: std::mem::transmute::<*mut c_void, WriteVarFn>(var),
					get_str_id: std::mem::transmute::<*mut c_void, GetStrIdFn>(str_id),
					dec_ref: std::mem::transmute::<*mut c_void, DecRefFn>(dec_ref),
					refcount: std::mem::transmute::<*mut c_void, RefcountFn>(refcount),
				})
			}
		})
		.as_ref()
}

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
		// RTLD_DEFAULT: look through everything already loaded, which includes libbyond.so
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

/// Reads a list's items into `into`, which keeps its size for the next read
fn read_values(api: &Api, list: &ByondValue, into: &mut Vec<ByondValue>) -> Result<(), String> {
	if into.len() < 256 {
		into.resize(256, ByondValue::null());
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

fn read_numbers(api: &Api, list: &ByondValue) -> Result<Vec<f64>, String> {
	let mut buffer = Vec::new();
	read_values(api, list, &mut buffer)?;
	Ok(buffer.iter().map(ByondValue::as_number).collect())
}

fn write_values(api: &Api, list: &ByondValue, values: &[ByondValue]) -> Result<(), String> {
	if unsafe { (api.write_list)(list, values.as_ptr(), values.len() as u32) } {
		Ok(())
	} else {
		Err("couldn't write a result list".into())
	}
}

fn turf_number(value: &ByondValue) -> Result<u32, String> {
	if value.kind == TYPE_TURF {
		Ok(value.data)
	} else {
		Err(format!("expected a turf, got type {}", value.kind))
	}
}

/// The arguments call_ext() passed, as a slice
unsafe fn arguments<'a>(argc: u32, argv: *const ByondValue) -> &'a [ByondValue] {
	if argv.is_null() || argc == 0 {
		&[]
	} else {
		std::slice::from_raw_parts(argv, argc as usize)
	}
}

/// What the engine keeps about turfs between ticks, by turf number: their kind and neighbours, which only change when
/// DM's atmos_adjacent_turfs does (DM sends them again then). u32::MAX for a turf it hasn't been told about.
#[derive(Default)]
struct Known {
	kind: Vec<u32>,
	adjacent: Vec<Vec<u32>>,
}

impl Known {
	fn set(&mut self, id: u32, kind: u32, adjacent: &[u32]) {
		let i = id as usize;
		if i >= self.kind.len() {
			self.kind.resize(i + 1, u32::MAX);
			self.adjacent.resize_with(i + 1, Vec::new);
		}
		self.kind[i] = kind;
		self.adjacent[i].clear();
		self.adjacent[i].extend_from_slice(adjacent);
	}

	fn get(&self, id: u32) -> Option<(u32, &[u32])> {
		let i = id as usize;
		match self.kind.get(i) {
			Some(&kind) if kind != u32::MAX => Some((kind, &self.adjacent[i])),
			_ => None,
		}
	}
}

struct State {
	config: engine::Config,
	tick: Tick,
	known: Known,
	/// atmos-engine-cache=shadow: turfs whose kept kind and neighbours were checked against what DM sent, and how many
	/// of those didn't match
	shadow_checked: u64,
	shadow_mismatches: u64,
	/// atmos_engine_write_setup() found writing works: the id of the string "temperature", and whether references read out
	/// of a list have to be released (they're temporary on older 516 builds, and count until released on newer ones)
	write_ready: bool,
	temperature_id: u32,
	release_reads: bool,
	refs: Vec<ByondValue>,
	/// A gas path's number -> its index in the engine, NO_GAS for anything else
	gas_lookup: Vec<u8>,
	/// Gas index -> its path
	gas_paths: Vec<ByondValue>,
	// Lists kept between ticks so they don't get made again every time
	turfs: Vec<ByondValue>,
	rows: Vec<ByondValue>,
	neighbours: Vec<ByondValue>,
	adjacent: Vec<u32>,
	gases: Vec<(usize, f64)>,
	wanted: Vec<u32>,
	out: Vec<ByondValue>,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);

/// Runs one of the calls, turning an error or a panic into a negative number for DM and a line in the server log
fn guarded(name: &str, call: impl FnOnce() -> Result<f32, String>) -> ByondValue {
	match catch_unwind(AssertUnwindSafe(call)) {
		Ok(Ok(value)) => ByondValue::num(value),
		Ok(Err(error)) => {
			eprintln!("hippie_atmos {name}: {error}");
			ByondValue::num(-1.0)
		}
		Err(_) => {
			eprintln!("hippie_atmos {name}: panicked");
			ByondValue::num(-2.0)
		}
	}
}

/// call_ext("hippie_atmos", "byond:atmos_engine_version")()
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_version(_argc: u32, _argv: *const ByondValue) -> ByondValue {
	ByondValue::num(ENGINE_VERSION)
}

/// call_ext("hippie_atmos", "byond:atmos_engine_setup")(settings, gas_paths): takes the constants and reactions (see
/// engine::Config::parse() for the layout) and every gas's path, in the order the settings list them. Returns how many
/// gases it took, or a negative number if it failed.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_setup(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("setup", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 2 {
			return Err(format!("{} arguments, wanted settings and gas paths", args.len()));
		}
		let config = engine::Config::parse(&read_numbers(api, &args[0])?)?;
		let mut gas_paths = Vec::new();
		read_values(api, &args[1], &mut gas_paths)?;
		if gas_paths.len() != config.gases {
			return Err(format!("{} gas paths for {} gases", gas_paths.len(), config.gases));
		}
		let biggest = gas_paths.iter().map(|path| path.data).max().unwrap_or(0) as usize;
		let mut gas_lookup = vec![NO_GAS; biggest + 1];
		for (index, path) in gas_paths.iter().enumerate() {
			gas_lookup[path.data as usize] = index as u8;
		}
		let gases = config.gases as f32;
		*STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(State {
			config,
			tick: Tick::new(),
			known: Known::default(),
			shadow_checked: 0,
			shadow_mismatches: 0,
			write_ready: false,
			temperature_id: 0,
			release_reads: false,
			refs: Vec::new(),
			gas_lookup,
			gas_paths,
			turfs: Vec::new(),
			rows: Vec::new(),
			neighbours: Vec::new(),
			adjacent: Vec::new(),
			gases: Vec::new(),
			wanted: Vec::new(),
			out: Vec::new(),
		});
		Ok(gases)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_run")(turfs, tiles, adjacent, planetary, awake, wanted): adds the turfs in
/// `turfs` and runs. `awake` is 1 for the first call of a tick, with `turfs` being SSair.active_turfs. For each turf,
/// `tiles` has how many gases it has (-1 for a turf with no air, with nothing else after), a path and moles for each,
/// then its temperature, how many neighbours it has, kind, excited group number, significant_share_ticker, whether it's
/// burning and its drawn overlay key. `adjacent` has those neighbours, one turf after another. `planetary` has G moles
/// and a temperature per planetary mix.
/// The engine keeps each turf's kind and neighbours. A neighbour count of -1 means use what it has (nothing in
/// `adjacent`, kind ignored). -2 - N means the same, but here are the N neighbours and the kind anyway, to check what it
/// has against (atmos-engine-cache=shadow).
/// Returns 1 when the tick is done, or 2 with the turfs it still needs in `wanted`, for calling this again with those.
/// A negative number if it failed.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_run(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("run", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 6 {
			return Err(format!("{} arguments, wanted turfs, tiles, adjacent, planetary, awake and wanted", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("ran before setup")?;
		let awake = args[4].as_number() != 0.0;
		if awake {
			state.tick.begin(&state.config);
		}
		read_values(api, &args[0], &mut state.turfs)?;
		read_values(api, &args[1], &mut state.rows)?;
		read_values(api, &args[2], &mut state.neighbours)?;
		let planetary = read_numbers(api, &args[3])?;

		state.adjacent.clear();
		for neighbour in &state.neighbours {
			state.adjacent.push(turf_number(neighbour)?);
		}
		{
		let State {
			tick,
			known,
			rows,
			turfs,
			adjacent,
			gases,
			gas_lookup,
			shadow_checked,
			shadow_mismatches,
			..
		} = &mut *state;
		let mut at = 0;
		let mut adjacent_at = 0;
		for turf in turfs.iter() {
			let id = turf_number(turf)?;
			let gas_count = rows[at].as_number() as i32;
			at += 1;
			if gas_count < 0 {
				tick.add(NewTile {
					id,
					gases: &[],
					temperature: 0.0,
					adjacent: &[],
					kind: KIND_NO_AIR,
					group: 0,
					ticker: 0.0,
					hotspot: false,
					drawn: 0.0,
					awake,
				});
				continue;
			}
			gases.clear();
			for _ in 0..gas_count {
				let gas = gas_lookup.get(rows[at].data as usize).copied().unwrap_or(NO_GAS);
				if gas == NO_GAS {
					return Err(format!("a gas setup wasn't told about (type {}, {})", rows[at].kind, rows[at].data));
				}
				gases.push((gas as usize, rows[at + 1].as_number()));
				at += 2;
			}
			let count = rows[at + 1].as_number() as i64;
			let sent_kind = rows[at + 2].as_number() as u32;
			if count >= 0 {
				// Its kind and neighbours, new or changed: kept for next time
				let n = count as usize;
				known.set(id, sent_kind, &adjacent[adjacent_at..adjacent_at + n]);
				adjacent_at += n;
			} else if count <= -2 {
				// What it should have, to check what it has against
				let n = (-2 - count) as usize;
				let sent = &adjacent[adjacent_at..adjacent_at + n];
				adjacent_at += n;
				*shadow_checked += 1;
				let matches = matches!(known.get(id), Some((kind, kept)) if kind == sent_kind && kept == sent);
				if !matches {
					*shadow_mismatches += 1;
					if *shadow_mismatches <= 10 {
						eprintln!("hippie_atmos cache: turf {id} kept {:?}, DM has kind {sent_kind} and {sent:?}", known.get(id));
					}
				}
			}
			let (kind, kept) = known.get(id).ok_or_else(|| format!("turf {id}'s kind and neighbours were never sent"))?;
			tick.add(NewTile {
				id,
				gases,
				temperature: rows[at].as_number(),
				adjacent: kept,
				kind,
				group: rows[at + 3].as_number() as u32,
				ticker: rows[at + 4].as_number(),
				hotspot: rows[at + 5].as_number() != 0.0,
				drawn: rows[at + 6].as_number(),
				awake,
			});
			at += 7;
		}
		if at != rows.len() || adjacent_at != adjacent.len() {
			return Err(format!("read {at} of {} numbers and {adjacent_at} of {} neighbours", rows.len(), adjacent.len()));
		}
		}

		state.wanted.clear();
		if state.tick.run(&state.config, &planetary, &mut state.wanted) {
			state.tick.finish(&state.config);
			return Ok(1.0);
		}
		if state.wanted.is_empty() {
			return Err("stopped without asking for anything".into());
		}
		state.out.clear();
		state.out.extend(state.wanted.iter().map(|&id| ByondValue::turf(id)));
		write_values(api, &args[5], &state.out)?;
		Ok(2.0)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_archives")(turfs, values): what the turfs' archives ended up as this tick,
/// for heat through walls, which works from them. `values` has, for each turf, -1 if it wasn't archived, or else its
/// archived temperature, how many gases it had, then a path and moles for each. Returns 1, or a negative number if it
/// failed.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_archives(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("archives", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 2 {
			return Err(format!("{} arguments, wanted turfs and values", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("archives before setup")?;
		read_values(api, &args[0], &mut state.turfs)?;
		state.out.clear();
		for turf in &state.turfs {
			match state.tick.archive_of(turf_number(turf)?, &mut state.gases) {
				None => state.out.push(ByondValue::num(-1.0)),
				Some(temperature) => {
					state.out.push(ByondValue::num(temperature as f32));
					state.out.push(ByondValue::num(state.gases.len() as f32));
					for &(gas, amount) in &state.gases {
						state.out.push(state.gas_paths[gas]);
						state.out.push(ByondValue::num(amount as f32));
					}
				}
			}
		}
		write_values(api, &args[1], &state.out)?;
		Ok(1.0)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_results")(active, changed, values, order, tickers, woken, slept, joins,
/// groups_big, groups_small, windy, wind_to, wind_force, react, redraw, redraw_keys, hot): what came of the tick. `active`
/// is SSair.active_turfs, written over in its new order. `values` has, for each turf in `changed`, how many gases
/// changed, a path and moles for each (0 moles means it's gone), then its temperature; pass null for it when
/// atmos_engine_write() writes the air instead. See engine::Tick for the rest.
/// Returns 1, or a negative number if it failed.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_results(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("results", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 17 {
			return Err(format!("{} arguments, wanted 17", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("results before setup")?;
		let tick = &state.tick;
		let out = &mut state.out;
		let turf = |tile: u32| ByondValue::turf(tick.turf(tile));

		out.clear();
		out.extend(tick.active.iter().map(|&tile| turf(tile)));
		write_values(api, &args[0], out)?;

		out.clear();
		out.extend(tick.changes.iter().map(|change| turf(change.tile)));
		write_values(api, &args[1], out)?;

		if args[2].kind != TYPE_NULL {
			// null when atmos_engine_write() writes the air instead
			out.clear();
			for change in &tick.changes {
				out.push(ByondValue::num(change.count as f32));
				let first = change.first as usize;
				for &(gas, amount) in &tick.gas_changes[first..first + change.count as usize] {
					out.push(state.gas_paths[gas as usize]);
					out.push(ByondValue::num(amount as f32));
				}
				out.push(ByondValue::num(change.temperature as f32));
			}
			write_values(api, &args[2], out)?;
		}

		out.clear();
		out.extend(tick.order.iter().map(|&tile| turf(tile)));
		write_values(api, &args[3], out)?;

		out.clear();
		out.extend(tick.order.iter().map(|&tile| ByondValue::num(tick.ticker(tile) as f32)));
		write_values(api, &args[4], out)?;

		for (list, tiles) in [
			(5, &tick.stayed_awake),
			(6, &tick.slept),
			(8, &tick.groups_big),
			(9, &tick.groups_small),
			(13, &tick.react),
			(16, &tick.hot),
		] {
			if !tiles.is_empty() {
				out.clear();
				out.extend(tiles.iter().map(|&tile| turf(tile)));
				write_values(api, &args[list], out)?;
			}
		}

		if !tick.group_joins.is_empty() {
			out.clear();
			for &(a, b) in &tick.group_joins {
				out.push(turf(a));
				out.push(turf(b));
			}
			write_values(api, &args[7], out)?;
		}

		if !tick.windy.is_empty() {
			out.clear();
			out.extend(tick.windy.iter().map(|wind| turf(wind.0)));
			write_values(api, &args[10], out)?;
			out.clear();
			out.extend(tick.windy.iter().map(|wind| turf(wind.1)));
			write_values(api, &args[11], out)?;
			out.clear();
			out.extend(tick.windy.iter().map(|wind| ByondValue::num(wind.2 as f32)));
			write_values(api, &args[12], out)?;
		}

		if !tick.redraw.is_empty() {
			out.clear();
			out.extend(tick.redraw.iter().map(|redraw| turf(redraw.0)));
			write_values(api, &args[14], out)?;
			out.clear();
			out.extend(tick.redraw.iter().map(|redraw| ByondValue::num(redraw.1 as f32)));
			write_values(api, &args[15], out)?;
		}
		Ok(1.0)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_cache_check")(out): with atmos-engine-cache=shadow, how many turfs had their
/// kept kind and neighbours checked against what DM sent, and how many of those didn't match, written into `out`.
/// Returns 1, or a negative number if it failed.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_cache_check(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("cache_check", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		let out = args.first().ok_or("no list")?;
		let guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_ref().ok_or("cache_check before setup")?;
		write_values(api, out, &[ByondValue::num(state.shadow_checked as f32), ByondValue::num(state.shadow_mismatches as f32)])?;
		Ok(1.0)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_write_setup")(probe): gets atmos_engine_write() ready. `probe` is a list
/// holding one datum nothing else touches meanwhile: reading it twice shows whether this BYOND counts what's read out of a
/// list as a reference until it's released. Returns 1 if writing works, 0 if it can't be used (DM writes the air itself
/// then), or a negative number if it failed.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_write_setup(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("write_setup", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("write_setup before setup")?;
		state.write_ready = false;
		let Some(writer) = writer() else {
			eprintln!("hippie_atmos write_setup: byondcore.dll is missing a function atmos_engine_write() needs");
			return Ok(0.0);
		};
		let probe_list = args.first().ok_or("no probe")?;
		let mut first = Vec::new();
		let mut second = Vec::new();
		read_values(api, probe_list, &mut first)?;
		let mut before = 0u32;
		if first.len() != 1 || !(writer.refcount)(&first[0], &mut before) {
			return Err("couldn't read the probe's reference count".into());
		}
		read_values(api, probe_list, &mut second)?;
		let mut after = 0u32;
		if second.len() != 1 || !(writer.refcount)(&second[0], &mut after) {
			return Err("couldn't read the probe's reference count".into());
		}
		let release = match after.wrapping_sub(before) {
			0 => false,
			1 => true,
			other => {
				eprintln!("hippie_atmos write_setup: reading the probe again added {other} references, not 0 or 1");
				return Ok(0.0);
			}
		};
		if release {
			(writer.dec_ref)(&first[0]);
			(writer.dec_ref)(&second[0]);
		}
		let temperature_id = (writer.get_str_id)(b"temperature\0".as_ptr());
		if temperature_id == u32::MAX || temperature_id == 0xFFFF {
			eprintln!("hippie_atmos write_setup: BYOND has no string \"temperature\"");
			return Ok(0.0);
		}
		state.temperature_id = temperature_id;
		state.release_reads = release;
		state.write_ready = true;
		Ok(if release { 1.0 } else { 2.0 })
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_write")(refs, removed, hot): writes the tick's new air straight into the
/// turfs whose air changed. `refs` has each changed turf's gas mixture and its gas list, in the order atmos_engine_results()
/// gave the turfs. Gases get their new moles and the mixture its temperature, in the same order DM's own write-back would. A
/// gas that ran out has to come off its list, which only DM can do: those go into `removed` as the turf's position in `refs`
/// (from 1) and the gas's path. `hot` gets the positions of turfs at 10000 K or more, in order, which DM exposes to their
/// temperature. Returns 1, or a negative number if it failed.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_write(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("write", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		let writer = writer().ok_or("writing isn't available")?;
		if args.len() < 3 {
			return Err(format!("{} arguments, wanted refs, removed and hot", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("write before setup")?;
		if !state.write_ready {
			return Err("write before write_setup".into());
		}
		let mut refs = std::mem::take(&mut state.refs);
		read_values(api, &args[0], &mut refs)?;
		let result = write_air(state, writer, &refs);
		// Whatever happened, what was read is let go of again
		if state.release_reads {
			for value in &refs {
				if value.kind != TYPE_NULL && value.kind != TYPE_NUMBER {
					(writer.dec_ref)(value);
				}
			}
		}
		state.refs = refs;
		let (removed, hot) = result?;
		if !removed.is_empty() {
			write_values(api, &args[1], &removed)?;
		}
		if !hot.is_empty() {
			write_values(api, &args[2], &hot)?;
		}
		Ok(1.0)
	})
}

/// atmos_engine_write()'s writing: returns the gases that ran out, for DM to take off their lists, and where the turfs at
/// 10000 K or more are
unsafe fn write_air(state: &State, writer: &Writer, refs: &[ByondValue]) -> Result<(Vec<ByondValue>, Vec<ByondValue>), String> {
	let tick = &state.tick;
	if refs.len() != tick.changes.len() * 2 {
		return Err(format!("{} references for {} changed turfs", refs.len(), tick.changes.len()));
	}
	let mut removed = Vec::new();
	let mut hot = Vec::new();
	for (position, change) in tick.changes.iter().enumerate() {
		let air = &refs[position * 2];
		let moles = &refs[position * 2 + 1];
		let first = change.first as usize;
		for &(gas, amount) in &tick.gas_changes[first..first + change.count as usize] {
			let path = &state.gas_paths[gas as usize];
			let amount = amount as f32;
			if amount != 0.0 {
				if !(writer.write_list_index)(moles, path, &ByondValue::num(amount)) {
					return Err(format!("couldn't write a gas into changed turf {}'s list", position + 1));
				}
			} else {
				removed.push(ByondValue::num((position + 1) as f32));
				removed.push(*path);
			}
		}
		let temperature = change.temperature as f32;
		if !(writer.write_var)(air, state.temperature_id, &ByondValue::num(temperature)) {
			return Err(format!("couldn't write changed turf {}'s temperature", position + 1));
		}
		if temperature >= 10000.0 {
			hot.push(ByondValue::num((position + 1) as f32));
		}
	}
	Ok((removed, hot))
}
