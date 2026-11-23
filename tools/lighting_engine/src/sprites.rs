//! Light textures (hippiestation/code/modules/lighting/light_sprites.dm): the lighting drawn as one little picture per chunk of
//! 8 x 8 turfs instead of one lighting object per turf. A picture's pixels are lighting corners, in the colour each corner
//! draws (its cache: the tone curve and bounce light in, as the lighting objects have it), and the client scales it up 32
//! times with smooth filtering, which blends between corners as a lighting object's gradient does.
//!
//! Chunk (kx, ky) is the turfs whose south-west corners are kx*8 .. kx*8+7 (and up). Its picture is 11 x 11: the corners
//! kx*8 - 1 .. kx*8 + 9, so the 9 corners across it and one more each side. The outer ring is see-through: smoothed, it
//! fades the picture out over the tile beyond its edge, where the next chunk's picture is drawn whole, so where two overlap
//! both draw the same colours and it doesn't matter which is on top.
//!
//! Pictures are PNG files in data/lightmaps/, named by a hash of what's in them, so a chunk that goes back to how it was
//! (a door shut again) uses the picture it had. No dependencies: the PNG's deflate stream is stored, not compressed.

use crate::engine::Engine;
use std::collections::HashSet;
use std::path::Path;

pub const DIR: &str = "data/lightmaps";
pub const CHUNK: i32 = 8;
/// Pixels a side: the chunk's corners and a ring
pub const SIDE: i32 = CHUNK + 3;

#[derive(Default)]
pub struct Chunks {
	pub dirty: Vec<(u32, i32, i32)>,
	marked: HashSet<(u32, i32, i32)>,
}

impl Chunks {
	pub fn mark(&mut self, z: usize, kx: i32, ky: i32) {
		let key = (z as u32, kx, ky);
		if self.marked.insert(key) {
			self.dirty.push(key);
		}
	}

	/// Every chunk whose picture has this corner in it
	pub fn mark_corner(&mut self, z: usize, cx: i32, cy: i32) {
		// Corner cx is in chunk kx's picture when kx*8 - 1 <= cx <= kx*8 + 9
		for kx in (cx - 9).div_euclid(CHUNK) + ((cx - 9).rem_euclid(CHUNK) != 0) as i32..=(cx + 1).div_euclid(CHUNK) {
			for ky in (cy - 9).div_euclid(CHUNK) + ((cy - 9).rem_euclid(CHUNK) != 0) as i32..=(cy + 1).div_euclid(CHUNK) {
				self.mark(z, kx, ky);
			}
		}
	}

	pub fn take(&mut self, max: usize) -> Vec<(u32, i32, i32)> {
		let n = self.dirty.len().min(max);
		let taken: Vec<_> = self.dirty.drain(..n).collect();
		for key in taken.iter() {
			self.marked.remove(key);
		}
		taken
	}
}

/// Every chunk with a lit corner in it, for turning the textures on
pub fn mark_all(engine: &mut Engine) -> usize {
	let cols = engine.maxx + 1;
	let mut chunks = engine.chunks.take().unwrap_or_default();
	for (z, level) in engine.levels.iter().enumerate() {
		let Some(level) = level else { continue };
		for (c, corner) in level.corners.iter().enumerate() {
			if corner.cache != [0.0; 3] {
				chunks.mark_corner(z, c as i32 % cols, c as i32 / cols);
			}
		}
	}
	let n = chunks.dirty.len();
	engine.chunks = Some(chunks);
	n
}

/// A chunk's picture, written to DIR unless a file of that name is there already. None for a chunk with no light in it.
pub fn chunk_picture(engine: &Engine, z: usize, kx: i32, ky: i32, scratch: &mut Vec<u8>) -> Result<Option<u64>, String> {
	let Some(Some(level)) = engine.levels.get(z) else {
		return Ok(None);
	};
	let cols = engine.maxx + 1;
	let rows = engine.maxy + 1;
	let (cx0, cy0) = (kx * CHUNK - 1, ky * CHUNK - 1);
	scratch.clear();
	let mut any = false;
	// Rows top to bottom, as PNG has them: a filter byte, then RGBA
	for j in (0..SIDE).rev() {
		scratch.push(0);
		for i in 0..SIDE {
			let (cx, cy) = (cx0 + i, cy0 + j);
			let mut px = [0u8; 4];
			if cx >= 0 && cy >= 0 && cx < cols && cy < rows {
				let cache = level.corners[(cy * cols + cx) as usize].cache;
				for k in 0..3 {
					px[k] = (cache[k].clamp(0.0, 1.0) * 255.0).round() as u8;
				}
				any |= px[0] != 0 || px[1] != 0 || px[2] != 0;
			}
			// The ring all but see-through, not quite: a fully see-through pixel can lose its colour on the way in, and the
			// smoothing then blends towards black
			px[3] = if i == 0 || j == 0 || i == SIDE - 1 || j == SIDE - 1 { 1 } else { 255 };
			scratch.extend_from_slice(&px);
		}
	}
	if !any {
		return Ok(None);
	}
	write_picture(SIDE as u32, scratch).map(Some)
}

