//! BYOND's view() for a light: which turfs a light on (tx, ty) can see within `range` tiles, worked out from the turfs'
//! OPAQUE flags (has_opaque_atom) the way BYOND works it out. The steps are Lummox JR's description of BYOND's own
//! (https://www.byond.com/forum/post/2130277#comment20659267), with the line of sight as OpenDream has it
//! (OpenDreamShared/Dream/ViewAlgorithm.cs) and the lamp light from his description.
//!
//! update_corners() lights the light's turf up (luminosity reach + 1, or more for bounce light) so view() sees the whole
//! square: every clear turf in sight has a clear way back to the light no longer than its distance (its vis2 chain), so the
//! lamp light reaches it, and darkness can't hide it. Darkness and the wall and corner step only decide which opaque turfs
//! view() hands back, and update_corners() passes over opaque turfs. So the light only needs the line of sight (steps 3 to
//! 5) and the clear turfs in it, which is all `clear_only` works out. The rest is kept for the shadow check, which also sets
//! the opaque turfs against view()'s: those also depend on lamps the engine doesn't know about (a turf with no lighting
//! object has luminosity 1, as do computers and fire alarms) and on which areas are lit.
//!
//! The tiles are a square (2 * range + 1) wide around the light, x eastward and y northward from its south-west corner;
//! those off the map aren't there at all.

use crate::engine::{DYNAMIC, OPAQUE};

/// How an opaque turf takes lamp light from a clear neighbour: from any lit one, or only from one lit 2 or more
pub const LAMP_FROM_ANY: u8 = 0;
pub const LAMP_FROM_TWO: u8 = 1;

/// Step 9, walls and corners: all found first and then marked (OpenDream), or marked as they're found, going through the
/// square column by column (x) or row by row (y), each column or row upward or downward
pub const BOUNDARY_AFTER: u8 = 0;
pub const BOUNDARY_X_UP: u8 = 1;
pub const BOUNDARY_X_DOWN: u8 = 2;
pub const BOUNDARY_Y_UP: u8 = 3;
pub const BOUNDARY_Y_DOWN: u8 = 4;

pub struct ViewScratch {
	width: i32,
	present: Vec<bool>,
	opaque: Vec<bool>,
	unlit_area: Vec<bool>,
	vis: Vec<i32>,
	vis2: Vec<i32>,
	lamp: Vec<i32>,
	frontier: Vec<usize>,
	next: Vec<usize>,
	boundary: Vec<usize>,
}

impl Default for ViewScratch {
	fn default() -> Self {
		ViewScratch {
			width: 0,
			present: Vec::new(),
			opaque: Vec::new(),
			unlit_area: Vec::new(),
			vis: Vec::new(),
			vis2: Vec::new(),
			lamp: Vec::new(),
			frontier: Vec::new(),
			next: Vec::new(),
			boundary: Vec::new(),
		}
	}
}

/// What a view needs to know beyond the turfs
#[derive(Clone, Copy)]
pub struct ViewArgs {
	pub tx: i32,
	pub ty: i32,
	pub range: i32,
	/// The light's turf's luminosity while update_corners() looks around
	pub eye_lum: i32,
	pub lamp_rule: u8,
	/// Turfs that aren't dynamically lit count as lit (their area's luminosity)
	pub undynamic_lit: bool,
	/// BOUNDARY_AFTER and co.
	pub boundary: u8,
	/// Only the clear turfs in sight, and only what it takes to find them (what update_corners() uses)
	pub clear_only: bool,
}

impl ViewScratch {
	#[inline]
	fn at(&self, x: i32, y: i32) -> usize {
		(y * self.width + x) as usize
	}

	/// Any neighbour of (x, y) that's there with `values` == d
	#[inline]
	fn neighbour_is(&self, values: &[i32], x: i32, y: i32, d: i32) -> bool {
		let w = self.width;
		for ny in (y - 1).max(0)..(y + 2).min(w) {
			for nx in (x - 1).max(0)..(x + 2).min(w) {
				if nx == x && ny == y {
					continue;
				}
				let i = (ny * w + nx) as usize;
				if self.present[i] && values[i] == d {
					return true;
				}
			}
		}
		false
	}

