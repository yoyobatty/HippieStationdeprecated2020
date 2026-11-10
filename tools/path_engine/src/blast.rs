//! Shaped explosions (the user's ruling, 2026-11-09: the same power as now; walls, doors and windows absorb and block; it spreads
//! through openings). For each tile of a square round the epicenter, how much further than the straight line the blast has come to
//! get there: the cheapest way round, where leaving a tile costs its explosion block on top of the step. Open floor costs nothing
//! extra, so in the open an explosion is exactly what it was; behind a wall it's what the wall blocks, unless there's a way round
//! that costs less.
//!
//! DM adds the extra to the straight-line distance (cheap_hypotenuse(), as before) and sorts tiles into devastation, heavy and
//! light as it always has. hippiestation/code/controllers/subsystem/explosions_shape.dm has the same search in DM, as the
//! fallback and for the check.

use std::cmp::Ordering;
use std::collections::BinaryHeap;

/// What a tile it can't get to at all comes back as
pub const UNREACHABLE: f32 = 1.0e6;
/// Below this the extra is float noise from adding up steps, and is nothing
const NOISE: f32 = 0.001;

#[derive(PartialEq)]
struct Node {
	cost: f32,
	index: u32,
}

impl Eq for Node {}

impl Ord for Node {
	// a min-heap on cost, ties by index so the order is the same every time
	fn cmp(&self, other: &Self) -> Ordering {
		other.cost.partial_cmp(&self.cost).unwrap_or(Ordering::Equal).then_with(|| other.index.cmp(&self.index))
	}
}

impl PartialOrd for Node {
	fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
		Some(self.cmp(other))
	}
}

/// `blocks` is size * size, rows bottom to top and x fastest, the epicenter in the middle; a negative block is no tile at all
/// (off the map). Returns the extra for every tile, in the same order.
pub fn shape(blocks: &[f32], size: usize) -> Vec<f32> {
	let n = size * size;
	let mut extra = vec![UNREACHABLE; n];
	if size == 0 || blocks.len() < n || size % 2 == 0 {
		return extra;
	}
	let r = (size / 2) as i32;
	let center = r as usize * size + r as usize;
	if blocks[center] < 0.0 {
		return extra;
	}
	let mut cost = vec![f32::INFINITY; n];
	let mut heap = BinaryHeap::new();
	cost[center] = 0.0;
	heap.push(Node { cost: 0.0, index: center as u32 });
	let size_i = size as i32;
	while let Some(Node { cost: c, index }) = heap.pop() {
		let i = index as usize;
		if c > cost[i] {
			continue;
		}
		let leaving = blocks[i].max(0.0);
		let x = (i % size) as i32;
		let y = (i / size) as i32;
		for dy in -1..=1 {
			for dx in -1..=1 {
				if dx == 0 && dy == 0 {
					continue;
				}
				let nx = x + dx;
				let ny = y + dy;
				if nx < 0 || ny < 0 || nx >= size_i || ny >= size_i {
					continue;
				}
				let j = (ny * size_i + nx) as usize;
				if blocks[j] < 0.0 {
					continue;
				}
				let step = if dx != 0 && dy != 0 {
					// A corner is only cut where one of the two tiles beside it is open: not between two wall corners
					let side_a = blocks[(y * size_i + nx) as usize];
					let side_b = blocks[(ny * size_i + x) as usize];
					if side_a != 0.0 && side_b != 0.0 {
						continue;
					}
					std::f32::consts::SQRT_2
				} else {
					1.0
				};
				let next = c + step + leaving;
				if next < cost[j] {
					cost[j] = next;
					heap.push(Node { cost: next, index: j as u32 });
				}
			}
		}
	}
	for (i, out) in extra.iter_mut().enumerate() {
		if !cost[i].is_finite() {
			continue;
		}
		let dx = ((i % size) as i32 - r).abs() as f32;
		let dy = ((i / size) as i32 - r).abs() as f32;
		let open = dx.max(dy) + (std::f32::consts::SQRT_2 - 1.0) * dx.min(dy);
		let more = cost[i] - open;
		*out = if more < NOISE { 0.0 } else { more };
	}
	extra
}

#[cfg(test)]
mod tests {
	use super::*;

	fn grid(rows: &[&str]) -> (Vec<f32>, usize) {
		// rows top to bottom as drawn; '.' open, '#' block 1, 'R' block 2, 'D' block 1 (a shut door), 'X' no tile
		let size = rows.len();
		let mut blocks = vec![0.0; size * size];
		for (row, line) in rows.iter().enumerate() {
			let y = size - 1 - row;
			for (x, c) in line.chars().enumerate() {
				blocks[y * size + x] = match c {
					'#' | 'D' => 1.0,
					'R' => 2.0,
					'X' => -1.0,
					_ => 0.0,
				};
			}
		}
		(blocks, size)
	}

	fn at(extra: &[f32], size: usize, x: usize, row: usize) -> f32 {
		extra[(size - 1 - row) * size + x]
	}

	#[test]
	fn open_floor_adds_nothing() {
		let (blocks, size) = grid(&[".......", ".......", ".......", ".......", ".......", ".......", "......."]);
		let extra = shape(&blocks, size);
		assert!(extra.iter().all(|&e| e == 0.0));
	}

	#[test]
	fn a_wall_with_no_way_round_adds_its_block() {
		// a wall right across: everything behind it is one more away
		let (blocks, size) = grid(&[".......", "#######", ".......", ".......", ".......", ".......", "......."]);
		let extra = shape(&blocks, size);
		assert_eq!(at(&extra, size, 3, 0), 1.0);
		assert_eq!(at(&extra, size, 3, 1), 0.0); // the wall itself is hit where it is
	}

	#[test]
	fn an_opening_lets_it_through() {
		// the same wall with a gap beside the tile behind: going through the gap costs less than the wall
		let (blocks, size) = grid(&[".......", "###.###", ".......", ".......", ".......", ".......", "......."]);
		let extra = shape(&blocks, size);
		assert_eq!(at(&extra, size, 3, 0), 0.0);
		// one along from the gap: round through it (about 0.59) costs less than through the wall (1)
		let beside = at(&extra, size, 1, 0);
		assert!(beside > 0.0 && beside < 1.0, "round through the gap costs a little: {beside}");
	}

	#[test]
	fn a_shut_door_blocks_like_a_wall() {
		let (blocks, size) = grid(&[".......", "###D###", ".......", ".......", ".......", ".......", "......."]);
		let extra = shape(&blocks, size);
		assert_eq!(at(&extra, size, 3, 0), 1.0);
	}

	#[test]
	fn no_cutting_between_two_wall_corners() {
		// a wall running corner to corner, x = row + 2, with the middle (4, 4) below it: the far side is behind the wall, not
		// through the gaps between its corners
		let (blocks, size) = grid(&[
			"..#......",
			"...#.....",
			"....#....",
			".....#...",
			"......#..",
			".......#.",
			"........#",
			".........",
			".........",
		]);
		let extra = shape(&blocks, size);
		let far = at(&extra, size, 6, 1);
		assert!(far >= 0.5, "behind a diagonal wall: {far}");
	}

	#[test]
	fn no_tile_is_unreachable() {
		let (blocks, size) = grid(&["XXXXXXX", ".......", ".......", ".......", ".......", ".......", "......."]);
		let extra = shape(&blocks, size);
		assert_eq!(at(&extra, size, 3, 0), UNREACHABLE);
	}
}
