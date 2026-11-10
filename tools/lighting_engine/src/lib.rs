//! Hippie's lighting engine, called from SSlighting (hippiestation/code/modules/lighting/lighting_engine.dm). The work
//! is in engine.rs; this is just the BYOND side of it.
//!
//! Like the atmos engine (tools/atmos_engine) it only reads lists and arguments DM passes, and writes into lists DM passes,
//! and those only ever hold numbers and turfs: neither is reference counted, so it never has a BYOND reference to look
//! after. The two BYOND API functions it uses are looked up in byondcore.dll at first use.

pub mod engine;
pub mod view;

use engine::{Engine, Update};
use view::{ViewArgs, ViewScratch, BOUNDARY_AFTER, BOUNDARY_X_DOWN, BOUNDARY_X_UP, BOUNDARY_Y_DOWN, BOUNDARY_Y_UP, LAMP_FROM_ANY, LAMP_FROM_TWO};
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Mutex;
use std::sync::OnceLock;

/// Bumped whenever what DM and the engine pass each other changes. DM won't use a library that says anything else.
pub const ENGINE_VERSION: f32 = 1.0;

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

struct State {
	engine: Engine,
	/// Turfs on one z-level
	per_level: u32,
	values: Vec<ByondValue>,
	seen: Vec<u32>,
	out: Vec<ByondValue>,
	view: ViewScratch,
	native_seen: Vec<u32>,
	check: ViewCheck,
}

/// The shadow view check (view mode 2): every light's view() set against the engine's own
#[derive(Default)]
struct ViewCheck {
	checked: u64,
	/// What update_corners() uses: the clear turfs, in order
	clear_same: u64,
	clear_different_set: u64,
	clear_different_order: u64,
	clear_samples: Vec<String>,
	same_set: u64,
	same_order: u64,
	/// Of those with the same set, how many came in another order
	order_only: u64,
	/// How many each other reading would have got right (the same turfs)
	variants: Vec<(String, u64)>,
	/// Turfs in the views that differed: seen by view() only, opaque and clear, and by the engine only
	dm_only_opaque: u64,
	dm_only_clear: u64,
	native_only_opaque: u64,
	native_only_clear: u64,
	/// Views the engine worked out twice and got two answers for
	unsteady: u64,
	samples: Vec<String>,
	orders: Vec<String>,
}

impl ViewCheck {
	fn report(&self) -> String {
		let mut s = format!(
			"Clear turfs (all a light uses), the engine's against view()'s: {} views, the same turfs in the same order {}, different turfs {}, the same turfs in another order {}\n",
			self.checked, self.clear_same, self.clear_different_set, self.clear_different_order
		);
		for sample in &self.clear_samples {
			s.push_str(sample);
			s.push_str("\n");
		}
		s += &format!(
			"\nAll turfs, opaque ones too: views checked {}: same turfs {}, in the same order {}, same turfs in another order {}, different turfs {}\n\
			 Turfs in those: view() only {} opaque and {} clear, the engine only {} opaque and {} clear; worked out twice and different {}\n",
			self.checked,
			self.same_set,
			self.same_order,
			self.order_only,
			self.checked - self.same_set,
			self.dm_only_opaque,
			self.dm_only_clear,
			self.native_only_opaque,
			self.native_only_clear,
			self.unsteady
		);
		for (name, same) in &self.variants {
			s.push_str(&format!("  {name}: the same turfs {same}\n"));
		}
		for o in &self.orders {
			s.push_str("\n");
			s.push_str(o);
		}
		for sample in &self.samples {
			s.push_str("\n");
			s.push_str(sample);
		}
		s
	}
}

/// The turfs as offsets from (tx, ty): "dx,dy dx,dy ..."
fn offsets(turfs: &[u32], maxx: i32, tx: i32, ty: i32) -> String {
	turfs
		.iter()
		.map(|&t| {
			let (x, y) = (t as i32 % maxx + 1, t as i32 / maxx + 1);
			format!("{},{}", x - tx, y - ty)
		})
		.collect::<Vec<_>>()
		.join(" ")
}

