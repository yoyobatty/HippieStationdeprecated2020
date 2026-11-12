//! Idle vents and scrubbers, watched by the engine (hippiestation/code/modules/atmospherics/idle_machines.dm).
//!
//! A vent or scrubber with nothing to do goes idle until its turf's air changes. Air on a vent's turf changes nearly every
//! tick while a room settles, and each change woke it to find out again that it had nothing to do. When one goes idle, DM
//! tells the engine its turf and the settings its own check uses, and when the engine changes a turf's air it wakes only
//! the idle ones whose check would now come out differently: a vent whose room has fallen below (or, siphoning, risen
//! above) its pressure bound, a scrubber with something on its tile to filter out. Anything else that changes a machine
//! (its settings, power, being moved) wakes it in DM, which tells the engine it's awake.

use crate::engine::{Config, KIND_NO_AIR, KIND_SPACE};
use crate::world::Known;
use std::collections::HashMap;

/// A vent_pump
pub const KIND_VENT: u32 = 1;
/// A vent_scrubber
pub const KIND_SCRUBBER: u32 = 2;
/// Idle for its own settings (off, welded, unpowered): only those wake it, and they do in DM
pub const KIND_SETTINGS: u32 = 3;

/// Vent flags: releasing into the room (else siphoning out of it), and checking the room's pressure (EXT_BOUND)
pub const VENT_RELEASING: u32 = 1;
pub const VENT_EXTERNAL_BOUND: u32 = 2;

/// How far past its bound a room's pressure has to be before the engine says a vent has nothing to do. DM works pressure
/// out in its own 32-bit steps, so right at the bound the two can come out either side of it: there the vent is woken,
/// and DM decides.
const PRESSURE_MARGIN: f64 = 0.01;

struct Watched {
	turf: u32,
	kind: u32,
	flags: u32,
	bound: f64,
	/// Scrubbers: the gases it filters, one bit each
	filters: u64,
}

#[derive(Default)]
pub struct Machines {
	/// By atmos_serial
	idle: HashMap<u32, Watched>,
	/// Turf -> the idle machines on it
	on_turf: HashMap<u32, Vec<u32>>,
	/// Machines to wake, for DM (atmos_serial)
	pub wake: Vec<u32>,
	/// Counts for benches: turfs looked at, machines kept idle, machines woken
	pub checked: u64,
	pub kept_idle: u64,
	pub woken: u64,
}

impl Machines {
	/// It went idle on `turf` with these settings
	pub fn idle(&mut self, serial: u32, turf: u32, kind: u32, flags: u32, bound: f64, filters: u64) {
		self.awake(serial);
		self.idle.insert(serial, Watched { turf, kind, flags, bound, filters });
		self.on_turf.entry(turf).or_default().push(serial);
	}

	/// It's running again (or gone): the engine stops watching it
	pub fn awake(&mut self, serial: u32) {
		if let Some(watched) = self.idle.remove(&serial) {
			if let Some(list) = self.on_turf.get_mut(&watched.turf) {
				list.retain(|&s| s != serial);
				if list.is_empty() {
					self.on_turf.remove(&watched.turf);
				}
			}
		}
	}

	pub fn watching(&self) -> usize {
		self.idle.len()
	}

	/// The air on `turf` changed: wake the idle machines on it that would have something to do
	pub fn air_changed(&mut self, cfg: &Config, known: &Known, turf: u32) {
		let Some(serials) = self.on_turf.get(&turf) else {
			return;
		};
		self.checked += 1;
		let mut waking = Vec::new();
		for &serial in serials {
			let watched = &self.idle[&serial];
			if would_act(cfg, known, watched) {
				waking.push(serial);
			} else {
				self.kept_idle += 1;
			}
		}
		for serial in waking {
			self.awake(serial);
			self.wake.push(serial);
			self.woken += 1;
		}
	}
}

