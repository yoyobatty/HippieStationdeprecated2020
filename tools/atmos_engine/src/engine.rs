//! The tile maths. Nothing in here knows about BYOND: it takes flat number lists and gives one back, so it can be
//! tested on its own (cargo test).
//!
//! DM keeps every turf's air as the only copy. Each atmos tick it packs the awake tiles and their neighbours, this
//! works out the sharing between them from the tick's starting values (so the order tiles come in doesn't matter),
//! and DM writes back whatever changed. The sharing follows LINDA's maths (code/modules/atmospherics/gasmixtures/
//! gas_mixture.dm, share() and compare()), so gas moves at the same speed players know.

/// What a tile is, from DM's packing. Anything 3 and up is a planetary turf using planetary mix (kind - 3).
pub const KIND_TURF: u32 = 0;
pub const KIND_SPACE: u32 = 1;
pub const KIND_FIXED: u32 = 2;
pub const KIND_PLANETARY: u32 = 3;

/// A tile only packed as somebody's neighbour, and an awake one.
pub const NEIGHBOUR: u8 = 0;
pub const AWAKE: u8 = 1;

/// Numbers per tile in the list DM packs: G moles, then these
pub const TILE_EXTRAS: usize = 6;

pub struct Reaction {
	/// 0 if the reaction has no temperature requirement
	pub min_temperature: f64,
	/// 0 if the reaction has no thermal energy requirement
	pub min_energy: f64,
	/// (gas index, minimum moles)
	pub gases: Vec<(usize, f64)>,
}

pub struct Config {
	pub gases: usize,
	pub specific_heat: Vec<f64>,
	/// Moles a gas needs before its overlay shows, negative for gases with no overlay
	pub moles_visible: Vec<f64>,
	pub visible_step: f64,
	pub visible_states: f64,
	pub reactions: Vec<Reaction>,
	pub min_moles_delta: f64,
	pub min_air_ratio: f64,
	pub min_temp_delta_suspend: f64,
	pub min_temp_delta_consider: f64,
	pub min_temp_to_move: f64,
	pub open_heat_transfer: f64,
	pub heat_capacity_vacuum: f64,
	pub min_heat_capacity: f64,
	pub tcmb: f64,
	pub r: f64,
	pub cell_volume: f64,
	pub molar_accuracy: f64,
	pub min_mole_count: f64,
	pub superconduct_temp: f64,
	pub superconduct_heat_capacity: f64,
	/// A share bigger than this keeps a group of tiles from being evened out (MINIMUM_AIR_TO_SUSPEND)
	pub min_air_to_suspend: f64,
	/// Ticks a group has to go without one before it's evened out (EXCITED_GROUP_BREAKDOWN_CYCLES)
	pub breakdown_ticks: f64,
}

/// How many constants come after the per-gas lists in the settings list, in Config's order from min_moles_delta on
const CONSTANTS: usize = 17;

impl Config {
	/// Settings list layout: gas count G; G specific heats; G visible-mole thresholds (-1 for no overlay); the visible
	/// step and state count; the 15 constants; then the reaction count and, per reaction, its minimum temperature,
	/// minimum thermal energy, how many gases it needs, and that many (gas index from 1, minimum moles) pairs.
	pub fn parse(data: &[f64]) -> Result<Config, String> {
		let mut at = 0usize;
		let mut next = |what: &str| -> Result<f64, String> {
			let value = *data.get(at).ok_or_else(|| format!("settings ran out at {what}"))?;
			at += 1;
			Ok(value)
		};
		let gases = next("gas count")? as usize;
		if gases == 0 || gases > 64 {
			return Err(format!("{gases} gases"));
		}
		let mut specific_heat = Vec::with_capacity(gases);
		for _ in 0..gases {
			specific_heat.push(next("specific heats")?);
		}
		let mut moles_visible = Vec::with_capacity(gases);
		for _ in 0..gases {
			moles_visible.push(next("visible moles")?);
		}
		let visible_step = next("visible step")?;
		let visible_states = next("visible states")?;
		let mut c = [0f64; CONSTANTS];
		for slot in c.iter_mut() {
			*slot = next("constants")?;
		}
		let reaction_count = next("reaction count")? as usize;
		let mut reactions = Vec::with_capacity(reaction_count);
		for _ in 0..reaction_count {
			let min_temperature = next("reaction temperature")?;
			let min_energy = next("reaction energy")?;
			let count = next("reaction gas count")? as usize;
			let mut needs = Vec::with_capacity(count);
			for _ in 0..count {
				let index = next("reaction gas")? as usize;
				let amount = next("reaction moles")?;
				if index == 0 || index > gases {
					return Err(format!("reaction needs gas {index} of {gases}"));
				}
				needs.push((index - 1, amount));
			}
			reactions.push(Reaction { min_temperature, min_energy, gases: needs });
		}
		Ok(Config {
			gases,
			specific_heat,
			moles_visible,
			visible_step,
			visible_states,
			reactions,
			min_moles_delta: c[0],
			min_air_ratio: c[1],
			min_temp_delta_suspend: c[2],
			min_temp_delta_consider: c[3],
			min_temp_to_move: c[4],
			open_heat_transfer: c[5],
			heat_capacity_vacuum: c[6],
			min_heat_capacity: c[7],
			tcmb: c[8],
			r: c[9],
			cell_volume: c[10],
			molar_accuracy: c[11],
			min_mole_count: c[12],
			superconduct_temp: c[13],
			superconduct_heat_capacity: c[14],
			min_air_to_suspend: c[15],
			breakdown_ticks: c[16],
		})
	}

