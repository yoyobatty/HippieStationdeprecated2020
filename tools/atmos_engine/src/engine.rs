//! The tile maths. Nothing in here knows about BYOND: tiles come in as numbers and results go out as numbers, so it can
//! be tested on its own (cargo test).
//!
//! This is LINDA's process_cell(), share() and temperature_share() done natively (code/modules/atmospherics/environmental/
//! LINDA_turf_tile.dm and gasmixtures/gas_mixture.dm). It keeps LINDA's order and quirks on purpose, because how air
//! behaves in game comes from them:
//! - Turfs go through a stack, last in first out, and a turf woken this tick goes on top. So a big difference runs
//!   through a lot of turfs in one tick, which is how gas gets so far so fast.
//! - Each pair shares once a tick, led by whichever turf gets there first. A turf's "archive" is its air from just
//!   before someone last shared with it, and shares work from the archives.
//! - Gas arriving in the second turf of a pair brings no heat with it when it barely changes that turf's heat capacity.
//! - Space shares at full strength when it leads: it takes everything and leaves the turf at 2.7 K.
//!
//! DM's turf air stays the only copy. Each tick DM packs the awake turfs, the engine says which other turfs it needs,
//! and DM packs those too, so nothing cached here can go stale. Reactions run in DM after the sweep.

use std::collections::HashMap;

/// What a tile is, from DM's packing. Anything 3 and up is a planetary turf using planetary mix (kind - 3).
pub const KIND_TURF: u32 = 0;
pub const KIND_SPACE: u32 = 1;
pub const KIND_FIXED: u32 = 2;
pub const KIND_PLANETARY: u32 = 3;
/// A turf with no air: something that stopped being open since the list it came from was made
pub const KIND_NO_AIR: u32 = u32::MAX;

/// Marks a turf in Tick::slot that's been asked for and hasn't come yet
const WANTED: u32 = u32::MAX;
/// Tick::group_flags: LINDA's LAST_SHARE_CHECK, a big share resets its excited group's cooldowns...
const FLAG_BIG: u8 = 1;
/// ...and a smaller one keeps it from being dismantled
const FLAG_SMALL: u8 = 2;

pub struct Reaction {
	/// 0 if the reaction has no temperature requirement
	pub min_temperature: f64,
	/// 0 if the reaction has no thermal energy requirement
	pub min_energy: f64,
	/// (gas index, minimum moles)
	pub gases: Vec<(usize, f64)>,
	/// One bit per gas it needs, to rule most reactions out at once
	pub needs: u64,
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
	/// A share bigger than this resets its excited group's cooldowns (MINIMUM_AIR_TO_SUSPEND)
	pub min_air_to_suspend: f64,
	/// Ticks without a share before a turf in an excited group goes to sleep (EXCITED_GROUP_DISMANTLE_CYCLES)
	pub dismantle_ticks: f64,
}

/// How many constants come after the per-gas lists in the settings list, in Config's order from min_moles_delta on
const CONSTANTS: usize = 17;

impl Config {
	/// Settings list layout: gas count G; G specific heats; G visible-mole thresholds (-1 for no overlay); the visible
	/// step and state count; the CONSTANTS constants; then the reaction count and, per reaction, its minimum temperature,
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
			let mut needed = Vec::with_capacity(count);
			let mut needs = 0u64;
			for _ in 0..count {
				let index = next("reaction gas")? as usize;
				let amount = next("reaction moles")?;
				if index == 0 || index > gases {
					return Err(format!("reaction needs gas {index} of {gases}"));
				}
				needed.push((index - 1, amount));
				needs |= 1 << (index - 1);
			}
			reactions.push(Reaction {
				min_temperature,
				min_energy,
				gases: needed,
				needs,
			});
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
			dismantle_ticks: c[16],
		})
	}

	/// DM's QUANTIZE(): round(x, MOLAR_ACCURACY), which rounds halves up
	fn quantize(&self, value: f64) -> f64 {
		(value / self.molar_accuracy + 0.5).floor() * self.molar_accuracy
	}

	fn real_heat_capacity(&self, moles: &[f64]) -> f64 {
		moles.iter().zip(&self.specific_heat).map(|(m, c)| m * c).sum()
	}

	/// heat_capacity() for what's on this kind of tile: space is always a vacuum, and turf air counts as one when empty
	fn heat_capacity(&self, kind: u32, moles: &[f64]) -> f64 {
		match kind {
			KIND_SPACE => self.heat_capacity_vacuum,
			KIND_FIXED => self.real_heat_capacity(moles),
			_ => {
				let real = self.real_heat_capacity(moles);
				if real == 0.0 {
					self.heat_capacity_vacuum
				} else {
					real
				}
			}
		}
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

	/// Would react() find anything to do here
	fn can_react(&self, moles: &[f64], temperature: f64, heat_capacity: f64) -> bool {
		let mut present = 0u64;
		for (gas, amount) in moles.iter().enumerate() {
			if *amount > 0.0 {
				present |= 1 << gas;
			}
		}
		let energy = temperature * heat_capacity;
		self.reactions.iter().any(|reaction| {
			reaction.needs & present == reaction.needs
				&& (reaction.min_temperature == 0.0 || temperature >= reaction.min_temperature)
				&& (reaction.min_energy == 0.0 || energy >= reaction.min_energy)
				&& reaction.gases.iter().all(|&(gas, need)| moles[gas] >= need)
		})
	}
}

fn mutable(kind: u32) -> bool {
	kind != KIND_SPACE && kind != KIND_FIXED && kind != KIND_NO_AIR
}

/// One turf DM packed
pub struct NewTile<'a> {
	/// The turf's number, which only has to be the same for the same turf this tick
	pub id: u32,
	/// (gas index, moles) for the gases it has
	pub gases: &'a [(usize, f64)],
	pub temperature: f64,
	/// The turfs it's atmos-adjacent to, in the order of its atmos_adjacent_turfs
	pub adjacent: &'a [u32],
	pub kind: u32,
	/// Its excited group's number, 0 for none
	pub group: u32,
	/// significant_share_ticker
	pub ticker: f64,
	pub hotspot: bool,
	/// The overlay key DM last drew it with, -1 if none
	pub drawn: f64,
	/// In SSair.active_turfs. These come first, in the list's order.
	pub awake: bool,
}

