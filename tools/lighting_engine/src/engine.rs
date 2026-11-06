//! The lighting engine: a straight copy of DM's /datum/light_source/proc/update_corners() and get_bounce_corners(),
//! remove_lum(), recalc_corner() and relight_in_place(), and of the corner and lighting object stages of SSlighting
//! (code/modules/lighting/). Same 32-bit float operations in the same order, so it gives every corner exactly what DM
//! would. DM still decides when a light needs working out and finds what it can see with view(); this does the rest.
//!
//! Places: turfs are numbered from 0 in each z-level, (y - 1) * maxx + (x - 1). Corners sit between turfs: corner
//! (cx, cy), cx in 0..=maxx and cy in 0..=maxy, is DM's /datum/lighting_corner made with New(cx, cy), at cx + 0.5, cy + 0.5.
//! Turf (x, y) has corners NE (x, y), SE (x, y - 1), SW (x - 1, y - 1) and NW (x - 1, y). A corner the DM engine
//! never made is dark, the same as one that's there with nothing lighting it.

/// The turf's has_opaque_atom: it blocks light
pub const OPAQUE: u8 = 1;
/// The turf's dynamic_lighting
pub const DYNAMIC: u8 = 2;
/// The turf has light sources of its own (its light_sources list), which makes it count though it isn't dynamically lit
pub const SOURCES: u8 = 4;
/// The turf has a lighting object to draw on
pub const OBJECT: u8 = 8;

/// LIGHTING_ROUND_VALUE
const ROUND_VALUE: f32 = 1.0 / 64.0;

#[derive(Clone, Default)]
pub struct Corner {
	pub lum: [f32; 3],
	pub bounce: [f32; 3],
	pub cache: [f32; 3],
	pub largest: f32,
	pub needs_update: bool,
	/// Light ids, as DM's affecting list: one entry each time a light took a hold, dropped one at a time
	pub affecting: Vec<u32>,
	// Scratch for the update under way, as on DM's corners
	stamp: u32,
	level: f32,
	bounce_stamp: u32,
	bounce_level: f32,
	// The updating light's strength here before it started, marked with its stamp: DM's effect_str[corner]
	old_mark: u32,
	old: f32,
	bounce_old_mark: u32,
	bounce_old: f32,
}

pub struct Level {
	pub corners: Vec<Corner>,
	pub flags: Vec<u8>,
	turf_stamp: Vec<u32>,
	spill: Vec<f32>,
	spill_mark: Vec<u32>,
	frontier_mark: Vec<u32>,
	object_queued: Vec<bool>,
}

pub struct Light {
	pub id: u32,
	pub z: usize,
	pub tx: i32,
	pub ty: i32,
	pub reach: i32,
	pub sheet: usize,
	pub power: f32,
	pub applied: [f32; 3],
	/// DM's effect_str: corner -> strength
	pub effect: Vec<(u32, f32)>,
	/// DM's bounce_str with bounce_levels: corner -> strength, level
	pub bounce: Vec<(u32, f32, f32)>,
}

pub struct Sheet {
	pub dim: i32,
	pub values: Vec<f32>,
}

/// What DM hands over for one light's update: see /datum/light_source/proc/update_corners()
pub struct Update {
	pub id: usize,
	pub z: usize,
	pub tx: i32,
	pub ty: i32,
	pub reach: i32,
	pub power: f32,
	pub lum: [f32; 3],
	pub sheet: usize,
	pub spill_sheet: usize,
	pub vis_only: bool,
	pub bounces: bool,
	pub scatters: bool,
	pub scatter_cutoff: f32,
	pub bounce_strength: f32,
	pub bounce_falloff: f32,
	pub bounce_cutoff: f32,
	pub bounce_depth: i32,
}

pub struct Engine {
	pub maxx: i32,
	pub maxy: i32,
	pub levels: Vec<Option<Level>>,
	pub lights: Vec<Option<Light>>,
	pub sheets: Vec<Option<Sheet>>,
	stamp: u32,
	frontier_round: u32,
	/// SSlighting's corners_queue: (z, corner)
	pub corner_queue: Vec<(u32, u32)>,
	/// SSlighting's objects_queue, by turf: (z, turf)
	pub object_queue: Vec<(u32, u32)>,
	// Kept between updates so they aren't made afresh every time
	reached: Vec<u32>,
	bounced: Vec<u32>,
	lit: Vec<u32>,
	spill_order: Vec<u32>,
	frontier: Vec<u32>,
	spilling: Vec<u32>,
}

const NORTH: u8 = 1;
const SOUTH: u8 = 2;
const EAST: u8 = 4;
const WEST: u8 = 8;