	fn is_corner(&self, x: i32, y: i32, dx: i32, dy: i32) -> bool {
		let (diag_x, diag_y) = (x + dx, y + dy);
		let w = self.width;
		if diag_x < 0 || diag_y < 0 || diag_x >= w || diag_y >= w {
			return false;
		}
		let diagonal = self.at(diag_x, diag_y);
		if !self.present[diagonal] {
			return false;
		}
		let cardinal1 = self.at(x, diag_y);
		let cardinal2 = self.at(diag_x, y);
		self.vis[diagonal] != 0
			&& self.vis[cardinal1] != 0
			&& self.vis[cardinal2] != 0
			&& self.opaque[cardinal1]
			&& self.opaque[cardinal2]
			&& !self.opaque[diagonal]
	}

	/// The turfs seen, numbered as the engine numbers them on the light's z-level, into `out` (cleared first): each row from
	/// west to east, the rows from south to north. `flags` are the z-level's turf flags.
	pub fn view(&mut self, flags: &[u8], maxx: i32, maxy: i32, a: &ViewArgs, out: &mut Vec<u32>) {
		out.clear();
		let r = a.range.max(0);
		let w = 2 * r + 1;
		let n = (w * w) as usize;
		self.width = w;
		self.present.clear();
		self.present.resize(n, false);
		self.opaque.clear();
		self.opaque.resize(n, false);
		self.unlit_area.clear();
		self.unlit_area.resize(n, false);
		self.vis.clear();
		self.vis.resize(n, 0);
		self.vis2.clear();
		self.vis2.resize(n, 0);
		self.lamp.clear();
		self.lamp.resize(n, 0);

		// Step 1: the tiles
		let (x0, y0) = (a.tx - r, a.ty - r);
		for j in 0..w {
			let y = y0 + j;
			if y < 1 || y > maxy {
				continue;
			}
			for i in 0..w {
				let x = x0 + i;
				if x < 1 || x > maxx {
					continue;
				}
				let f = flags[((y - 1) * maxx + (x - 1)) as usize];
				let k = (j * w + i) as usize;
				self.present[k] = true;
				self.opaque[k] = f & OPAQUE != 0;
				self.unlit_area[k] = !(a.undynamic_lit && f & DYNAMIC == 0);
			}
		}
		let (ex, ey) = (r, r);
		let eye = self.at(ex, ey);

		// Step 3, the diagonal shadows: rings outward, into vis2
		let highest_max = (w - ex).max(w - ey);
		for d in 0..highest_max {
			let lower_x = ex - d - 1;
			let upper_x = ex + d + 1;
			for x in lower_x.max(0)..=upper_x.min(w - 1) {
				let mut y = ey - d - 1;
				let upper_y = ey + d + 1;
				let skip_middle = x != lower_x && x != upper_x;
				if y < 0 {
					y = if skip_middle { upper_y } else { 0 };
				}
				while y <= upper_y && y < w {
					let k = self.at(x, y);
					if self.present[k] && self.neighbour_is(&self.vis2, x, y, d) {
						self.vis2[k] = if self.opaque[k] { -1 } else { d + 1 };
					}
					if skip_middle && y != upper_y {
						y = upper_y;
					} else {
						y += 1;
					}
				}
			}
		}

		// Step 4, the straight shadows: diamonds outward, into vis
		let highest_sum = (w - ex) + (w - ey);
		for d in 0..highest_sum {
			let lower_x = (ex - d - 1).max(0);
			let upper_x = (ex + d + 1).min(w - 1);
			for x in lower_x..=upper_x {
				let offset = (d + 1) - (ex - x).abs();
				self.straight(x, ey - offset, d);
				if offset != 0 {
					self.straight(x, ey + offset, d);
				}
			}
		}

		// Step 5, the eye
		if self.present[eye] {
			self.vis[eye] = 1;
		}

		if a.clear_only {
			self.emit_all(r, x0, y0, maxx, true, out);
			return;
		}

		// Step 6, the lamp light, from the light's turf: a clear turf takes a neighbour's less one, an opaque one 1
		if self.present[eye] && a.eye_lum > 0 {
			self.lamp[eye] = a.eye_lum;
			self.frontier.clear();
			self.frontier.push(eye);
			let need = if a.lamp_rule == LAMP_FROM_TWO { 2 } else { 1 };
			while !self.frontier.is_empty() {
				self.next.clear();
				for fi in 0..self.frontier.len() {
					let k = self.frontier[fi];
					let v = self.lamp[k];
					let (x, y) = (k as i32 % w, k as i32 / w);
					for ny in (y - 1).max(0)..(y + 2).min(w) {
						for nx in (x - 1).max(0)..(x + 2).min(w) {
							let m = (ny * w + nx) as usize;
							if m == k || !self.present[m] {
								continue;
							}
							if self.opaque[m] {
								if v >= need && self.lamp[m] < 1 {
									self.lamp[m] = 1;
								}
							} else if v - 1 > self.lamp[m] {
								self.lamp[m] = v - 1;
								self.next.push(m);
							}
						}
					}
				}
				std::mem::swap(&mut self.frontier, &mut self.next);
			}
		}

		// Step 8: what's dark goes, unless its area is lit
		for k in 0..n {
			if self.present[k] {
				self.vis2[k] = self.vis[k];
				if self.lamp[k] == 0 && self.unlit_area[k] {
					self.vis[k] = 0;
				}
			}
		}

		// Step 9: walls and corners between what's seen
		self.boundary.clear();
		let in_place = a.boundary != BOUNDARY_AFTER;
		for outer in 0..w {
			for inner in 0..w {
				let (x, y) = match a.boundary {
					BOUNDARY_X_UP => (outer, inner),
					BOUNDARY_X_DOWN => (outer, w - 1 - inner),
					BOUNDARY_Y_UP => (inner, outer),
					BOUNDARY_Y_DOWN => (inner, w - 1 - outer),
					_ => (outer, inner),
				};
				let k = self.at(x, y);
				if !self.present[k] || !self.opaque[k] || self.vis[k] != 0 {
					continue;
				}
				if self.is_boundary(x, y) {
					if in_place {
						self.vis[k] = -1;
					} else {
						self.boundary.push(k);
					}
				}
			}
		}
		for bi in 0..self.boundary.len() {
			let k = self.boundary[bi];
			self.vis[k] = -1;
		}

		self.emit_all(r, x0, y0, maxx, false, out);
	}