/// A turf whose air changed: new temperature, and gas_changes[first..first + count] are its gases that changed
pub struct Change {
	pub tile: u32,
	pub first: u32,
	pub count: u32,
	pub temperature: f64,
}

/// One atmos tick of turfs. Kept between ticks so its lists don't get made again every time.
#[derive(Default)]
pub struct Tick {
	gases: usize,
	count: usize,
	id: Vec<u32>,
	moles: Vec<f64>,
	/// What DM has, to tell what changed
	start: Vec<f64>,
	archive: Vec<f64>,
	temperature: Vec<f64>,
	start_temperature: Vec<f64>,
	temperature_archived: Vec<f64>,
	/// Turf numbers until the tile's neighbours are all here (ready), tile indices after
	adjacent: Vec<u32>,
	adjacent_at: Vec<u32>,
	adjacent_count: Vec<u32>,
	kind: Vec<u32>,
	excited: Vec<bool>,
	group: Vec<u32>,
	ticker: Vec<f64>,
	hotspot: Vec<bool>,
	drawn: Vec<f64>,
	/// Has had its turn this tick (current_cycle)
	processed: Vec<bool>,
	/// Has been archived this tick (archived_cycle)
	archived: Vec<bool>,
	/// All its neighbours are here
	ready: Vec<bool>,
	/// A share has touched it
	touched: Vec<bool>,
	/// Strongest push this tick and which tile it's toward
	wind: Vec<(f64, u32)>,
	/// Turf number -> tile index + 1 this tick
	slot: Vec<u32>,
	/// Turf numbers asked for this tick, so a tick that stopped halfway leaves no marks in slot
	requested: Vec<u32>,
	/// DM's group number -> our number for it this tick
	group_numbers: HashMap<u32, u32>,
	/// Excited groups as a union-find. 0 is no group.
	group_parent: Vec<u32>,
	group_flags: Vec<u8>,
	/// A tile in each group, for telling DM which group
	group_tile: Vec<u32>,
	stack: Vec<u32>,
	/// Tiles that started awake
	awake: Vec<u32>,
	/// Tiles woken this tick, in order
	woken: Vec<u32>,
	/// Planetary mix -> its tile this tick
	planets: Vec<u32>,

	// What came of the tick, from finish(). Tile numbers can go to turf() for the turf's number.
	/// Tiles in the order they had their turn, with ticker() to read their new significant_share_ticker
	pub order: Vec<u32>,
	pub changes: Vec<Change>,
	pub gas_changes: Vec<(u8, f64)>,
	/// SSair.active_turfs after this tick, in order
	pub active: Vec<u32>,
	/// Tiles that were woken and are still awake
	pub stayed_awake: Vec<u32>,
	/// Tiles that were awake and now aren't
	pub slept: Vec<u32>,
	/// Tiles LINDA would put in one excited group, in order: a new group if neither is in one, a merge if they're in two
	pub group_joins: Vec<(u32, u32)>,
	/// A tile from each excited group that had a big share
	pub groups_big: Vec<u32>,
	/// A tile from each excited group that only had a smaller share
	pub groups_small: Vec<u32>,
	/// (tile, the tile it pushes toward, pressure difference)
	pub windy: Vec<(u32, u32, f64)>,
	/// Tiles that had their turn and where a reaction's requirements are met
	pub react: Vec<u32>,
	/// (tile, new overlay key)
	pub redraw: Vec<(u32, f64)>,
	/// Tiles that had their turn and are hot enough to start conducting heat through walls
	pub hot: Vec<u32>,
}

impl Tick {
	pub fn new() -> Tick {
		Tick::default()
	}

	/// Starts a new tick
	pub fn begin(&mut self, cfg: &Config) {
		for &id in &self.id {
			if id != u32::MAX {
				self.slot[id as usize] = 0;
			}
		}
		for &id in &self.requested {
			self.slot[id as usize] = 0;
		}
		self.requested.clear();
		self.gases = cfg.gases;
		self.count = 0;
		for list in [&mut self.id, &mut self.adjacent, &mut self.adjacent_at, &mut self.adjacent_count, &mut self.kind] {
			list.clear();
		}
		for list in [&mut self.moles, &mut self.start, &mut self.archive, &mut self.temperature, &mut self.start_temperature] {
			list.clear();
		}
		self.temperature_archived.clear();
		for list in [&mut self.excited, &mut self.hotspot, &mut self.processed, &mut self.archived] {
			list.clear();
		}
		self.ready.clear();
		self.touched.clear();
		self.group.clear();
		self.ticker.clear();
		self.drawn.clear();
		self.wind.clear();
		self.group_numbers.clear();
		self.group_parent.clear();
		self.group_parent.push(0);
		self.group_flags.clear();
		self.group_flags.push(0);
		self.group_tile.clear();
		self.group_tile.push(0);
		self.stack.clear();
		self.awake.clear();
		self.woken.clear();
		self.planets.clear();
		self.order.clear();
		self.changes.clear();
		self.gas_changes.clear();
		self.active.clear();
		self.stayed_awake.clear();
		self.slept.clear();
		self.group_joins.clear();
		self.groups_big.clear();
		self.groups_small.clear();
		self.windy.clear();
		self.react.clear();
		self.redraw.clear();
		self.hot.clear();
	}

	/// The turf number of a tile
	pub fn turf(&self, tile: u32) -> u32 {
		self.id[tile as usize]
	}

	/// What a turf's archive is after this tick, if it got archived: its temperature, and (gas index, moles) for its gases
	pub fn archive_of(&self, id: u32, gases: &mut Vec<(usize, f64)>) -> Option<f64> {
		let slot = self.slot.get(id as usize).copied().unwrap_or(0);
		if slot == 0 || slot == WANTED {
			return None;
		}
		let i = slot as usize - 1;
		if !self.archived[i] || !mutable(self.kind[i]) {
			return None;
		}
		let g = self.gases;
		gases.clear();
		for gas in 0..g {
			let amount = self.archive[i * g + gas];
			if amount != 0.0 {
				gases.push((gas, amount));
			}
		}
		Some(self.temperature_archived[i])
	}