impl State {
	/// A turf's z-level and number on it
	fn place(&self, turf: &ByondValue) -> Result<(usize, u32), String> {
		if turf.kind != TYPE_TURF {
			return Err(format!("expected a turf, got type {}", turf.kind));
		}
		Ok(((turf.data / self.per_level) as usize + 1, turf.data % self.per_level))
	}
}

static STATE: Mutex<Option<State>> = Mutex::new(None);

fn guarded(name: &str, call: impl FnOnce() -> Result<f32, String>) -> ByondValue {
	match catch_unwind(AssertUnwindSafe(call)) {
		Ok(Ok(value)) => ByondValue::num(value),
		Ok(Err(error)) => {
			eprintln!("hippie_lighting {name}: {error}");
			ByondValue::num(-1.0)
		}
		Err(_) => {
			eprintln!("hippie_lighting {name}: panicked");
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

/// call_ext("hippie_lighting", "byond:lighting_setup")(maxx, maxy, maxz, turfs, coordinates): starts afresh for a world this
/// size. `turfs` are a few turfs and `coordinates` their x, y and z, to check turfs are numbered the way the engine thinks.
/// Returns ENGINE_VERSION.
#[no_mangle]
pub unsafe extern "C" fn lighting_setup(argc: u32, argv: *const ByondValue) -> ByondValue {
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
				return Err(format!(
					"turf ({x},{y},{z}) is numbered {} (type {}), not {expected}",
					turf.data, turf.kind
				));
			}
		}
		*STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(State {
			engine: Engine::new(maxx, maxy, maxz as usize),
			per_level,
			values: Vec::new(),
			seen: Vec::new(),
			out: Vec::new(),
			view: ViewScratch::default(),
			native_seen: Vec::new(),
			check: ViewCheck::default(),
		});
		Ok(ENGINE_VERSION)
	})
}

/// lighting_flags(list): turf, flags, turf, flags... (engine::OPAQUE and co.)
#[no_mangle]
pub unsafe extern "C" fn lighting_flags(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("flags", |api, state| {
		let mut values = std::mem::take(&mut state.values);
		read_values(api, args.first().ok_or("no list")?, &mut values)?;
		let mut i = 0;
		while i + 1 < values.len() {
			let (z, t) = state.place(&values[i])?;
			state.engine.set_flags(z, t, values[i + 1].as_int() as u8);
			i += 2;
		}
		let n = (values.len() / 2) as f32;
		state.values = values;
		Ok(n)
	})
}

/// lighting_flag(turf, flags): one turf's flags
#[no_mangle]
pub unsafe extern "C" fn lighting_flag(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("flag", |_, state| {
		if args.len() < 2 {
			return Err("wanted a turf and its flags".into());
		}
		let (z, t) = state.place(&args[0])?;
		state.engine.set_flags(z, t, args[1].as_int() as u8);
		Ok(1.0)
	})
}

/// lighting_sheet(id, size, values): a light sheet, its rows one after another
#[no_mangle]
pub unsafe extern "C" fn lighting_sheet(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("sheet", |api, state| {
		if args.len() < 3 {
			return Err("wanted an id, a size and the values".into());
		}
		let mut values = std::mem::take(&mut state.values);
		read_values(api, &args[2], &mut values)?;
		let dim = args[1].as_int();
		if values.len() != (dim * dim) as usize {
			return Err(format!("a {dim} wide sheet with {} values", values.len()));
		}
		state.engine.set_sheet(
			args[0].as_int() as usize,
			dim,
			values.iter().map(ByondValue::as_f32).collect(),
		);
		state.values = values;
		Ok(1.0)
	})
}

