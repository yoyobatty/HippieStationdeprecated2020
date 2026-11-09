//! The bots' floods (bot_pathing_permissive.dm), breadth first, a level at a time, with the same answers about tiles as a search
//! (search.rs) and the station picture (picture.rs) answering what it knows:
//! - forward, bot_flood_reachable(): every tile reachable from the start within so many steps
//! - backward, bot_sealed_pocket(): every tile that can reach the start (there the destination), stopping at the bot's own tile or
//!   at too many tiles
//!
//! Which tiles a flood reaches doesn't depend on the order it looks at them in, only on the steps it's allowed, so the set is
//! the one DM's flood finds.

use crate::picture::Picture;
use crate::search::{reverse, FastMap, DIRS};

/// No tile: where a backward flood starts there's no search start to answer differently for
pub const NO_TILE: u32 = u32::MAX;

pub struct FloodSettings {
	pub maxx: i32,
	pub maxy: i32,
	pub per_level: u32,
	pub start: u32,
	/// Backward: "can that tile step onto this one" instead of "can this tile step onto that one"
	pub backward: bool,
	/// Levels to go out at most (0 for no limit)
	pub max_steps: u32,
	/// Stop, too big, once this many tiles are in it (0 for no limit)
	pub max_tiles: usize,
	/// Stop if this tile is reached (the bot's own, for a backward flood)
	pub stop_at: u32,
	/// Stop too if it reaches a hallway tile (Picture::is_hub())
	pub stop_at_hub: bool,
	pub simulated_only: bool,
	pub use_picture: bool,
}

pub enum FloodOutcome {
	/// Wants the tiles in `asked` told about, then step() again
	Need,
	/// Finished: every tile reached, whether it reached `stop_at`, whether it grew past `max_tiles`
	Done(Vec<u32>, bool, bool),
}

pub struct Flood {
	s: FloodSettings,
	classes: FastMap<u32, u32>,
	reached: FastMap<u32, ()>,
	order: Vec<u32>,
	frontier: Vec<u32>,
	steps: u32,
	pub asked: Vec<u32>,
	pub tiles_asked: usize,
	pub picture_hits: usize,
	pub rounds: usize,
}

const ASKED: u32 = u32::MAX;

impl Flood {
	pub fn new(s: FloodSettings) -> Flood {
		let mut reached = FastMap::default();
		reached.insert(s.start, ());
		let start = s.start;
		Flood { s, classes: FastMap::default(), reached, order: vec![start], frontier: vec![start], steps: 0, asked: Vec::new(), tiles_asked: 0, picture_hits: 0, rounds: 0 }
	}

	pub fn answer(&mut self, answers: &[u32]) -> Result<(), String> {
		if answers.len() != self.asked.len() {
			return Err(format!("{} answers for {} tiles", answers.len(), self.asked.len()));
		}
		for (i, &turf) in self.asked.iter().enumerate() {
			self.classes.insert(turf, answers[i]);
		}
		self.asked.clear();
		Ok(())
	}

	fn step_turf(&self, turf: u32, dir: u8) -> Option<u32> {
		let level = turf / self.s.per_level * self.s.per_level;
		let local = turf % self.s.per_level;
		let (mut x, mut y) = ((local % self.s.maxx as u32) as i32, (local / self.s.maxx as u32) as i32);
		match dir {
			1 => y += 1,
			2 => y -= 1,
			4 => x += 1,
			_ => x -= 1,
		}
		if x < 0 || y < 0 || x >= self.s.maxx || y >= self.s.maxy {
			return None;
		}
		Some(level + (y * self.s.maxx + x) as u32)
	}

	fn class(&self, turf: u32) -> u32 {
		*self.classes.get(&turf).unwrap_or(&0)
	}

	/// Can a bot step from `from` onto `to`, going `dir`?
	fn allowed(&self, from: u32, to: u32, dir: u8) -> bool {
		self.class(from) & ((dir as u32) << 4) == 0 && self.class(to) & reverse(dir) as u32 == 0
	}

	fn want(&mut self, picture: &Picture, turf: u32) {
		if self.classes.contains_key(&turf) {
			return;
		}
		if self.s.use_picture {
			if let Some(answer) = picture.answer(turf, self.s.start, self.s.simulated_only) {
				self.classes.insert(turf, answer);
				self.picture_hits += 1;
				return;
			}
		}
		self.classes.insert(turf, ASKED);
		self.asked.push(turf);
	}

