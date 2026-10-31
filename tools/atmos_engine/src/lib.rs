//! Hippie's tile atmos engine, called from SSair (hippiestation/code/modules/atmospherics/tile_engine.dm).
//! The maths is in engine.rs; this is just the BYOND side of it.
//!
//! It only ever reads lists DM passes in and writes into lists DM passes in, and those only hold numbers, gas paths and
//! turfs. None of those are reference counted, so it never has a BYOND reference to look after. The two BYOND API
//! functions it uses (see BYOND's byondapi/byondapi.h) are looked up in byondcore.dll at first use, so the library works
//! with any 516 build that has them.

pub mod engine;

use engine::{NewTile, Tick, KIND_NO_AIR};
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Mutex, OnceLock};

/// Bumped whenever the lists DM and the engine pass each other change shape. DM won't use a library that says
/// anything else and runs LINDA instead.
pub const ENGINE_VERSION: f32 = 8.0;

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

struct State {
	config: engine::Config,
	tick: Tick,
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
		let rows = &state.rows;
		let mut at = 0;
		let mut adjacent_at = 0;
		for turf in &state.turfs {
			let id = turf_number(turf)?;
			let gas_count = rows[at].as_number() as i32;
			at += 1;
			if gas_count < 0 {
				state.tick.add(NewTile {
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
			state.gases.clear();
			for _ in 0..gas_count {
				let gas = state.gas_lookup.get(rows[at].data as usize).copied().unwrap_or(NO_GAS);
				if gas == NO_GAS {
					return Err(format!("a gas setup wasn't told about (type {}, {})", rows[at].kind, rows[at].data));
				}
				state.gases.push((gas as usize, rows[at + 1].as_number()));
				at += 2;
			}
			let neighbours = rows[at + 1].as_number() as usize;
			state.tick.add(NewTile {
				id,
				gases: &state.gases,
				temperature: rows[at].as_number(),
				adjacent: &state.adjacent[adjacent_at..adjacent_at + neighbours],
				kind: rows[at + 2].as_number() as u32,
				group: rows[at + 3].as_number() as u32,
				ticker: rows[at + 4].as_number(),
				hotspot: rows[at + 5].as_number() != 0.0,
				drawn: rows[at + 6].as_number(),
				awake,
			});
			at += 7;
			adjacent_at += neighbours;
		}
		if at != rows.len() || adjacent_at != state.adjacent.len() {
			return Err(format!("read {at} of {} numbers and {adjacent_at} of {} neighbours", rows.len(), state.adjacent.len()));
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
/// changed, a path and moles for each (0 moles means it's gone), then its temperature. See engine::Tick for the rest.
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