impl Engine {
	pub fn new(maxx: i32, maxy: i32, maxz: usize) -> Self {
		let mut levels = Vec::new();
		levels.resize_with(maxz + 1, || None);
		Engine {
			maxx,
			maxy,
			levels,
			lights: Vec::new(),
			sheets: Vec::new(),
			stamp: 0,
			frontier_round: 0,
			corner_queue: Vec::new(),
			object_queue: Vec::new(),
			reached: Vec::new(),
			bounced: Vec::new(),
			lit: Vec::new(),
			spill_order: Vec::new(),
			frontier: Vec::new(),
			spilling: Vec::new(),
		}
	}

	pub fn turfs_per_level(&self) -> u32 {
		(self.maxx * self.maxy) as u32
	}

	/// The z-level's grids, made the first time anything happens there. z counts from 1.
	pub fn level(&mut self, z: usize) -> &mut Level {
		if z >= self.levels.len() {
			self.levels.resize_with(z + 1, || None);
		}
		let turfs = (self.maxx * self.maxy) as usize;
		let corners = ((self.maxx + 1) * (self.maxy + 1)) as usize;
		self.levels[z].get_or_insert_with(|| Level {
			corners: vec![Corner::default(); corners],
			flags: vec![0; turfs],
			turf_stamp: vec![0; turfs],
			spill: vec![0.0; turfs],
			spill_mark: vec![0; turfs],
			frontier_mark: vec![0; turfs],
			object_queued: vec![false; turfs],
		})
	}

	#[inline]
	fn corner_index(&self, cx: i32, cy: i32) -> u32 {
		(cy * (self.maxx + 1) + cx) as u32
	}

	#[inline]
	pub fn turf_xy(&self, turf: u32) -> (i32, i32) {
		let t = turf as i32;
		(t % self.maxx + 1, t / self.maxx + 1)
	}

	#[inline]
	fn corner_xy(&self, corner: u32) -> (i32, i32) {
		let c = corner as i32;
		(c % (self.maxx + 1), c / (self.maxx + 1))
	}

	/// NE, SE, SW, NW
	#[inline]
	fn turf_corners(&self, x: i32, y: i32) -> [u32; 4] {
		[
			self.corner_index(x, y),
			self.corner_index(x, y - 1),
			self.corner_index(x - 1, y - 1),
			self.corner_index(x - 1, y),
		]
	}

	pub fn set_flags(&mut self, z: usize, turf: u32, flags: u8) {
		self.level(z).flags[turf as usize] = flags;
	}

	pub fn set_sheet(&mut self, id: usize, dim: i32, values: Vec<f32>) {
		if id >= self.sheets.len() {
			self.sheets.resize_with(id + 1, || None);
		}
		self.sheets[id] = Some(Sheet { dim, values });
	}

	/// LUM_FALLOFF(): the sheet's value for a corner, from a light on (tx, ty) reaching `reach` tiles
	#[inline]
	fn falloff(sheet: &Sheet, reach: i32, tx: i32, ty: i32, cx: i32, cy: i32) -> f32 {
		let ix = cx - tx + reach + 1;
		let iy = cy - ty + reach + 1;
		if ix < 0 || iy < 0 || ix >= sheet.dim || iy >= sheet.dim {
			return 0.0; // DM would read past its sheet and fail; nothing reached gets here
		}
		sheet.values[(ix * sheet.dim + iy) as usize]
	}

	fn next_stamp(&mut self) -> u32 {
		self.stamp = self.stamp.wrapping_add(1);
		if self.stamp == 0 {
			// Every stamp starts over, as reset_lighting_stamps() does
			for level in self.levels.iter_mut().flatten() {
				for c in level.corners.iter_mut() {
					c.stamp = 0;
					c.bounce_stamp = 0;
					c.old_mark = 0;
					c.bounce_old_mark = 0;
				}
				for s in level.turf_stamp.iter_mut() {
					*s = 0;
				}
				for s in level.spill_mark.iter_mut() {
					*s = 0;
				}
			}
			self.stamp = 1;
		}
		self.stamp
	}

	/// ADD_CORNER_LUM
	#[inline]
	fn add_lum(level: &mut Level, queue: &mut Vec<(u32, u32)>, z: usize, corner: u32, d: [f32; 3]) {
		if d[0] != 0.0 || d[1] != 0.0 || d[2] != 0.0 {
			let c = &mut level.corners[corner as usize];
			c.lum[0] += d[0];
			c.lum[1] += d[1];
			c.lum[2] += d[2];
			if !c.needs_update {
				c.needs_update = true;
				queue.push((z as u32, corner));
			}
		}
	}

	/// ADD_CORNER_BOUNCE
	#[inline]
	fn add_bounce(level: &mut Level, queue: &mut Vec<(u32, u32)>, z: usize, corner: u32, d: [f32; 3]) {
		if d[0] != 0.0 || d[1] != 0.0 || d[2] != 0.0 {
			let c = &mut level.corners[corner as usize];
			c.bounce[0] += d[0];
			c.bounce[1] += d[1];
			c.bounce[2] += d[2];
			if !c.needs_update {
				c.needs_update = true;
				queue.push((z as u32, corner));
			}
		}
	}

