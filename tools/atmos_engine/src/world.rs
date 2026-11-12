//! What the engine keeps between ticks. Nothing in here knows about BYOND either.
//!
//! `Known` is what it has of each turf from DM: its kind and neighbours, and its air as DM holds it after the last tick.
//!
//! `World` is LINDA's own state, for when the engine runs it instead of DM (atmos-engine-own): which turfs are awake and
//! in what order (SSair.active_turfs), each turf's significant_share_ticker, excited group, whether it's burning and the
//! overlay key DM last drew it with, and the excited groups themselves (SSair.excited_groups), with their cooldowns.
//! DM tells it what changed between ticks as events, in the order they happened (add_to_active() and the rest), and
//! each tick's results and the excited groups' step change it the way LINDA's DM code would. Every rule here is a copy
//! of a DM proc, named where it is.

use crate::engine::{mutable, Config, Tick, KIND_FIXED, KIND_NO_AIR, KIND_PLANETARY, KIND_SPACE};

/// add_to_active(T)
pub const EVENT_WAKE: u32 = 1;
/// add_to_active(T, blockchanges = TRUE): its excited group is let go of first
pub const EVENT_WAKE_BLOCK: u32 = 2;
/// remove_from_active(T): asleep, and its excited group let go of
pub const EVENT_REMOVE: u32 = 3;
/// sleep_active_turf(T): asleep, still in its group
pub const EVENT_SLEEP: u32 = 4;
/// T.active_hotspot set
pub const EVENT_HOTSPOT_ON: u32 = 5;
/// T.active_hotspot cleared
pub const EVENT_HOTSPOT_OFF: u32 = 6;
/// A hotspot keeping its turf's excited group going: reset_cooldowns()
pub const EVENT_RESET_GROUP: u32 = 7;
/// A reaction redrew the turf, so what it was drawn with isn't known (tile_engine_drawn = -1)
pub const EVENT_UNDRAWN: u32 = 8;
/// A new turf in its place (ChangeTurf): nothing drawn, not burning, and its kind, neighbours and air sent again
pub const EVENT_NEW_TURF: u32 = 9;

/// What the engine has of turfs between ticks, by turf number
#[derive(Default)]
pub struct Known {
	/// u32::MAX for not known
	kind: Vec<u32>,
	adjacent: Vec<Vec<u32>>,
	/// Its air as DM holds it after the last tick it was in (temperature, then (gas index, moles)). NaN temperature for
	/// none kept.
	air_temperature: Vec<f32>,
	air_gases: Vec<Vec<(u8, f32)>>,
}

impl Known {
	pub fn set(&mut self, id: u32, kind: u32, adjacent: &[u32]) {
		let i = id as usize;
		if i >= self.kind.len() {
			self.kind.resize(i + 1, u32::MAX);
			self.adjacent.resize_with(i + 1, Vec::new);
		}
		self.kind[i] = kind;
		self.adjacent[i].clear();
		self.adjacent[i].extend_from_slice(adjacent);
	}

	pub fn set_air(&mut self, id: u32, temperature: f32, gases: &[(u8, f32)]) {
		let i = id as usize;
		if i >= self.air_temperature.len() {
			self.air_temperature.resize(i + 1, f32::NAN);
			self.air_gases.resize_with(i + 1, Vec::new);
		}
		self.air_temperature[i] = temperature;
		self.air_gases[i].clear();
		self.air_gases[i].extend_from_slice(gases);
	}

	pub fn air(&self, id: u32) -> Option<(f32, &[(u8, f32)])> {
		let i = id as usize;
		match self.air_temperature.get(i) {
			Some(&t) if !t.is_nan() => Some((t, &self.air_gases[i])),
			_ => None,
		}
	}

	pub fn get(&self, id: u32) -> Option<(u32, &[u32])> {
		let i = id as usize;
		match self.kind.get(i) {
			Some(&kind) if kind != u32::MAX => Some((kind, &self.adjacent[i])),
			_ => None,
		}
	}

	/// DM changed its air: it has to be sent again before it's used
	pub fn forget_air(&mut self, id: u32) {
		if let Some(t) = self.air_temperature.get_mut(id as usize) {
			*t = f32::NAN;
		}
	}

	/// Its neighbours changed (or it's a new turf): its kind and neighbours have to be sent again
	pub fn forget_kind(&mut self, id: u32) {
		if let Some(kind) = self.kind.get_mut(id as usize) {
			*kind = u32::MAX;
		}
	}

