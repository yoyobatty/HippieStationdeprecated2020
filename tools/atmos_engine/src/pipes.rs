//! Pipe networks evening out their air (datum_pipeline.dm, reconcile_gases()). Nothing in here knows about BYOND.
//!
//! When anything on a pipe network changes its air, SSair evens out the air across every gas mixture on it (the pipes' shared
//! air, every machine's own air, a canister on a connector): the totals of every gas, the heat, then each mixture gets the total
//! at its share of the volume. On the distro loop that's two hundred mixtures read and written for one vent topping up a room.
//! The engine keeps every mixture's air as DM holds it after the last time it was evened out, so DM only sends the ones that
//! changed since; it works the totals out in DM's own 32-bit steps and order, and hands back the shared air.

use std::collections::HashMap;

/// A mixture's air as DM holds it: its volume, temperature and gases in its list's order
#[derive(Clone, Default, PartialEq)]
pub struct Mix {
	pub volume: f32,
	pub temperature: f32,
	pub gases: Vec<(u8, f32)>,
}

/// What evening out a network comes to: the total volume and temperature, and the gases in the order their list has them.
/// Each mixture gets temperature, and each gas at amount * (its volume / volume).
pub struct Total {
	pub volume: f32,
	pub temperature: f32,
	pub gases: Vec<(u8, f32)>,
}

#[derive(Default)]
pub struct Pipes {
	/// By the mixture's number (DM's pipe_engine_id)
	pub kept: HashMap<u32, Mix>,
	/// Checks (atmos-engine-pipes=shadow): mixtures checked, how many differed though nothing marked them changed
	pub checked: u64,
	pub wrong: u64,
	pub log: Vec<String>,
}

/// DM's QUANTIZE() and MINIMUM_MOLE_COUNT check in garbage_collect(), for a mixture with no archive: round(x, MOLAR_ACCURACY)
/// in DM's 32-bit steps (in 64 bits a total right at the edge came out the other side)
pub fn negligible(amount: f32, molar_accuracy: f64, min_mole_count: f64) -> bool {
	let accuracy = molar_accuracy as f32;
	((amount / accuracy + 0.5).floor() * accuracy) < min_mole_count as f32
}

/// BYOND's values_dot(gases, specific heats): it goes through the second list, in its order (the gases' order here), multiplies
/// exactly and rounds to 32 bits as it adds (both checked against BYOND 516.1688, 700 of 700)
pub fn values_dot(gases: &[(u8, f32)], specific_heat: &[f64]) -> f32 {
	let mut sorted: [Option<f32>; 64] = [None; 64];
	for &(gas, amount) in gases {
		sorted[gas as usize] = Some(amount);
	}
	let mut dot: f32 = 0.0;
	for (g, heat) in specific_heat.iter().enumerate() {
		if let Some(amount) = sorted[g] {
			dot = (dot as f64 + amount as f64 * heat) as f32;
		}
	}
	dot
}

/// reconcile_gases() over `members` (in GL order): the totals, the way DM adds them up, rounding to 32 bits at every step.
/// `specific_heat` by gas index.
pub fn even_out(members: &[&Mix], specific_heat: &[f64], molar_accuracy: f64, min_mole_count: f64) -> Total {
	let mut volume: f32 = 0.0;
	let mut heat_capacity: f32 = 0.0;
	let mut energy: f32 = 0.0;
	let mut order: Vec<u8> = Vec::new();
	let mut amounts = [0f32; 64];
	let mut present = [false; 64];
	for mix in members {
		volume += mix.volume;
		for &(gas, amount) in &mix.gases {
			let g = gas as usize;
			if !present[g] {
				present[g] = true;
				order.push(gas);
			}
			amounts[g] += amount;
			heat_capacity += amount * specific_heat[g] as f32;
		}
		energy += mix.temperature * values_dot(&mix.gases, specific_heat);
	}
	let temperature = if heat_capacity != 0.0 { energy / heat_capacity } else { 0.0 };
	let gases = order
		.into_iter()
		.filter(|&gas| !negligible(amounts[gas as usize], molar_accuracy, min_mole_count))
		.map(|gas| (gas, amounts[gas as usize]))
		.collect();
	Total { volume, temperature, gases }
}

/// A mixture's air after evening out: G.temperature = total temperature, its gases cut and refilled from the total's at its
/// share of the volume
pub fn share_of(total: &Total, volume: f32) -> Mix {
	let share = volume / total.volume;
	Mix {
		volume,
		temperature: total.temperature,
		gases: total.gases.iter().map(|&(gas, amount)| (gas, amount * share)).collect(),
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn mix(volume: f32, temperature: f32, gases: &[(u8, f32)]) -> Mix {
		Mix { volume, temperature, gases: gases.to_vec() }
	}

	#[test]
	fn evening_out_shares_by_volume_and_keeps_heat() {
		let a = mix(200.0, 300.0, &[(0, 10.0)]);
		let b = mix(600.0, 100.0, &[(0, 30.0), (1, 5.0)]);
		let total = even_out(&[&a, &b], &[20.0, 30.0], 1e-4, 0.01);
		assert_eq!(total.volume, 800.0);
		assert_eq!(total.gases, vec![(0, 40.0), (1, 5.0)]);
		let heat = 10.0f32 * 20.0 + 30.0 * 20.0 + 5.0 * 30.0;
		let energy = 300.0f32 * (10.0 * 20.0) + 100.0f32 * (30.0 * 20.0 + 5.0 * 30.0);
		assert_eq!(total.temperature, energy / heat);
		let shared = share_of(&total, 200.0);
		assert_eq!(shared.gases, vec![(0, 10.0), (1, 1.25)]);
	}

	#[test]
	fn a_trace_of_gas_goes() {
		let a = mix(100.0, 300.0, &[(0, 10.0), (1, 0.004)]);
		let total = even_out(&[&a], &[20.0, 30.0], 1e-4, 0.01);
		assert_eq!(total.gases, vec![(0, 10.0)]);
	}
}
