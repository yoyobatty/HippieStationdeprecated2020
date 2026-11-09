//! One A* search, step for step the same as AStar() in code/__HELPERS/AStar.dm: the same open list (a binary heap kept in a
//! list, with the same comparisons and swaps), the same node weights worked out in the same single precision, so the same
//! node comes off it at every step and every path is the same one, not just as short.
//!
//! What it doesn't know is what a tile lets a bot do: DM says that (bot_path_engine.dm), one tile at a time, the first time
//! the search needs it. A search runs until it needs a tile it hasn't been told about, asks for that one and the ones it will
//! likely need next, and DM answers and lets it go on.
//!
//! What DM says for a tile, as one number:
//! - bits 0-3: stepping onto it from the neighbour that way is refused (NORTH 1, SOUTH 2, EAST 4, WEST 8: the direction from
//!   this tile to the one stepped from)
//! - bits 4-7: stepping off it that way is refused (a window or windoor on it facing that way)
//! - bits 8 and up: its penalty, for the bots' weighted searches (bot_turf_penalty())

use crate::picture::Picture;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

pub const DIRS: [u8; 4] = [1, 2, 4, 8];

/// get_dir()'s opposite, as AStar() works it out: swapping the odd and even bits
pub fn reverse(dir: u8) -> u8 {
	((dir & 0x55) << 1) | ((dir & 0xAA) >> 1)
}

/// Fx hashing: turf numbers are spread well enough already
#[derive(Default)]
pub struct FxHasher(u64);

impl Hasher for FxHasher {
	fn finish(&self) -> u64 {
		self.0
	}
	fn write(&mut self, bytes: &[u8]) {
		for &b in bytes {
			self.0 = (self.0.rotate_left(5) ^ b as u64).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
		}
	}
	fn write_u32(&mut self, n: u32) {
		self.0 = (self.0.rotate_left(5) ^ n as u64).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
	}
}

pub type FastMap<K, V> = HashMap<K, V, BuildHasherDefault<FxHasher>>;

/// The two costs the bots use: Distance_cardinal() (a step is 1, the estimate the Manhattan distance) and bot_weighted_distance()
/// (a step is 1 and the tile's penalty, the estimate the Manhattan distance and the end tile's penalty)
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Cost {
	Cardinal,
	Weighted,
}

/// PF_TIEBREAKER: f = g + h * (1 + 0.005)
const TIEBREAK: f32 = 1.0f32 + 0.005f32;

/// A tile asked about and not answered yet
const ASKED: u32 = u32::MAX;
const NONE: u32 = u32::MAX;

#[derive(Clone, Copy)]
struct Node {
	turf: u32,
	prev: u32,
	f: f32,
	g: f32,
	h: f32,
	nt: i32,
	bf: u8,
}

pub struct Settings {
	pub maxx: i32,
	pub maxy: i32,
	pub per_level: u32,
	pub start: u32,
	pub end: u32,
	/// 0 for no limit
	pub maxnodedepth: i32,
	/// 0 for none
	pub mintargetdist: f32,
	pub cost: Cost,
	pub end_penalty: f32,
	pub exclude: Option<u32>,
	/// How many of the nodes next on the open list to ask about the tiles of too, when it has to ask (0: only what it needs now)
	pub ahead: usize,
	/// AStar()'s simulated_only: the station picture's open space is asked about then
	pub simulated_only: bool,
	/// Take what the station picture knows instead of asking DM (picture.rs)
	pub use_picture: bool,
}