	/// Everything the engine needs of a turf to run it: its kind and neighbours, and its air unless it has none
	pub fn complete(&self, id: u32) -> bool {
		match self.get(id) {
			Some((KIND_NO_AIR, _)) => true,
			Some(_) => self.air(id).is_some(),
			None => false,
		}
	}
}

/// An excited group. `serial` is 0 once it's gone; otherwise it says which entry of World::group_order is its own.
pub struct Group {
	pub members: Vec<u32>,
	pub breakdown: u32,
	pub dismantle: u32,
	serial: u32,
}

/// A turf whose air the excited groups' step changed: its new temperature, and World::gas_changes[first..first + count]
/// are its gases that changed (0 moles for one that's gone)
pub struct AirChange {
	pub id: u32,
	pub first: u32,
	pub count: u32,
	pub temperature: f64,
}

#[derive(Default)]
pub struct World {
	/// Per turf: the serial of its entry in `active`, 0 if it's asleep (LINDA's `excited`)
	entry: Vec<u32>,
	pub ticker: Vec<f64>,
	pub group: Vec<u32>,
	pub hotspot: Vec<bool>,
	pub drawn: Vec<f64>,
	/// The SSair fire it last had its turn in, -1 for never (its current_cycle)
	pub last_turn: Vec<f64>,
	/// SSair.active_turfs: (turf, serial). An entry whose serial isn't its turf's `entry` any more was taken off.
	active: Vec<(u32, u32)>,
	serial: u32,
	/// Index 0 is no group
	pub groups: Vec<Group>,
	free_groups: Vec<u32>,
	/// SSair.excited_groups: (group, serial), the same way as `active`
	group_order: Vec<(u32, u32)>,
	group_serial: u32,

	// What the excited groups' step changed, for DM
	pub air_changes: Vec<AirChange>,
	pub gas_changes: Vec<(u8, f64)>,
	/// (turf, overlay key)
	pub redraw: Vec<(u32, f64)>,
	/// Every turf a group that broke down woke, in order: add_to_active() on each, which DM does its own part of (it wakes
	/// the idle machines on them)
	pub poked: Vec<u32>,
	/// Groups that broke down and were dismantled in the last step, for benches
	pub broke_down: u32,
	pub dismantled: u32,
}

impl World {
	pub fn new() -> World {
		let mut world = World::default();
		world.groups.push(Group {
			members: Vec::new(),
			breakdown: 0,
			dismantle: 0,
			serial: 0,
		});
		world
	}

	fn ensure(&mut self, id: u32) {
		let i = id as usize;
		if i >= self.entry.len() {
			let n = i + 1;
			self.entry.resize(n, 0);
			self.ticker.resize(n, 0.0);
			self.group.resize(n, 0);
			self.hotspot.resize(n, false);
			self.drawn.resize(n, -1.0);
			self.last_turn.resize(n, -1.0);
		}
	}

	pub fn awake(&self, id: u32) -> bool {
		self.entry.get(id as usize).is_some_and(|&e| e != 0)
	}

	pub fn group_of(&self, id: u32) -> u32 {
		self.group.get(id as usize).copied().unwrap_or(0)
	}

	pub fn ticker_of(&self, id: u32) -> f64 {
		self.ticker.get(id as usize).copied().unwrap_or(0.0)
	}

	pub fn hotspot_of(&self, id: u32) -> bool {
		self.hotspot.get(id as usize).copied().unwrap_or(false)
	}

	pub fn drawn_of(&self, id: u32) -> f64 {
		self.drawn.get(id as usize).copied().unwrap_or(-1.0)
	}

	pub fn last_turn_of(&self, id: u32) -> f64 {
		self.last_turn.get(id as usize).copied().unwrap_or(-1.0)
	}

	/// active_turfs += T
	fn push_active(&mut self, id: u32) {
		self.ensure(id);
		self.serial += 1;
		self.entry[id as usize] = self.serial;
		self.active.push((id, self.serial));
	}

	/// active_turfs -= T
	fn take_off(&mut self, id: u32) {
		if let Some(entry) = self.entry.get_mut(id as usize) {
			*entry = 0;
		}
	}

	/// SSair.active_turfs as it is, in order
	pub fn active(&mut self) -> &[(u32, u32)] {
		let entry = &self.entry;
		self.active.retain(|&(id, serial)| entry[id as usize] == serial);
		&self.active
	}