	fn remove_affecting(corner: &mut Corner, id: u32) {
		if let Some(at) = corner.affecting.iter().position(|&l| l == id) {
			corner.affecting.remove(at);
		}
	}

	/// /datum/light_source/proc/update_corners(), from where it starts looking around. `seen` is what view() handed back,
	/// as turfs on the light's z-level, in its order.
	pub fn update(&mut self, u: &Update, seen: &[u32]) -> Result<(), String> {
		if u.id >= self.lights.len() {
			self.lights.resize_with(u.id + 1, || None);
		}
		let mut light = self.lights[u.id].take().unwrap_or(Light {
			id: u.id as u32,
			z: u.z,
			tx: u.tx,
			ty: u.ty,
			reach: u.reach,
			sheet: u.sheet,
			power: u.power,
			applied: [0.0; 3],
			effect: Vec::new(),
			bounce: Vec::new(),
		});
		if light.z != u.z && (!light.effect.is_empty() || !light.bounce.is_empty()) {
			// Moved to another z-level with its light still on the old one: DM keeps one set of corners for both, so take
			// it off there first, as working it out afresh would drop every corner it no longer reaches
			self.remove_light(&mut light);
		}
		let result = self.update_light(&mut light, u, seen);
		self.lights[u.id] = Some(light);
		result
	}

	fn update_light(&mut self, light: &mut Light, u: &Update, seen: &[u32]) -> Result<(), String> {
		let stamp = self.next_stamp();
		let z = u.z;
		let maxx = self.maxx;
		let sheets = std::mem::take(&mut self.sheets);
		let result = (|| {
			let sheet = sheets.get(u.sheet).and_then(|s| s.as_ref()).ok_or("no such sheet")?;
			let spill_sheet = sheets
				.get(u.spill_sheet)
				.and_then(|s| s.as_ref())
				.ok_or("no such spill sheet")?;
			self.level(z);
			let mut reached = std::mem::take(&mut self.reached);
			let mut bounced = std::mem::take(&mut self.bounced);
			let mut lit = std::mem::take(&mut self.lit);
			reached.clear();
			bounced.clear();
			lit.clear();
			let (tx, ty, reach) = (u.tx, u.ty, u.reach);
			let mut queue = std::mem::take(&mut self.corner_queue);
			{
				let corner_dims = (self.maxx, self.maxy);
				let level = self.levels[z].as_mut().unwrap();
				// What we light now, for the reached and removal loops below (DM's effect_str lookups)
				for &(c, s) in light.effect.iter() {
					let corner = &mut level.corners[c as usize];
					corner.old_mark = stamp;
					corner.old = s;
				}
				// GATHER_CORNER over every turf view() handed back
				for &t in seen {
					let flags = level.flags[t as usize];
					if (flags & DYNAMIC == 0 && flags & SOURCES == 0) || flags & OPAQUE != 0 {
						continue;
					}
					let x = t as i32 % maxx + 1;
					let y = t as i32 / maxx + 1;
					let corners = [
						(y * (corner_dims.0 + 1) + x) as u32,
						((y - 1) * (corner_dims.0 + 1) + x) as u32,
						((y - 1) * (corner_dims.0 + 1) + x - 1) as u32,
						(y * (corner_dims.0 + 1) + x - 1) as u32,
					];
					let corner_xy = [(x, y), (x, y - 1), (x - 1, y - 1), (x - 1, y)];
					for k in 0..4 {
						let corner = &mut level.corners[corners[k] as usize];
						if corner.stamp == stamp {
							continue;
						}
						corner.stamp = stamp;
						let (cx, cy) = corner_xy[k];
						let lvl = Self::falloff(sheet, reach, tx, ty, cx, cy);
						if u.scatters {
							let scatter_level = Self::falloff(spill_sheet, reach, tx, ty, cx, cy);
							if lvl > 0.0 && lvl >= scatter_level {
								corner.level = lvl;
								reached.push(corners[k]);
							} else {
								corner.level = 0.0;
								if scatter_level >= u.scatter_cutoff {
									corner.bounce_stamp = stamp;
									corner.bounce_level = scatter_level;
									bounced.push(corners[k]);
								}
							}
						} else if lvl > 0.0 {
							corner.level = lvl;
							reached.push(corners[k]);
						} else {
							corner.level = 0.0;
						}
					}
					if u.bounces {
						let lights_corner = |c: &Corner| c.level > 0.0 || c.bounce_stamp == stamp;
						if lights_corner(&level.corners[corners[0] as usize])
							|| lights_corner(&level.corners[corners[1] as usize])
							|| lights_corner(&level.corners[corners[2] as usize])
							|| lights_corner(&level.corners[corners[3] as usize])
						{
							level.turf_stamp[t as usize] = stamp;
							lit.push(t);
						}
					}
				}

				// Our direct light: onto the corners we reach, then off those we no longer do
				let power = u.power;
				let lum = u.lum;
				let applied = light.applied;
				let mut effect = Vec::with_capacity(reached.len());
				for &c in reached.iter() {
					let corner = &mut level.corners[c as usize];
					let old;
					if corner.old_mark != stamp {
						corner.affecting.push(u.id as u32);
						old = 0.0f32;
					} else {
						old = corner.old;
						if u.vis_only {
							effect.push((c, old));
							corner.old_mark = 0; // still ours: not one to take off below
							continue;
						}
					}
					corner.old_mark = 0;
					let strength = corner.level * power;
					effect.push((c, strength));
					let d = [
						strength * lum[0] - old * applied[0],
						strength * lum[1] - old * applied[1],
						strength * lum[2] - old * applied[2],
					];
					Self::add_lum(level, &mut queue, z, c, d);
				}
				for &(c, s) in light.effect.iter() {
					let corner = &mut level.corners[c as usize];
					if corner.stamp != stamp || corner.level <= 0.0 {
						let strength = -s;
						let d = [strength * applied[0], strength * applied[1], strength * applied[2]];
						Self::remove_affecting(corner, u.id as u32);
						Self::add_lum(level, &mut queue, z, c, d);
					}
					level.corners[c as usize].old_mark = 0;
				}
				light.effect = effect;
			}

			// Bounce light, always worked out afresh
			if u.bounces {
				self.bounce_corners(z, &lit, spill_sheet, tx, ty, reach, stamp, u, &mut bounced);
			}
			{
				let level = self.levels[z].as_mut().unwrap();
				if !light.bounce.is_empty() || !bounced.is_empty() {
					let power = u.power;
					let lum = u.lum;
					let applied = light.applied;
					for &(c, s, _) in light.bounce.iter() {
						let corner = &mut level.corners[c as usize];
						corner.bounce_old_mark = stamp;
						corner.bounce_old = s;
					}
					let mut bounce = Vec::with_capacity(bounced.len());
					for &c in bounced.iter() {
						let corner = &mut level.corners[c as usize];
						let old;
						if corner.bounce_old_mark != stamp {
							corner.affecting.push(u.id as u32);
							old = 0.0f32;
						} else {
							old = corner.bounce_old;
						}
						corner.bounce_old_mark = 0;
						let lvl = corner.bounce_level;
						let strength = lvl * power;
						bounce.push((c, strength, lvl));
						let d = [
							strength * lum[0] - old * applied[0],
							strength * lum[1] - old * applied[1],
							strength * lum[2] - old * applied[2],
						];
						Self::add_bounce(level, &mut queue, z, c, d);
					}
					for &(c, s, _) in light.bounce.iter() {
						let corner = &mut level.corners[c as usize];
						if corner.bounce_stamp != stamp {
							let strength = -s;
							let d = [strength * applied[0], strength * applied[1], strength * applied[2]];
							Self::remove_affecting(corner, u.id as u32);
							Self::add_bounce(level, &mut queue, z, c, d);
						}
						level.corners[c as usize].bounce_old_mark = 0;
					}
					light.bounce = bounce;
				}
			}
			light.z = z;
			light.tx = tx;
			light.ty = ty;
			light.reach = reach;
			light.sheet = u.sheet;
			light.power = u.power;
			light.applied = u.lum;
			self.corner_queue = queue;
			self.reached = reached;
			self.bounced = bounced;
			self.lit = lit;
			Ok(())
		})();
		self.sheets = sheets;
		result
	}