	/// DM's QUANTIZE(): round(x, MOLAR_ACCURACY), which rounds halves up
	fn quantize(&self, value: f64) -> f64 {
		(value / self.molar_accuracy + 0.5).floor() * self.molar_accuracy
	}

	fn real_heat_capacity(&self, moles: &[f64]) -> f64 {
		moles.iter().zip(&self.specific_heat).map(|(m, c)| m * c).sum()
	}

	/// Heat capacity the way DM's turf mixtures count it: an empty one counts as HEAT_CAPACITY_VACUUM
	fn turf_heat_capacity(&self, moles: &[f64]) -> f64 {
		let real = self.real_heat_capacity(moles);
		if real == 0.0 {
			self.heat_capacity_vacuum
		} else {
			real
		}
	}

	/// LINDA's compare(): is the difference between our air and theirs worth sharing over
	fn significant(&self, ours: &[f64], our_temp: f64, theirs: &[f64], their_temp: f64) -> bool {
		let mut our_total = 0.0;
		for (mine, other) in ours.iter().zip(theirs) {
			let delta = (mine - other).abs();
			if delta > self.min_moles_delta && delta > mine * self.min_air_ratio {
				return true;
			}
			our_total += mine;
		}
		our_total > self.min_moles_delta && (our_temp - their_temp).abs() > self.min_temp_delta_suspend
	}

	/// Which overlay state each visible gas is in, the way update_visuals() picks them
	fn visual_level(&self, gas: usize, moles: f64) -> u32 {
		let threshold = self.moles_visible[gas];
		if threshold < 0.0 || moles <= threshold {
			return 0;
		}
		(moles / self.visible_step).ceil().min(self.visible_states) as u32
	}

	/// A 24 bit hash of every visible gas's overlay state, so it fits a DM number exactly. DM keeps the one it last
	/// drew each tile with, and a different one means update_visuals() would draw something else.
	pub fn visual_key(&self, moles: &[f64]) -> f64 {
		let mut hash: u32 = 2166136261;
		for (gas, amount) in moles.iter().enumerate() {
			if self.moles_visible[gas] < 0.0 {
				continue;
			}
			hash = (hash ^ (self.visual_level(gas, *amount) + 1)).wrapping_mul(16777619);
		}
		(hash & 0x00FF_FFFF) as f64
	}

	fn can_react(&self, moles: &[f64], temperature: f64, heat_capacity: f64) -> bool {
		let energy = temperature * heat_capacity;
		self.reactions.iter().any(|reaction| {
			(reaction.min_temperature == 0.0 || temperature >= reaction.min_temperature)
				&& (reaction.min_energy == 0.0 || energy >= reaction.min_energy)
				&& reaction.gases.iter().all(|&(gas, need)| moles[gas] > 0.0 && moles[gas] >= need)
		})
	}
}

fn mutable(kind: u32) -> bool {
	kind != KIND_SPACE && kind != KIND_FIXED
}