	/// How many tiles have been packed this tick
	pub fn packed(&self) -> usize {
		self.count
	}

	pub fn ticker(&self, tile: u32) -> f64 {
		self.ticker[tile as usize]
	}

	/// Puts a tile in with the others. Every field gets a value here, so nothing else has to think about a half-made tile.
	fn push(&mut self, id: u32, gases: &[(usize, f64)], temperature: f64, kind: u32) -> usize {
		let g = self.gases;
		let i = self.count;
		self.count += 1;
		self.id.push(id);
		let at = self.moles.len();
		self.moles.resize(at + g, 0.0);
		for &(gas, amount) in gases {
			// Rounding in share() can leave a little under nothing in DM's lists
			self.moles[at + gas] = amount.max(0.0);
		}
		self.start.extend_from_slice(&self.moles[at..at + g]);
		self.archive.extend_from_slice(&self.moles[at..at + g]);
		self.temperature.push(temperature);
		self.start_temperature.push(temperature);
		self.temperature_archived.push(temperature);
		self.adjacent_at.push(self.adjacent.len() as u32);
		self.adjacent_count.push(0);
		self.kind.push(kind);
		self.excited.push(false);
		self.group.push(0);
		self.ticker.push(0.0);
		self.hotspot.push(false);
		self.drawn.push(-1.0);
		self.processed.push(false);
		self.archived.push(false);
		self.ready.push(false);
		self.touched.push(false);
		self.wind.push((0.0, u32::MAX));
		i
	}

	/// Adds a turf DM packed. Awake ones have to come first, in active_turfs' order.
	pub fn add(&mut self, tile: NewTile) {
		let id = tile.id as usize;
		if id >= self.slot.len() {
			self.slot.resize(id + 1, 0);
		}
		if self.slot[id] != 0 && self.slot[id] != WANTED {
			return; // on the list twice
		}
		let i = self.push(tile.id, tile.gases, tile.temperature, tile.kind);
		self.slot[id] = i as u32 + 1;
		self.adjacent.extend_from_slice(tile.adjacent);
		self.adjacent_count[i] = tile.adjacent.len() as u32;
		self.ticker[i] = tile.ticker;
		self.hotspot[i] = tile.hotspot;
		self.drawn[i] = tile.drawn;
		if tile.group != 0 {
			let next = self.group_parent.len() as u32;
			let number = *self.group_numbers.entry(tile.group).or_insert(next);
			if number == next {
				self.group_parent.push(next);
				self.group_flags.push(0);
				self.group_tile.push(i as u32);
			}
			self.group[i] = number;
		}
		if tile.awake && tile.kind != KIND_NO_AIR {
			self.excited[i] = true;
			self.stack.push(i as u32);
			self.awake.push(i as u32);
		}
	}

	/// Runs turfs until there are none left or one needs a turf that hasn't been packed. Returns true when it's done;
	/// otherwise `wanted` says which turfs to add before calling this again. LINDA's process_active_turfs(): the last
	/// turf on the list goes first, and turfs woken on the way go on the end.
	pub fn run(&mut self, cfg: &Config, planetary: &[f64], wanted: &mut Vec<u32>) -> bool {
		while let Some(&top) = self.stack.last() {
			let i = top as usize;
			if !self.ready[i] && !self.make_ready(i) {
				self.want_missing(wanted);
				return false;
			}
			self.stack.pop();
			self.process_cell(cfg, planetary, i);
		}
		true
	}

	/// Turns a tile's neighbours from turf numbers into tiles, if they're all here
	fn make_ready(&mut self, i: usize) -> bool {
		let from = self.adjacent_at[i] as usize;
		let to = from + self.adjacent_count[i] as usize;
		for k in from..to {
			let slot = self.slot.get(self.adjacent[k] as usize).copied().unwrap_or(0);
			if slot == 0 || slot == WANTED {
				return false;
			}
		}
		for k in from..to {
			self.adjacent[k] = self.slot[self.adjacent[k] as usize] - 1;
		}
		self.ready[i] = true;
		true
	}

	/// Everything on the stack is likely to have its turn this tick, so this asks for all their neighbours at once
	fn want_missing(&mut self, wanted: &mut Vec<u32>) {
		for s in 0..self.stack.len() {
			let i = self.stack[s] as usize;
			if self.ready[i] {
				continue;
			}
			let from = self.adjacent_at[i] as usize;
			for k in from..from + self.adjacent_count[i] as usize {
				let id = self.adjacent[k] as usize;
				if id >= self.slot.len() {
					self.slot.resize(id + 1, 0);
				}
				if self.slot[id] == 0 {
					self.slot[id] = WANTED;
					wanted.push(id as u32);
					self.requested.push(id as u32);
				}
			}
		}
	}

	fn find(&mut self, mut group: u32) -> u32 {
		while self.group_parent[group as usize] != group {
			let parent = self.group_parent[group as usize];
			self.group_parent[group as usize] = self.group_parent[parent as usize];
			group = self.group_parent[group as usize];
		}
		group
	}

	fn new_group(&mut self, tile: usize) -> u32 {
		let number = self.group_parent.len() as u32;
		self.group_parent.push(number);
		self.group_flags.push(0);
		self.group_tile.push(tile as u32);
		number
	}

	/// /turf/open/archive(). Immutable air's archive never changes.
	fn archive(&mut self, i: usize) {
		self.archived[i] = true;
		if mutable(self.kind[i]) {
			let g = self.gases;
			self.archive[i * g..(i + 1) * g].copy_from_slice(&self.moles[i * g..(i + 1) * g]);
			self.temperature_archived[i] = self.temperature[i];
		}
	}