	/// get_bounce_corners()
	#[allow(clippy::too_many_arguments)]
	fn bounce_corners(
		&mut self,
		z: usize,
		lit: &[u32],
		sheet: &Sheet,
		tx: i32,
		ty: i32,
		reach: i32,
		stamp: u32,
		u: &Update,
		bounced: &mut Vec<u32>,
	) {
		let maxx = self.maxx;
		let maxy = self.maxy;
		let strength = u.bounce_strength;
		let falloff = u.bounce_falloff;
		let cutoff = u.bounce_cutoff;
		let mut spill_order = std::mem::take(&mut self.spill_order);
		let mut frontier = std::mem::take(&mut self.frontier);
		let mut spilling = std::mem::take(&mut self.spilling);
		spill_order.clear();
		frontier.clear();
		self.frontier_round = self.frontier_round.wrapping_add(1);
		let mut round = self.frontier_round;
		let level = self.levels[z].as_mut().unwrap();
		let step = |x: i32, y: i32, dir: u8| -> Option<u32> {
			let (nx, ny) = match dir {
				NORTH => (x, y + 1),
				SOUTH => (x, y - 1),
				EAST => (x + 1, y),
				_ => (x - 1, y),
			};
			if nx < 1 || ny < 1 || nx > maxx || ny > maxy {
				None
			} else {
				Some(((ny - 1) * maxx + (nx - 1)) as u32)
			}
		};
		// CAN_SPILL_INTO
		let can_spill = |level: &Level, t: u32| -> bool {
			let f = level.flags[t as usize];
			level.turf_stamp[t as usize] != stamp && f & OPAQUE == 0 && f & DYNAMIC != 0
		};
		// spill[t], null reading as 0
		let spill_of = |level: &Level, t: u32| -> f32 {
			if level.spill_mark[t as usize] == stamp {
				level.spill[t as usize]
			} else {
				0.0
			}
		};
		let sheet_at = |cx: i32, cy: i32| -> f32 { Self::falloff(sheet, reach, tx, ty, cx, cy) };

		for &l in lit {
			if level.flags[l as usize] & DYNAMIC == 0 {
				continue;
			}
			let x = l as i32 % maxx + 1;
			let y = l as i32 / maxx + 1;
			// SPILL_OUT_OF(lit, dir, the two corners on that edge)
			for (dir, c1, c2) in [
				(NORTH, (x - 1, y), (x, y)),
				(SOUTH, (x - 1, y - 1), (x, y - 1)),
				(EAST, (x, y - 1), (x, y)),
				(WEST, (x - 1, y - 1), (x - 1, y)),
			] {
				if let Some(n) = step(x, y, dir) {
					if can_spill(level, n) {
						let lvl = sheet_at(c1.0, c1.1).min(sheet_at(c2.0, c2.1)) * strength;
						if lvl >= cutoff && lvl > spill_of(level, n) {
							if level.spill_mark[n as usize] != stamp {
								level.spill_mark[n as usize] = stamp;
								spill_order.push(n);
							}
							level.spill[n as usize] = lvl;
							if level.frontier_mark[n as usize] != round {
								level.frontier_mark[n as usize] = round;
								frontier.push(n);
							}
						}
					}
				}
			}
		}

		// On into the shadows, dimming as it goes
		for _depth in 2..=u.bounce_depth {
			std::mem::swap(&mut spilling, &mut frontier);
			frontier.clear();
			self.frontier_round = self.frontier_round.wrapping_add(1);
			round = self.frontier_round;
			for &s in spilling.iter() {
				let lvl = level.spill[s as usize] * falloff;
				if lvl < cutoff {
					continue;
				}
				let x = s as i32 % maxx + 1;
				let y = s as i32 / maxx + 1;
				for dir in [NORTH, SOUTH, EAST, WEST] {
					if let Some(n) = step(x, y, dir) {
						if can_spill(level, n) && lvl > spill_of(level, n) {
							if level.spill_mark[n as usize] != stamp {
								level.spill_mark[n as usize] = stamp;
								spill_order.push(n);
							}
							level.spill[n as usize] = lvl;
							if level.frontier_mark[n as usize] != round {
								level.frontier_mark[n as usize] = round;
								frontier.push(n);
							}
						}
					}
				}
			}
		}

		// A shadowed tile's spill lights its corners, bar those we light directly (BOUNCE_ONTO)
		for &s in spill_order.iter() {
			let lvl = level.spill[s as usize];
			let x = s as i32 % maxx + 1;
			let y = s as i32 / maxx + 1;
			for c in [
				(y * (maxx + 1) + x) as u32,
				((y - 1) * (maxx + 1) + x) as u32,
				((y - 1) * (maxx + 1) + x - 1) as u32,
				(y * (maxx + 1) + x - 1) as u32,
			] {
				let corner = &mut level.corners[c as usize];
				if corner.stamp != stamp || corner.level <= 0.0 {
					if corner.bounce_stamp != stamp {
						corner.bounce_stamp = stamp;
						corner.bounce_level = lvl;
						bounced.push(c);
					} else if lvl > corner.bounce_level {
						corner.bounce_level = lvl;
					}
				}
			}
		}
		self.spill_order = spill_order;
		self.frontier = frontier;
		self.spilling = spilling;
	}