	pub fn active_count(&mut self) -> usize {
		self.active().len()
	}

	/// SSair.excited_groups as it is, in order
	pub fn group_order(&mut self) -> Vec<u32> {
		let groups = &self.groups;
		self.group_order.retain(|&(group, serial)| groups[group as usize].serial == serial);
		self.group_order.iter().map(|&(group, _)| group).collect()
	}

	/// new /datum/excited_group: on the end of SSair.excited_groups
	fn new_group(&mut self) -> u32 {
		self.group_serial += 1;
		let serial = self.group_serial;
		let group = match self.free_groups.pop() {
			Some(group) => group,
			None => {
				self.groups.push(Group {
					members: Vec::new(),
					breakdown: 0,
					dismantle: 0,
					serial: 0,
				});
				(self.groups.len() - 1) as u32
			}
		};
		let g = &mut self.groups[group as usize];
		g.members.clear();
		g.breakdown = 0;
		g.dismantle = 0;
		g.serial = serial;
		self.group_order.push((group, serial));
		group
	}

	/// excited_group/add_turf()
	fn add_turf(&mut self, group: u32, id: u32) {
		self.ensure(id);
		let g = &mut self.groups[group as usize];
		g.members.push(id);
		g.dismantle = 0;
		self.group[id as usize] = group;
	}

	/// excited_group/merge_groups(): ours.merge_groups(theirs). The bigger one takes the other's turfs and stays where it
	/// is in SSair.excited_groups; the other goes.
	fn merge(&mut self, ours: u32, theirs: u32) {
		let (keep, gone) = if self.groups[ours as usize].members.len() > self.groups[theirs as usize].members.len() {
			(ours, theirs)
		} else {
			(theirs, ours)
		};
		let moving = std::mem::take(&mut self.groups[gone as usize].members);
		for &id in &moving {
			self.group[id as usize] = keep;
		}
		let breakdown = self.groups[keep as usize].breakdown.min(self.groups[gone as usize].breakdown);
		let k = &mut self.groups[keep as usize];
		k.members.extend_from_slice(&moving);
		k.breakdown = breakdown;
		k.dismantle = 0;
		self.retire(gone);
	}

	/// The group is off SSair.excited_groups, and its number can be used again
	fn retire(&mut self, group: u32) {
		let g = &mut self.groups[group as usize];
		g.serial = 0;
		g.members.clear();
		self.free_groups.push(group);
	}

	/// excited_group/garbage_collect(): its turfs are in no group, and it's gone
	fn garbage_collect(&mut self, group: u32) {
		if group == 0 || self.groups[group as usize].serial == 0 {
			return;
		}
		let members = std::mem::take(&mut self.groups[group as usize].members);
		for &id in &members {
			if self.group[id as usize] == group {
				self.group[id as usize] = 0;
			}
		}
		self.groups[group as usize].members = members;
		self.retire(group);
	}

	/// add_to_active()
	pub fn wake(&mut self, id: u32, blockchanges: bool) {
		self.ensure(id);
		self.ticker[id as usize] = 0.0;
		if blockchanges {
			self.garbage_collect(self.group[id as usize]);
		}
		if !self.awake(id) {
			self.push_active(id);
		}
	}

	/// One thing DM did, in the order it did it. Returns false for an event it doesn't know.
	pub fn event(&mut self, kind: u32, id: u32) -> bool {
		self.ensure(id);
		let i = id as usize;
		match kind {
			EVENT_WAKE => self.wake(id, false),
			EVENT_WAKE_BLOCK => self.wake(id, true),
			EVENT_REMOVE => {
				self.take_off(id);
				self.garbage_collect(self.group[i]);
			}
			EVENT_SLEEP => self.take_off(id),
			EVENT_HOTSPOT_ON => self.hotspot[i] = true,
			EVENT_HOTSPOT_OFF => self.hotspot[i] = false,
			EVENT_RESET_GROUP => {
				let group = self.group[i];
				if group != 0 {
					let g = &mut self.groups[group as usize];
					g.breakdown = 0;
					g.dismantle = 0;
				}
			}
			EVENT_UNDRAWN => self.drawn[i] = -1.0,
			EVENT_NEW_TURF => {
				self.drawn[i] = -1.0;
				self.hotspot[i] = false;
			}
			_ => return false,
		}
		true
	}