/// One atmos tick. `tiles` has G + 6 numbers per tile: G moles, temperature, how many tiles it's atmos-adjacent to,
/// kind, awake state, the overlay key DM last drew it with (-1 if none), and how many ticks since it last had a
/// share bigger than MINIMUM_AIR_TO_SUSPEND. `pairs` are tile indices from 0, two per pair, each pair once and at
/// least one of each pair awake. `planetary` has G moles and a temperature per planetary mix. Indices DM gets back
/// count from 1.
///
/// Writes these sections to `out`, each starting with how many entries follow:
/// - changed tiles: index, G moles, temperature
/// - wind: tile, the neighbour it pushes toward, pressure difference (for consider_pressure_difference())
/// - neighbours to wake
/// - awake tiles that were quiet this tick
/// - awake tiles where a reaction's requirements are met
/// - tiles whose gas overlays need redrawing: index, new overlay key
/// - awake tiles hot enough to start conducting heat through walls
/// - awake tiles that had a share bigger than MINIMUM_AIR_TO_SUSPEND
/// - tiles in groups that got evened out this tick
pub fn tick(cfg: &Config, tiles: &[f64], pairs: &[usize], planetary: &[f64], out: &mut Vec<f64>) -> Result<(), String> {
	let g = cfg.gases;
	let stride = g + TILE_EXTRAS;
	if tiles.len() % stride != 0 {
		return Err(format!("{} tile numbers isn't a whole number of tiles of {stride}", tiles.len()));
	}
	if pairs.len() % 2 != 0 {
		return Err("odd number of pair indices".into());
	}
	if planetary.len() % (g + 1) != 0 {
		return Err("planetary mixes aren't G + 1 numbers each".into());
	}
	let n = tiles.len() / stride;
	let planets = planetary.len() / (g + 1);

	let mut start = vec![0f64; n * g];
	let mut temp = vec![0f64; n];
	let mut adjacent = vec![0f64; n];
	let mut kind = vec![0u32; n];
	let mut awake = vec![NEIGHBOUR; n];
	let mut drawn = vec![-1f64; n];
	let mut calm = vec![0f64; n];
	for i in 0..n {
		let row = &tiles[i * stride..(i + 1) * stride];
		for gas in 0..g {
			start[i * g + gas] = row[gas].max(0.0);
		}
		temp[i] = row[g];
		adjacent[i] = row[g + 1];
		kind[i] = row[g + 2] as u32;
		awake[i] = row[g + 3] as u8;
		drawn[i] = row[g + 4];
		calm[i] = row[g + 5];
		if kind[i] >= KIND_PLANETARY && (kind[i] - KIND_PLANETARY) as usize >= planets {
			return Err(format!("tile {i} uses planetary mix {} of {planets}", kind[i] - KIND_PLANETARY));
		}
	}

	let mut heat_capacity = vec![0f64; n];
	let mut total = vec![0f64; n];
	for i in 0..n {
		let moles = &start[i * g..(i + 1) * g];
		total[i] = moles.iter().sum();
		heat_capacity[i] = if kind[i] == KIND_SPACE { cfg.heat_capacity_vacuum } else { cfg.turf_heat_capacity(moles) };
	}

	let mut moles = start.clone();
	let mut energy_in = vec![0f64; n];
	let mut heat_capacity_in = vec![0f64; n];
	// Conduction changes temperature by heat over the tile's starting heat capacity, like temperature_share()
	let mut conduction = vec![0f64; n];
	let mut biggest_share = vec![0f64; n];
	let mut wind = vec![(0f64, usize::MAX); n];
	let mut wake = vec![false; n];
	// Awake tiles sharing with each other this tick, for evening out groups of them below
	let mut linked: Vec<(usize, usize)> = Vec::new();

	for pair in pairs.chunks_exact(2) {
		let (mut a, mut b) = (pair[0], pair[1]);
		if a >= n || b >= n || a == b {
			return Err(format!("bad pair {a}, {b} of {n} tiles"));
		}
		// Always share from the side whose air can change: space and fixed air only ever give or take
		if !mutable(kind[a]) {
			std::mem::swap(&mut a, &mut b);
		}
		if !mutable(kind[a]) {
			continue;
		}
		let b_mutable = mutable(kind[b]);
		if awake[b] == NEIGHBOUR && awake[a] == NEIGHBOUR {
			continue;
		}
		// A sleeping neighbour only joins in if the difference is worth it, like LINDA's compare()
		let sleeper = if awake[b] == NEIGHBOUR { Some(b) } else if awake[a] == NEIGHBOUR { Some(a) } else { None };
		if sleeper.is_some()
			&& !cfg.significant(&start[a * g..(a + 1) * g], temp[a], &start[b * g..(b + 1) * g], temp[b])
		{
			continue;
		}
		if let Some(s) = sleeper {
			if mutable(kind[s]) {
				wake[s] = true;
			}
		} else if b_mutable {
			linked.push((a, b));
		}

		let our_coeff = 1.0 / (adjacent[a] + 1.0);
		let their_coeff = 1.0 / (adjacent[b] + 1.0);
		let temperature_delta = temp[a] - temp[b];
		let consider_heat = temperature_delta.abs() > cfg.min_temp_delta_consider;
		let mut moved = 0.0;
		let mut abs_moved = 0.0;
		let mut heat_capacity_out = 0.0; // of the gas going from a to b
		let mut heat_capacity_back = 0.0; // of the gas going from b to a
		for gas in 0..g {
			let mut delta = cfg.quantize(start[a * g + gas] - start[b * g + gas]);
			if delta == 0.0 {
				continue;
			}
			delta *= if delta > 0.0 { our_coeff } else { their_coeff };
			moles[a * g + gas] -= delta;
			if b_mutable {
				moles[b * g + gas] += delta;
			}
			moved += delta;
			abs_moved += delta.abs();
			if consider_heat {
				let gas_heat_capacity = delta * cfg.specific_heat[gas];
				if delta > 0.0 {
					heat_capacity_out += gas_heat_capacity;
				} else {
					heat_capacity_back -= gas_heat_capacity;
				}
			}
		}
		biggest_share[a] = biggest_share[a].max(abs_moved);
		biggest_share[b] = biggest_share[b].max(abs_moved);

		if consider_heat {
			// The gas carries its heat with it at the temperature of the side it left
			energy_in[a] += heat_capacity_back * temp[b] - heat_capacity_out * temp[a];
			heat_capacity_in[a] += heat_capacity_back - heat_capacity_out;
			if b_mutable {
				energy_in[b] += heat_capacity_out * temp[a] - heat_capacity_back * temp[b];
				heat_capacity_in[b] += heat_capacity_out - heat_capacity_back;
			}
			// Then conduction, as LINDA does when the gas moved didn't change their heat capacity much
			let theirs_before = heat_capacity[b];
			let theirs_after = theirs_before + heat_capacity_out - heat_capacity_back;
			if theirs_before.abs() > cfg.min_heat_capacity && (theirs_after / theirs_before - 1.0).abs() < 0.1 {
				let (ours, theirs) = (heat_capacity[a], heat_capacity[b]);
				if ours > cfg.min_heat_capacity && theirs > cfg.min_heat_capacity {
					let heat = cfg.open_heat_transfer * temperature_delta * (ours * theirs / (ours + theirs));
					conduction[a] -= heat / ours;
					if b_mutable {
						conduction[b] += heat / theirs;
					}
				}
			}
		}

		// Wind: the pressure difference across the pair, the way share() works it out for consider_pressure_difference()
		if temperature_delta > cfg.min_temp_to_move || moved.abs() > cfg.min_moles_delta {
			let difference = (temp[a] * total[a] - temp[b] * total[b]) * cfg.r / cfg.cell_volume;
			let (from, to, size) = if difference > 0.0 { (a, b, difference) } else { (b, a, -difference) };
			if size > 0.0 && size > wind[from].0 {
				wind[from] = (size, to);
			}
		}
	}

	let mut new_temp = temp.clone();
	for i in 0..n {
		if !mutable(kind[i]) {
			continue;
		}
		let mut t = temp[i];
		if heat_capacity_in[i] != 0.0 || energy_in[i] != 0.0 {
			let after = heat_capacity[i] + heat_capacity_in[i];
			if after > cfg.min_heat_capacity {
				t = (heat_capacity[i] * temp[i] + energy_in[i]) / after;
			}
		}
		new_temp[i] = (t + conduction[i]).max(cfg.tcmb);
	}

	// Planetary turfs then share with the planet's air at 0.8 strength, from where the tick left them, and conduct
	// heat with it as if it had five times its heat capacity (LINDA's process_cell())
	for i in 0..n {
		if kind[i] < KIND_PLANETARY || awake[i] == NEIGHBOUR {
			continue;
		}
		let p = (kind[i] - KIND_PLANETARY) as usize;
		let planet = &planetary[p * (g + 1)..p * (g + 1) + g];
		let planet_temp = planetary[p * (g + 1) + g];
		let here_temp = new_temp[i];
		if !cfg.significant(&moles[i * g..(i + 1) * g], here_temp, planet, planet_temp) {
			continue;
		}
		let here_heat_capacity = cfg.turf_heat_capacity(&moles[i * g..(i + 1) * g]);
		let consider_heat = (here_temp - planet_temp).abs() > cfg.min_temp_delta_consider;
		let mut abs_moved = 0.0;
		let mut heat_capacity_out = 0.0;
		let mut heat_capacity_back = 0.0;
		for gas in 0..g {
			let mut delta = cfg.quantize(moles[i * g + gas] - planet[gas]);
			if delta == 0.0 {
				continue;
			}
			delta *= 0.8;
			moles[i * g + gas] -= delta;
			abs_moved += delta.abs();
			if consider_heat {
				let gas_heat_capacity = delta * cfg.specific_heat[gas];
				if delta > 0.0 {
					heat_capacity_out += gas_heat_capacity;
				} else {
					heat_capacity_back -= gas_heat_capacity;
				}
			}
		}
		biggest_share[i] = biggest_share[i].max(abs_moved);
		let mut t = here_temp;
		if consider_heat {
			let after = here_heat_capacity + heat_capacity_back - heat_capacity_out;
			if after > cfg.min_heat_capacity {
				t = (here_heat_capacity * here_temp - heat_capacity_out * here_temp + heat_capacity_back * planet_temp) / after;
			}
		}
		let planet_heat_capacity = cfg.real_heat_capacity(planet) * 5.0;
		let ours = cfg.turf_heat_capacity(&moles[i * g..(i + 1) * g]);
		if (t - planet_temp).abs() > cfg.min_temp_delta_consider && ours > cfg.min_heat_capacity && planet_heat_capacity > cfg.min_heat_capacity {
			let heat = cfg.open_heat_transfer * (t - planet_temp) * (ours * planet_heat_capacity / (ours + planet_heat_capacity));
			t -= heat / ours;
		}
		new_temp[i] = t.max(cfg.tcmb);
	}

	// Groups of awake tiles sharing with each other get evened out once none of them has had a share bigger than
	// MINIMUM_AIR_TO_SUSPEND for breakdown_ticks ticks, like LINDA's excited group self_breakdown(): every tile gets
	// the group's average, at the temperature their heat adds up to. That's how rooms settle instead of creeping
	// together forever. DM keeps each tile's count of ticks since its last big share (calm).
	let big: Vec<bool> = (0..n).map(|i| biggest_share[i] > cfg.min_air_to_suspend).collect();
	let mut group: Vec<usize> = (0..n).collect();
	fn root(group: &mut [usize], mut i: usize) -> usize {
		while group[i] != i {
			group[i] = group[group[i]];
			i = group[i];
		}
		i
	}
	for &(a, b) in &linked {
		let (ra, rb) = (root(&mut group, a), root(&mut group, b));
		if ra != rb {
			group[ra.max(rb)] = ra.min(rb);
		}
	}
	let mut in_a_group = vec![false; n];
	for &(a, b) in &linked {
		in_a_group[a] = true;
		in_a_group[b] = true;
	}
	let mut members: std::collections::BTreeMap<usize, Vec<usize>> = std::collections::BTreeMap::new();
	for i in 0..n {
		if in_a_group[i] {
			let r = root(&mut group, i);
			members.entry(r).or_default().push(i);
		}
	}
	let mut broke_down = Vec::new();
	for tiles_in_group in members.values() {
		let settled = tiles_in_group.iter().all(|&i| !big[i] && calm[i] + 1.0 >= cfg.breakdown_ticks);
		if !settled {
			continue;
		}
		let mut sum = vec![0f64; g];
		let mut energy = 0.0;
		let mut group_heat_capacity = 0.0;
		for &i in tiles_in_group {
			let here = &moles[i * g..(i + 1) * g];
			for gas in 0..g {
				sum[gas] += here[gas];
			}
			let capacity = cfg.turf_heat_capacity(here);
			energy += new_temp[i] * capacity;
			group_heat_capacity += capacity;
		}
		let count = tiles_in_group.len() as f64;
		for value in sum.iter_mut() {
			*value /= count;
			if cfg.quantize(*value) < cfg.min_mole_count {
				*value = 0.0;
			}
		}
		let average_temp = if group_heat_capacity > 0.0 { energy / group_heat_capacity } else { cfg.tcmb };
		for &i in tiles_in_group {
			if kind[i] >= KIND_PLANETARY {
				// Planetary turfs just go back to the planet's air, as in self_breakdown()
				let p = (kind[i] - KIND_PLANETARY) as usize;
				moles[i * g..(i + 1) * g].copy_from_slice(&planetary[p * (g + 1)..p * (g + 1) + g]);
				new_temp[i] = planetary[p * (g + 1) + g];
			} else {
				moles[i * g..(i + 1) * g].copy_from_slice(&sum);
				new_temp[i] = average_temp;
			}
			broke_down.push(i);
		}
	}
	broke_down.sort_unstable();

	// Tiny leftovers go, the way garbage_collect() drops them, and nothing goes below zero
	for i in 0..n {
		if !mutable(kind[i]) {
			continue;
		}
		for gas in 0..g {
			let index = i * g + gas;
			if moles[index] < 0.0 {
				moles[index] = 0.0;
			}
			if moles[index] != start[index]
				&& cfg.quantize(moles[index]) < cfg.min_mole_count
				&& cfg.quantize(start[index]) < cfg.min_mole_count
			{
				moles[index] = 0.0;
			}
		}
	}

	// Changed tiles, compared at the precision DM keeps (32-bit floats)
	let mut changed = Vec::new();
	for i in 0..n {
		if !mutable(kind[i]) {
			continue;
		}
		let differs = (new_temp[i] as f32) != (temp[i] as f32)
			|| (0..g).any(|gas| (moles[i * g + gas] as f32) != (start[i * g + gas] as f32));
		if differs {
			changed.push(i);
		}
	}
	out.push(changed.len() as f64);
	for &i in &changed {
		out.push(i as f64 + 1.0);
		out.extend_from_slice(&moles[i * g..(i + 1) * g]);
		out.push(new_temp[i]);
	}

	let windy: Vec<usize> = (0..n).filter(|&i| wind[i].1 != usize::MAX).collect();
	out.push(windy.len() as f64);
	for &i in &windy {
		out.push(i as f64 + 1.0);
		out.push(wind[i].1 as f64 + 1.0);
		out.push(wind[i].0);
	}

	let woken: Vec<usize> = (0..n).filter(|&i| wake[i]).collect();
	out.push(woken.len() as f64);
	out.extend(woken.iter().map(|&i| i as f64 + 1.0));

	let mut quiet = Vec::new();
	let mut react = Vec::new();
	let mut visuals = Vec::new();
	let mut superconduct = Vec::new();
	for i in 0..n {
		if !mutable(kind[i]) {
			continue;
		}
		let now = &moles[i * g..(i + 1) * g];
		let real_heat_capacity = cfg.real_heat_capacity(now);
		let hot = new_temp[i] >= cfg.superconduct_temp && real_heat_capacity >= cfg.superconduct_heat_capacity;
		let key = cfg.visual_key(now);
		if key != drawn[i] {
			visuals.push((i, key));
		}
		if awake[i] == NEIGHBOUR {
			continue;
		}
		if hot {
			superconduct.push(i);
		}
		let heat_capacity_now = if real_heat_capacity == 0.0 { cfg.heat_capacity_vacuum } else { real_heat_capacity };
		if cfg.can_react(now, new_temp[i], heat_capacity_now) {
			react.push(i);
		}
		if !hot && biggest_share[i] <= cfg.min_moles_delta && (new_temp[i] - temp[i]).abs() < cfg.min_temp_delta_consider {
			quiet.push(i);
		}
	}
	for list in [&quiet, &react] {
		out.push(list.len() as f64);
		out.extend(list.iter().map(|&i| i as f64 + 1.0));
	}
	out.push(visuals.len() as f64);
	for &(i, key) in &visuals {
		out.push(i as f64 + 1.0);
		out.push(key);
	}
	out.push(superconduct.len() as f64);
	out.extend(superconduct.iter().map(|&i| i as f64 + 1.0));
	let had_big_share: Vec<usize> = (0..n).filter(|&i| big[i] && awake[i] != NEIGHBOUR && mutable(kind[i])).collect();
	for list in [&had_big_share, &broke_down] {
		out.push(list.len() as f64);
		out.extend(list.iter().map(|&i| i as f64 + 1.0));
	}
	Ok(())
}