pub enum Outcome {
	/// Wants the tiles in `asked` told about, then step() again
	Need,
	/// The path, start to end, and how many tiles the search opened
	Found(Vec<u32>, usize),
	/// No path: every tile it opened, and whether maxnodedepth stopped it expanding any
	NoRoute(Vec<u32>, bool),
	/// Something AStar() itself would have had a runtime error over: let DM's own search do it
	Abort(&'static str),
}

pub struct Search {
	s: Settings,
	end_x: i32,
	end_y: i32,
	nodes: Vec<Node>,
	/// The open list, from 1 like DM's list (heap[0] is unused)
	heap: Vec<u32>,
	/// Each node's place in the heap, 0 when it isn't in it
	pos: Vec<u32>,
	openc: FastMap<u32, u32>,
	classes: FastMap<u32, u32>,
	/// A node taken off the open list that is waiting for its tiles
	pending: u32,
	started: bool,
	depth_cut: bool,
	ahead: usize,
	/// The tiles to tell it about, in order
	pub asked: Vec<u32>,
	/// Tiles DM was asked about, for the stats
	pub tiles_asked: usize,
	/// Tiles the station picture answered instead
	pub picture_hits: usize,
	pub rounds: usize,
}

impl Search {
	pub fn new(s: Settings) -> Search {
		let local = s.end % s.per_level;
		let (end_x, end_y) = ((local % s.maxx as u32) as i32, (local / s.maxx as u32) as i32);
		let ahead = s.ahead;
		Search {
			s,
			end_x,
			end_y,
			nodes: Vec::new(),
			heap: vec![NONE],
			pos: Vec::new(),
			openc: FastMap::default(),
			classes: FastMap::default(),
			pending: NONE,
			started: false,
			depth_cut: false,
			ahead,
			asked: Vec::new(),
			tiles_asked: 0,
			picture_hits: 0,
			rounds: 0,
		}
	}

	/// What DM said about the tiles last asked about, in the same order
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

	/// The estimate from a tile: its Manhattan distance to the end, and the end's penalty for the weighted cost
	fn estimate(&self, turf: u32) -> f32 {
		let local = turf % self.s.per_level;
		let (x, y) = ((local % self.s.maxx as u32) as i32, (local / self.s.maxx as u32) as i32);
		let manhattan = ((x - self.end_x).abs() + (y - self.end_y).abs()) as f32;
		if self.s.cost == Cost::Weighted {
			manhattan + self.s.end_penalty
		} else {
			manhattan
		}
	}

	/// PathNode's f. DM rounds to single precision after each step, as this does (checked in BYOND 516.1688, 2026-11-08: 60 of 60
	/// weights where rounding once would differ came out this way)
	fn weight(&self, g: f32, h: f32) -> f32 {
		g + h * TIEBREAK
	}

	fn add_node(&mut self, turf: u32, prev: u32, g: f32, h: f32, nt: i32, bf: u8) -> u32 {
		let f = self.weight(g, h);
		self.nodes.push(Node { turf, prev, f, g, h, nt, bf });
		self.pos.push(0);
		(self.nodes.len() - 1) as u32
	}

	fn swim(&mut self, mut index: usize) {
		let node = self.heap[index];
		let node_f = self.nodes[node as usize].f;
		let mut parent = index / 2;
		while parent > 0 {
			let above = self.heap[parent];
			if node_f >= self.nodes[above as usize].f {
				break;
			}
			self.heap[index] = above;
			self.pos[above as usize] = index as u32;
			index = parent;
			parent = index / 2;
		}
		self.heap[index] = node;
		self.pos[node as usize] = index as u32;
	}

	fn sink(&mut self, mut index: usize) {
		let count = self.heap.len() - 1;
		let node = self.heap[index];
		let node_f = self.nodes[node as usize].f;
		let mut child = index * 2;
		while child <= count {
			let mut below = self.heap[child];
			if child < count {
				let right = self.heap[child + 1];
				if self.nodes[right as usize].f < self.nodes[below as usize].f {
					child += 1;
					below = right;
				}
			}
			if self.nodes[below as usize].f >= node_f {
				break;
			}
			self.heap[index] = below;
			self.pos[below as usize] = index as u32;
			index = child;
			child = index * 2;
		}
		self.heap[index] = node;
		self.pos[node as usize] = index as u32;
	}

	fn pop(&mut self) -> u32 {
		let count = self.heap.len() - 1;
		let top = self.heap[1];
		self.heap[1] = self.heap[count];
		self.heap.truncate(count);
		self.pos[top as usize] = 0;
		if count > 1 {
			self.pos[self.heap[1] as usize] = 1;
			self.sink(1);
		}
		top
	}

	fn push(&mut self, node: u32) {
		self.heap.push(node);
		let at = self.heap.len() - 1;
		self.swim(at);
	}

	fn known(&self, turf: u32) -> bool {
		self.classes.get(&turf).is_some_and(|&c| c != ASKED)
	}