	/// remove_lum()
	pub fn remove(&mut self, id: usize) {
		if let Some(mut light) = self.lights.get_mut(id).and_then(|l| l.take()) {
			self.remove_light(&mut light);
			// What's left of it (its last brightness and colour) stays, as DM's light source keeps them
			self.lights[id] = Some(light);
		}
	}

	fn remove_light(&mut self, light: &mut Light) {
		let z = light.z;
		let applied = light.applied;
		let mut queue = std::mem::take(&mut self.corner_queue);
		let light_id = light.id;
		let level = self.level(z);
		for &(c, s) in light.effect.iter() {
			let strength = -s;
			let d = [strength * applied[0], strength * applied[1], strength * applied[2]];
			Self::add_lum(level, &mut queue, z, c, d);
			Self::remove_affecting(&mut level.corners[c as usize], light_id);
		}
		light.effect.clear();
		for &(c, s, _) in light.bounce.iter() {
			let strength = -s;
			let d = [strength * applied[0], strength * applied[1], strength * applied[2]];
			Self::add_bounce(level, &mut queue, z, c, d);
			Self::remove_affecting(&mut level.corners[c as usize], light_id);
		}
		light.bounce.clear();
		self.corner_queue = queue;
	}

	/// The light is gone for good
	pub fn forget(&mut self, id: usize) {
		self.remove(id);
		if let Some(slot) = self.lights.get_mut(id) {
			*slot = None;
		}
	}