/// lighting_update(id, x, y, z, reach, power, red, green, blue, sheet, spill sheet, flags, scatter cutoff, bounce strength,
/// bounce falloff, bounce cutoff, bounce depth, seen, view mode, eye luminosity): what update_corners() works out once it's
/// looked around. Flags: 1 only what it can see has changed, 2 it bounces, 4 it scatters. View mode (bits 1-2): 0 `seen` is
/// what view() handed back; 1 the engine works out what the light sees itself (view.rs) and `seen` isn't looked at; 2 as 0,
/// and the engine's own view is set against it (lighting_view_report()). Bit 4: the other lamp rule; bit 8: turfs that
/// aren't dynamically lit count as lit. Eye luminosity is what update_corners() set the light's turf's luminosity to.
#[no_mangle]
pub unsafe extern "C" fn lighting_update(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("update", |api, state| {
		if args.len() < 18 {
			return Err(format!("{} arguments, wanted 18", args.len()));
		}
		let flags = args[11].as_int();
		let update = Update {
			id: args[0].as_int() as usize,
			tx: args[1].as_int(),
			ty: args[2].as_int(),
			z: args[3].as_int() as usize,
			reach: args[4].as_int(),
			power: args[5].as_f32(),
			lum: [args[6].as_f32(), args[7].as_f32(), args[8].as_f32()],
			sheet: args[9].as_int() as usize,
			spill_sheet: args[10].as_int() as usize,
			vis_only: flags & 1 != 0,
			bounces: flags & 2 != 0,
			scatters: flags & 4 != 0,
			scatter_cutoff: args[12].as_f32(),
			bounce_strength: args[13].as_f32(),
			bounce_falloff: args[14].as_f32(),
			bounce_cutoff: args[15].as_f32(),
			bounce_depth: args[16].as_int(),
		};
		let view_mode = if args.len() > 18 { args[18].as_int() } else { 0 };
		let view_args = ViewArgs {
			tx: update.tx,
			ty: update.ty,
			range: update.reach,
			eye_lum: if args.len() > 19 { args[19].as_int() } else { update.reach + 1 },
			lamp_rule: if view_mode & 4 != 0 { LAMP_FROM_TWO } else { LAMP_FROM_ANY },
			undynamic_lit: view_mode & 8 != 0,
			boundary: ((view_mode >> 4) & 7) as u8,
			clear_only: view_mode & 3 == 1,
		};
		let (maxx, maxy) = (state.engine.maxx, state.engine.maxy);
		let mut values = std::mem::take(&mut state.values);
		let mut seen = std::mem::take(&mut state.seen);
		seen.clear();
		if view_mode & 3 == 1 {
			let level = state.engine.level(update.z);
			state.view.view(&level.flags, maxx, maxy, &view_args, &mut seen);
		} else {
			read_values(api, &args[17], &mut values)?;
			let first = (update.z as u32 - 1) * state.per_level;
			for v in values.iter() {
				if v.kind == TYPE_TURF && v.data >= first && v.data - first < state.per_level {
					seen.push(v.data - first);
				}
			}
			if view_mode & 3 == 2 {
				check_view(state, &update, &view_args, &seen);
			}
		}
		let result = state.engine.update(&update, &seen);
		state.values = values;
		state.seen = seen;
		result.map(|_| 1.0)
	})
}