	/// What view() hands back is in rings outward from the light, each ring from west to east and each column of it from
	/// south to north
	fn emit_all(&self, r: i32, x0: i32, y0: i32, maxx: i32, clear_only: bool, out: &mut Vec<u32>) {
		for d in 0..=r {
			for dx in -d..=d {
				let i = r + dx;
				if dx == -d || dx == d {
					for dy in -d..=d {
						self.emit(i, r + dy, x0, y0, maxx, clear_only, out);
					}
				} else {
					self.emit(i, r - d, x0, y0, maxx, clear_only, out);
					if d != 0 {
						self.emit(i, r + d, x0, y0, maxx, clear_only, out);
					}
				}
			}
		}
	}

	#[inline]
	fn emit(&self, i: i32, j: i32, x0: i32, y0: i32, maxx: i32, clear_only: bool, out: &mut Vec<u32>) {
		let k = (j * self.width + i) as usize;
		if self.present[k] && self.vis[k] != 0 && !(clear_only && self.opaque[k]) {
			out.push(((y0 + j - 1) * maxx + (x0 + i - 1)) as u32);
		}
	}

	/// Step 9's test: an opaque turf between two seen ones in a line, or the corner of two seen walls round a seen floor
	fn is_boundary(&self, x: i32, y: i32) -> bool {
		let w = self.width;
		if x != 0 && x != w - 1 {
			let (east, west) = (self.at(x - 1, y), self.at(x + 1, y));
			if self.present[east] && self.present[west] && self.vis[east] != 0 && self.vis[west] != 0 {
				return true;
			}
		}
		if y != 0 && y != w - 1 {
			let (north, south) = (self.at(x, y - 1), self.at(x, y + 1));
			if self.present[north] && self.present[south] && self.vis[north] != 0 && self.vis[south] != 0 {
				return true;
			}
		}
		self.is_corner(x, y, 1, 1) || self.is_corner(x, y, 1, -1) || self.is_corner(x, y, -1, -1) || self.is_corner(x, y, -1, 1)
	}