	/// relight_in_place(): brightness or colour only, nothing else changed
	pub fn relight(&mut self, id: usize, power: f32, lum: [f32; 3]) -> Result<(), String> {
		let mut light = self.lights.get_mut(id).and_then(|l| l.take()).ok_or("no such light")?;
		let sheets = std::mem::take(&mut self.sheets);
		let result = (|| {
			let sheet = sheets.get(light.sheet).and_then(|s| s.as_ref()).ok_or("no such sheet")?;
			let z = light.z;
			let applied = light.applied;
			let mut queue = std::mem::take(&mut self.corner_queue);
			let (tx, ty, reach) = (light.tx, light.ty, light.reach);
			let cols = self.maxx + 1;
			let level = self.level(z);
			for entry in light.effect.iter_mut() {
				let c = entry.0;
				let old = entry.1;
				let (cx, cy) = (c as i32 % cols, c as i32 / cols);
				let strength = Self::falloff(sheet, reach, tx, ty, cx, cy) * power;
				entry.1 = strength;
				let d = [
					strength * lum[0] - old * applied[0],
					strength * lum[1] - old * applied[1],
					strength * lum[2] - old * applied[2],
				];
				Self::add_lum(level, &mut queue, z, c, d);
			}
			for entry in light.bounce.iter_mut() {
				let c = entry.0;
				let old = entry.1;
				let strength = entry.2 * power;
				entry.1 = strength;
				let d = [
					strength * lum[0] - old * applied[0],
					strength * lum[1] - old * applied[1],
					strength * lum[2] - old * applied[2],
				];
				Self::add_bounce(level, &mut queue, z, c, d);
			}
			light.power = power;
			light.applied = lum;
			self.corner_queue = queue;
			Ok(())
		})();
		self.sheets = sheets;
		self.lights[id] = Some(light);
		result
	}

	/// lighting_build_overlay()'s recalc_corner() for every light on each of the turf's corners, NE, SE, SW, NW
	pub fn recalc_turf(&mut self, z: usize, x: i32, y: i32) {
		let corners = self.turf_corners(x, y);
		let cols = self.maxx + 1;
		for c in corners {
			let ids: Vec<u32> = self.level(z).corners[c as usize].affecting.clone();
			for id in ids {
				let Some(mut light) = self.lights.get_mut(id as usize).and_then(|l| l.take()) else {
					continue;
				};
				if light.z == z && !light.bounce.iter().any(|b| b.0 == c) {
					if let Some(Some(sheet)) = self.sheets.get(light.sheet) {
						let (cx, cy) = (c as i32 % cols, c as i32 / cols);
						let level_value = Self::falloff(sheet, light.reach, light.tx, light.ty, cx, cy);
						let power = light.power;
						let lum = light.applied;
						let applied = light.applied;
						let mut queue = std::mem::take(&mut self.corner_queue);
						let level = self.levels[z].as_mut().unwrap();
						let at = light.effect.iter().position(|e| e.0 == c);
						let mut old = 0.0f32;
						if let Some(i) = at {
							let strength = light.effect[i].1;
							if strength != 0.0 {
								let neg = -strength;
								let d = [neg * applied[0], neg * applied[1], neg * applied[2]];
								Self::add_lum(level, &mut queue, z, c, d);
								light.effect[i].1 = 0.0;
							}
							old = light.effect[i].1;
						}
						let strength = level_value * power;
						match at {
							Some(i) => light.effect[i].1 = strength,
							None => light.effect.push((c, strength)),
						}
						let d = [
							strength * lum[0] - old * applied[0],
							strength * lum[1] - old * applied[1],
							strength * lum[2] - old * applied[2],
						];
						Self::add_lum(level, &mut queue, z, c, d);
						self.corner_queue = queue;
					}
				}
				self.lights[id as usize] = Some(light);
			}
		}
	}