/// View mode 2: the engine's own view against view()'s, counted, and the first few that differ kept for the report
fn check_view(state: &mut State, update: &Update, a: &ViewArgs, seen: &[u32]) {
	let (maxx, maxy) = (state.engine.maxx, state.engine.maxy);
	let mut native = std::mem::take(&mut state.native_seen);
	let level = state.engine.level(update.z);
	state.view.view(&level.flags, maxx, maxy, a, &mut native);
	// What a light uses: the clear turfs, in order (update_corners() passes over opaque ones)
	let mut clear = Vec::new();
	let clear_args = ViewArgs { clear_only: true, ..*a };
	{
		let mut scratch2 = ViewScratch::default();
		scratch2.view(&level.flags, maxx, maxy, &clear_args, &mut clear);
	}
	let dm_clear: Vec<u32> = seen.iter().copied().filter(|&t| level.flags[t as usize] & engine::OPAQUE == 0).collect();
	let check = &mut state.check;
	if clear == dm_clear {
		check.clear_same += 1;
	} else {
		let mut c1 = clear.clone();
		c1.sort_unstable();
		let mut c2 = dm_clear.clone();
		c2.sort_unstable();
		if c1 == c2 {
			check.clear_different_order += 1;
		} else {
			check.clear_different_set += 1;
		}
		if check.clear_samples.len() < 20 {
			let dm_only: Vec<u32> = c2.iter().copied().filter(|t| c1.binary_search(t).is_err()).collect();
			let native_only: Vec<u32> = c1.iter().copied().filter(|t| c2.binary_search(t).is_err()).collect();
			check.clear_samples.push(format!(
				"Clear turfs different at ({}, {}, {}) reach {}: view() only {} / engine only {}\n  view(): {}\n  engine: {}",
				update.tx,
				update.ty,
				update.z,
				update.reach,
				offsets(&dm_only, maxx, update.tx, update.ty),
				offsets(&native_only, maxx, update.tx, update.ty),
				offsets(&dm_clear, maxx, update.tx, update.ty),
				offsets(&clear, maxx, update.tx, update.ty)
			));
		}
	}
	check.checked += 1;
	{
		let mut again = Vec::new();
		let mut scratch2 = ViewScratch::default();
		scratch2.view(&level.flags, maxx, maxy, a, &mut again);
		if again != native {
			check.unsteady += 1;
		}
	}
	let mut dm_sorted = seen.to_vec();
	dm_sorted.sort_unstable();
	let mut native_sorted = native.clone();
	native_sorted.sort_unstable();
	let same_set = dm_sorted == native_sorted;
	if same_set {
		check.same_set += 1;
		if native.as_slice() == seen {
			check.same_order += 1;
		} else {
			check.order_only += 1;
		}
	}
	if check.orders.len() < 3 && native.as_slice() != seen {
		check.orders.push(format!(
			"Order at ({}, {}, {}) reach {}:\n  view(): {}\n  engine: {}\n",
			update.tx,
			update.ty,
			update.z,
			update.reach,
			offsets(seen, maxx, update.tx, update.ty),
			offsets(&native, maxx, update.tx, update.ty)
		));
	}
	if !same_set {
		let opaque = |t: u32| level.flags[t as usize] & engine::OPAQUE != 0;
		for &t in dm_sorted.iter().filter(|t| native_sorted.binary_search(t).is_err()) {
			if opaque(t) {
				check.dm_only_opaque += 1;
			} else {
				check.dm_only_clear += 1;
			}
		}
		for &t in native_sorted.iter().filter(|t| dm_sorted.binary_search(t).is_err()) {
			if opaque(t) {
				check.native_only_opaque += 1;
			} else {
				check.native_only_clear += 1;
			}
		}
	}
	if !same_set && check.samples.len() < 40 {
		let dm_only: Vec<u32> = dm_sorted.iter().copied().filter(|t| native_sorted.binary_search(t).is_err()).collect();
		let native_only: Vec<u32> = native_sorted.iter().copied().filter(|t| dm_sorted.binary_search(t).is_err()).collect();
		let flags = &level.flags;
		let picture = state.view.picture(maxx, a, |t| {
			if dm_only.contains(&t) {
				Some('D')
			} else if native_only.contains(&t) {
				Some('N')
			} else if dm_sorted.binary_search(&t).is_ok() {
				Some(if flags[t as usize] & engine::OPAQUE != 0 { 'W' } else { 'o' })
			} else {
				None
			}
		});
		let dump = state.view.dump();
		check.samples.push(format!(
			"Different at ({}, {}, {}) reach {} luminosity {}{}: view() only {} / engine only {}\n(D view() only, N engine only, W/o seen by both opaque/clear, # opaque, . clear, @ the light)\n{}engine's vis/lamp:\n{}",
			update.tx,
			update.ty,
			update.z,
			update.reach,
			a.eye_lum,
			if update.vis_only { ", a door" } else { "" },
			offsets(&dm_only, maxx, update.tx, update.ty),
			offsets(&native_only, maxx, update.tx, update.ty),
			picture,
			dump
		));
	}
	// The other readings, on every view, to see which BYOND agrees with
	let variants: [(&str, ViewArgs); 7] = [
		("other lamp rule", ViewArgs { lamp_rule: if a.lamp_rule == LAMP_FROM_ANY { LAMP_FROM_TWO } else { LAMP_FROM_ANY }, ..*a }),
		("undynamic turfs lit (or not)", ViewArgs { undynamic_lit: !a.undynamic_lit, ..*a }),
		("walls marked after", ViewArgs { boundary: BOUNDARY_AFTER, ..*a }),
		("walls marked as found, x up", ViewArgs { boundary: BOUNDARY_X_UP, ..*a }),
		("walls marked as found, x down", ViewArgs { boundary: BOUNDARY_X_DOWN, ..*a }),
		("walls marked as found, y up", ViewArgs { boundary: BOUNDARY_Y_UP, ..*a }),
		("walls marked as found, y down", ViewArgs { boundary: BOUNDARY_Y_DOWN, ..*a }),
	];
	if check.variants.is_empty() {
		check.variants = variants.iter().map(|(name, _)| (name.to_string(), 0)).collect();
	}
	for (i, (_, args)) in variants.iter().enumerate() {
		state.view.view(&level.flags, maxx, maxy, args, &mut native);
		native.sort_unstable();
		if native == dm_sorted {
			check.variants[i].1 += 1;
		}
	}
	state.native_seen = native;
	let _ = maxy;
}