#[cfg(test)]
mod tests {
	use super::*;

	/// The real gases' specific heats in meta_gas_list() order isn't needed here: three made-up gases will do
	fn config() -> Config {
		let mut settings = vec![3.0, 20.0, 20.0, 200.0, -1.0, -1.0, 0.25, 0.25, 4.0];
		let moles_cellstandard = 101.325 * 2500.0 / (293.15 * 8.31);
		settings.extend_from_slice(&[
			moles_cellstandard * 0.001, // min_moles_delta
			0.001,                      // min_air_ratio
			4.0,                        // min_temp_delta_suspend
			0.5,                        // min_temp_delta_consider
			293.15 + 100.0,             // min_temp_to_move
			0.4,                        // open_heat_transfer
			7000.0,                     // heat_capacity_vacuum
			0.0003,                     // min_heat_capacity
			2.7,                        // tcmb
			8.31,                       // r
			2500.0,                     // cell_volume
			1e-4,                       // molar_accuracy
			0.01,                       // min_mole_count
			293.15 + 400.0,             // superconduct_temp
			moles_cellstandard * 0.005, // superconduct_heat_capacity
			moles_cellstandard * 0.1,   // min_air_to_suspend
			5.0,                        // breakdown_ticks
		]);
		// One reaction: gas 3 above 1 mole, over 400 K
		settings.extend_from_slice(&[1.0, 400.0, 0.0, 1.0, 3.0, 1.0]);
		Config::parse(&settings).unwrap()
	}