fn write_picture(side: u32, rows: &[u8]) -> Result<u64, String> {
	let hash = fnv1a(rows);
	let path = Path::new(DIR).join(file_name(hash));
	if !path.exists() {
		std::fs::write(&path, png(side, side, rows)).map_err(|e| format!("writing {}: {e}", path.display()))?;
	}
	Ok(hash)
}

/// Pixels a tile in a fine picture
pub const FINE: i32 = 4;
/// Pixels a side in a fine picture: the chunk's 8 tiles at FINE a tile, and two rings of pixels each side
pub const FINE_SIDE: i32 = CHUNK * FINE + 4;
/// How far round a light's middle its shadows are traced from (tiles), for soft edges
const LIGHT_SPREAD: f32 = 0.2;
/// A wall face turned away from a light still gets this much of it, the rest by how squarely the light falls on it
const WALL_AMBIENT: f32 = 0.3;
/// How much darker a wall gets deep in from its lit face (at the middle of the tile)
const WALL_DEPTH_FADE: f32 = 0.8;

/// A fine chunk picture: FINE pixels a tile, each lit by every light near the chunk that can see it, traced through the turfs
/// (from LIGHT_SPREAD round the light's middle, so shadows have soft edges). The light's falloff is its sheet read between
/// corners. A pixel on a wall takes the light on the wall's nearest open face, by how squarely the light falls on that face.
/// Bounce light comes from the corners as it is, and the tone curve goes on last, as on a corner.
///
/// Positions here are in tiles, turf x covering x - 1 .. x, so corner cx (the turf's north-east) is at cx.
pub fn fine_picture(engine: &Engine, z: usize, kx: i32, ky: i32, scratch: &mut Vec<u8>) -> Result<Option<u64>, String> {
	let Some(Some(level)) = engine.levels.get(z) else {
		return Ok(None);
	};
	let (maxx, maxy) = (engine.maxx, engine.maxy);
	let cols = maxx + 1;
	let opaque = |x: i32, y: i32| -> bool {
		x < 1 || y < 1 || x > maxx || y > maxy || level.flags[((y - 1) * maxx + (x - 1)) as usize] & crate::engine::OPAQUE != 0
	};
	// The lights on any corner of the chunk's picture, and a corner round it
	let mut lights: Vec<u32> = Vec::new();
	for cy in (ky * CHUNK - 2).max(0)..=(ky * CHUNK + CHUNK + 2).min(maxy) {
		for cx in (kx * CHUNK - 2).max(0)..=(kx * CHUNK + CHUNK + 2).min(maxx) {
			for &id in level.corners[(cy * cols + cx) as usize].affecting.iter() {
				if !lights.contains(&id) {
					lights.push(id);
				}
			}
		}
	}
	let bounce_at = |u: f32, v: f32| -> [f32; 3] {
		// Bilinear between the corners round (u, v)
		let (fx, fy) = (u.floor() as i32, v.floor() as i32);
		let (tx, ty) = (u - fx as f32, v - fy as f32);
		let mut out = [0.0f32; 3];
		for (cx, cy, w) in [(fx, fy, (1.0 - tx) * (1.0 - ty)), (fx + 1, fy, tx * (1.0 - ty)), (fx, fy + 1, (1.0 - tx) * ty), (fx + 1, fy + 1, tx * ty)] {
			if cx < 0 || cy < 0 || cx > maxx || cy > maxy || w == 0.0 {
				continue;
			}
			let b = level.corners[(cy * cols + cx) as usize].bounce;
			for k in 0..3 {
				out[k] += b[k] * w;
			}
		}
		out
	};
	let side = FINE_SIDE;
	let step = 1.0 / FINE as f32;
	// Pixel i's middle: two rings of pixels west of the chunk (the outer see-through, the inner drawn whole so where two chunks'
	// pictures overlap, one of them is always solid)
	let u0 = (kx * CHUNK) as f32 - step * 1.5;
	let v0 = (ky * CHUNK) as f32 - step * 1.5;
	let n = (side * side) as usize;
	let mut lit = vec![[0.0f32; 3]; n];
	// Per light, per pixel: where it takes the light (pu, pv), the wall face's normal and its depth in, the falloff there, and
	// whether the light's middle sees it (-1: nothing to light)
	let mut take: Vec<(f32, f32, Option<(f32, f32)>, f32, f32)> = vec![(0.0, 0.0, None, 0.0, 0.0); n];
	let mut middle: Vec<i8> = vec![-1; n];
	let spread = [(LIGHT_SPREAD, 0.0), (-LIGHT_SPREAD, 0.0), (0.0, LIGHT_SPREAD), (0.0, -LIGHT_SPREAD)];
	for &id in lights.iter() {
		let Some(Some(light)) = engine.lights.get(id as usize) else { continue };
		let Some(Some(sheet)) = engine.sheets.get(light.sheet) else { continue };
		if light.z != z || light.power == 0.0 {
			continue;
		}
		let (lx, ly) = (light.tx as f32 - 0.5, light.ty as f32 - 0.5);
		let reach = light.reach as f32 + 1.5;
		let colour = [light.applied[0], light.applied[1], light.applied[2]];
		// First the light's middle alone, for every pixel
		for j in 0..side {
			for i in 0..side {
				let at = (j * side + i) as usize;
				middle[at] = -1;
				let (u, v) = (u0 + i as f32 * step, v0 + j as f32 * step);
				if (u - lx).abs() > reach || (v - ly).abs() > reach {
					continue;
				}
				let (tx, ty) = (u.floor() as i32 + 1, v.floor() as i32 + 1);
				// Where the light is taken: the pixel itself, or for a wall the nearest open face, a hair outside it
				let (pu, pv, normal, depth) = if opaque(tx, ty) {
					let (fx, fy) = (u - (tx - 1) as f32, v - (ty - 1) as f32);
					let mut best: Option<(f32, f32, f32, (f32, f32))> = None;
					for (open, dist, pu, pv, n) in [
						(!opaque(tx - 1, ty), fx, (tx - 1) as f32 - 0.01, v, (-1.0, 0.0)),
						(!opaque(tx + 1, ty), 1.0 - fx, tx as f32 + 0.01, v, (1.0, 0.0)),
						(!opaque(tx, ty - 1), fy, u, (ty - 1) as f32 - 0.01, (0.0, -1.0)),
						(!opaque(tx, ty + 1), 1.0 - fy, u, ty as f32 + 0.01, (0.0, 1.0)),
					] {
						if open && best.map_or(true, |b| dist < b.0) {
							best = Some((dist, pu, pv, n));
						}
					}
					let Some((dist, pu, pv, n)) = best else { continue };
					(pu, pv, Some(n), dist)
				} else {
					(u, v, None, 0.0)
				};
				let falloff = sheet_at(sheet, light.reach, light.tx, light.ty, pu, pv) * light.power;
				if falloff <= 0.0 {
					continue;
				}
				take[at] = (pu, pv, normal, depth, falloff);
				middle[at] = clear_line(&opaque, lx, ly, pu, pv) as i8;
			}
		}
		// Then the soft edge: only a pixel whose neighbours don't all agree with it is traced from round the middle too
		for j in 0..side {
			for i in 0..side {
				let at = (j * side + i) as usize;
				let me = middle[at];
				if me < 0 {
					continue;
				}
				let mut edge = false;
				for (di, dj) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
					let (ni, nj) = (i + di, j + dj);
					if ni >= 0 && nj >= 0 && ni < side && nj < side {
						let other = middle[(nj * side + ni) as usize];
						if other >= 0 && other != me {
							edge = true;
							break;
						}
					}
				}
				let (pu, pv, normal, depth, falloff) = take[at];
				let mut seen = me as f32;
				if edge {
					for (dx, dy) in spread {
						if clear_line(&opaque, lx + dx, ly + dy, pu, pv) {
							seen += 1.0;
						}
					}
					seen /= (spread.len() + 1) as f32;
				}
				if seen == 0.0 {
					continue;
				}
				let mut amount = falloff * seen;
				if let Some((nx, ny)) = normal {
					// N . L for a wall's face: the light a tile up, as LIGHTING_HEIGHT has it
					let (ex, ey, ez) = (lx - pu, ly - pv, 1.0f32);
					let len = (ex * ex + ey * ey + ez * ez).sqrt();
					let facing = ((nx * ex + ny * ey) / len).max(0.0);
					amount *= (WALL_AMBIENT + (1.0 - WALL_AMBIENT) * facing) * (1.0 - WALL_DEPTH_FADE * depth);
				}
				let px = &mut lit[at];
				for k in 0..3 {
					px[k] += amount * colour[k];
				}
			}
		}
	}
	scratch.clear();
	let mut any = false;
	for j in (0..side).rev() {
		scratch.push(0);
		for i in 0..side {
			let (u, v) = (u0 + i as f32 * step, v0 + j as f32 * step);
			let mut c = lit[(j * side + i) as usize];
			let b = bounce_at(u, v);
			for k in 0..3 {
				c[k] += b[k] * (1.0 - c[k]).clamp(0.0, 1.0);
			}
			let largest = c[0].max(c[1]).max(c[2]);
			let factor = crate::engine::tone_factor(largest, engine.tone_knee);
			let mut px = [0u8; 4];
			for k in 0..3 {
				px[k] = ((c[k] * factor).clamp(0.0, 1.0) * 255.0).round() as u8;
			}
			any |= px[0] != 0 || px[1] != 0 || px[2] != 0;
			px[3] = if i == 0 || j == 0 || i == side - 1 || j == side - 1 { 1 } else { 255 };
			scratch.extend_from_slice(&px);
		}
	}
	if !any {
		return Ok(None);
	}
	write_picture(side as u32, scratch).map(Some)
}

