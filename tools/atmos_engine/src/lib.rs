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
pub mod world;

use engine::{NewTile, Tick, KIND_NO_AIR};
use std::collections::HashMap;
use world::{Known, World};
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Mutex, OnceLock};

/// Bumped whenever the lists DM and the engine pass each other change shape. DM won't use a library that says
/// anything else and runs LINDA instead.
pub const ENGINE_VERSION: f32 = 12.0;

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

struct State {
	config: engine::Config,
	tick: Tick,
	known: Known,
	/// atmos-engine-cache=shadow: turfs whose kept kind and neighbours were checked against what DM sent, and how many
	/// of those didn't match
	shadow_checked: u64,
	shadow_mismatches: u64,
	/// atmos-engine-air=shadow: turfs whose kept air was checked against what DM sent, how many didn't match, and a few of
	/// those that didn't (turf numbers) for DM to say where they are
	air_checked: u64,
	air_mismatches: u64,
	air_samples: Vec<u32>,
	/// Turfs sent as kept that the engine has no air for, this call
	missing: Vec<u32>,
	final_gases: Vec<(u8, f32)>,
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
	/// LINDA's own state, when the engine runs it (atmos-engine-own=on) or keeps a copy to check (shadow); see world.rs
	world: World,
	/// atmos_engine_own_run(): 0 between ticks, 1 once this tick's awake turfs are in
	own_phase: u8,
	/// Turfs the tick asked DM for, added when they come
	pending: Vec<u32>,
	/// atmos-engine-own=shadow: the air the engine would have given turfs when their groups broke down, checked against
	/// what DM gave them when DM next sends it
	shadow_air: Vec<(u32, f32, Vec<(u8, f32)>)>,
	shadow_breakdown: HashMap<u32, (f32, Vec<(u8, f32)>)>,
	breakdown_checked: u64,
	breakdown_wrong: u64,
	/// Of those that matched, how many weren't exactly the same (32-bit) numbers
	breakdown_inexact: u64,
	/// atmos-engine-own=shadow: ticks checked, then how many had a different active list, and turfs with a different
	/// ticker, burning or drawn key, then ticks with different groups
	own_checks: u64,
	own_wrong: [u64; 5],
	own_log: Vec<String>,
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
			air_checked: 0,
			air_mismatches: 0,
			air_samples: Vec::new(),
			missing: Vec::new(),
			final_gases: Vec::new(),
			out: Vec::new(),
			world: World::new(),
			own_phase: 0,
			pending: Vec::new(),
			shadow_air: Vec::new(),
			shadow_breakdown: HashMap::new(),
			breakdown_checked: 0,
			breakdown_wrong: 0,
			breakdown_inexact: 0,
			own_checks: 0,
			own_wrong: [0; 5],
			own_log: Vec::new(),
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
/// It keeps their air too, as DM holds it after each tick (atmos_engine_kept_air). A gas count of -2 means use that: no
/// gases and no temperature follow. -3 - N means the same, but here are the N gases and the temperature anyway, to check
/// what it has against (atmos-engine-air=shadow); the sent air is the one used.
/// Returns 1 when the tick is done, or 2 with the turfs it still needs in `wanted`, for calling this again with those. 3 if
/// it has no air for some turfs sent as kept: those are in `wanted`, and nothing from this call was taken, so DM sends the
/// same call again with their air.
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
		// Turfs sent as kept that there's no kept air for: asked for before anything of this call is taken in
		state.missing.clear();
		{
			let mut at = 0;
			for turf in state.turfs.iter() {
				let gas_count = state.rows[at].as_number() as i64;
				at += 1;
				if gas_count == -1 {
					continue;
				}
				if gas_count == -2 {
					let id = turf_number(turf)?;
					if state.known.air(id).is_none() {
						state.missing.push(id);
					}
					at += 6;
				} else {
					let n = if gas_count <= -3 { -3 - gas_count } else { gas_count } as usize;
					at += 2 * n + 7;
				}
			}
		}
		if !state.missing.is_empty() {
			state.out.clear();
			state.out.extend(state.missing.iter().map(|&id| ByondValue::turf(id)));
			write_values(api, &args[5], &state.out)?;
			return Ok(3.0);
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
			air_checked,
			air_mismatches,
			air_samples,
			..
		} = &mut *state;
		let mut at = 0;
		let mut adjacent_at = 0;
		for turf in turfs.iter() {
			let id = turf_number(turf)?;
			let gas_count = rows[at].as_number() as i32;
			at += 1;
			if gas_count == -1 {
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
			let kept_row = gas_count == -2;
			let check_row = gas_count <= -3;
			let sent_gases = if kept_row { 0 } else if check_row { -3 - gas_count } else { gas_count } as usize;
			gases.clear();
			for _ in 0..sent_gases {
				let gas = gas_lookup.get(rows[at].data as usize).copied().unwrap_or(NO_GAS);
				if gas == NO_GAS {
					return Err(format!("a gas setup wasn't told about (type {}, {})", rows[at].kind, rows[at].data));
				}
				gases.push((gas as usize, rows[at + 1].as_number()));
				at += 2;
			}
			let temperature = if kept_row {
				let (kept_temperature, kept_gases) = known.air(id).ok_or_else(|| format!("turf {id}'s air was never sent"))?;
				gases.extend(kept_gases.iter().map(|&(gas, amount)| (gas as usize, amount as f64)));
				kept_temperature as f64
			} else {
				let sent_temperature = rows[at].as_number();
				at += 1;
				if check_row {
					*air_checked += 1;
					if !kept_matches(known.air(id), sent_temperature, gases) {
						*air_mismatches += 1;
						if air_samples.len() < 40 {
							air_samples.push(id);
						}
						if *air_mismatches <= 10 {
							eprintln!("hippie_atmos air: turf {id} kept {:?}, DM has {sent_temperature} K and {gases:?}", known.air(id));
						}
					}
				}
				sent_temperature
			};
			let count = rows[at].as_number() as i64;
			let sent_kind = rows[at + 1].as_number() as u32;
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
				temperature,
				adjacent: kept,
				kind,
				group: rows[at + 2].as_number() as u32,
				ticker: rows[at + 3].as_number(),
				hotspot: rows[at + 4].as_number() != 0.0,
				drawn: rows[at + 5].as_number(),
				awake,
			});
			at += 6;
		}
		if at != rows.len() || adjacent_at != adjacent.len() {
			return Err(format!("read {at} of {} numbers and {adjacent_at} of {} neighbours", rows.len(), adjacent.len()));
		}
		}

		state.wanted.clear();
		if state.tick.run(&state.config, &planetary, &mut state.wanted) {
			state.tick.finish(&state.config);
			// What DM will hold of every turf in the tick, kept for next time
			let State { tick, known, final_gases, world, .. } = &mut *state;
			for i in 0..tick.packed() {
				if let Some((id, temperature)) = tick.final_air(i, final_gases) {
					known.set_air(id, temperature, final_gases);
				}
			}
			// atmos-engine-own=shadow: SSair.times_fired, and the engine keeps its copy of LINDA's state up to date
			if let Some(fire) = args.get(6).filter(|fire| fire.kind == TYPE_NUMBER) {
				world.absorb(tick, fire.as_number());
			}
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

		// Any list can be null, for results that aren't wanted (with atmos-engine-own=on the engine keeps who's awake, the
		// tickers and the groups itself)
		let wanted = |k: usize| args[k].kind != TYPE_NULL;
		if wanted(0) {
			out.clear();
			out.extend(tick.active.iter().map(|&tile| turf(tile)));
			write_values(api, &args[0], out)?;
		}

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

		if wanted(3) {
			out.clear();
			out.extend(tick.order.iter().map(|&tile| turf(tile)));
			write_values(api, &args[3], out)?;
		}

		if wanted(4) {
			out.clear();
			out.extend(tick.order.iter().map(|&tile| ByondValue::num(tick.ticker(tile) as f32)));
			write_values(api, &args[4], out)?;
		}

		for (list, tiles) in [
			(5, &tick.stayed_awake),
			(6, &tick.slept),
			(8, &tick.groups_big),
			(9, &tick.groups_small),
			(13, &tick.react),
			(16, &tick.hot),
		] {
			if !tiles.is_empty() && wanted(list) {
				out.clear();
				out.extend(tiles.iter().map(|&tile| turf(tile)));
				write_values(api, &args[list], out)?;
			}
		}

		if !tick.group_joins.is_empty() && wanted(7) {
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

/// Whether the air the engine would have given a turf when its group broke down is what DM gave it, near enough: the
/// two add up in a different order, so the last bits can differ
fn breakdown_matches(temperature: f32, gases: &[(u8, f32)], sent_temperature: f64, sent: &[(usize, f64)]) -> bool {
	let close = |a: f64, b: f64| (a - b).abs() <= 1e-4 * a.abs().max(b.abs()).max(1.0);
	if !close(temperature as f64, sent_temperature) {
		return false;
	}
	let amount = |list: &mut dyn Iterator<Item = (usize, f64)>, gas: usize| list.filter(|&(g, _)| g == gas).map(|(_, a)| a).sum::<f64>();
	(0..64usize).all(|gas| {
		let ours = amount(&mut gases.iter().map(|&(g, a)| (g as usize, a as f64)), gas);
		let theirs = amount(&mut sent.iter().copied(), gas);
		close(ours, theirs)
	})
}

/// Whether the kept air is the same as what DM sent: every gas, and the temperature, as DM's 32-bit numbers (a gas DM
/// has at 0 is the same as one it hasn't got)
fn kept_matches(kept: Option<(f32, &[(u8, f32)])>, temperature: f64, sent: &[(usize, f64)]) -> bool {
	let Some((kept_temperature, kept_gases)) = kept else {
		return false;
	};
	if kept_temperature != temperature as f32 {
		return false;
	}
	let sent_nonzero = sent.iter().filter(|&&(_, amount)| amount as f32 != 0.0).count();
	if sent_nonzero != kept_gases.len() {
		return false;
	}
	sent.iter().filter(|&&(_, amount)| amount as f32 != 0.0).all(|&(gas, amount)| {
		kept_gases.iter().any(|&(kept_gas, kept_amount)| kept_gas as usize == gas && kept_amount == amount as f32)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_kept_air")(): 1. That the library keeps turfs' air (a gas count of -2 in
/// atmos_engine_run), so DM only sends a turf's air when DM changed it. An older library hasn't got this.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_kept_air(_argc: u32, _argv: *const ByondValue) -> ByondValue {
	ByondValue::num(1.0)
}

/// call_ext("hippie_atmos", "byond:atmos_engine_air_check")(out): with atmos-engine-air=shadow, how many turfs had their
/// kept air checked against what DM sent and how many didn't match, then some of those turfs, written into `out`
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_air_check(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("air_check", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		let guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_ref().ok_or("air_check before setup")?;
		let Some(out) = args.first() else {
			return Err("no list to write into".into());
		};
		let mut values = vec![ByondValue::num(state.air_checked as f32), ByondValue::num(state.air_mismatches as f32)];
		values.extend(state.air_samples.iter().map(|&id| ByondValue::turf(id)));
		write_values(api, out, &values)?;
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
		let changes: Vec<(u32, u32, f64)> = state.tick.changes.iter().map(|c| (c.first, c.count, c.temperature)).collect();
		let result = write_air(state, writer, &refs, &changes, &state.tick.gas_changes);
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
/// `changes` is (first, count, temperature) for each changed turf, where gas_changes[first..first + count] are its gases
unsafe fn write_air(state: &State, writer: &Writer, refs: &[ByondValue], changes: &[(u32, u32, f64)], gas_changes: &[(u8, f64)]) -> Result<(Vec<ByondValue>, Vec<ByondValue>), String> {
	if refs.len() != changes.len() * 2 {
		return Err(format!("{} references for {} changed turfs", refs.len(), changes.len()));
	}
	let mut removed = Vec::new();
	let mut hot = Vec::new();
	for (position, &(first, count, temperature)) in changes.iter().enumerate() {
		let air = &refs[position * 2];
		let moles = &refs[position * 2 + 1];
		let first = first as usize;
		for &(gas, amount) in &gas_changes[first..first + count as usize] {
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
		let temperature = temperature as f32;
		if !(writer.write_var)(air, state.temperature_id, &ByondValue::num(temperature)) {
			return Err(format!("couldn't write changed turf {}'s temperature", position + 1));
		}
		if temperature >= 10000.0 {
			hot.push(ByondValue::num((position + 1) as f32));
		}
	}
	Ok((removed, hot))
}

// ---------------------------------------------------------------------------------------------
// atmos-engine-own: the engine runs LINDA's awake turfs, tickers and excited groups itself (world.rs), and DM only tells it
// what DM did to them between ticks, instead of packing every awake turf every tick
// ---------------------------------------------------------------------------------------------

/// Reads turfs DM packed in full (atmos_engine_run()'s rows, a gas count of -1 for a turf with no air) into what the engine
/// keeps. The last four numbers of a row (group, ticker, burning, drawn) are the engine's own now, so they're skipped.
fn learn_rows(known: &mut Known, gas_lookup: &[u8], turfs: &[ByondValue], rows: &[ByondValue], adjacent: &[u32]) -> Result<(), String> {
	let mut at = 0;
	let mut adjacent_at = 0;
	let mut gases: Vec<(u8, f32)> = Vec::new();
	for turf in turfs {
		let id = turf_number(turf)?;
		let gas_count = rows.get(at).ok_or("the rows ran out")?.as_number() as i64;
		at += 1;
		if gas_count == -1 {
			known.set(id, KIND_NO_AIR, &[]);
			known.forget_air(id);
			continue;
		}
		if gas_count < 0 {
			return Err(format!("turf {id} wasn't sent in full (gas count {gas_count})"));
		}
		gases.clear();
		for _ in 0..gas_count {
			let gas = gas_lookup.get(rows[at].data as usize).copied().unwrap_or(NO_GAS);
			if gas == NO_GAS {
				return Err(format!("a gas setup wasn't told about (type {}, {})", rows[at].kind, rows[at].data));
			}
			let amount = rows[at + 1].as_number() as f32;
			if amount != 0.0 {
				gases.push((gas, amount));
			}
			at += 2;
		}
		let temperature = rows[at].as_number() as f32;
		let count = rows[at + 1].as_number() as i64;
		let kind = rows[at + 2].as_number() as u32;
		if count < 0 {
			return Err(format!("turf {id}'s neighbours weren't sent"));
		}
		let n = count as usize;
		let neighbours = adjacent.get(adjacent_at..adjacent_at + n).ok_or("the neighbours ran out")?;
		known.set(id, kind, neighbours);
		adjacent_at += n;
		known.set_air(id, temperature, &gases);
		at += 7;
	}
	if at != rows.len() || adjacent_at != adjacent.len() {
		return Err(format!("read {at} of {} numbers and {adjacent_at} of {} neighbours", rows.len(), adjacent.len()));
	}
	Ok(())
}

/// Puts a turf the engine has everything for into the tick
fn add_known(tick: &mut Tick, known: &Known, world: &World, id: u32, awake: bool, gases: &mut Vec<(usize, f64)>) -> Result<(), String> {
	let (kind, adjacent) = known.get(id).ok_or_else(|| format!("turf {id}'s kind and neighbours were never sent"))?;
	if kind == KIND_NO_AIR {
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
		return Ok(());
	}
	let (temperature, air) = known.air(id).ok_or_else(|| format!("turf {id}'s air was never sent"))?;
	gases.clear();
	gases.extend(air.iter().map(|&(gas, amount)| (gas as usize, amount as f64)));
	tick.add(NewTile {
		id,
		gases,
		temperature: temperature as f64,
		adjacent,
		kind,
		group: world.group_of(id),
		ticker: world.ticker_of(id),
		hotspot: world.hotspot_of(id),
		drawn: world.drawn_of(id),
		awake,
	});
	Ok(())
}

/// Reads the turfs, rows and neighbours DM passed (the first three arguments) into the state's buffers
unsafe fn read_packed(api: &Api, state: &mut State, args: &[ByondValue]) -> Result<(), String> {
	read_values(api, &args[0], &mut state.turfs)?;
	read_values(api, &args[1], &mut state.rows)?;
	read_values(api, &args[2], &mut state.neighbours)?;
	state.adjacent.clear();
	for neighbour in &state.neighbours {
		state.adjacent.push(turf_number(neighbour)?);
	}
	learn_rows(&mut state.known, &state.gas_lookup, &state.turfs, &state.rows, &state.adjacent)
}

fn write_turfs(api: &Api, list: &ByondValue, ids: &[u32], out: &mut Vec<ByondValue>) -> Result<(), String> {
	out.clear();
	out.extend(ids.iter().map(|&id| ByondValue::turf(id)));
	write_values(api, list, out)
}

/// call_ext("hippie_atmos", "byond:atmos_engine_own_load")(active, tickers, burning, groups): the engine takes over LINDA's
/// state from DM (atmos-engine-own=on or shadow): SSair.active_turfs with each one's significant_share_ticker in `tickers`,
/// the turfs that are burning, and SSair.excited_groups in order, each as its breakdown and dismantle cooldowns, how many
/// turfs it has, then those turfs. Returns how many turfs are awake.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_own_load(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("own_load", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 4 {
			return Err(format!("{} arguments, wanted active, tickers, burning and groups", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("own_load before setup")?;
		let mut values = Vec::new();
		read_values(api, &args[0], &mut values)?;
		let tickers = read_numbers(api, &args[1])?;
		if tickers.len() != values.len() {
			return Err(format!("{} tickers for {} awake turfs", tickers.len(), values.len()));
		}
		let mut active = Vec::with_capacity(values.len());
		for (value, &ticker) in values.iter().zip(&tickers) {
			active.push((turf_number(value)?, ticker));
		}
		read_values(api, &args[2], &mut values)?;
		let burning = values.iter().map(turf_number).collect::<Result<Vec<u32>, String>>()?;
		read_values(api, &args[3], &mut values)?;
		let mut groups = Vec::new();
		let mut at = 0;
		while at < values.len() {
			let breakdown = values[at].as_number() as u32;
			let dismantle = values.get(at + 1).ok_or("a group ran out")?.as_number() as u32;
			let count = values.get(at + 2).ok_or("a group ran out")?.as_number() as usize;
			at += 3;
			let members = values.get(at..at + count).ok_or("a group's turfs ran out")?.iter().map(turf_number).collect::<Result<Vec<u32>, String>>()?;
			at += count;
			groups.push((breakdown, dismantle, members));
		}
		state.world.load(&active, &burning, &groups);
		state.own_phase = 0;
		state.pending.clear();
		state.shadow_breakdown.clear();
		Ok(state.world.active_count() as f32)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_own_sync")(events, touched, dirty): what DM did since the engine last heard
/// from it. `events` is pairs of an event number (see world.rs) and a turf, in the order they happened; `touched` has turfs
/// whose air DM changed, which the engine asks for again when it needs them, and `dirty` turfs whose neighbours changed.
/// Returns 1.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_own_sync(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("own_sync", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 3 {
			return Err(format!("{} arguments, wanted events, touched and dirty", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("own_sync before setup")?;
		let State { turfs, world, known, .. } = &mut *state;
		read_values(api, &args[0], turfs)?;
		if turfs.len() % 2 != 0 {
			return Err(format!("{} numbers in the events, not pairs", turfs.len()));
		}
		for pair in turfs.chunks(2) {
			let kind = pair[0].as_number() as u32;
			let id = turf_number(&pair[1])?;
			if !world.event(kind, id) {
				return Err(format!("event {kind} isn't one the engine knows"));
			}
			if kind == world::EVENT_NEW_TURF {
				known.forget_air(id);
				known.forget_kind(id);
			}
		}
		read_values(api, &args[1], turfs)?;
		for turf in turfs.iter() {
			known.forget_air(turf_number(turf)?);
		}
		read_values(api, &args[2], turfs)?;
		for turf in turfs.iter() {
			known.forget_kind(turf_number(turf)?);
		}
		Ok(1.0)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_own_run")(turfs, rows, adjacent, planetary, fire, wanted, stats): one tick,
/// with the engine going through its own awake turfs (atmos-engine-own=on). The first call of a tick passes no turfs. A
/// turf the engine needs and hasn't got everything for goes into `wanted` and it returns 2; DM calls again with those packed
/// in full (atmos_engine_run()'s rows). `fire` is SSair.times_fired. Returns 1 when the tick is done, with [awake turfs,
/// excited groups, turfs that had a turn, turfs in the tick] in `stats`; atmos_engine_results() has the rest.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_own_run(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("own_run", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 7 {
			return Err(format!("{} arguments, wanted turfs, rows, adjacent, planetary, fire, wanted and stats", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("own_run before setup")?;
		read_packed(api, state, args)?;
		let planetary = read_numbers(api, &args[3])?;
		let fire = args[4].as_number();
		let State {
			tick,
			known,
			world,
			config,
			pending,
			own_phase,
			gases,
			wanted,
			out,
			final_gases,
			..
		} = &mut *state;
		if *own_phase == 0 {
			// The awake turfs go in first and in order, so they all have to be here before the tick starts
			wanted.clear();
			for &(id, _) in world.active() {
				if !known.complete(id) {
					wanted.push(id);
				}
			}
			if !wanted.is_empty() {
				write_turfs(api, &args[5], wanted, out)?;
				return Ok(2.0);
			}
			tick.begin(config);
			let awake: Vec<u32> = world.active().iter().map(|&(id, _)| id).collect();
			for id in awake {
				add_known(tick, known, world, id, true, gases)?;
			}
			*own_phase = 1;
			pending.clear();
		} else {
			for id in std::mem::take(pending) {
				add_known(tick, known, world, id, false, gases)?;
			}
		}
		loop {
			wanted.clear();
			if tick.run(config, &planetary, wanted) {
				tick.finish(config);
				for i in 0..tick.packed() {
					if let Some((id, temperature)) = tick.final_air(i, final_gases) {
						known.set_air(id, temperature, final_gases);
					}
				}
				world.absorb(tick, fire);
				*own_phase = 0;
				let stats = [world.active_count() as f32, world.group_order().len() as f32, tick.order.len() as f32, tick.packed() as f32];
				out.clear();
				out.extend(stats.iter().map(|&n| ByondValue::num(n)));
				write_values(api, &args[6], out)?;
				return Ok(1.0);
			}
			if wanted.is_empty() {
				return Err("stopped without asking for anything".into());
			}
			// Anything the engine has everything for goes straight in; DM only packs the rest
			let mut ask = Vec::new();
			for k in 0..wanted.len() {
				let id = wanted[k];
				if known.complete(id) {
					add_known(tick, known, world, id, false, gases)?;
				} else {
					ask.push(id);
				}
			}
			if !ask.is_empty() {
				write_turfs(api, &args[5], &ask, out)?;
				*pending = ask;
				return Ok(2.0);
			}
		}
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_own_groups")(turfs, rows, adjacent, planetary, mode, wanted, stats):
/// SSair.process_excited_groups() for the engine's excited groups. Mode 1 changes the air (atmos-engine-own=on), and
/// atmos_engine_group_results() then has what changed; mode 2 only works out what it would have been, to check against
/// what DM does (shadow). Returns 2 with turfs in `wanted` when it needs them packed in full first (the turfs of a group
/// about to break down), then 1 with [groups broken down, groups dismantled, turfs whose air changed, awake turfs, excited
/// groups] in `stats`.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_own_groups(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("own_groups", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 7 {
			return Err(format!("{} arguments, wanted turfs, rows, adjacent, planetary, mode, wanted and stats", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("own_groups before setup")?;
		read_packed(api, state, args)?;
		let planetary = read_numbers(api, &args[3])?;
		let apply = args[4].as_number() == 1.0;
		let State {
			known,
			world,
			config,
			wanted,
			out,
			shadow_air,
			shadow_breakdown,
			..
		} = &mut *state;
		wanted.clear();
		world.groups_need(config, known, wanted);
		if !wanted.is_empty() {
			write_turfs(api, &args[5], wanted, out)?;
			return Ok(2.0);
		}
		shadow_air.clear();
		world.process_groups(config, known, &planetary, apply, shadow_air)?;
		for (id, temperature, gases) in shadow_air.drain(..) {
			shadow_breakdown.insert(id, (temperature, gases));
		}
		let stats = [world.broke_down as f32, world.dismantled as f32, world.air_changes.len() as f32, world.active_count() as f32, world.group_order().len() as f32];
		out.clear();
		out.extend(stats.iter().map(|&n| ByondValue::num(n)));
		write_values(api, &args[6], out)?;
		Ok(1.0)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_group_results")(changed, values, redraw, redraw_keys, poked): the air the
/// excited groups' step changed and the overlays it changed, like atmos_engine_results(), and every turf it woke (`poked`). `values` has, for each turf in `changed`,
/// how many gases changed, a path and moles for each (0 moles for one that's gone), then its temperature; null when
/// atmos_engine_group_write() writes the air instead. Returns 1.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_group_results(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("group_results", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 4 {
			return Err(format!("{} arguments, wanted changed, values, redraw and redraw_keys", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("group_results before setup")?;
		let State { world, out, gas_paths, .. } = &mut *state;
		if !world.air_changes.is_empty() {
			out.clear();
			out.extend(world.air_changes.iter().map(|change| ByondValue::turf(change.id)));
			write_values(api, &args[0], out)?;
			if args[1].kind != TYPE_NULL {
				out.clear();
				for change in &world.air_changes {
					out.push(ByondValue::num(change.count as f32));
					let first = change.first as usize;
					for &(gas, amount) in &world.gas_changes[first..first + change.count as usize] {
						out.push(gas_paths[gas as usize]);
						out.push(ByondValue::num(amount as f32));
					}
					out.push(ByondValue::num(change.temperature as f32));
				}
				write_values(api, &args[1], out)?;
			}
		}
		if !world.redraw.is_empty() {
			out.clear();
			out.extend(world.redraw.iter().map(|&(id, _)| ByondValue::turf(id)));
			write_values(api, &args[2], out)?;
			out.clear();
			out.extend(world.redraw.iter().map(|&(_, key)| ByondValue::num(key as f32)));
			write_values(api, &args[3], out)?;
		}
		if !world.poked.is_empty() && args.len() > 4 && args[4].kind != TYPE_NULL {
			write_turfs(api, &args[4], &world.poked, out)?;
		}
		Ok(1.0)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_group_write")(refs, removed, hot): atmos_engine_write() for the air the
/// excited groups' step changed, in atmos_engine_group_results()'s order
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_group_write(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("group_write", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		let writer = writer().ok_or("writing isn't available")?;
		if args.len() < 3 {
			return Err(format!("{} arguments, wanted refs, removed and hot", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("group_write before setup")?;
		if !state.write_ready {
			return Err("group_write before write_setup".into());
		}
		let mut refs = std::mem::take(&mut state.refs);
		read_values(api, &args[0], &mut refs)?;
		let changes: Vec<(u32, u32, f64)> = state.world.air_changes.iter().map(|c| (c.first, c.count, c.temperature)).collect();
		let result = write_air(state, writer, &refs, &changes, &state.world.gas_changes);
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

/// call_ext("hippie_atmos", "byond:atmos_engine_own_turn")(turf): the SSair fire the turf last had its turn in (its
/// current_cycle), -1 for never
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_own_turn(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("own_turn", || {
		let id = turf_number(args.first().ok_or("no turf")?)?;
		let guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_ref().ok_or("own_turn before setup")?;
		Ok(state.world.last_turn_of(id) as f32)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_own_active")(turfs, tickers): the engine's SSair.active_turfs in order,
/// with each one's significant_share_ticker, for DM to carry on from (LINDA after a failure) or count. Returns how many.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_own_active(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("own_active", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 2 {
			return Err(format!("{} arguments, wanted turfs and tickers", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("own_active before setup")?;
		let State { world, out, .. } = &mut *state;
		let ids: Vec<u32> = world.active().iter().map(|&(id, _)| id).collect();
		write_turfs(api, &args[0], &ids, out)?;
		out.clear();
		out.extend(ids.iter().map(|&id| ByondValue::num(world.ticker_of(id) as f32)));
		write_values(api, &args[1], out)?;
		Ok(ids.len() as f32)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_own_check")(active, values, groups, out): atmos-engine-own=shadow, before
/// each tick: checks the engine's copy of LINDA's state against DM's. `active` is SSair.active_turfs, `values` has each
/// one's significant_share_ticker, whether it's burning and its tile_engine_drawn, and `groups` is SSair.excited_groups as
/// atmos_engine_own_load() takes them. `out` gets the totals so far: ticks checked, ticks with a different active list,
/// turfs with a different ticker, burning or drawn, ticks with different groups, turfs whose group breakdown was checked
/// and how many of those differed. Returns 1.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_own_check(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("own_check", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 4 {
			return Err(format!("{} arguments, wanted active, values, groups and out", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("own_check before setup")?;
		let mut turfs = Vec::new();
		read_values(api, &args[0], &mut turfs)?;
		let values = read_numbers(api, &args[1])?;
		if values.len() != turfs.len() * 3 {
			return Err(format!("{} values for {} awake turfs", values.len(), turfs.len()));
		}
		let mut active = Vec::with_capacity(turfs.len());
		for (k, turf) in turfs.iter().enumerate() {
			active.push((turf_number(turf)?, values[k * 3], values[k * 3 + 1] != 0.0, values[k * 3 + 2]));
		}
		let mut flat = Vec::new();
		read_values(api, &args[2], &mut flat)?;
		let mut groups = Vec::new();
		let mut at = 0;
		while at < flat.len() {
			let breakdown = flat[at].as_number() as u32;
			let dismantle = flat.get(at + 1).ok_or("a group ran out")?.as_number() as u32;
			let count = flat.get(at + 2).ok_or("a group ran out")?.as_number() as usize;
			at += 3;
			let members = flat.get(at..at + count).ok_or("a group's turfs ran out")?.iter().map(turf_number).collect::<Result<Vec<u32>, String>>()?;
			at += count;
			groups.push((breakdown, dismantle, members));
		}
		let mut log = Vec::new();
		let mut drawn_wrong = Vec::new();
		let wrong = state.world.check(&active, &groups, &mut log, &mut drawn_wrong);
		state.own_checks += 1;
		for k in 0..5 {
			state.own_wrong[k] += wrong[k];
		}
		for line in log {
			if state.own_log.len() < 40 {
				eprintln!("hippie_atmos own check (tick {}): {line}", state.own_checks);
				state.own_log.push(line);
			}
		}
		let mut totals = vec![state.own_checks as f32];
		totals.extend(state.own_wrong.iter().map(|&n| n as f32));
		totals.push(state.breakdown_checked as f32);
		totals.push(state.breakdown_wrong as f32);
		totals.push(state.breakdown_inexact as f32);
		let mut totals: Vec<ByondValue> = totals.into_iter().map(ByondValue::num).collect();
		// Then a few turfs whose drawn key differed this tick, for DM to say where they are
		totals.extend(drawn_wrong.iter().take(5).map(|&id| ByondValue::turf(id)));
		write_values(api, &args[3], &totals)?;
		Ok(1.0)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_own_breakdown_check")(turfs, rows, adjacent, wanted): atmos-engine-own=shadow,
/// right after DM's excited groups have had their step: checks the air DM gave the turfs of groups that broke down against
/// what the engine worked out for them. The first call passes no turfs and gets the ones to send in `wanted` (returning 2;
/// 1 if there are none); the second sends them packed in full. Returns 1.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_own_breakdown_check(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("own_breakdown_check", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 4 {
			return Err(format!("{} arguments, wanted turfs, rows, adjacent and wanted", args.len()));
		}
		let mut guard = STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let state = guard.as_mut().ok_or("own_breakdown_check before setup")?;
		read_packed(api, state, args)?;
		let State { turfs, known, shadow_breakdown, breakdown_checked, breakdown_wrong, breakdown_inexact, out, .. } = &mut *state;
		// A fifth argument of 1: the MC paused DM's groups halfway, so other things changed the air in between; nothing to check
		if args.get(4).is_some_and(|discard| discard.as_number() == 1.0) {
			shadow_breakdown.clear();
			return Ok(1.0);
		}
		if turfs.is_empty() {
			if shadow_breakdown.is_empty() {
				return Ok(1.0);
			}
			let mut ids: Vec<u32> = shadow_breakdown.keys().copied().collect();
			ids.sort_unstable();
			write_turfs(api, &args[3], &ids, out)?;
			return Ok(2.0);
		}
		let mut sent: Vec<(usize, f64)> = Vec::new();
		for turf in turfs.iter() {
			let id = turf_number(turf)?;
			let Some((engine_temperature, engine_gases)) = shadow_breakdown.remove(&id) else {
				continue;
			};
			let Some((temperature, gases)) = known.air(id) else {
				continue; // a wall now
			};
			sent.clear();
			sent.extend(gases.iter().map(|&(gas, amount)| (gas as usize, amount as f64)));
			*breakdown_checked += 1;
			if !breakdown_matches(engine_temperature, &engine_gases, temperature as f64, &sent) {
				*breakdown_wrong += 1;
				if *breakdown_wrong <= 10 {
					eprintln!("hippie_atmos own: turf {id} broke down to {engine_temperature} K {engine_gases:?} in the engine, DM gave it {temperature} K {sent:?}");
				}
			} else if engine_temperature != temperature || engine_gases.as_slice() != gases {
				*breakdown_inexact += 1;
				if *breakdown_inexact <= 10 {
					eprintln!("hippie_atmos own: turf {id} broke down to {engine_temperature} K {engine_gases:?} in the engine, DM gave it {temperature} K {gases:?} (close)");
				}
			}
		}
		shadow_breakdown.clear();
		Ok(1.0)
	})
}