	/// The corner stage: each corner queued works out what it draws, and queues the lighting objects that draw it
	pub fn flush_corners(&mut self) {
		let mut queue = std::mem::take(&mut self.corner_queue);
		let maxx = self.maxx;
		let maxy = self.maxy;
		for &(z, c) in queue.iter() {
			let z = z as usize;
			let Some(level) = self.levels.get_mut(z).and_then(|l| l.as_mut()) else {
				continue;
			};
			let corner = &mut level.corners[c as usize];
			corner.needs_update = false;
			let changed = update_cache(corner);
			let unlit = corner.affecting.is_empty();
			if changed {
				let cx = c as i32 % (maxx + 1);
				let cy = c as i32 / (maxx + 1);
				// master_NE, master_SE, master_SW, master_NW
				for (x, y) in [(cx + 1, cy + 1), (cx + 1, cy), (cx, cy), (cx, cy + 1)] {
					if x < 1 || y < 1 || x > maxx || y > maxy {
						continue;
					}
					let t = ((y - 1) * maxx + (x - 1)) as usize;
					if level.flags[t] & OBJECT != 0 && !level.object_queued[t] {
						level.object_queued[t] = true;
						self.object_queue.push((z as u32, t as u32));
					}
				}
			}
			if unlit {
				// No light on it any more: DM deletes the corner here, float leftovers and all, and its lighting objects draw
				// it dark from then on; a corner it makes later starts from nothing
				let corner = &mut level.corners[c as usize];
				corner.lum = [0.0; 3];
				corner.bounce = [0.0; 3];
				corner.cache = [0.0; 3];
				corner.largest = 0.0;
			}
		}
		queue.clear();
		self.corner_queue = queue;
	}

	/// What a turf's lighting object draws: the SW, SE, NW and NE corners' colours, then the brightest of them
	pub fn object_values(&self, z: usize, turf: u32) -> [f32; 13] {
		let mut out = [0.0f32; 13];
		let Some(level) = self.levels.get(z).and_then(|l| l.as_ref()) else {
			return out;
		};
		let (x, y) = self.turf_xy(turf);
		let [ne, se, sw, nw] = self.turf_corners(x, y);
		let mut max = 0.0f32;
		for (i, c) in [sw, se, nw, ne].into_iter().enumerate() {
			let corner = &level.corners[c as usize];
			out[i * 3] = corner.cache[0];
			out[i * 3 + 1] = corner.cache[1];
			out[i * 3 + 2] = corner.cache[2];
			if i == 0 {
				max = corner.largest;
			} else {
				max = max.max(corner.largest);
			}
		}
		out[12] = max;
		out
	}

	/// Empties the lighting object queue without drawing anything: the shadow check, where DM draws
	pub fn drop_objects(&mut self) {
		for (z, t) in std::mem::take(&mut self.object_queue) {
			if let Some(level) = self.levels.get_mut(z as usize).and_then(|l| l.as_mut()) {
				level.object_queued[t as usize] = false;
			}
		}
	}

	/// Takes lighting objects off the queue, up to `max` of them
	pub fn take_objects(&mut self, max: usize, mut each: impl FnMut(u32, u32, [f32; 13])) -> usize {
		let n = self.object_queue.len().min(max);
		let taken: Vec<(u32, u32)> = self.object_queue.drain(..n).collect();
		for (z, t) in taken {
			let values = self.object_values(z as usize, t);
			if let Some(level) = self.levels.get_mut(z as usize).and_then(|l| l.as_mut()) {
				level.object_queued[t as usize] = false;
			}
			each(z, t, values);
		}
		self.object_queue.len()
	}

	/// get_lumcount()'s total: lum_r + lum_b + lum_g over the turf's corners, NE, SE, SW, NW
	pub fn lumcount(&self, z: usize, turf: u32) -> f32 {
		let Some(level) = self.levels.get(z).and_then(|l| l.as_ref()) else {
			return 0.0;
		};
		let (x, y) = self.turf_xy(turf);
		let mut total = 0.0f32;
		for c in self.turf_corners(x, y) {
			let corner = &level.corners[c as usize];
			total += corner.lum[0] + corner.lum[2] + corner.lum[1];
		}
		total
	}

	/// The lights on a turf's corners, each once
	pub fn affecting(&mut self, z: usize, turf: u32) -> Vec<u32> {
		let (x, y) = self.turf_xy(turf);
		let corners = self.turf_corners(x, y);
		let level = self.level(z);
		let mut out: Vec<u32> = Vec::new();
		for c in corners {
			for &id in level.corners[c as usize].affecting.iter() {
				if !out.contains(&id) {
					out.push(id);
				}
			}
		}
		out
	}