/// A light's sheet read anywhere, between its corners: what LUM_FALLOFF() gives at a corner
fn sheet_at(sheet: &crate::engine::Sheet, reach: i32, tx: i32, ty: i32, u: f32, v: f32) -> f32 {
	let fx = u - tx as f32 + reach as f32 + 1.0;
	let fy = v - ty as f32 + reach as f32 + 1.0;
	let (ix, iy) = (fx.floor() as i32, fy.floor() as i32);
	let (ax, ay) = (fx - ix as f32, fy - iy as f32);
	let get = |x: i32, y: i32| -> f32 {
		if x < 0 || y < 0 || x >= sheet.dim || y >= sheet.dim {
			0.0
		} else {
			sheet.values[(x * sheet.dim + y) as usize]
		}
	};
	get(ix, iy) * (1.0 - ax) * (1.0 - ay) + get(ix + 1, iy) * ax * (1.0 - ay) + get(ix, iy + 1) * (1.0 - ax) * ay + get(ix + 1, iy + 1) * ax * ay
}

/// Whether the line from (au, av) to (bu, bv) crosses no opaque turf on the way (neither end's own turf counts)
fn clear_line(opaque: &impl Fn(i32, i32) -> bool, au: f32, av: f32, bu: f32, bv: f32) -> bool {
	let (mut x, mut y) = (au.floor() as i32 + 1, av.floor() as i32 + 1);
	let (ex, ey) = (bu.floor() as i32 + 1, bv.floor() as i32 + 1);
	let (du, dv) = (bu - au, bv - av);
	let sx = if du > 0.0 { 1 } else { -1 };
	let sy = if dv > 0.0 { 1 } else { -1 };
	let t_dx = if du != 0.0 { (1.0 / du).abs() } else { f32::INFINITY };
	let t_dy = if dv != 0.0 { (1.0 / dv).abs() } else { f32::INFINITY };
	// Turf x covers x - 1 .. x: the next line crossed going east is at x, going west at x - 1
	let mut t_x = if du > 0.0 { (x as f32 - au) / du } else if du < 0.0 { ((x - 1) as f32 - au) / du } else { f32::INFINITY };
	let mut t_y = if dv > 0.0 { (y as f32 - av) / dv } else if dv < 0.0 { ((y - 1) as f32 - av) / dv } else { f32::INFINITY };
	let mut guard = 0;
	while (x, y) != (ex, ey) {
		if t_x < t_y {
			x += sx;
			t_x += t_dx;
		} else {
			y += sy;
			t_y += t_dy;
		}
		if (x, y) == (ex, ey) {
			return true;
		}
		if opaque(x, y) {
			return false;
		}
		guard += 1;
		if guard > 64 {
			return false;
		}
	}
	true
}