	/// Puts immutable air back, as its garbage_collect() does after anything touches it
	fn restore(&mut self, i: usize) {
		let g = self.gases;
		self.moles[i * g..(i + 1) * g].copy_from_slice(&self.start[i * g..(i + 1) * g]);
		self.temperature[i] = self.start_temperature[i];
	}

	/// LINDA's compare(): is the difference between our air and theirs worth sharing over
	fn compare(&self, cfg: &Config, i: usize, j: usize) -> bool {
		let g = self.gases;
		let ours = &self.moles[i * g..(i + 1) * g];
		let theirs = &self.moles[j * g..(j + 1) * g];
		let mut our_total = 0.0;
		for gas in 0..g {
			let (mine, other) = (ours[gas], theirs[gas]);
			let delta = (mine - other).abs();
			if delta > cfg.min_moles_delta && delta > mine * cfg.min_air_ratio {
				return true;
			}
			our_total += mine;
		}
		our_total > cfg.min_moles_delta && (self.temperature[i] - self.temperature[j]).abs() > cfg.min_temp_delta_suspend
	}

	/// temperature_share(sharer): conduction, worked out from the archives. It sets the sharer's temperature from its
	/// archive, which is what throws away any heat gas just brought it in share().
	fn temperature_share(&mut self, cfg: &Config, i: usize, j: usize, coefficient: f64, their_capacity: Option<f64>) {
		let g = self.gases;
		let their_temperature = self.temperature_archived[j];
		let delta = self.temperature_archived[i] - their_temperature;
		if delta.abs() <= cfg.min_temp_delta_consider {
			return;
		}
		let ours = cfg.heat_capacity(self.kind[i], &self.archive[i * g..(i + 1) * g]);
		let theirs = their_capacity.unwrap_or_else(|| cfg.heat_capacity(self.kind[j], &self.archive[j * g..(j + 1) * g]));
		if theirs > cfg.min_heat_capacity && ours > cfg.min_heat_capacity {
			let heat = coefficient * delta * (ours * theirs / (ours + theirs));
			self.temperature[i] = (self.temperature[i] - heat / ours).max(cfg.tcmb);
			self.temperature[j] = (their_temperature + heat / theirs).max(cfg.tcmb);
		}
	}

	/// share(): returns the pressure difference for wind (0 for none, positive if i pushes toward j) and last_share
	fn share(&mut self, cfg: &Config, i: usize, j: usize, mut our_coeff: f64, mut their_coeff: f64) -> (f64, f64) {
		let g = self.gases;
		let our_kind = self.kind[i];
		let their_kind = self.kind[j];
		if !mutable(our_kind) {
			// immutable/share() calls ..(sharer), so it goes at full strength
			our_coeff = 1.0;
			their_coeff = 1.0;
		}
		let our_archived = self.temperature_archived[i];
		let their_archived = self.temperature_archived[j];
		let temperature_delta = our_archived - their_archived;
		let consider_heat = temperature_delta.abs() > cfg.min_temp_delta_consider;
		let mut old_self_capacity = 0.0;
		let mut old_sharer_capacity = 0.0;
		if consider_heat {
			old_self_capacity = cfg.heat_capacity(our_kind, &self.moles[i * g..(i + 1) * g]);
			old_sharer_capacity = cfg.heat_capacity(their_kind, &self.moles[j * g..(j + 1) * g]);
		}

		let mut self_to_sharer = 0.0; // heat capacity of the gas going from us to them
		let mut sharer_to_self = 0.0; // and from them to us
		let mut moved = 0.0;
		let mut abs_moved = 0.0;
		for gas in 0..g {
			let difference = self.archive[i * g + gas] - self.archive[j * g + gas];
			if difference == 0.0 {
				continue;
			}
			let mut delta = cfg.quantize(difference);
			if delta == 0.0 {
				continue;
			}
			delta *= if delta > 0.0 { our_coeff } else { their_coeff };
			if consider_heat {
				let gas_heat_capacity = delta * cfg.specific_heat[gas];
				if delta > 0.0 {
					self_to_sharer += gas_heat_capacity;
				} else {
					sharer_to_self -= gas_heat_capacity;
				}
			}
			self.moles[i * g + gas] -= delta;
			self.moles[j * g + gas] += delta;
			moved += delta;
			abs_moved += delta.abs();
		}
		self.touched[i] = true;
		self.touched[j] = true;

		if consider_heat {
			let new_self_capacity = old_self_capacity + sharer_to_self - self_to_sharer;
			let new_sharer_capacity = old_sharer_capacity + self_to_sharer - sharer_to_self;
			if new_self_capacity > cfg.min_heat_capacity {
				self.temperature[i] = (old_self_capacity * self.temperature[i] - self_to_sharer * our_archived
					+ sharer_to_self * their_archived)
					/ new_self_capacity;
			}
			if new_sharer_capacity > cfg.min_heat_capacity {
				self.temperature[j] = (old_sharer_capacity * self.temperature[j] - sharer_to_self * their_archived
					+ self_to_sharer * our_archived)
					/ new_sharer_capacity;
				if old_sharer_capacity.abs() > cfg.min_heat_capacity
					&& (new_sharer_capacity / old_sharer_capacity - 1.0).abs() < 0.1
				{
					self.temperature_share(cfg, i, j, cfg.open_heat_transfer, None);
				}
			}
		}

		if !mutable(their_kind) {
			self.restore(j);
		}
		let mut pressure_difference = 0.0;
		if temperature_delta > cfg.min_temp_to_move || moved.abs() > cfg.min_moles_delta {
			let our_moles: f64 = self.moles[i * g..(i + 1) * g].iter().sum();
			let their_moles: f64 = self.moles[j * g..(j + 1) * g].iter().sum();
			pressure_difference = (our_archived * (our_moles + moved) - their_archived * (their_moles - moved)) * cfg.r / cfg.cell_volume;
		}
		if !mutable(our_kind) {
			self.temperature[j] = self.start_temperature[i]; // sharer.temperature = initial_temperature
			self.restore(i);
		}
		(pressure_difference, abs_moved)
	}

	/// consider_pressure_difference()
	fn push_wind(&mut self, from: usize, to: usize, difference: f64) {
		if difference > self.wind[from].0 {
			self.wind[from] = (difference, to as u32);
		}
	}