	fn tile(moles: [f64; 3], temperature: f64, adjacent: f64, kind: u32, awake: u8) -> Vec<f64> {
		let cfg = config();
		vec![moles[0], moles[1], moles[2], temperature, adjacent, kind as f64, awake as f64, cfg.visual_key(&moles), 0.0]
	}

	#[test]
	fn settled_groups_get_evened_out() {
		let cfg = config();
		let mut tiles = Vec::new();
		for (amount, temperature) in [(100.0, 300.0), (101.0, 300.0), (102.0, 330.0)] {
			let mut row = tile([amount, 0.0, 0.0], temperature, 2.0, KIND_TURF, AWAKE);
			row[8] = 10.0; // calm for long enough
			tiles.extend(row);
		}
		let mut out = Vec::new();
		tick(&cfg, &tiles, &[0, 1, 1, 2], &[], &mut out).unwrap();
		let changed = out[0] as usize;
		assert_eq!(changed, 3);
		let values: Vec<(f64, f64)> = (0..changed).map(|k| (out[1 + k * 5 + 1], out[1 + k * 5 + 4])).collect();
		// Heat: (100 * 300 + 101 * 300 + 102 * 330) / 303 = 310.10 K, give or take this tick's own sharing first
		for (amount, temperature) in &values {
			assert!((amount - 101.0).abs() < 1e-6, "every tile gets the average: {values:?}");
			assert!((temperature - 310.10).abs() < 0.05, "at the temperature their heat adds up to: {values:?}");
			assert_eq!(*temperature, values[0].1, "all the same: {values:?}");
		}
		// The last section lists the tiles that got evened out
		assert_eq!(&out[out.len() - 4..], &[3.0, 1.0, 2.0, 3.0]);
	}