/// What the machine's process_atmos() would find on its turf: true unless it's sure to say ATMOS_IDLE
fn would_act(cfg: &Config, known: &Known, watched: &Watched) -> bool {
	let Some((kind, _)) = known.get(watched.turf) else {
		return true;
	};
	if kind == KIND_NO_AIR {
		return true; // not an open turf any more: DM sorts it out
	}
	let Some((temperature, gases)) = known.air(watched.turf) else {
		return true;
	};
	match watched.kind {
		KIND_VENT => {
			if watched.flags & VENT_EXTERNAL_BOUND == 0 {
				return true; // nothing about the room stops it
			}
			// return_pressure(): total moles * R * T / V; space's is 0
			let pressure = if kind == KIND_SPACE {
				0.0
			} else {
				let moles: f64 = gases.iter().map(|&(_, amount)| amount as f64).sum();
				moles * cfg.r * temperature as f64 / cfg.cell_volume
			};
			if watched.flags & VENT_RELEASING != 0 {
				watched.bound - pressure > -PRESSURE_MARGIN // not yet full enough out there
			} else {
				pressure - watched.bound > -PRESSURE_MARGIN // not yet empty enough out there
			}
		}
		KIND_SCRUBBER => gases.iter().any(|&(gas, amount)| amount != 0.0 && watched.filters & (1 << gas) != 0),
		KIND_SETTINGS => false,
		_ => true,
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::engine::KIND_TURF;

	fn config() -> Config {
		let mut settings = vec![2.0, 20.0, 30.0, -1.0, -1.0, 0.25, 4.0];
		settings.extend_from_slice(&[0.5, 0.001, 4.0, 0.5, 393.15, 0.4, 7000.0, 0.0003, 2.7, 8.31, 2500.0, 1e-4, 0.01, 693.15, 5.0, 10.0, 11.0, 5.0]);
		settings.push(0.0);
		Config::parse(&settings).unwrap()
	}

	#[test]
	fn a_vent_wakes_only_once_the_room_is_below_its_bound() {
		let cfg = config();
		let mut known = Known::default();
		known.set(7, KIND_TURF, &[]);
		// 101.325 kPa at 293.15 K in 2500 L is about 103.98 mol, so this is a little over
		known.set_air(7, 293.15, &[(0, 105.0)]); // 102.3 kPa
		let mut machines = Machines::default();
		machines.idle(1, 7, KIND_VENT, VENT_RELEASING | VENT_EXTERNAL_BOUND, 101.325, 0);
		machines.air_changed(&cfg, &known, 7);
		assert!(machines.wake.is_empty(), "full enough: stays idle");
		known.set_air(7, 293.15, &[(0, 90.0)]);
		machines.air_changed(&cfg, &known, 7);
		assert_eq!(machines.wake, vec![1]);
		assert_eq!(machines.watching(), 0);
	}

	#[test]
	fn a_scrubber_wakes_for_a_gas_it_filters() {
		let cfg = config();
		let mut known = Known::default();
		known.set(3, KIND_TURF, &[]);
		known.set_air(3, 293.15, &[(0, 100.0)]);
		let mut machines = Machines::default();
		machines.idle(9, 3, KIND_SCRUBBER, 0, 0.0, 1 << 1);
		machines.air_changed(&cfg, &known, 3);
		assert!(machines.wake.is_empty());
		known.set_air(3, 293.15, &[(0, 100.0), (1, 0.5)]);
		machines.air_changed(&cfg, &known, 3);
		assert_eq!(machines.wake, vec![9]);
	}

	#[test]
	fn right_at_the_bound_dm_decides() {
		let cfg = config();
		let mut known = Known::default();
		known.set(7, KIND_TURF, &[]);
		let moles = 101.325 * 2500.0 / (8.31 * 293.15);
		known.set_air(7, 293.15, &[(0, moles as f32)]);
		let mut machines = Machines::default();
		machines.idle(1, 7, KIND_VENT, VENT_RELEASING | VENT_EXTERNAL_BOUND, 101.325, 0);
		machines.air_changed(&cfg, &known, 7);
		assert_eq!(machines.wake, vec![1]);
	}
}