	/// Starts from DM's state: SSair.active_turfs with each one's ticker, which turfs are burning, and SSair.excited_groups
	/// with their cooldowns and turfs, in order
	/// What it had drawn and when turfs last had their turn are kept: DM doesn't send those, and has the same.
	pub fn load(&mut self, active: &[(u32, f64)], burning: &[u32], groups: &[(u32, u32, Vec<u32>)]) {
		let drawn = std::mem::take(&mut self.drawn);
		let last_turn = std::mem::take(&mut self.last_turn);
		*self = World::new();
		if !drawn.is_empty() {
			self.ensure(drawn.len() as u32 - 1);
			self.drawn[..drawn.len()].copy_from_slice(&drawn);
			self.last_turn[..last_turn.len()].copy_from_slice(&last_turn);
		}
		for &(id, ticker) in active {
			if !self.awake(id) {
				self.push_active(id);
			}
			self.ticker[id as usize] = ticker;
		}
		for &id in burning {
			self.ensure(id);
			self.hotspot[id as usize] = true;
		}
		for (breakdown, dismantle, members) in groups {
			let group = self.new_group();
			for &id in members {
				self.add_turf(group, id);
			}
			let g = &mut self.groups[group as usize];
			g.breakdown = *breakdown;
			g.dismantle = *dismantle;
		}
	}

	/// What the tick did, the way SSair's follow-up to it (tile_engine_process()) writes it into DM: tickers, who's
	/// awake and in what order, excited groups joining and merging in the order LINDA's process_cell() would have, their
	/// cooldowns, and the overlays DM is about to draw. `fire` is SSair.times_fired.
	pub fn absorb(&mut self, tick: &Tick, fire: f64) {
		for tile in 0..tick.packed() as u32 {
			let id = tick.turf(tile);
			if id == u32::MAX {
				continue; // a planetary mix's own tile
			}
			self.ensure(id);
			self.ticker[id as usize] = tick.ticker(tile);
		}
		for &tile in &tick.order {
			let id = tick.turf(tile);
			if id != u32::MAX {
				self.last_turn[id as usize] = fire;
			}
		}
		// The tick's new active_turfs is the whole list
		for k in 0..self.active.len() {
			let (id, serial) = self.active[k];
			if self.entry[id as usize] == serial {
				self.entry[id as usize] = 0;
			}
		}
		self.active.clear();
		for &tile in &tick.active {
			self.push_active(tick.turf(tile));
		}
		for &(a, b) in &tick.group_joins {
			let (a, b) = (tick.turf(a), tick.turf(b));
			let ours = self.group[a as usize];
			let theirs = self.group[b as usize];
			if ours != 0 && theirs != 0 {
				if ours != theirs {
					self.merge(ours, theirs);
				}
			} else {
				let joined = if ours != 0 {
					ours
				} else if theirs != 0 {
					theirs
				} else {
					self.new_group()
				};
				if ours == 0 {
					self.add_turf(joined, a);
				}
				if theirs == 0 && a != b {
					self.add_turf(joined, b);
				}
			}
		}
		for &tile in &tick.groups_big {
			let group = self.group[tick.turf(tile) as usize];
			if group != 0 {
				let g = &mut self.groups[group as usize];
				g.breakdown = 0;
				g.dismantle = 0;
			}
		}
		for &tile in &tick.groups_small {
			let group = self.group[tick.turf(tile) as usize];
			if group != 0 {
				self.groups[group as usize].dismantle = 0;
			}
		}
		for &(tile, key) in &tick.redraw {
			self.drawn[tick.turf(tile) as usize] = key;
		}
	}

	/// The turfs whose air or kind the excited groups' step needs and the engine hasn't got: everyone in a group that's
	/// about to break down
	pub fn groups_need(&mut self, cfg: &Config, known: &Known, wanted: &mut Vec<u32>) {
		for group in self.group_order() {
			let g = &self.groups[group as usize];
			if (g.breakdown + 1) as f64 >= cfg.breakdown_ticks {
				wanted.extend(g.members.iter().copied().filter(|&id| !known.complete(id)));
			}
		}
		wanted.sort_unstable();
		wanted.dedup();
	}

