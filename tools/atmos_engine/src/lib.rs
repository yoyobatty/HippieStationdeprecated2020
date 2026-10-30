//! Hippie's tile atmos engine, called from SSair (hippiestation/code/modules/atmospherics/tile_engine.dm).
//! The maths is in engine.rs; this is just the BYOND side of it.
//!
//! It only ever reads lists DM passes in and writes into a list DM passes in, so it never makes a BYOND value that
//! needs its reference looked after. The two BYOND API functions it uses (see BYOND's byondapi/byondapi.h) are
//! looked up in byondcore.dll at first use, so the library works with any 516 build that has them.

pub mod engine;

use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Mutex, OnceLock};

/// Bumped whenever the lists DM and the engine pass each other change shape. DM won't use a library that says
/// anything else and runs LINDA instead.
pub const ENGINE_VERSION: f32 = 3.0;

const TYPE_NULL: u8 = 0x00;
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
		ByondValue { kind: TYPE_NUMBER, junk: [0; 3], data: value.to_bits() }
	}

	fn as_number(&self) -> f64 {
		if self.kind == TYPE_NUMBER {
			f32::from_bits(self.data) as f64
		} else {
			0.0 // nulls (from DM growing a list) count as 0
		}
	}

	fn null() -> Self {
		ByondValue { kind: TYPE_NULL, junk: [0; 3], data: 0 }
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

fn read_numbers(api: &Api, list: &ByondValue) -> Result<Vec<f64>, String> {
	let mut buffer = vec![ByondValue::null(); 256];
	loop {
		let mut len = buffer.len() as u32;
		let ok = unsafe { (api.read_list)(list, buffer.as_mut_ptr(), &mut len) };
		if ok {
			buffer.truncate(len as usize);
			return Ok(buffer.iter().map(ByondValue::as_number).collect());
		}
		if len as usize <= buffer.len() {
			return Err("couldn't read a list".into());
		}
		buffer = vec![ByondValue::null(); len as usize];
	}
}

fn write_numbers(api: &Api, list: &ByondValue, values: &[f64]) -> Result<(), String> {
	let items: Vec<ByondValue> = values.iter().map(|value| ByondValue::num(*value as f32)).collect();
	if unsafe { (api.write_list)(list, items.as_ptr(), items.len() as u32) } {
		Ok(())
	} else {
		Err("couldn't write the result list".into())
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

static CONFIG: Mutex<Option<engine::Config>> = Mutex::new(None);

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

/// call_ext("hippie_atmos", "byond:atmos_engine_setup")(settings): takes the gas list, constants and reactions (see
/// engine::Config::parse() for the layout) and returns how many gases it took, or a negative number if it failed
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_setup(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("setup", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		let settings = args.first().ok_or("no settings list")?;
		let config = engine::Config::parse(&read_numbers(api, settings)?)?;
		let gases = config.gases as f32;
		*CONFIG.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(config);
		Ok(gases)
	})
}

/// call_ext("hippie_atmos", "byond:atmos_engine_tick")(tiles, pairs, planetary, result): one atmos tick (see
/// engine::tick() for the lists). Fills `result` and returns 1, or a negative number if it failed.
#[no_mangle]
pub unsafe extern "C" fn atmos_engine_tick(argc: u32, argv: *const ByondValue) -> ByondValue {
	let args = arguments(argc, argv);
	guarded("tick", || {
		let api = api().ok_or("byondcore.dll doesn't have Byond_ReadList and Byond_WriteList")?;
		if args.len() < 4 {
			return Err(format!("{} arguments, wanted tiles, pairs, planetary and result", args.len()));
		}
		let guard = CONFIG.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
		let config = guard.as_ref().ok_or("ticked before setup")?;
		let tiles = read_numbers(api, &args[0])?;
		let mut pairs = Vec::new();
		for index in read_numbers(api, &args[1])? {
			if index < 1.0 {
				return Err(format!("pair index {index}"));
			}
			pairs.push(index as usize - 1);
		}
		let planetary = read_numbers(api, &args[2])?;
		let mut out = Vec::new();
		engine::tick(config, &tiles, &pairs, &planetary, &mut out)?;
		write_numbers(api, &args[3], &out)?;
		Ok(1.0)
	})
}