	#[test]
	fn busy_groups_are_left_alone() {
		let cfg = config();
		let mut tiles = Vec::new();
		for amount in [100.0, 101.0] {
			let mut row = tile([amount, 0.0, 0.0], 300.0, 1.0, KIND_TURF, AWAKE);
			row[8] = 2.0; // not calm for long enough yet
			tiles.extend(row);
		}
		let mut out = Vec::new();
		tick(&cfg, &tiles, &[0, 1], &[], &mut out).unwrap();
		assert_eq!(out[out.len() - 1], 0.0, "nothing evened out");
	}

	struct Result {
		changed: Vec<(usize, Vec<f64>, f64)>,
		wind: Vec<(usize, usize, f64)>,
		wake: Vec<usize>,
		quiet: Vec<usize>,
		react: Vec<usize>,
	}

	fn run(tiles: &[Vec<f64>], pairs: &[usize]) -> Result {
		let cfg = config();
		let flat: Vec<f64> = tiles.concat();
		let mut out = Vec::new();
		tick(&cfg, &flat, pairs, &[], &mut out).unwrap();
		let mut at = 0;
		let mut take = || {
			let v = out[at];
			at += 1;
			v
		};
		let mut changed = Vec::new();
		for _ in 0..take() as usize {
			let i = take() as usize - 1;
			let moles = vec![take(), take(), take()];
			let temperature = take();
			changed.push((i, moles, temperature));
		}
		let mut wind = Vec::new();
		for _ in 0..take() as usize {
			wind.push((take() as usize - 1, take() as usize - 1, take()));
		}
		let mut list = || {
			let count = take() as usize;
			(0..count).map(|_| take() as usize - 1).collect::<Vec<_>>()
		};
		let wake = list();
		let quiet = list();
		let react = list();
		Result { changed, wind, wake, quiet, react }
	}