	/// Asks for this node's tile and its neighbours it will look at, if not known or asked for already. What the station picture
	/// knows it takes from there.
	fn ask_around(&mut self, picture: &Picture, node: u32) {
		let n = self.nodes[node as usize];
		let ask = |search: &mut Search, turf: u32| {
			if !search.classes.contains_key(&turf) {
				if search.s.use_picture {
					if let Some(answer) = picture.answer(turf, search.s.start, search.s.simulated_only) {
						search.classes.insert(turf, answer);
						search.picture_hits += 1;
						return;
					}
				}
				search.classes.insert(turf, ASKED);
				search.asked.push(turf);
			}
		};
		ask(self, n.turf);
		for dir in DIRS {
			if n.bf & dir == 0 {
				continue;
			}
			if let Some(t) = self.step_turf(n.turf, dir) {
				if Some(t) != self.s.exclude {
					ask(self, t);
				}
			}
		}
	}

	fn has_all(&self, node: u32) -> bool {
		let n = self.nodes[node as usize];
		if !self.known(n.turf) {
			return false;
		}
		for dir in DIRS {
			if n.bf & dir == 0 {
				continue;
			}
			if let Some(t) = self.step_turf(n.turf, dir) {
				if Some(t) != self.s.exclude && !self.known(t) {
					return false;
				}
			}
		}
		true
	}

	fn class(&self, turf: u32) -> u32 {
		*self.classes.get(&turf).unwrap_or(&0)
	}

	fn penalty(&self, turf: u32) -> f32 {
		(self.class(turf) >> 8) as f32
	}

	/// Can a bot step from `from` onto `to`, going `dir`?
	fn allowed(&self, from: u32, to: u32, dir: u8) -> bool {
		self.class(from) & ((dir as u32) << 4) == 0 && self.class(to) & reverse(dir) as u32 == 0
	}

	/// Runs until it finishes or needs tiles told about (in `asked`)
	pub fn step(&mut self, picture: &Picture) -> Outcome {
		if !self.started {
			self.started = true;
			let h = self.estimate(self.s.start);
			let start = self.add_node(self.s.start, NONE, 0.0, h, 0, 15);
			self.push(start);
			self.openc.insert(self.s.start, start);
		}
		self.rounds += 1;
		loop {
			let cur = if self.pending != NONE {
				std::mem::replace(&mut self.pending, NONE)
			} else {
				if self.heap.len() <= 1 {
					let opened = self.nodes.iter().map(|n| n.turf).collect();
					return Outcome::NoRoute(opened, self.depth_cut);
				}
				self.pop()
			};
			let n = self.nodes[cur as usize];
			let close_enough = self.s.mintargetdist != 0.0 && self.estimate(n.turf) <= self.s.mintargetdist;
			if n.turf == self.s.end || close_enough {
				let mut path = vec![n.turf];
				let mut at = n.prev;
				while at != NONE {
					path.push(self.nodes[at as usize].turf);
					at = self.nodes[at as usize].prev;
				}
				path.reverse();
				return Outcome::Found(path, self.openc.len());
			}
			if self.s.maxnodedepth == 0 || n.nt <= self.s.maxnodedepth {
				if !self.has_all(cur) {
					self.ask_around(picture, cur);
					// and the tiles of the nodes likely to come off the open list next, more each time a search goes on
					let ahead = self.ahead.min(self.heap.len() - 1);
					for i in 1..=ahead {
						let node = self.heap[i];
						self.ask_around(picture, node);
					}
					if !self.asked.is_empty() {
						self.pending = cur;
						self.tiles_asked += self.asked.len();
						return Outcome::Need;
					}
					// the station picture knew them all: on without asking DM
				}
				if let Err(why) = self.expand(cur) {
					return Outcome::Abort(why);
				}
			} else {
				self.depth_cut = true;
			}
			self.nodes[cur as usize].bf = 0;
		}
	}

