//! The station picture: what kind of tile each one is, as far as getting about goes, kept between searches so DM isn't asked about
//! the same tiles over and over. DM says a tile's kind along with its answer (bot_path_engine.dm), and tells the engine which tiles
//! have changed since (station_picture.dm), which forgets them until it's told again.
//!
//! Only tiles whose answer is the same for every bot and every search are kept: open floor with nothing on it but things that can't
//! get in anybody's way (items, pipes, cables, decals...), open space, and solid turf. Anything else (a door, a window, a table, a
//! machine, a chair with somebody in it, fire, a pool) is asked about every time, as before.

/// Not known: ask DM
pub const UNKNOWN: u8 = 0;
/// Open floor and nothing on it that could stop anybody: nothing refused, no penalty
pub const OPEN: u8 = 1;
/// A dense turf: refused from every side, unless it's where a search starts (DM says what windows on it allow then)
pub const SOLID: u8 = 2;
/// Open space and nothing on it: open to a search that isn't simulated_only; a simulated_only one asks DM (bot_turf_crossable_without_boots())
pub const OPEN_SPACE: u8 = 3;
/// Asked every time
pub const VOLATILE: u8 = 4;

/// The kind in what DM answers is in these bits, above the answer itself (search.rs)
pub const KIND_SHIFT: u32 = 20;
pub const ANSWER_MASK: u32 = (1 << KIND_SHIFT) - 1;

#[derive(Default)]
pub struct Picture {
	kinds: Vec<u8>,
	/// Tiles in a hallway, where bot_sealed_pocket() stops: nowhere small is shut in if it reaches one
	hubs: Vec<bool>,
}

impl Picture {
	pub fn new(size: usize) -> Picture {
		Picture { kinds: vec![UNKNOWN; size], hubs: Vec::new() }
	}

	pub fn kind(&self, turf: u32) -> u8 {
		*self.kinds.get(turf as usize).unwrap_or(&UNKNOWN)
	}

	pub fn set(&mut self, turf: u32, kind: u8) {
		let at = turf as usize;
		if at >= self.kinds.len() {
			// a z-level made since setup
			self.kinds.resize(at + 1, UNKNOWN);
		}
		self.kinds[at] = kind;
	}

	pub fn forget(&mut self, turf: u32) {
		if let Some(kind) = self.kinds.get_mut(turf as usize) {
			*kind = UNKNOWN;
		}
	}

	/// What DM would answer for this tile in a search from `start`, if the picture knows without asking
	pub fn answer(&self, turf: u32, start: u32, simulated_only: bool) -> Option<u32> {
		match self.kind(turf) {
			OPEN => Some(0),
			SOLID if turf != start => Some(15),
			OPEN_SPACE if !simulated_only => Some(0),
			_ => None,
		}
	}

	/// The hallway tiles, afresh
	pub fn set_hubs(&mut self, turfs: impl Iterator<Item = u32>) {
		self.hubs.clear();
		for turf in turfs {
			let at = turf as usize;
			if at >= self.hubs.len() {
				self.hubs.resize(at + 1, false);
			}
			self.hubs[at] = true;
		}
	}

	pub fn is_hub(&self, turf: u32) -> bool {
		*self.hubs.get(turf as usize).unwrap_or(&false)
	}

	/// How many tiles are known, by kind (OPEN, SOLID, OPEN_SPACE, VOLATILE)
	pub fn counts(&self) -> [u64; 4] {
		let mut counts = [0u64; 4];
		for &kind in &self.kinds {
			if (OPEN..=VOLATILE).contains(&kind) {
				counts[(kind - 1) as usize] += 1;
			}
		}
		counts
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn answers() {
		let mut p = Picture::new(10);
		p.set(1, OPEN);
		p.set(2, SOLID);
		p.set(3, OPEN_SPACE);
		p.set(4, VOLATILE);
		assert_eq!(p.answer(1, 0, true), Some(0));
		assert_eq!(p.answer(2, 0, false), Some(15));
		assert_eq!(p.answer(2, 2, false), None, "a solid start is asked about");
		assert_eq!(p.answer(3, 0, false), Some(0));
		assert_eq!(p.answer(3, 0, true), None, "space for a simulated_only search is asked about");
		assert_eq!(p.answer(4, 0, false), None);
		assert_eq!(p.answer(5, 0, false), None);
		p.forget(1);
		assert_eq!(p.answer(1, 0, false), None);
		p.set(20, OPEN);
		assert_eq!(p.answer(20, 0, false), Some(0), "grows for a new z-level");
	}
}