	/// The last view's visibility and lamp light, for a report: vis then lamp for each turf of the square, rows south to north
	pub fn dump(&self) -> String {
		let w = self.width;
		let mut s = String::new();
		for j in (0..w).rev() {
			for i in 0..w {
				let k = (j * w + i) as usize;
				s.push_str(&format!("{:>3}/{:<2}", self.vis[k], self.lamp[k]));
			}
			s.push('\n');
		}
		s
	}

	#[inline]
	fn straight(&mut self, x: i32, y: i32, d: i32) {
		if y < 0 || y >= self.width {
			return;
		}
		let k = self.at(x, y);
		if self.present[k] && self.neighbour_is(&self.vis, x, y, d) {
			if self.opaque[k] {
				self.vis[k] = -1;
			} else if self.vis2[k] != 0 {
				self.vis[k] = d + 1;
			}
		}
	}

	/// A picture of the last view's square for a report, north at the top: '#' opaque, '.' clear, ' ' off the map, '@' the
	/// light; `mark(turf)` can put something else on a turf (it gets the engine's number for it)
	pub fn picture(&self, maxx: i32, a: &ViewArgs, mark: impl Fn(u32) -> Option<char>) -> String {
		let r = a.range.max(0);
		let w = 2 * r + 1;
		let (x0, y0) = (a.tx - r, a.ty - r);
		let mut s = String::new();
		for j in (0..w).rev() {
			for i in 0..w {
				let k = (j * w + i) as usize;
				let c = if k >= self.present.len() || !self.present[k] {
					' '
				} else {
					let turf = ((y0 + j - 1) * maxx + (x0 + i - 1)) as u32;
					if let Some(c) = mark(turf) {
						c
					} else if i == r && j == r {
						'@'
					} else if self.opaque[k] {
						'#'
					} else {
						'.'
					}
				};
				s.push(c);
			}
			s.push('\n');
		}
		s
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn run(map: &[&str], tx: i32, ty: i32, range: i32) -> Vec<(i32, i32)> {
		let maxy = map.len() as i32;
		let maxx = map[0].len() as i32;
		let mut flags = vec![DYNAMIC; (maxx * maxy) as usize];
		for (row, line) in map.iter().enumerate() {
			let y = maxy - row as i32; // the first line is the north edge
			for (col, c) in line.chars().enumerate() {
				if c == '#' {
					flags[((y - 1) * maxx + col as i32) as usize] |= OPAQUE;
				}
			}
		}
		let mut scratch = ViewScratch::default();
		let mut out = Vec::new();
		let a = ViewArgs { tx, ty, range, eye_lum: range + 1, lamp_rule: LAMP_FROM_ANY, undynamic_lit: false, boundary: BOUNDARY_AFTER, clear_only: false };
		scratch.view(&flags, maxx, maxy, &a, &mut out);
		out.iter().map(|&t| (t as i32 % maxx + 1 - tx, t as i32 / maxx + 1 - ty)).collect()
	}

	#[test]
	fn open_square_sees_everything() {
		let map = [".....", ".....", ".....", ".....", "....."];
		assert_eq!(run(&map, 3, 3, 2).len(), 25);
	}

	#[test]
	fn a_wall_hides_what_is_behind_it() {
		// The light at (3, 3); a wall line at y = 4 from x = 1 to 5: the wall shows, the row above it doesn't
		let map = [".....", "#####", ".....", ".....", "....."];
		let seen = run(&map, 3, 3, 2);
		assert!(seen.contains(&(0, 1)), "the wall right above is seen");
		assert!(!seen.contains(&(0, 2)), "what's behind the wall isn't");
		assert!(seen.contains(&(0, -2)), "the open floor below is");
	}
}