/// The four 16-bit parts of a hash, which DM gets as numbers (a float holds 16 bits exactly) and names the file by
pub fn hash_parts(hash: u64) -> [u16; 4] {
	[(hash >> 48) as u16, (hash >> 32) as u16, (hash >> 16) as u16, hash as u16]
}

pub fn file_name(hash: u64) -> String {
	let p = hash_parts(hash);
	format!("{}_{}_{}_{}.png", p[0], p[1], p[2], p[3])
}

fn fnv1a(data: &[u8]) -> u64 {
	let mut h: u64 = 0xcbf29ce484222325;
	for &b in data {
		h ^= b as u64;
		h = h.wrapping_mul(0x100000001b3);
	}
	h
}

/// An 8-bit RGBA PNG of `rows` (already filtered: a 0 before each row), its deflate stream stored
pub fn png(w: u32, h: u32, rows: &[u8]) -> Vec<u8> {
	let mut out = Vec::with_capacity(rows.len() + 128);
	out.extend_from_slice(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
	let mut ihdr = Vec::with_capacity(13);
	ihdr.extend_from_slice(&w.to_be_bytes());
	ihdr.extend_from_slice(&h.to_be_bytes());
	ihdr.extend_from_slice(&[8, 6, 0, 0, 0]);
	chunk(&mut out, b"IHDR", &ihdr);
	let mut z = Vec::with_capacity(rows.len() + 16);
	z.extend_from_slice(&[0x78, 0x01]);
	let mut blocks = rows.chunks(65535).peekable();
	if blocks.peek().is_none() {
		z.extend_from_slice(&[1, 0, 0, 0xFF, 0xFF]);
	}
	while let Some(block) = blocks.next() {
		z.push(if blocks.peek().is_none() { 1 } else { 0 });
		let len = block.len() as u16;
		z.extend_from_slice(&len.to_le_bytes());
		z.extend_from_slice(&(!len).to_le_bytes());
		z.extend_from_slice(block);
	}
	z.extend_from_slice(&adler32(rows).to_be_bytes());
	chunk(&mut out, b"IDAT", &z);
	chunk(&mut out, b"IEND", &[]);
	out
}

fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
	out.extend_from_slice(&(data.len() as u32).to_be_bytes());
	out.extend_from_slice(kind);
	out.extend_from_slice(data);
	let mut crc = Crc::new();
	crc.add(kind);
	crc.add(data);
	out.extend_from_slice(&crc.done().to_be_bytes());
}