/// lighting_view_ready(): 1, from a library that can work out what a light sees itself (view modes 1 and 2 of lighting_update())
#[no_mangle]
pub unsafe extern "C" fn lighting_view_ready(_argc: u32, _argv: *const ByondValue) -> ByondValue {
	ByondValue::num(1.0)
}

/// lighting_view_report(): writes what the shadow view check (view mode 2) has found to data/lighting_view_check.txt and
/// returns how many views had different turfs
#[no_mangle]
pub unsafe extern "C" fn lighting_view_report(_argc: u32, _argv: *const ByondValue) -> ByondValue {
	with_state("view report", |_, state| {
		std::fs::write("data/lighting_view_check.txt", state.check.report()).map_err(|e| e.to_string())?;
		Ok((state.check.checked - state.check.same_set) as f32)
	})
}

/// lighting_relight(id, power, red, green, blue): relight_in_place()
#[no_mangle]
pub unsafe extern "C" fn lighting_relight(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("relight", |_, state| {
		if args.len() < 5 {
			return Err("wanted an id, power and colour".into());
		}
		state.engine.relight(
			args[0].as_int() as usize,
			args[1].as_f32(),
			[args[2].as_f32(), args[3].as_f32(), args[4].as_f32()],
		)?;
		Ok(1.0)
	})
}

/// lighting_remove(id): remove_lum()
#[no_mangle]
pub unsafe extern "C" fn lighting_remove(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("remove", |_, state| {
		state.engine.remove(args.first().ok_or("no id")?.as_int() as usize);
		Ok(1.0)
	})
}

/// lighting_forget(id): the light source is gone; takes its light off and frees its id
#[no_mangle]
pub unsafe extern "C" fn lighting_forget(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("forget", |_, state| {
		state.engine.forget(args.first().ok_or("no id")?.as_int() as usize);
		Ok(1.0)
	})
}

/// lighting_recalc(turf): lighting_build_overlay()'s recalc_corner() for the lights on each of its corners
#[no_mangle]
pub unsafe extern "C" fn lighting_recalc(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("recalc", |_, state| {
		let (z, t) = state.place(args.first().ok_or("no turf")?)?;
		let (x, y) = state.engine.turf_xy(t);
		state.engine.recalc_turf(z, x, y);
		Ok(1.0)
	})
}

/// lighting_affecting(turf, out): the ids of the lights on the turf's corners, for reconsider_lights()
#[no_mangle]
pub unsafe extern "C" fn lighting_affecting(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("affecting", |api, state| {
		if args.len() < 2 {
			return Err("wanted a turf and a list".into());
		}
		let (z, t) = state.place(&args[0])?;
		let ids = state.engine.affecting(z, t);
		if ids.is_empty() {
			return Ok(0.0);
		}
		let out: Vec<ByondValue> = ids.iter().map(|&id| ByondValue::num(id as f32)).collect();
		write_values(api, &args[1], &out)?;
		Ok(ids.len() as f32)
	})
}