	/// SSair.process_excited_groups(): every group, last first, counts a tick, and breaks down (evens out its air and
	/// wakes its turfs) or is dismantled (its turfs sleep) when it's been long enough. The air it changes goes into `known`
	/// and air_changes for DM; `apply` false works it all out without changing any air (DM does it, atmos-engine-own=shadow),
	/// and `shadow_air` gets what the engine would have made the air instead.
	pub fn process_groups(&mut self, cfg: &Config, known: &mut Known, planetary: &[f64], apply: bool, shadow_air: &mut Vec<(u32, f32, Vec<(u8, f32)>)>) -> Result<(), String> {
		self.air_changes.clear();
		self.gas_changes.clear();
		self.redraw.clear();
		self.poked.clear();
		self.broke_down = 0;
		self.dismantled = 0;
		let order = self.group_order();
		for &group in order.iter().rev() {
			if self.groups[group as usize].serial == 0 {
				continue;
			}
			let g = &mut self.groups[group as usize];
			g.breakdown += 1;
			g.dismantle += 1;
			if g.breakdown as f64 >= cfg.breakdown_ticks {
				self.self_breakdown(cfg, known, planetary, group, apply, shadow_air)?;
				self.broke_down += 1;
			} else if g.dismantle as f64 >= cfg.dismantle_ticks {
				self.dismantle(group);
				self.dismantled += 1;
			}
		}
		Ok(())
	}

	/// excited_group/self_breakdown(poke_turfs = TRUE)
	fn self_breakdown(&mut self, cfg: &Config, known: &mut Known, planetary: &[f64], group: u32, apply: bool, shadow_air: &mut Vec<(u32, f32, Vec<(u8, f32)>)>) -> Result<(), String> {
		let gases = cfg.gases;
		let members = std::mem::take(&mut self.groups[group as usize].members);
		// DM's arithmetic, which rounds to 32 bits after every step, in the same order: each turf's heat capacity (gas by gas
		// in its list's order, values_dot()), energy and heat capacity added up turf by turf, each gas likewise, then divided
		let mut sums32 = vec![0.0f32; gases];
		let mut energy: f32 = 0.0;
		let mut heat_capacity: f32 = 0.0;
		let mut count: f32 = 0.0;
		for &id in &members {
			let (kind, _) = known.get(id).ok_or_else(|| format!("breaking down a group with turf {id}, whose kind was never sent"))?;
			if kind == KIND_NO_AIR {
				continue; // a wall now: DM takes turfs out of their group when that happens, so this shouldn't come up
			}
			count += 1.0;
			let (temperature, air) = known.air(id).ok_or_else(|| format!("breaking down a group with turf {id}, whose air was never sent"))?;
			let capacity: f32 = if kind == KIND_SPACE {
				cfg.heat_capacity_vacuum as f32
			} else {
				let dot = crate::pipes::values_dot(air, &cfg.specific_heat);
				if dot == 0.0 && kind != KIND_FIXED {
					cfg.heat_capacity_vacuum as f32 // a turf's air counts as a vacuum when it's empty
				} else {
					dot
				}
			};
			energy += temperature * capacity;
			heat_capacity += capacity;
			for &(gas, amount) in air {
				sums32[gas as usize] += amount;
			}
		}
		let temperature = if heat_capacity != 0.0 { (energy / heat_capacity) as f64 } else { 0.0 };
		let mut sums = vec![0.0f64; gases];
		let mut moles = vec![0.0f64; gases];
		for gas in 0..gases {
			let mut amount = sums32[gas];
			if count > 0.0 {
				amount /= count;
			}
			// garbage_collect(): a new mix has no archive, so only what it has counts
			sums[gas] = if crate::pipes::negligible(amount, cfg.molar_accuracy, cfg.min_mole_count) { 0.0 } else { amount as f64 };
		}

		let mut new_gases: Vec<(u8, f32)> = Vec::new();
		let mut new_moles = vec![0.0f64; gases];
		for &id in &members {
			let (kind, _) = known.get(id).expect("checked above");
			if kind == KIND_NO_AIR {
				continue;
			}
			if mutable(kind) {
				let new_temperature = if kind >= KIND_PLANETARY && kind != KIND_NO_AIR {
					// A planetary turf takes its planet's air instead
					let mix = (kind - KIND_PLANETARY) as usize;
					let row = planetary.get(mix * (gases + 1)..(mix + 1) * (gases + 1)).ok_or("a planetary mix that was never sent")?;
					new_moles.copy_from_slice(&row[..gases]);
					row[gases]
				} else {
					new_moles.copy_from_slice(&sums);
					temperature
				};
				new_gases.clear();
				for (gas, &amount) in new_moles.iter().enumerate() {
					if amount as f32 != 0.0 {
						new_gases.push((gas as u8, amount as f32));
					}
				}
				if apply {
					let (old_temperature, old_air) = known.air(id).expect("checked above");
					moles.iter_mut().for_each(|m| *m = 0.0);
					for &(gas, amount) in old_air {
						moles[gas as usize] = amount as f64;
					}
					let first = self.gas_changes.len();
					for gas in 0..gases {
						if new_moles[gas] as f32 != moles[gas] as f32 {
							self.gas_changes.push((gas as u8, new_moles[gas]));
						}
					}
					if self.gas_changes.len() > first || new_temperature as f32 != old_temperature {
						self.air_changes.push(AirChange {
							id,
							first: first as u32,
							count: (self.gas_changes.len() - first) as u32,
							temperature: new_temperature,
						});
					}
					known.set_air(id, new_temperature as f32, &new_gases);
				} else {
					shadow_air.push((id, new_temperature as f32, new_gases.clone()));
				}
				// update_visuals(), if it would look different
				if apply {
					let key = cfg.visual_key(&new_moles);
					if key != self.drawn[id as usize] {
						self.redraw.push((id, key));
						self.drawn[id as usize] = key;
					}
				}
			}
			// poke_turfs: SSair.add_to_active(T), then T.significant_share_ticker = EXCITED_GROUP_DISMANTLE_CYCLES
			self.wake(id, false);
			self.poked.push(id);
			self.ticker[id as usize] = cfg.dismantle_ticks;
		}
		let g = &mut self.groups[group as usize];
		g.members = members;
		g.breakdown = 0;
		Ok(())
	}