	#[test]
	fn gas_is_conserved_between_two_tiles() {
		let r = run(&[tile([80.0, 20.0, 0.0], 293.15, 1.0, KIND_TURF, AWAKE), tile([0.0, 0.0, 0.0], 293.15, 1.0, KIND_TURF, AWAKE)], &[0, 1]);
		assert_eq!(r.changed.len(), 2);
		let total: f64 = r.changed.iter().flat_map(|(_, m, _)| m.iter()).sum();
		assert!((total - 100.0).abs() < 1e-9, "total {total}");
		// Each side moves half the difference when each has one neighbour
		let a = &r.changed.iter().find(|c| c.0 == 0).unwrap().1;
		assert!((a[0] - 40.0).abs() < 1e-6, "{a:?}");
		assert_eq!(r.wind.len(), 1);
		assert_eq!((r.wind[0].0, r.wind[0].1), (0, 1));
	}

	#[test]
	fn space_takes_gas_away() {
		let r = run(&[tile([100.0, 0.0, 0.0], 293.15, 4.0, KIND_TURF, AWAKE), tile([0.0, 0.0, 0.0], 2.7, 4.0, KIND_SPACE, NEIGHBOUR)], &[0, 1]);
		assert_eq!(r.changed.len(), 1, "space itself never changes");
		let (_, moles, temperature) = &r.changed[0];
		assert!((moles[0] - 80.0).abs() < 1e-6, "{moles:?}");
		// LINDA: the gas leaving carries its own heat, then conduction with the vacuum takes
		// 0.4 * 290.45 * (2000 * 7000 / 9000) J over the starting 2000 J/K: down to about 202.8 K
		assert!((*temperature - 202.78).abs() < 0.05, "venting gas should cool like LINDA's, got {temperature}");
		assert!(r.wake.is_empty(), "space never wakes");
	}

	#[test]
	fn small_differences_dont_wake_sleepers() {
		let r = run(&[tile([100.0, 0.0, 0.0], 293.15, 4.0, KIND_TURF, AWAKE), tile([100.05, 0.0, 0.0], 293.15, 4.0, KIND_TURF, NEIGHBOUR)], &[0, 1]);
		assert!(r.changed.is_empty());
		assert!(r.wake.is_empty());
		assert_eq!(r.quiet, vec![0]);
	}