	/// Checks the books, as lighting_bench_check() does: every corner's light is what the lights on it say they give it,
	/// and corners and lights agree on which lights which. Returns the problems found.
	pub fn check(&self) -> Vec<String> {
		let mut problems = Vec::new();
		let mut expected: std::collections::HashMap<(usize, u32), [f64; 6]> = std::collections::HashMap::new();
		let mut holds: std::collections::HashMap<(usize, u32), Vec<u32>> = std::collections::HashMap::new();
		for (id, light) in self.lights.iter().enumerate() {
			let Some(light) = light else { continue };
			for &(c, s) in light.effect.iter() {
				let e = expected.entry((light.z, c)).or_insert([0.0; 6]);
				for k in 0..3 {
					e[k] += (s * light.applied[k]) as f64;
				}
				holds.entry((light.z, c)).or_default().push(id as u32);
			}
			for &(c, s, _) in light.bounce.iter() {
				let e = expected.entry((light.z, c)).or_insert([0.0; 6]);
				for k in 0..3 {
					e[3 + k] += (s * light.applied[k]) as f64;
				}
				holds.entry((light.z, c)).or_default().push(id as u32);
			}
		}
		for (z, level) in self.levels.iter().enumerate() {
			let Some(level) = level else { continue };
			for (c, corner) in level.corners.iter().enumerate() {
				let e = expected.get(&(z, c as u32)).copied().unwrap_or([0.0; 6]);
				for k in 0..3 {
					if (corner.lum[k] as f64 - e[k]).abs() > 0.001 || (corner.bounce[k] as f64 - e[3 + k]).abs() > 0.001 {
						let (cx, cy) = self.corner_xy(c as u32);
						problems.push(format!(
							"corner {},{},{} has {:?} {:?}, its lights give it {:?}",
							cx, cy, z, corner.lum, corner.bounce, e
						));
						break;
					}
				}
				let mut a = corner.affecting.clone();
				let mut b = holds.get(&(z, c as u32)).cloned().unwrap_or_default();
				a.sort_unstable();
				b.sort_unstable();
				if a != b {
					let (cx, cy) = self.corner_xy(c as u32);
					problems.push(format!(
						"corner {},{},{} thinks lights {:?} affect it, they say {:?}",
						cx, cy, z, a, b
					));
				}
			}
		}
		problems
	}
}

/// lighting_corner/update_objects()'s sums: returns whether what it draws changed
pub fn update_cache(corner: &mut Corner) -> bool {
	let mut lum_r = corner.lum[0];
	let mut lum_g = corner.lum[1];
	let mut lum_b = corner.lum[2];
	if corner.bounce[0] != 0.0 || corner.bounce[1] != 0.0 || corner.bounce[2] != 0.0 {
		lum_r += corner.bounce[0] * (1.0 - lum_r).clamp(0.0, 1.0);
		lum_g += corner.bounce[1] * (1.0 - lum_g).clamp(0.0, 1.0);
		lum_b += corner.bounce[2] * (1.0 - lum_b).clamp(0.0, 1.0);
	}
	let largest = lum_r.max(lum_g).max(lum_b);
	let mut factor = 1.0f32;
	if largest > 1.0 {
		factor = 1.0 / largest;
	}
	let old = corner.cache;
	corner.cache = [round_to(lum_r * factor), round_to(lum_g * factor), round_to(lum_b * factor)];
	corner.largest = round_to(largest);
	old != corner.cache
}

/// round(value, LIGHTING_ROUND_VALUE)
#[inline]
pub fn round_to(value: f32) -> f32 {
	(value / ROUND_VALUE + 0.5).floor() * ROUND_VALUE
}

#[cfg(test)]
mod tests {
	use super::*;

	fn flat_sheet(reach: i32, value: f32) -> Sheet {
		let dim = 2 * reach + 2;
		Sheet {
			dim,
			values: vec![value; (dim * dim) as usize],
		}
	}

	fn update(id: usize, x: i32, y: i32, reach: i32) -> Update {
		Update {
			id,
			z: 1,
			tx: x,
			ty: y,
			reach,
			power: 1.0,
			lum: [1.0, 0.5, 0.25],
			sheet: 0,
			spill_sheet: 0,
			vis_only: false,
			bounces: false,
			scatters: false,
			scatter_cutoff: 0.02,
			bounce_strength: 0.5,
			bounce_falloff: 0.5,
			bounce_cutoff: 0.02,
			bounce_depth: 3,
		}
	}

	#[test]
	fn a_light_lights_what_it_sees_and_takes_it_off_again() {
		let mut e = Engine::new(10, 10, 1);
		let sheet = flat_sheet(2, 0.5);
		e.set_sheet(0, sheet.dim, sheet.values.clone());
		for t in 0..100 {
			e.set_flags(1, t, DYNAMIC | OBJECT);
		}
		let seen: Vec<u32> = (0..100)
			.filter(|&t| {
				let (x, y) = (t as i32 % 10 + 1, t as i32 / 10 + 1);
				(x - 5).abs() <= 2 && (y - 5).abs() <= 2
			})
			.collect();
		e.update(&update(1, 5, 5, 2), &seen).unwrap();
		assert_eq!(e.lights[1].as_ref().unwrap().effect.len(), 36);
		let c = e.corner_index(5, 5);
		assert_eq!(e.levels[1].as_ref().unwrap().corners[c as usize].lum, [0.5, 0.25, 0.125]);
		assert!(e.check().is_empty());
		e.flush_corners();
		assert!(!e.object_queue.is_empty());
		e.remove(1);
		assert_eq!(e.levels[1].as_ref().unwrap().corners[c as usize].lum, [0.0, 0.0, 0.0]);
		assert!(e.check().is_empty());
	}

	#[test]
	fn rounding_matches_byond() {
		assert_eq!(round_to(0.5), 0.5);
		assert_eq!(round_to(1.0 / 128.0), 1.0 / 64.0);
		assert_eq!(round_to(0.0), 0.0);
	}
}