	/// excited_group/dismantle(): every turf in it goes to sleep, and the group goes
	fn dismantle(&mut self, group: u32) {
		let members = std::mem::take(&mut self.groups[group as usize].members);
		for &id in &members {
			self.take_off(id);
			self.ticker[id as usize] = 0.0;
		}
		self.groups[group as usize].members = members;
		self.garbage_collect(group);
	}

	/// How the engine's state compares with DM's, for atmos-engine-own=shadow: DM's active_turfs with each one's ticker,
	/// whether it's burning and its drawn key, and DM's excited groups in order (breakdown and dismantle cooldowns, then
	/// the turfs). Returns how many of each thing differed: [active list, tickers, burning, drawn, groups]; `drawn_wrong`
	/// gets the turfs whose drawn key differed.
	pub fn check(&mut self, active: &[(u32, f64, bool, f64)], groups: &[(u32, u32, Vec<u32>)], log: &mut Vec<String>, drawn_wrong: &mut Vec<u32>) -> [u64; 5] {
		let mut wrong = [0u64; 5];
		let ours: Vec<u32> = self.active().iter().map(|&(id, _)| id).collect();
		let theirs: Vec<u32> = active.iter().map(|&(id, ..)| id).collect();
		if ours != theirs {
			wrong[0] += 1;
			if log.len() < 20 {
				let first = ours.iter().zip(&theirs).position(|(a, b)| a != b).unwrap_or(ours.len().min(theirs.len()));
				log.push(format!("active turfs: engine has {}, DM {}, first different at {first}: engine {:?}, DM {:?}", ours.len(), theirs.len(), ours.get(first), theirs.get(first)));
			}
		}
		for &(id, ticker, burning, drawn) in active {
			if self.ticker_of(id) as f32 != ticker as f32 {
				wrong[1] += 1;
				if log.len() < 20 {
					log.push(format!("turf {id} ticker: engine {}, DM {ticker}", self.ticker_of(id)));
				}
			}
			if self.hotspot_of(id) != burning {
				wrong[2] += 1;
				if log.len() < 20 {
					log.push(format!("turf {id} burning: engine {}, DM {burning}", self.hotspot_of(id)));
				}
			}
			if self.drawn_of(id) as f32 != drawn as f32 {
				wrong[3] += 1;
				drawn_wrong.push(id);
				if log.len() < 20 {
					log.push(format!("turf {id} drawn: engine {}, DM {drawn}", self.drawn_of(id)));
				}
			}
		}
		let order = self.group_order();
		let mut groups_wrong = order.len() != groups.len();
		if !groups_wrong {
			for (k, &group) in order.iter().enumerate() {
				let g = &self.groups[group as usize];
				let (breakdown, dismantle, members) = &groups[k];
				let mut ours: Vec<u32> = g.members.clone();
				let mut theirs = members.clone();
				ours.sort_unstable();
				theirs.sort_unstable();
				if g.breakdown != *breakdown || g.dismantle != *dismantle || ours != theirs {
					groups_wrong = true;
					if log.len() < 20 {
						log.push(format!("group {k}: engine cooldowns {}/{} with {} turfs, DM {breakdown}/{dismantle} with {}", g.breakdown, g.dismantle, ours.len(), theirs.len()));
					}
					break;
				}
			}
		} else if log.len() < 20 {
			log.push(format!("groups: engine has {}, DM {}", order.len(), groups.len()));
		}
		if groups_wrong {
			wrong[4] += 1;
		}
		wrong
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::engine::{NewTile, KIND_TURF};

	fn config() -> Config {
		let mut settings = vec![3.0, 20.0, 20.0, 200.0, -1.0, -1.0, 0.25, 0.25, 4.0];
		let moles_cellstandard = 101.325 * 2500.0 / (293.15 * 8.31);
		settings.extend_from_slice(&[
			moles_cellstandard * 0.001,
			0.001,
			4.0,
			0.5,
			293.15 + 100.0,
			0.4,
			7000.0,
			0.0003,
			2.7,
			8.31,
			2500.0,
			1e-4,
			0.01,
			293.15 + 400.0,
			moles_cellstandard * 0.005,
			moles_cellstandard * 0.1,
			11.0,
			5.0,
		]);
		settings.push(0.0);
		Config::parse(&settings).unwrap()
	}

	fn active_ids(world: &mut World) -> Vec<u32> {
		world.active().iter().map(|&(id, _)| id).collect()
	}

	#[test]
	fn waking_puts_a_turf_on_the_end_once() {
		let mut world = World::new();
		world.event(EVENT_WAKE, 5);
		world.event(EVENT_WAKE, 3);
		world.ticker[5] = 7.0;
		world.event(EVENT_WAKE, 5);
		assert_eq!(active_ids(&mut world), vec![5, 3]);
		assert_eq!(world.ticker[5], 0.0, "add_to_active() resets the ticker even for an awake turf");
		world.event(EVENT_SLEEP, 5);
		world.event(EVENT_WAKE, 5);
		assert_eq!(active_ids(&mut world), vec![3, 5], "a turf woken again goes on the end");
	}

	#[test]
	fn the_bigger_group_takes_the_smaller_and_keeps_its_place() {
		let mut world = World::new();
		let a = world.new_group();
		let b = world.new_group();
		let c = world.new_group();
		world.add_turf(a, 1);
		world.add_turf(b, 2);
		world.add_turf(b, 3);
		world.add_turf(c, 4);
		world.groups[a as usize].breakdown = 1;
		world.groups[b as usize].breakdown = 3;
		world.groups[b as usize].dismantle = 4;
		world.merge(a, b);
		assert_eq!(world.group_order(), vec![b, c]);
		assert_eq!(world.group[1], b);
		assert_eq!(world.groups[b as usize].members, vec![2, 3, 1]);
		assert_eq!(world.groups[b as usize].breakdown, 1);
		assert_eq!(world.groups[b as usize].dismantle, 0);
	}

	#[test]
	fn removing_a_turf_lets_its_group_go_but_sleeping_doesnt() {
		let mut world = World::new();
		let g = world.new_group();
		world.add_turf(g, 1);
		world.add_turf(g, 2);
		world.event(EVENT_WAKE, 1);
		world.event(EVENT_WAKE, 2);
		world.event(EVENT_SLEEP, 1);
		assert_eq!(world.group[1], g);
		world.event(EVENT_REMOVE, 2);
		assert_eq!(world.group[1], 0);
		assert_eq!(world.group[2], 0);
		assert!(world.group_order().is_empty());
		assert!(active_ids(&mut world).is_empty());
	}

	#[test]
	fn a_quiet_group_is_dismantled_and_its_turfs_sleep() {
		let cfg = config();
		let mut known = Known::default();
		let mut world = World::new();
		let g = world.new_group();
		for id in [1, 2] {
			world.add_turf(g, id);
			world.wake(id, false);
			known.set(id, KIND_TURF, &[]);
			known.set_air(id, 293.15, &[(0, 50.0)]);
		}
		world.groups[g as usize].breakdown = 0;
		let mut shadow = Vec::new();
		for tick in 1..=11 {
			// Breaking down every 5 ticks resets the breakdown count only, so keep it from happening
			world.groups[g as usize].breakdown = 0;
			world.process_groups(&cfg, &mut known, &[], true, &mut shadow).unwrap();
			if tick < 11 {
				assert_eq!(world.group_order(), vec![g]);
			}
		}
		assert!(world.group_order().is_empty());
		assert!(active_ids(&mut world).is_empty());
		assert_eq!(world.group[1], 0);
	}

	#[test]
	fn breaking_down_evens_out_the_air_counting_space_as_a_vacuum() {
		let cfg = config();
		let mut known = Known::default();
		let mut world = World::new();
		let g = world.new_group();
		world.add_turf(g, 1);
		world.add_turf(g, 2);
		world.add_turf(g, 3);
		known.set(1, KIND_TURF, &[]);
		known.set_air(1, 300.0, &[(0, 90.0)]);
		known.set(2, KIND_TURF, &[]);
		known.set_air(2, 300.0, &[(0, 30.0)]);
		known.set(3, KIND_SPACE, &[]);
		known.set_air(3, 2.7, &[]);
		world.groups[g as usize].breakdown = 4;
		let mut shadow = Vec::new();
		let mut wanted = Vec::new();
		world.groups_need(&cfg, &known, &mut wanted);
		assert!(wanted.is_empty());
		world.process_groups(&cfg, &mut known, &[], true, &mut shadow).unwrap();
		assert_eq!(world.broke_down, 1);
		let (t1, air1) = known.air(1).unwrap();
		assert_eq!(air1, &[(0u8, 40.0f32)]);
		// In 32 bits, step by step, as DM works it out
		let energy = 300.0f32 * (90.0 * 20.0) + 300.0f32 * (30.0 * 20.0) + 2.7f32 * 7000.0;
		let capacity = 90.0f32 * 20.0 + 30.0 * 20.0 + 7000.0;
		assert_eq!(t1, energy / capacity);
		assert_eq!(known.air(3).unwrap().1, &[] as &[(u8, f32)], "space keeps its air");
		assert_eq!(world.air_changes.len(), 2);
		assert_eq!(active_ids(&mut world), vec![1, 2, 3], "every turf is woken, in the group's order");
		assert_eq!(world.poked, vec![1, 2, 3]);
		assert_eq!(world.ticker[2], cfg.dismantle_ticks);
		assert_eq!(world.groups[g as usize].breakdown, 0);
	}

	#[test]
	fn a_group_about_to_break_down_asks_for_air_it_hasnt_got() {
		let cfg = config();
		let mut known = Known::default();
		let mut world = World::new();
		let g = world.new_group();
		world.add_turf(g, 1);
		world.add_turf(g, 2);
		known.set(1, KIND_TURF, &[]);
		known.set_air(1, 300.0, &[(0, 90.0)]);
		known.set(2, KIND_TURF, &[]);
		known.set_air(2, 300.0, &[(0, 30.0)]);
		known.forget_air(2);
		let mut wanted = Vec::new();
		world.groups[g as usize].breakdown = 3;
		world.groups_need(&cfg, &known, &mut wanted);
		assert!(wanted.is_empty(), "not breaking down this tick");
		world.groups[g as usize].breakdown = 4;
		world.groups_need(&cfg, &known, &mut wanted);
		assert_eq!(wanted, vec![2]);
	}

	#[test]
	fn a_tick_joins_turfs_into_groups_the_way_dm_would() {
		let cfg = config();
		let mut tick = Tick::new();
		tick.begin(&cfg);
		let gases_full = [(0usize, 100.0)];
		tick.add(NewTile { id: 1, gases: &gases_full, temperature: 293.15, adjacent: &[2], kind: KIND_TURF, group: 0, ticker: 0.0, hotspot: false, drawn: -1.0, awake: true });
		tick.add(NewTile { id: 2, gases: &[], temperature: 293.15, adjacent: &[1], kind: KIND_TURF, group: 0, ticker: 0.0, hotspot: false, drawn: -1.0, awake: false });
		let mut wanted = Vec::new();
		assert!(tick.run(&cfg, &[], &mut wanted));
		tick.finish(&cfg);
		let mut world = World::new();
		world.wake(1, false);
		world.absorb(&tick, 3.0);
		assert_eq!(active_ids(&mut world), vec![1, 2]);
		let g = world.group[1];
		assert_ne!(g, 0);
		assert_eq!(world.group[2], g);
		assert_eq!(world.group_order(), vec![g]);
		assert_eq!(world.last_turn[1], 3.0);
	}
}