fn adler32(data: &[u8]) -> u32 {
	let (mut a, mut b) = (1u32, 0u32);
	for chunk in data.chunks(5552) {
		for &x in chunk {
			a += x as u32;
			b += a;
		}
		a %= 65521;
		b %= 65521;
	}
	(b << 16) | a
}

struct Crc(u32);

impl Crc {
	fn new() -> Self {
		Crc(0xFFFF_FFFF)
	}
	fn add(&mut self, data: &[u8]) {
		for &b in data {
			let mut c = (self.0 ^ b as u32) & 0xFF;
			for _ in 0..8 {
				c = if c & 1 != 0 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 };
			}
			self.0 = (self.0 >> 8) ^ c;
		}
	}
	fn done(&self) -> u32 {
		self.0 ^ 0xFFFF_FFFF
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn png_checksums_are_the_known_ones() {
		let mut c = Crc::new();
		c.add(b"IEND");
		assert_eq!(c.done(), 0xAE42_6082);
		assert_eq!(adler32(b"Wikipedia"), 0x11E6_0398);
	}

	#[test]
	fn a_wall_turf_shadows_the_line_through_it() {
		// Turf 3 (covering 2 .. 3) on row 1 is a wall
		let opaque = |x: i32, y: i32| x == 3 && y == 1;
		assert!(!clear_line(&opaque, 0.5, 0.5, 4.5, 0.5));
		assert!(clear_line(&opaque, 0.5, 0.5, 1.9, 0.5));
		assert!(clear_line(&opaque, 0.5, 0.5, 4.5, 2.5)); // passes above it, through turf (3, 2)
		assert!(!clear_line(&opaque, 0.5, 0.5, 4.5, 1.5)); // clips its top edge
		assert!(!clear_line(&opaque, 4.5, 0.5, 0.5, 0.5)); // either way round
		assert!(clear_line(&opaque, 2.5, 0.5, 4.5, 0.5)); // from inside it: its own turf doesn't count
		// The sheet read at a corner is the corner's value
		let sheet = crate::engine::Sheet { dim: 5, values: (0..25).map(|v| v as f32).collect() };
		assert_eq!(sheet_at(&sheet, 1, 10, 10, 9.0, 11.0), sheet.values[(1 * 5 + 3) as usize]);
	}

	#[test]
	fn a_corner_marks_every_chunk_whose_picture_has_it() {
		for cx in -3..30 {
			let mut chunks = Chunks::default();
			chunks.mark_corner(1, cx, 4);
			let mut got: Vec<i32> = chunks.dirty.iter().map(|k| k.1).collect();
			got.sort();
			got.dedup();
			let want: Vec<i32> = (-5..10).filter(|kx| kx * CHUNK - 1 <= cx && cx <= kx * CHUNK + 9).collect();
			assert_eq!(got, want, "corner {cx}");
		}
	}
}