	/// A planetary mix's tile, added the first time a turf wants it this tick. It's just immutable air nobody's next to.
	fn planet(&mut self, cfg: &Config, planetary: &[f64], mix: usize) -> usize {
		if mix >= self.planets.len() {
			self.planets.resize(mix + 1, u32::MAX);
		}
		if self.planets[mix] != u32::MAX {
			return self.planets[mix] as usize;
		}
		let g = cfg.gases;
		let row = &planetary[mix * (g + 1)..(mix + 1) * (g + 1)];
		let gases: Vec<(usize, f64)> = (0..g).map(|gas| (gas, row[gas])).collect();
		let tile = self.push(u32::MAX, &gases, row[g], KIND_FIXED);
		self.processed[tile] = true;
		self.ready[tile] = true;
		self.planets[mix] = tile as u32;
		tile
	}

	/// LINDA's LAST_SHARE_CHECK and PLANET_SHARE_CHECK. Says whether the share counts as significant.
	fn share_check(&mut self, cfg: &Config, group: u32, last_share: f64) -> bool {
		if last_share > cfg.min_air_to_suspend {
			self.group_flags[group as usize] |= FLAG_BIG;
			true
		} else if last_share > cfg.min_moles_delta {
			self.group_flags[group as usize] |= FLAG_SMALL;
			true
		} else {
			false
		}
	}

	/// process_cell(), apart from react(), which DM does after the sweep
	fn process_cell(&mut self, cfg: &Config, planetary: &[f64], i: usize) {
		if !self.archived[i] {
			self.archive(i);
		}
		self.processed[i] = true;
		self.order.push(i as u32);
		let mut ticker = self.ticker[i] + 1.0;
		let mut ours = self.find(self.group[i]);
		let our_coeff = 1.0 / (self.adjacent_count[i] as f64 + 1.0);
		let from = self.adjacent_at[i] as usize;
		for k in from..from + self.adjacent_count[i] as usize {
			let j = self.adjacent[k] as usize;
			if self.processed[j] || self.kind[j] == KIND_NO_AIR {
				continue;
			}
			self.archive(j);

			let theirs = self.find(self.group[j]);
			if ours != 0 && theirs != 0 && ours != theirs {
				self.group_parent[theirs as usize] = ours;
				self.group_flags[ours as usize] |= self.group_flags[theirs as usize];
				self.group_joins.push((i as u32, j as u32));
			}
			let mut should_share = false;
			if ours != 0 && theirs != 0 && self.excited[j] {
				should_share = true;
			} else if self.compare(cfg, i, j) {
				self.ticker[j] = 0.0;
				if !self.excited[j] {
					self.excited[j] = true;
					self.stack.push(j as u32);
					self.woken.push(j as u32);
				}
				if ours == 0 || theirs == 0 {
					let joined = if ours != 0 {
						ours
					} else if theirs != 0 {
						theirs
					} else {
						self.new_group(i)
					};
					self.group[i] = if ours == 0 { joined } else { self.group[i] };
					self.group[j] = if theirs == 0 { joined } else { self.group[j] };
					self.group_joins.push((i as u32, j as u32));
					ours = self.find(joined);
				}
				should_share = true;
			}
			if should_share {
				let their_coeff = 1.0 / (self.adjacent_count[j] as f64 + 1.0);
				let (difference, last_share) = self.share(cfg, i, j, our_coeff, their_coeff);
				if difference > 0.0 {
					self.push_wind(i, j, difference);
				} else if difference < 0.0 {
					self.push_wind(j, i, -difference);
				}
				if self.share_check(cfg, ours, last_share) {
					ticker = 0.0;
					self.ticker[j] = 0.0;
				}
			}
		}

		if self.kind[i] >= KIND_PLANETARY && self.kind[i] != KIND_NO_AIR {
			// Share with the air "above" the turf
			let p = self.planet(cfg, planetary, (self.kind[i] - KIND_PLANETARY) as usize);
			self.archive(i);
			if self.compare(cfg, i, p) {
				if ours == 0 {
					ours = self.new_group(i);
					self.group[i] = ours;
					self.group_joins.push((i as u32, i as u32));
				}
				let (_, last_share) = self.share(cfg, i, p, 0.8, 0.8);
				// With an inflated heat capacity, to share faster with a big atmosphere
				let g = self.gases;
				let planet_capacity = cfg.real_heat_capacity(&self.moles[p * g..(p + 1) * g]) * 5.0;
				self.temperature_share(cfg, i, p, cfg.open_heat_transfer, Some(planet_capacity));
				self.restore(p);
				if self.share_check(cfg, ours, last_share) {
					ticker = 0.0;
				}
			}
		}

		if !self.is_hot(cfg, i) && !self.hotspot[i] {
			if ours == 0 || ticker > cfg.dismantle_ticks {
				self.excited[i] = false; // remove_from_active() or sleep_active_turf(): it stays in its group
			}
		}
		self.ticker[i] = ticker;
	}

	/// consider_superconductivity(starting = TRUE)
	fn is_hot(&self, cfg: &Config, i: usize) -> bool {
		let g = self.gases;
		self.temperature[i] >= cfg.superconduct_temp
			&& mutable(self.kind[i])
			&& cfg.heat_capacity(self.kind[i], &self.moles[i * g..(i + 1) * g]) >= cfg.superconduct_heat_capacity
	}