	pub fn step(&mut self, picture: &Picture) -> FloodOutcome {
		self.rounds += 1;
		loop {
			if self.frontier.is_empty() || (self.s.max_steps != 0 && self.steps >= self.s.max_steps) {
				return FloodOutcome::Done(std::mem::take(&mut self.order), false, false);
			}
			// what this level needs: the frontier's tiles and their neighbours not reached yet
			let frontier = std::mem::take(&mut self.frontier);
			for &t in &frontier {
				self.want(picture, t);
				for dir in DIRS {
					if let Some(n) = self.step_turf(t, dir) {
						if !self.reached.contains_key(&n) {
							self.want(picture, n);
						}
					}
				}
			}
			if !self.asked.is_empty() {
				self.frontier = frontier;
				self.tiles_asked += self.asked.len();
				return FloodOutcome::Need;
			}
			self.steps += 1;
			let mut next = Vec::new();
			for &t in &frontier {
				for dir in DIRS {
					let Some(n) = self.step_turf(t, dir) else {
						continue;
					};
					if self.reached.contains_key(&n) {
						continue;
					}
					let ok = if self.s.backward { self.allowed(n, t, reverse(dir)) } else { self.allowed(t, n, dir) };
					if !ok {
						continue;
					}
					if n == self.s.stop_at || (self.s.stop_at_hub && picture.is_hub(n)) {
						return FloodOutcome::Done(std::mem::take(&mut self.order), true, false);
					}
					self.reached.insert(n, ());
					self.order.push(n);
					if self.s.max_tiles != 0 && self.order.len() > self.s.max_tiles {
						return FloodOutcome::Done(std::mem::take(&mut self.order), false, true);
					}
					next.push(n);
				}
			}
			self.frontier = next;
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn grid(map: &[&str]) -> (i32, i32, FastMap<char, u32>, Vec<u32>) {
		let maxy = map.len() as i32;
		let maxx = map[0].len() as i32;
		let mut marks = FastMap::default();
		let mut walls = Vec::new();
		for (row, line) in map.iter().enumerate() {
			let y = maxy - 1 - row as i32;
			for (x, c) in line.chars().enumerate() {
				let id = (y * maxx + x as i32) as u32;
				match c {
					'#' => walls.push(id),
					'.' => {}
					other => {
						marks.insert(other, id);
					}
				}
			}
		}
		(maxx, maxy, marks, walls)
	}

	fn flood(map: &[&str], from: char, backward: bool, stop: Option<char>, max_tiles: usize) -> FloodOutcome {
		let (maxx, maxy, marks, walls) = grid(map);
		let mut f = Flood::new(FloodSettings {
			maxx,
			maxy,
			per_level: (maxx * maxy) as u32,
			start: marks[&from],
			backward,
			max_steps: 0,
			max_tiles,
			stop_at: stop.map(|c| marks[&c]).unwrap_or(NO_TILE),
			stop_at_hub: false,
			simulated_only: false,
			use_picture: false,
		});
		let picture = Picture::default();
		loop {
			match f.step(&picture) {
				FloodOutcome::Need => {
					let answers: Vec<u32> = f.asked.iter().map(|t| if walls.contains(t) { 15 } else { 0 }).collect();
					f.answer(&answers).unwrap();
				}
				done => return done,
			}
		}
	}

	#[test]
	fn forward_room() {
		match flood(&["S.#..", "..#..", "..#.."], 'S', false, None, 0) {
			FloodOutcome::Done(tiles, stopped, big) => {
				assert_eq!(tiles.len(), 6);
				assert!(!stopped && !big);
			}
			_ => panic!(),
		}
	}

	#[test]
	fn backward_pocket_and_stops() {
		// dest D shut in with one tile; walls reached as leaves, as DM's flood adds them (it only asks the tile stepped onto)
		match flood(&["#####", "#D.#B", "#####"], 'D', true, Some('B'), 300) {
			FloodOutcome::Done(tiles, stopped, big) => {
				assert!(!stopped && !big);
				assert!(tiles.len() >= 2);
			}
			_ => panic!(),
		}
		match flood(&["D...B"], 'D', true, Some('B'), 300) {
			FloodOutcome::Done(_, stopped, _) => assert!(stopped),
			_ => panic!(),
		}
		match flood(&["D....", ".....", "....."], 'D', true, None, 5) {
			FloodOutcome::Done(_, _, big) => assert!(big),
			_ => panic!(),
		}
	}
}