/// lighting_flush(max, out): the corner stage, then up to `max` lighting objects to draw: turf, then 13 numbers (see
/// engine::Engine::object_values()). Returns how many are still waiting. A `max` below 0 throws the objects away: DM draws
/// them itself in the shadow check.
#[no_mangle]
pub unsafe extern "C" fn lighting_flush(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("flush", |api, state| {
		if args.len() < 2 {
			return Err("wanted a count and a list".into());
		}
		state.engine.flush_corners();
		if args[0].as_f32() < 0.0 {
			state.engine.drop_objects();
			return Ok(0.0);
		}
		let mut out = std::mem::take(&mut state.out);
		out.clear();
		let per_level = state.per_level;
		let left = state.engine.take_objects(args[0].as_int().max(0) as usize, |z, t, values| {
			out.push(ByondValue::turf((z - 1) * per_level + t));
			for v in values {
				out.push(ByondValue::num(v));
			}
		});
		if !out.is_empty() {
			write_values(api, &args[1], &out)?;
		}
		state.out = out;
		Ok(left as f32)
	})
}

/// lighting_object(turf, out): what that turf's lighting object draws, as lighting_flush() gives it
#[no_mangle]
pub unsafe extern "C" fn lighting_object(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("object", |api, state| {
		if args.len() < 2 {
			return Err("wanted a turf and a list".into());
		}
		let (z, t) = state.place(&args[0])?;
		let values: Vec<ByondValue> = state.engine.object_values(z, t).iter().map(|&v| ByondValue::num(v)).collect();
		write_values(api, &args[1], &values)?;
		Ok(1.0)
	})
}

/// lighting_lumcount(turf): get_lumcount()'s total light on the turf's corners
#[no_mangle]
pub unsafe extern "C" fn lighting_lumcount(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("lumcount", |_, state| {
		let (z, t) = state.place(args.first().ok_or("no turf")?)?;
		Ok(state.engine.lumcount(z, t))
	})
}

/// lighting_tone(knee): where the tone curve starts from here on (engine::tone_factor(), GLOB.lighting_tone_knee). Every lit
/// corner works out what it draws again at the next flush. Returns how many corners were queued.
#[no_mangle]
pub unsafe extern "C" fn lighting_tone(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("tone", |_, state| {
		let knee = args.first().ok_or("no knee")?.as_f32();
		if !(knee > 0.0) {
			return Err(format!("knee {knee}, wanted above 0"));
		}
		Ok(state.engine.set_tone(knee) as f32)
	})
}

/// lighting_eye(turf, range_x, range_y): how bright what can be seen from the turf looks, for eye adaptation
/// (hippiestation/code/modules/lighting/eye_adapt.dm). The clear turfs in sight of it (the lights' own view, view.rs) up to
/// range_x tiles east and west and range_y north and south, those with a lighting object, each the average luminance of its
/// corners as drawn: their average, 0 to 1. With nothing lit dynamically in sight, 1 (nothing to adjust to).
#[no_mangle]
pub unsafe extern "C" fn lighting_eye(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("eye", |_, state| {
		if args.len() < 3 {
			return Err("wanted a turf and two ranges".into());
		}
		let (z, t) = state.place(&args[0])?;
		let (rx, ry) = (args[1].as_int().clamp(0, 32), args[2].as_int().clamp(0, 32));
		let (tx, ty) = state.engine.turf_xy(t);
		let range = rx.max(ry);
		let view_args = ViewArgs {
			tx,
			ty,
			range,
			eye_lum: range + 1,
			lamp_rule: LAMP_FROM_ANY,
			undynamic_lit: false,
			boundary: BOUNDARY_AFTER,
			clear_only: true,
		};
		let (maxx, maxy) = (state.engine.maxx, state.engine.maxy);
		let mut seen = std::mem::take(&mut state.seen);
		let level = state.engine.level(z);
		state.view.view(&level.flags, maxx, maxy, &view_args, &mut seen);
		seen.retain(|&s| {
			let (x, y) = (s as i32 % maxx + 1, s as i32 / maxx + 1);
			(x - tx).abs() <= rx && (y - ty).abs() <= ry
		});
		let brightness = state.engine.brightness(z, &seen);
		state.seen = seen;
		Ok(brightness.unwrap_or(1.0))
	})
}