	fn expand(&mut self, cur: u32) -> Result<(), &'static str> {
		for dir in DIRS {
			let n = self.nodes[cur as usize];
			if n.bf & dir == 0 {
				continue;
			}
			let Some(t) = self.step_turf(n.turf, dir) else {
				continue;
			};
			if Some(t) == self.s.exclude {
				continue;
			}
			let r = reverse(dir);
			let newg = n.g + if self.s.cost == Cost::Weighted { 1.0 + self.penalty(t) } else { 1.0 };
			if let Some(&cn) = self.openc.get(&t) {
				self.nodes[cn as usize].bf &= 15 ^ r;
				if newg < self.nodes[cn as usize].g && self.allowed(n.turf, t, dir) {
					let h = self.nodes[cn as usize].h;
					let f = self.weight(newg, h);
					let node = &mut self.nodes[cn as usize];
					node.prev = cur;
					node.g = newg;
					node.f = f;
					node.nt = n.nt + 1;
					let at = self.pos[cn as usize] as usize;
					if at == 0 {
						// open.Find() gives 0 for a node no longer on the open list, and AStar() indexes the list with it
						return Err("a closed node got a shorter way in");
					}
					self.swim(at);
					self.sink(at);
				}
			} else if self.allowed(n.turf, t, dir) {
				let h = self.estimate(t);
				let node = self.add_node(t, cur, newg, h, n.nt + 1, 15 ^ r);
				self.push(node);
				self.openc.insert(t, node);
			}
		}
		Ok(())
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	/// A grid with walls ('#') and answers made from it, searched start to end
	fn run(map: &[&str], cost: Cost) -> (Outcome, usize) {
		run_with(map, cost, false)
	}

	/// The same, with a station picture that knows every tile already if `pictured`
	fn run_with(map: &[&str], cost: Cost, pictured: bool) -> (Outcome, usize) {
		let maxy = map.len() as i32;
		let maxx = map[0].len() as i32;
		let mut start = 0;
		let mut end = 0;
		let mut walls = Vec::new();
		for (row, line) in map.iter().enumerate() {
			let y = maxy - 1 - row as i32;
			for (x, c) in line.chars().enumerate() {
				let id = (y * maxx + x as i32) as u32;
				match c {
					'S' => start = id,
					'E' => end = id,
					'#' => walls.push(id),
					_ => {}
				}
			}
		}
		let mut s = Search::new(Settings {
			maxx,
			maxy,
			per_level: (maxx * maxy) as u32,
			start,
			end,
			maxnodedepth: 0,
			mintargetdist: 0.0,
			cost,
			end_penalty: 0.0,
			exclude: None,
			ahead: 0,
			simulated_only: false,
			use_picture: pictured,
		});
		let mut picture = Picture::new((maxx * maxy) as usize);
		if pictured {
			for id in 0..(maxx * maxy) as u32 {
				picture.set(id, if walls.contains(&id) { crate::picture::SOLID } else { crate::picture::OPEN });
			}
		}
		let mut rounds = 0;
		loop {
			match s.step(&picture) {
				Outcome::Need => {
					rounds += 1;
					let answers: Vec<u32> = s.asked.iter().map(|t| if walls.contains(t) { 15 } else { 0 }).collect();
					s.answer(&answers).unwrap();
				}
				other => return (other, rounds),
			}
		}
	}

	#[test]
	fn finds_a_way_round() {
		let (outcome, _) = run(&["S.#..", "..#..", "....E"], Cost::Cardinal);
		match outcome {
			Outcome::Found(path, _) => assert_eq!(path.len(), 7),
			_ => panic!("no path"),
		}
	}

	#[test]
	fn walled_off() {
		let (outcome, _) = run(&["S.#..", "..#..", "..#.E"], Cost::Cardinal);
		match outcome {
			Outcome::NoRoute(opened, cut) => {
				assert_eq!(opened.len(), 6);
				assert!(!cut);
			}
			_ => panic!("found a path through a wall"),
		}
	}

	/// What the picture knows gives the same path as asking, without asking
	#[test]
	fn picture_same_path_no_asking() {
		let map = ["S.#......", "..#.###..", "..#...#..", "....#.#.E"];
		for cost in [Cost::Cardinal, Cost::Weighted] {
			let (asked, asked_rounds) = run_with(&map, cost, false);
			let (pictured, pictured_rounds) = run_with(&map, cost, true);
			match (asked, pictured) {
				(Outcome::Found(a, opened_a), Outcome::Found(b, opened_b)) => {
					assert_eq!(a, b);
					assert_eq!(opened_a, opened_b);
				}
				_ => panic!("no path"),
			}
			assert!(asked_rounds > 0);
			assert_eq!(pictured_rounds, 0, "the picture knew every tile");
		}
	}

	#[test]
	fn reverse_dirs() {
		assert_eq!(reverse(1), 2);
		assert_eq!(reverse(2), 1);
		assert_eq!(reverse(4), 8);
		assert_eq!(reverse(8), 4);
	}
}