	/// Works out what DM has to do with all that
	pub fn finish(&mut self, cfg: &Config) {
		let g = self.gases;
		for i in 0..self.count {
			if !self.touched[i] || !mutable(self.kind[i]) {
				continue;
			}
			let first = self.gas_changes.len();
			for gas in 0..g {
				let index = i * g + gas;
				let before = self.start[index];
				let mut amount = self.moles[index].max(0.0);
				// Tiny leftovers go, the way garbage_collect() drops them
				if amount != before && cfg.quantize(amount) < cfg.min_mole_count && cfg.quantize(before) < cfg.min_mole_count {
					amount = 0.0;
				}
				self.moles[index] = amount;
				// DM keeps 32-bit floats, so nothing smaller than that is a change
				if amount as f32 != before as f32 {
					self.gas_changes.push((gas as u8, amount));
				}
			}
			let temperature = self.temperature[i];
			if self.gas_changes.len() > first || temperature as f32 != self.start_temperature[i] as f32 {
				self.changes.push(Change {
					tile: i as u32,
					first: first as u32,
					count: (self.gas_changes.len() - first) as u32,
					temperature,
				});
			}
		}

		for k in 0..self.order.len() {
			let i = self.order[k] as usize;
			if !mutable(self.kind[i]) {
				continue;
			}
			let now = &self.moles[i * g..(i + 1) * g];
			let key = cfg.visual_key(now);
			if key != self.drawn[i] {
				self.redraw.push((i as u32, key));
			}
			let capacity = cfg.heat_capacity(self.kind[i], now);
			if cfg.can_react(now, self.temperature[i], capacity) {
				self.react.push(i as u32);
			}
			if self.is_hot(cfg, i) {
				self.hot.push(i as u32);
			}
		}

		for k in 0..self.awake.len() {
			let i = self.awake[k];
			if self.excited[i as usize] {
				self.active.push(i);
			} else {
				self.slept.push(i);
			}
		}
		for k in 0..self.woken.len() {
			let i = self.woken[k];
			if self.excited[i as usize] {
				self.active.push(i);
				self.stayed_awake.push(i);
			}
		}

		for group in 1..self.group_parent.len() {
			if self.group_parent[group] != group as u32 {
				continue;
			}
			let flags = self.group_flags[group];
			if flags & FLAG_BIG != 0 {
				self.groups_big.push(self.group_tile[group]);
			} else if flags & FLAG_SMALL != 0 {
				self.groups_small.push(self.group_tile[group]);
			}
		}

		for i in 0..self.count {
			let (difference, toward) = self.wind[i];
			if toward != u32::MAX {
				self.windy.push((i as u32, toward, difference));
			}
		}
	}
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
			11.0,                       // dismantle_ticks
		]);
		// One reaction: gas 3 above 1 mole, over 400 K
		settings.extend_from_slice(&[1.0, 400.0, 0.0, 1.0, 3.0, 1.0]);
		Config::parse(&settings).unwrap()
	}

	#[derive(Clone)]
	struct Row {
		id: u32,
		moles: [f64; 3],
		temperature: f64,
		adjacent: Vec<u32>,
		kind: u32,
		group: u32,
		ticker: f64,
		hotspot: bool,
		awake: bool,
	}

	fn floor(id: u32, moles: f64, temperature: f64, adjacent: &[u32], awake: bool) -> Row {
		Row {
			id,
			moles: [moles, 0.0, 0.0],
			temperature,
			adjacent: adjacent.to_vec(),
			kind: KIND_TURF,
			group: 0,
			ticker: 0.0,
			hotspot: false,
			awake,
		}
	}

	fn space(id: u32, adjacent: &[u32], awake: bool) -> Row {
		Row {
			kind: KIND_SPACE,
			..floor(id, 0.0, 2.7, adjacent, awake)
		}
	}

	fn add(tick: &mut Tick, cfg: &Config, row: &Row) {
		let gases: Vec<(usize, f64)> = (0..3).filter(|&gas| row.moles[gas] != 0.0).map(|gas| (gas, row.moles[gas])).collect();
		tick.add(NewTile {
			id: row.id,
			gases: &gases,
			temperature: row.temperature,
			adjacent: &row.adjacent,
			kind: row.kind,
			group: row.group,
			ticker: row.ticker,
			hotspot: row.hotspot,
			drawn: cfg.visual_key(&row.moles),
			awake: row.awake,
		});
	}

	/// Runs one tick the way DM does: awake rows first, then whichever others the engine asks for
	fn run(rows: &[Row], planetary: &[f64]) -> (Tick, Config, usize) {
		let cfg = config();
		let mut tick = Tick::new();
		tick.begin(&cfg);
		for row in rows.iter().filter(|row| row.awake) {
			add(&mut tick, &cfg, row);
		}
		let mut rounds = 0;
		loop {
			rounds += 1;
			let mut wanted = Vec::new();
			if tick.run(&cfg, planetary, &mut wanted) {
				break;
			}
			assert!(!wanted.is_empty(), "stopped without asking for anything");
			for id in wanted {
				let row = rows.iter().find(|row| row.id == id).expect("asked for a turf that isn't there");
				add(&mut tick, &cfg, row);
			}
		}
		tick.finish(&cfg);
		(tick, cfg, rounds)
	}

	/// A turf's gases and temperature after a tick, whether it changed or not
	fn air(tick: &Tick, id: u32) -> ([f64; 3], f64) {
		let i = tick.slot[id as usize] - 1;
		let g = tick.gases;
		let i = i as usize;
		let mut moles = [0.0; 3];
		moles.copy_from_slice(&tick.moles[i * g..(i + 1) * g]);
		(moles, tick.temperature[i])
	}

	fn turfs(tick: &Tick, tiles: &[u32]) -> Vec<u32> {
		tiles.iter().map(|&tile| tick.turf(tile)).collect()
	}

	#[test]
	fn gas_is_conserved_between_two_tiles() {
		let (tick, _, _) = run(
			&[floor(1, 100.0, 293.15, &[2], true), floor(2, 0.0, 293.15, &[1], true)],
			&[],
		);
		// Turf 2 goes first (last on the list) and takes half of the difference, as each has one neighbour
		assert!((air(&tick, 1).0[0] - 50.0).abs() < 1e-9);
		assert!((air(&tick, 2).0[0] - 50.0).abs() < 1e-9);
		assert_eq!(turfs(&tick, &tick.order), vec![2, 1]);
		assert_eq!(tick.windy.len(), 1);
		assert_eq!((tick.turf(tick.windy[0].0), tick.turf(tick.windy[0].1)), (1, 2));
	}

	#[test]
	fn each_pair_shares_once_a_tick() {
		let (tick, _, _) = run(
			&[floor(1, 100.0, 293.15, &[2], true), floor(2, 0.0, 293.15, &[1], true)],
			&[],
		);
		assert_eq!(tick.changes.len(), 2);
		assert_eq!(tick.gas_changes.len(), 2, "no second share on turf 1's turn");
	}

	#[test]
	fn a_woken_turf_goes_right_after_the_one_that_woke_it() {
		// A corridor with only turf 1 awake. Turf 2 wakes and has its turn at once, and wakes turf 3 by comparing air. It
		// has nothing to give turf 3 yet though: its archive is from before it got any gas.
		let mut rows = vec![floor(1, 5000.0, 293.15, &[2], true)];
		for id in 2..6 {
			rows.push(floor(id, 0.0, 293.15, &[id - 1, id + 1], false));
		}
		rows.push(floor(6, 0.0, 293.15, &[5], false));
		let (tick, _, rounds) = run(&rows, &[]);
		assert_eq!(turfs(&tick, &tick.order), vec![1, 2, 3]);
		assert_eq!(air(&tick, 1).0[0], 2500.0);
		assert_eq!(air(&tick, 2).0[0], 2500.0);
		assert_eq!(air(&tick, 3).0[0], 0.0);
		assert_eq!(rounds, 4, "turf 1's neighbour, turf 2's, then turf 3's had to be asked for");
	}

	#[test]
	fn gas_gets_further_through_turfs_already_awake() {
		// Turfs 1 and 3 both go before turf 2 between them. Turf 3 archives turf 2 again before sharing with it, and that
		// archive has what turf 1 just gave it, so gas from turf 1 reaches turf 3 in one tick.
		let mut one = floor(1, 300.0, 293.15, &[2], true);
		let mut two = floor(2, 0.0, 293.15, &[1, 3], true);
		let mut three = floor(3, 0.0, 293.15, &[2], true);
		one.group = 1;
		two.group = 1;
		three.group = 1;
		// Popped from the end
		let (tick, _, _) = run(&[two, three, one], &[]);
		assert_eq!(turfs(&tick, &tick.order), vec![1, 3, 2]);
		assert!(air(&tick, 3).0[0] > 0.0, "gas went two turfs along");
		let total: f64 = (1..=3).map(|id| air(&tick, id).0[0]).sum();
		assert!((total - 300.0).abs() < 1e-6, "total {total}");
	}

	#[test]
	fn a_turf_leading_a_share_with_space_keeps_some() {
		let (tick, _, _) = run(
			&[
				floor(1, 100.0, 293.15, &[2, 3, 4, 5], true),
				space(2, &[1], false),
				floor(3, 100.0, 293.15, &[1], false),
				floor(4, 100.0, 293.15, &[1], false),
				floor(5, 100.0, 293.15, &[1], false),
			],
			&[],
		);
		let (moles, temperature) = air(&tick, 1);
		assert!((moles[0] - 80.0).abs() < 1e-6, "{moles:?}");
		// The gas leaving carries its own heat, then conduction with the vacuum takes
		// 0.4 * 290.45 * (2000 * 7000 / 9000) J over the starting 2000 J/K: down to about 202.8 K
		assert!((temperature - 202.78).abs() < 0.05, "got {temperature}");
		assert_eq!(air(&tick, 2).0, [0.0, 0.0, 0.0], "space stays empty");
	}

	#[test]
	fn space_leading_a_share_takes_everything() {
		let (tick, _, _) = run(&[floor(1, 100.0, 293.15, &[2], false), space(2, &[1], true)], &[]);
		let (moles, temperature) = air(&tick, 1);
		assert!(moles[0].abs() < 1e-3, "{moles:?}");
		assert_eq!(temperature, 2.7);
		assert_eq!(air(&tick, 2).0, [0.0, 0.0, 0.0], "space stays empty");
		assert_eq!(turfs(&tick, &tick.woken), vec![1], "and it wakes the turf");
	}

	#[test]
	fn gas_arriving_in_the_second_turf_brings_no_heat() {
		// Hot turf 2 goes first and gives a little gas to cold turf 1. That barely changes turf 1's heat capacity, so its
		// temperature comes from its archive plus conduction, and the heat in the arriving gas is gone.
		let (tick, _, _) = run(
			&[floor(1, 100.0, 300.0, &[2], true), floor(2, 100.1, 900.0, &[1], true)],
			&[],
		);
		let (hot_capacity, cold_capacity) = (100.1 * 20.0, 100.0 * 20.0);
		let heat = 0.4 * 600.0 * (hot_capacity * cold_capacity / (hot_capacity + cold_capacity));
		assert!((air(&tick, 1).1 - (300.0 + heat / cold_capacity)).abs() < 1e-6);
		assert!((air(&tick, 2).1 - (900.0 - heat / hot_capacity)).abs() < 1e-6);
	}

	#[test]
	fn small_differences_dont_wake_sleepers() {
		let (tick, _, _) = run(
			&[floor(1, 100.0, 293.15, &[2], true), floor(2, 100.05, 293.15, &[1], false)],
			&[],
		);
		assert!(tick.changes.is_empty());
		assert!(tick.woken.is_empty());
		assert_eq!(turfs(&tick, &tick.slept), vec![1], "nothing to do and no group: it goes straight back to sleep");
		assert!(tick.active.is_empty());
	}

	#[test]
	fn big_differences_wake_sleepers_and_join_them_up() {
		let (tick, _, _) = run(
			&[floor(1, 100.0, 293.15, &[2], true), floor(2, 50.0, 293.15, &[1], false)],
			&[],
		);
		assert_eq!(turfs(&tick, &tick.stayed_awake), vec![2]);
		assert_eq!(turfs(&tick, &tick.active), vec![1, 2]);
		assert_eq!(tick.group_joins.len(), 1);
		let (a, b) = tick.group_joins[0];
		assert_eq!((tick.turf(a), tick.turf(b)), (1, 2));
		assert_eq!(turfs(&tick, &tick.groups_big), vec![1], "a 25 mole share resets the group's cooldowns");
	}

	#[test]
	fn turfs_in_two_groups_merge_however_alike() {
		let mut one = floor(1, 100.0, 293.15, &[2], true);
		let mut two = floor(2, 100.0, 293.15, &[1], true);
		one.group = 7;
		two.group = 9;
		let (tick, _, _) = run(&[one, two], &[]);
		assert_eq!(tick.group_joins.len(), 1);
		assert!(tick.changes.is_empty());
		assert!(tick.groups_big.is_empty() && tick.groups_small.is_empty());
	}

	#[test]
	fn turfs_sleep_after_enough_quiet_ticks_but_stay_in_their_group() {
		let mut quiet = floor(1, 100.0, 293.15, &[], true);
		quiet.group = 3;
		quiet.ticker = 11.0;
		let (tick, _, _) = run(&[quiet.clone()], &[]);
		assert_eq!(turfs(&tick, &tick.slept), vec![1]);
		quiet.ticker = 5.0;
		let (tick, _, _) = run(&[quiet.clone()], &[]);
		assert!(tick.slept.is_empty());
		assert_eq!(tick.ticker(tick.order[0]), 6.0);
		quiet.ticker = 11.0;
		quiet.hotspot = true;
		let (tick, _, _) = run(&[quiet], &[]);
		assert!(tick.slept.is_empty(), "a burning turf stays awake");
	}

	#[test]
	fn a_share_resets_both_turfs_tickers() {
		let mut one = floor(1, 100.0, 293.15, &[2], true);
		let mut two = floor(2, 50.0, 293.15, &[1], true);
		one.group = 1;
		two.group = 1;
		one.ticker = 8.0;
		two.ticker = 8.0;
		let (tick, _, _) = run(&[one, two], &[]);
		// Turf 2 led and resets both. Then turf 1 has its turn, with the pair already done.
		assert_eq!(turfs(&tick, &tick.order), vec![2, 1]);
		assert_eq!(tick.ticker(tick.order[0]), 0.0);
		assert_eq!(tick.ticker(tick.order[1]), 1.0);
	}

	#[test]
	fn reactions_need_their_requirements() {
		let burner = |moles: f64, temperature: f64| Row {
			moles: [0.0, 0.0, moles],
			..floor(1, 0.0, temperature, &[], true)
		};
		assert!(run(&[burner(5.0, 300.0)], &[]).0.react.is_empty());
		assert_eq!(run(&[burner(5.0, 500.0)], &[]).0.react.len(), 1);
		assert!(run(&[burner(0.5, 500.0)], &[]).0.react.is_empty());
	}

	#[test]
	fn planetary_turfs_relax_toward_the_planet() {
		let row = Row {
			kind: KIND_PLANETARY,
			..floor(1, 0.0, 300.0, &[], true)
		};
		let planet = [20.0, 80.0, 0.0, 300.0];
		let (tick, _, _) = run(&[row], &planet);
		let (moles, _) = air(&tick, 1);
		assert!((moles[0] - 16.0).abs() < 1e-6 && (moles[1] - 64.0).abs() < 1e-6, "0.8 of the way there: {moles:?}");
		assert_eq!(tick.group_joins, vec![(0, 0)], "joins a group of its own");
		assert_eq!(tick.changes.len(), 1, "the planet's own air isn't a change");
	}

	#[test]
	fn overlays_redraw_only_when_they_would_look_different() {
		let cfg = config();
		let mut tick = Tick::new();
		tick.begin(&cfg);
		let moles = [50.0, 0.0, 0.0];
		tick.add(NewTile {
			id: 1,
			gases: &[(0, 50.0)],
			temperature: 293.15,
			adjacent: &[],
			kind: KIND_TURF,
			group: 0,
			ticker: 0.0,
			hotspot: false,
			drawn: cfg.visual_key(&moles),
			awake: true,
		});
		tick.add(NewTile {
			id: 2,
			gases: &[(0, 50.0)],
			temperature: 293.15,
			adjacent: &[],
			kind: KIND_TURF,
			group: 0,
			ticker: 0.0,
			hotspot: false,
			drawn: -1.0,
			awake: true,
		});
		assert!(tick.run(&cfg, &[], &mut Vec::new()));
		tick.finish(&cfg);
		assert_eq!(turfs(&tick, &tick.redraw.iter().map(|r| r.0).collect::<Vec<_>>()), vec![2], "never drawn, so it gets drawn");
		assert_eq!(tick.redraw[0].1, cfg.visual_key(&moles));
		assert_ne!(cfg.visual_key(&moles), cfg.visual_key(&[50.0, 0.0, 0.6]));
	}

	#[test]
	fn archives_are_from_just_before_a_turfs_last_share() {
		let (tick, _, _) = run(
			&[floor(1, 100.0, 293.15, &[2], true), floor(2, 0.0, 293.15, &[1], true)],
			&[],
		);
		let mut gases = Vec::new();
		// Turf 2 led, so it archived turf 1 with all its gas, and after the share turf 1 has half of that
		assert_eq!(tick.archive_of(1, &mut gases), Some(293.15));
		assert_eq!(gases, vec![(0, 100.0)]);
		assert_eq!(air(&tick, 1).0[0], 50.0);
		assert_eq!(tick.archive_of(9, &mut gases), None, "a turf nobody archived this tick");
	}

	#[test]
	fn turfs_left_behind_on_the_list_come_back_a_new_tick() {
		let cfg = config();
		let mut tick = Tick::new();
		tick.begin(&cfg);
		add(&mut tick, &cfg, &floor(1, 100.0, 293.15, &[2], true));
		let mut wanted = Vec::new();
		assert!(!tick.run(&cfg, &[], &mut wanted));
		assert_eq!(wanted, vec![2]);
		// A new tick after that one stopped halfway has nothing left over from it
		tick.begin(&cfg);
		add(&mut tick, &cfg, &floor(2, 100.0, 293.15, &[], true));
		assert!(tick.run(&cfg, &[], &mut Vec::new()));
		tick.finish(&cfg);
		assert_eq!(turfs(&tick, &tick.order), vec![2]);
	}
}