	#[test]
	fn big_differences_wake_sleepers() {
		let r = run(&[tile([100.0, 0.0, 0.0], 293.15, 4.0, KIND_TURF, AWAKE), tile([50.0, 0.0, 0.0], 293.15, 4.0, KIND_TURF, NEIGHBOUR)], &[0, 1]);
		assert_eq!(r.wake, vec![1]);
		assert!(r.quiet.is_empty());
	}

	#[test]
	fn heat_is_conserved_with_conduction() {
		let cfg = config();
		let tiles = [tile([100.0, 0.0, 0.0], 400.0, 1.0, KIND_TURF, AWAKE), tile([100.0, 0.0, 0.0], 300.0, 1.0, KIND_TURF, AWAKE)].concat();
		let mut out = Vec::new();
		tick(&cfg, &tiles, &[0, 1], &[], &mut out).unwrap();
		// two changed tiles: index, 3 moles, temperature each
		let t0 = out[1 + 4];
		let t1 = out[1 + 5 + 4];
		assert!(t0 < 400.0 && t1 > 300.0);
		assert!(((t0 + t1) - 700.0).abs() < 1e-6, "same heat capacity on both sides, so the temperatures should sum the same: {t0} + {t1}");
	}

	#[test]
	fn reactions_need_their_requirements() {
		let cold = run(&[tile([0.0, 0.0, 5.0], 300.0, 0.0, KIND_TURF, AWAKE)], &[]);
		assert!(cold.react.is_empty());
		let hot = run(&[tile([0.0, 0.0, 5.0], 500.0, 0.0, KIND_TURF, AWAKE)], &[]);
		assert_eq!(hot.react, vec![0]);
		let too_little = run(&[tile([0.0, 0.0, 0.5], 500.0, 0.0, KIND_TURF, AWAKE)], &[]);
		assert!(too_little.react.is_empty());
	}

	#[test]
	fn planetary_turfs_relax_toward_the_planet() {
		let cfg = config();
		let tiles = tile([0.0, 0.0, 0.0], 300.0, 4.0, KIND_PLANETARY, AWAKE);
		let planet = [20.0, 80.0, 0.0, 300.0];
		let mut out = Vec::new();
		tick(&cfg, &tiles, &[], &planet, &mut out).unwrap();
		assert_eq!(out[0], 1.0, "one changed tile");
		assert!((out[2] - 16.0).abs() < 1e-6 && (out[3] - 64.0).abs() < 1e-6, "0.8 of the way to the planet: {:?}", &out[2..5]);
	}

	#[test]
	fn overlays_redraw_only_when_they_would_look_different() {
		let cfg = config();
		// Gas 3 is the visible one (moles visible 0.25, step 0.25, 4 states)
		let mut tiles = tile([50.0, 0.0, 0.0], 293.15, 0.0, KIND_TURF, AWAKE);
		let mut out = Vec::new();
		tick(&cfg, &tiles, &[], &[], &mut out).unwrap();
		// sections: changed 0, wind 0, wake 0, quiet 1 (index), react 0, redraw count...
		assert_eq!(&out[..6], &[0.0, 0.0, 0.0, 1.0, 1.0, 0.0]);
		assert_eq!(out[6], 0.0, "drawn with the right key already, nothing to redraw");
		tiles[7] = -1.0;
		out.clear();
		tick(&cfg, &tiles, &[], &[], &mut out).unwrap();
		assert_eq!(out[6], 1.0, "never drawn, so it gets drawn");
		assert_eq!(out[8], cfg.visual_key(&[50.0, 0.0, 0.0]));
		assert_ne!(cfg.visual_key(&[50.0, 0.0, 0.0]), cfg.visual_key(&[50.0, 0.0, 0.6]));
	}

	#[test]
	fn order_of_pairs_doesnt_matter() {
		let tiles = vec![
			tile([90.0, 10.0, 0.0], 350.0, 2.0, KIND_TURF, AWAKE),
			tile([10.0, 50.0, 3.0], 293.15, 2.0, KIND_TURF, AWAKE),
			tile([0.0, 0.0, 0.0], 293.15, 2.0, KIND_TURF, AWAKE),
		];
		let one = run(&tiles, &[0, 1, 1, 2, 0, 2]);
		let two = run(&tiles, &[1, 2, 0, 2, 0, 1]);
		assert_eq!(one.changed.len(), two.changed.len());
		for (x, y) in one.changed.iter().zip(&two.changed) {
			assert_eq!(x.0, y.0);
			for (p, q) in x.1.iter().zip(&y.1) {
				assert!((p - q).abs() < 1e-9);
			}
			assert!((x.2 - y.2).abs() < 1e-9);
		}
	}
}