/// lighting_corners(turf, out): the turf's corners NE, SE, SW, NW, each as light (3), bounce light (3), colour drawn (3) and
/// the brightest channel drawn
#[no_mangle]
pub unsafe extern "C" fn lighting_corners(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("corners", |api, state| {
		if args.len() < 2 {
			return Err("wanted a turf and a list".into());
		}
		let (z, t) = state.place(&args[0])?;
		let (x, y) = state.engine.turf_xy(t);
		let maxx = state.engine.maxx;
		let level = state.engine.level(z);
		let mut out = Vec::with_capacity(40);
		for (cx, cy) in [(x, y), (x, y - 1), (x - 1, y - 1), (x - 1, y)] {
			let c = &level.corners[(cy * (maxx + 1) + cx) as usize];
			for v in c.lum.iter().chain(c.bounce.iter()).chain(c.cache.iter()) {
				out.push(ByondValue::num(*v));
			}
			out.push(ByondValue::num(c.largest));
		}
		write_values(api, &args[1], &out)?;
		Ok(1.0)
	})
}

/// lighting_light(id, out): the corners a light lights, as x, y, strength, then 1 for bounce light or 0 - corners at x + 0.5
#[no_mangle]
pub unsafe extern "C" fn lighting_light(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("light", |api, state| {
		if args.len() < 2 {
			return Err("wanted an id and a list".into());
		}
		let cols = state.engine.maxx + 1;
		let Some(Some(light)) = state.engine.lights.get(args[0].as_int() as usize) else {
			return Ok(0.0);
		};
		let mut out = Vec::new();
		for &(c, s) in light.effect.iter() {
			out.extend([
				ByondValue::num((c as i32 % cols) as f32),
				ByondValue::num((c as i32 / cols) as f32),
				ByondValue::num(s),
				ByondValue::num(0.0),
			]);
		}
		for &(c, s, _) in light.bounce.iter() {
			out.extend([
				ByondValue::num((c as i32 % cols) as f32),
				ByondValue::num((c as i32 / cols) as f32),
				ByondValue::num(s),
				ByondValue::num(1.0),
			]);
		}
		if !out.is_empty() {
			write_values(api, &args[1], &out)?;
		}
		Ok((out.len() / 4) as f32)
	})
}

/// lighting_dump(z, out): every corner on a z-level with any light or anything drawn: x, y, light (3), bounce light (3),
/// colour drawn (3)
#[no_mangle]
pub unsafe extern "C" fn lighting_dump(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	with_state("dump", |api, state| {
		if args.len() < 2 {
			return Err("wanted a z-level and a list".into());
		}
		let z = args[0].as_int() as usize;
		let cols = state.engine.maxx + 1;
		let mut out = Vec::new();
		if let Some(Some(level)) = state.engine.levels.get(z) {
			for (c, corner) in level.corners.iter().enumerate() {
				if corner
					.lum
					.iter()
					.chain(corner.bounce.iter())
					.chain(corner.cache.iter())
					.any(|&v| v != 0.0)
				{
					out.extend([
						ByondValue::num((c as i32 % cols) as f32),
						ByondValue::num((c as i32 / cols) as f32),
					]);
					for v in corner.lum.iter().chain(corner.bounce.iter()).chain(corner.cache.iter()) {
						out.push(ByondValue::num(*v));
					}
				}
			}
		}
		if !out.is_empty() {
			write_values(api, &args[1], &out)?;
		}
		Ok((out.len() / 11) as f32)
	})
}

/// lighting_check(): the engine's books (see engine::Engine::check()); problems go to the server's error output. Returns
/// how many there were.
#[no_mangle]
pub unsafe extern "C" fn lighting_check(_argc: u32, _argv: *const ByondValue) -> ByondValue {
	with_state("check", |_, state| {
		let problems = state.engine.check();
		for p in problems.iter().take(10) {
			eprintln!("hippie_lighting check: {p}");
		}
		Ok(problems.len() as f32)
	})
}
