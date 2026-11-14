//! Hippie's map parser, called from /datum/parsed_map (hippiestation/code/modules/mapping/map_engine.dm).
//!
//! It reads a .dmm the way code/modules/mapping/reader.dm does, step for step: the same regex walk over the file (written out
//! by hand, since it needs a look-ahead), the same blank-line trimming and bounds for each coordinate block, and the same
//! splitting of each model into members and of each member's {vars} into fields. What it can't settle the way DM would
//! (bare values: paths, decimals, files, list(...), null) it hands back as text for DM's own parse_constant(). Typepaths
//! are left to DM too: only text2path() knows which exist.
//!
//! DM calls it with text and gets JSON back (see map_parse() for the shape). It never holds anything of BYOND's.

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};

/// Bumped whenever the JSON DM gets changes. DM won't use a library that says anything else.
pub const ENGINE_VERSION: &str = "1";

/// Fields of a member's {vars}, as reader.dm's readlist(text, ";") finds them
#[derive(Debug, PartialEq)]
pub enum Field {
	/// "name" with no "=": DM adds the name on its own
	Plain(String),
	/// name = whole number, which text2num() reads exactly
	Number(String, i64),
	/// name = "text": the text between the first quote and the next one, as parse_constant() takes it
	Text(String, String),
	/// name = anything else, for DM's parse_constant()
	Bare(String, String),
}

#[derive(Debug, PartialEq)]
pub struct Member {
	pub path: String,
	pub fields: Vec<Field>,
}

pub struct GridSet {
	pub x: f64,
	pub y: f64,
	pub z: f64,
	pub lines: Vec<String>,
}

pub struct Parsed {
	pub key_len: usize,
	/// The six bounds, or None when there were no coordinate blocks (DM nulls them)
	pub bounds: Option<[f64; 6]>,
	/// Model keys and their text, in the order DM's grid_models gets them (empty unless loading)
	pub models: Vec<(String, String)>,
	pub sets: Vec<GridSet>,
}

/// Crop limits; None is DM's -INFINITY / INFINITY
#[derive(Clone, Copy, Default)]
pub struct Crop {
	pub x_lower: Option<f64>,
	pub x_upper: Option<f64>,
	pub y_lower: Option<f64>,
	pub y_upper: Option<f64>,
}

impl Crop {
	fn xl(&self) -> f64 {
		self.x_lower.unwrap_or(f64::NEG_INFINITY)
	}
	fn xu(&self) -> f64 {
		self.x_upper.unwrap_or(f64::INFINITY)
	}
	fn yl(&self) -> f64 {
		self.y_lower.unwrap_or(f64::NEG_INFINITY)
	}
	fn yu(&self) -> f64 {
		self.y_upper.unwrap_or(f64::INFINITY)
	}
}

/// DM's clamp(value, low, high)
fn clamp(value: f64, low: f64, high: f64) -> f64 {
	low.max(value.min(high))
}

enum Found {
	/// key, body, and where the match ends
	Model(usize, usize, usize, usize, usize),
	/// x, y, z, the grid text, and where the match ends
	Coords(f64, f64, f64, usize, usize, usize),
}

/// The next match of reader.dm's dmmRegex at or after `from`:
/// "([a-zA-Z]+)" = \(((?:.|\n)*?)\)\n(?!\t)  or  \((\d+),(\d+),(\d+)\) = \{"([a-zA-Z\n]*)"\}
/// The two can't start on the same character, so the leftmost start decides.
fn find_next(text: &[u8], from: usize) -> Option<Found> {
	let len = text.len();
	let mut i = from;
	// Once a model's closing ")\n" can't be found from some point, it can't be found from anywhere after it either
	let mut no_close_after = usize::MAX;
	while i < len {
		match text[i] {
			b'"' => {
				let key_start = i + 1;
				let mut j = key_start;
				while j < len && text[j].is_ascii_alphabetic() {
					j += 1;
				}
				if j > key_start && text[j..].starts_with(b"\" = (") {
					let body_start = j + 5;
					if body_start < no_close_after {
						let mut k = body_start;
						let mut closed = None;
						while k + 1 < len {
							if text[k] == b')' && text[k + 1] == b'\n' && (k + 2 >= len || text[k + 2] != b'\t') {
								closed = Some(k);
								break;
							}
							k += 1;
						}
						match closed {
							Some(k) => return Some(Found::Model(key_start, j, body_start, k, k + 2)),
							None => no_close_after = body_start,
						}
					}
				}
			}
			b'(' => {
				if let Some(found) = coords_at(text, i) {
					return Some(found);
				}
			}
			_ => {}
		}
		i += 1;
	}
	None
}

fn digits(text: &[u8], at: usize) -> Option<(f64, usize)> {
	let mut j = at;
	while j < text.len() && text[j].is_ascii_digit() {
		j += 1;
	}
	if j == at {
		return None;
	}
	let value = std::str::from_utf8(&text[at..j]).ok()?.parse::<f64>().ok()?;
	Some((value, j))
}

fn coords_at(text: &[u8], i: usize) -> Option<Found> {
	let (x, j) = digits(text, i + 1)?;
	if text.get(j) != Some(&b',') {
		return None;
	}
	let (y, j) = digits(text, j + 1)?;
	if text.get(j) != Some(&b',') {
		return None;
	}
	let (z, j) = digits(text, j + 1)?;
	if !text[j..].starts_with(b") = {\"") {
		return None;
	}
	let grid_start = j + 6;
	let mut k = grid_start;
	while k < text.len() && (text[k].is_ascii_alphabetic() || text[k] == b'\n') {
		k += 1;
	}
	if !text[k..].starts_with(b"\"}") {
		return None;
	}
	Some(Found::Coords(x, y, z, grid_start, k, k + 2))
}

/// What file2text() gives DM: line ends as \n, no byte order mark
pub fn normalise(mut bytes: Vec<u8>) -> Vec<u8> {
	if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
		bytes.drain(..3);
	}
	if bytes.contains(&b'\r') {
		let mut out = Vec::with_capacity(bytes.len());
		let mut i = 0;
		while i < bytes.len() {
			if bytes[i] == b'\r' && bytes.get(i + 1) == Some(&b'\n') {
				i += 1;
				continue;
			}
			out.push(bytes[i]);
			i += 1;
		}
		bytes = out;
	}
	bytes
}

fn text_of(bytes: &[u8]) -> String {
	String::from_utf8_lossy(bytes).into_owned()
}

/// /datum/parsed_map/New(), less the parts that make DM objects
pub fn parse(text: &[u8], crop: Crop, measure: bool) -> Result<Parsed, String> {
	let (xl, xu, yl, yu) = (crop.xl(), crop.xu(), crop.yl(), crop.yu());
	let mut bounds = [f64::INFINITY, f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY];
	let mut key_len = 0usize;
	let mut models: Vec<(String, String)> = Vec::new();
	let mut model_index: std::collections::HashMap<Vec<u8>, usize> = std::collections::HashMap::new();
	let mut sets = Vec::new();
	let mut pos = 0;
	while let Some(found) = find_next(text, pos) {
		match found {
			Found::Model(ks, ke, bs, be, end) => {
				pos = end;
				let key = &text[ks..ke];
				// Duplicate keys are skipped, unless the first one's text was empty (DM's grid_models[key] is false then)
				let existing = model_index.get(key).copied();
				if let Some(at) = existing {
					if !models[at].1.is_empty() {
						continue;
					}
				}
				if key_len != key.len() {
					if key_len == 0 {
						key_len = key.len();
					} else {
						return Err("Inconsistent key length in DMM".into());
					}
				}
				if !measure {
					let body = text_of(&text[bs..be]);
					match existing {
						Some(at) => models[at].1 = body,
						None => {
							model_index.insert(key.to_vec(), models.len());
							models.push((text_of(key), body));
						}
					}
				}
			}
			Found::Coords(x, y, z, gs, ge, end) => {
				pos = end;
				if key_len == 0 {
					return Err("Coords before model definition in DMM".into());
				}
				if x < xl || x > xu {
					continue;
				}
				bounds[0] = bounds[0].min(clamp(x, xl, xu));
				bounds[2] = bounds[2].min(z);
				bounds[5] = bounds[5].max(z);

				let mut lines: Vec<&[u8]> = text[gs..ge].split(|&c| c == b'\n').collect();
				// Leading blank lines go; if they're all blank, the last one stays
				let mut leading = 0;
				while leading < lines.len() {
					leading += 1;
					if !lines[leading - 1].is_empty() {
						break;
					}
				}
				if leading > 1 {
					lines.drain(0..leading - 1);
				}
				if lines.is_empty() {
					continue;
				}
				if lines.last().map_or(false, |l| l.is_empty()) {
					lines.pop();
				}
				bounds[1] = bounds[1].min(clamp(y, yl, yu));
				let top = y + lines.len() as f64 - 1.0;
				bounds[4] = bounds[4].max(clamp(top, yl, yu));
				let mut max_x = x;
				if let Some(first) = lines.first() {
					max_x = max_x.max(x + first.len() as f64 / key_len as f64 - 1.0);
				}
				bounds[3] = clamp(bounds[3].max(max_x), xl, xu);
				sets.push(GridSet {
					x,
					y: top,
					z,
					lines: if measure { Vec::new() } else { lines.iter().map(|l| text_of(l)).collect() },
				});
			}
		}
	}
	let bounds = if bounds[0] == f64::INFINITY { None } else { Some(bounds) };
	Ok(Parsed { key_len, bounds, models, sets })
}

/// DM's trimtext()
fn trim(bytes: &[u8]) -> &[u8] {
	let mut start = 0;
	let mut end = bytes.len();
	while start < end && bytes[start].is_ascii_whitespace() {
		start += 1;
	}
	while end > start && bytes[end - 1].is_ascii_whitespace() {
		end -= 1;
	}
	&bytes[start..end]
}

fn find(text: &[u8], what: u8, from: usize) -> Option<usize> {
	if from >= text.len() {
		return None;
	}
	text[from..].iter().position(|&c| c == what).map(|p| p + from)
}

/// reader.dm's find_next_delimiter_position(), 0-based; None where DM says 0. It gives up (Err) where DM would loop forever.
fn next_delimiter(text: &[u8], from: usize, delimiter: u8, opening: u8, closing: u8) -> Result<Option<usize>, String> {
	let mut position = from;
	let mut next_delimiter = find(text, delimiter, position);
	let mut next_opening = find(text, opening, position);
	let mut rounds = 0;
	while let (Some(open), Some(delim)) = (next_opening, next_delimiter) {
		if open >= delim {
			break;
		}
		rounds += 1;
		if rounds > text.len() + 2 {
			return Err("unclosed bracket or quote in a model".into());
		}
		// No closing one: DM goes back to the start of the text
		position = find(text, closing, open + 1).map_or(0, |c| c + 1);
		next_delimiter = find(text, delimiter, position);
		next_opening = find(text, opening, position);
	}
	Ok(next_delimiter)
}

/// The value side of a field, the way parse_constant() starts on it
fn value_of(name: String, text: &[u8]) -> Field {
	let digits_from = if text.first() == Some(&b'-') { 1 } else { 0 };
	if text.len() > digits_from && text.len() - digits_from <= 7 && text[digits_from..].iter().all(|c| c.is_ascii_digit()) {
		if let Ok(n) = std::str::from_utf8(text).unwrap_or("").parse::<i64>() {
			return Field::Number(name, n);
		}
	}
	if text.first() == Some(&b'"') {
		let end = find(text, b'"', 1).unwrap_or(text.len());
		return Field::Text(name, text_of(&text[1..end]));
	}
	Field::Bare(name, text_of(text))
}

/// readlist(text, ";")
fn read_fields(text: &[u8]) -> Result<Vec<Field>, String> {
	let mut out = Vec::new();
	if text.is_empty() {
		return Ok(out);
	}
	let mut old = 0;
	loop {
		let position = next_delimiter(text, old, b';', b'"', b'"')?;
		let end = position.unwrap_or(text.len());
		let equals = find(&text[..end.max(old)], b'=', old);
		let left = text_of(trim(&text[old.min(end)..equals.unwrap_or(end).max(old.min(end))]));
		if let Some(p) = position {
			old = p + 1;
		}
		match equals {
			Some(eq) => out.push(value_of(left, trim(&text[(eq + 1).min(end)..end]))),
			None => out.push(Field::Plain(left)),
		}
		if position.is_none() {
			break;
		}
	}
	Ok(out)
}

/// One model's text split into its members, as build_cache() does it
pub fn split_model(model: &[u8]) -> Result<Vec<Member>, String> {
	let mut members = Vec::new();
	let mut old = 0;
	loop {
		let dpos = next_delimiter(model, old, b',', b'{', b'}')?;
		let segment = &model[old.min(model.len())..dpos.unwrap_or(model.len()).max(old.min(model.len()))];
		let full_def = trim(segment);
		let variables_start = full_def.iter().position(|&c| c == b'{');
		let path = text_of(trim(&full_def[..variables_start.unwrap_or(full_def.len())]));
		if let Some(d) = dpos {
			old = d + 1;
		}
		let mut fields = Vec::new();
		if let Some(vs) = variables_start {
			// copytext(full_def, vs + 1, -(last character)): drops the closing } (or whatever the last character is)
			let mut end = full_def.len();
			if end > 0 {
				end -= 1;
				while end > 0 && (full_def[end] & 0xC0) == 0x80 {
					end -= 1;
				}
			}
			let inner = if vs + 1 < end { &full_def[vs + 1..end] } else { &[][..] };
			fields = read_fields(inner)?;
		}
		members.push(Member { path, fields });
		if dpos.is_none() {
			break;
		}
	}
	Ok(members)
}

pub fn json_string(out: &mut String, text: &str) {
	out.push('"');
	for c in text.chars() {
		match c {
			'"' => out.push_str("\\\""),
			'\\' => out.push_str("\\\\"),
			'\n' => out.push_str("\\n"),
			'\r' => out.push_str("\\r"),
			'\t' => out.push_str("\\t"),
			c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
			c => out.push(c),
		}
	}
	out.push('"');
}

fn json_number(out: &mut String, value: f64) {
	if value.fract() == 0.0 && value.abs() < 1e15 {
		out.push_str(&format!("{}", value as i64));
	} else {
		out.push_str(&format!("{}", value));
	}
}

/// The answer DM decodes:
/// {"key_len":N, "bounds":[6]|null, "models":[[key, text], ...], "split":[[[path, [field, ...]], ...], ...], "sets":[[x, y, z, [line, ...]], ...]}
/// A field is [name] (no value), [name, 1, number], [name, 2, "text"] or [name, 3, "bare"]. "split" runs alongside
/// "models". Measuring gives only key_len and bounds. An error is {"error":"..."}.
pub fn to_json(parsed: &Parsed, measure: bool) -> Result<String, String> {
	let mut out = String::with_capacity(1024);
	out.push_str(&format!("{{\"key_len\":{},\"bounds\":", parsed.key_len));
	match &parsed.bounds {
		None => out.push_str("null"),
		Some(b) => {
			out.push('[');
			for (i, v) in b.iter().enumerate() {
				if i > 0 {
					out.push(',');
				}
				json_number(&mut out, *v);
			}
			out.push(']');
		}
	}
	if !measure {
		out.push_str(",\"models\":[");
		for (i, (key, text)) in parsed.models.iter().enumerate() {
			if i > 0 {
				out.push(',');
			}
			out.push('[');
			json_string(&mut out, key);
			out.push(',');
			json_string(&mut out, text);
			out.push(']');
		}
		out.push_str("],\"split\":[");
		for (i, (_, text)) in parsed.models.iter().enumerate() {
			if i > 0 {
				out.push(',');
			}
			out.push('[');
			for (m, member) in split_model(text.as_bytes())?.iter().enumerate() {
				if m > 0 {
					out.push(',');
				}
				out.push('[');
				json_string(&mut out, &member.path);
				out.push_str(",[");
				for (f, field) in member.fields.iter().enumerate() {
					if f > 0 {
						out.push(',');
					}
					out.push('[');
					match field {
						Field::Plain(name) => json_string(&mut out, name),
						Field::Number(name, n) => {
							json_string(&mut out, name);
							out.push_str(&format!(",1,{}", n));
						}
						Field::Text(name, t) => {
							json_string(&mut out, name);
							out.push_str(",2,");
							json_string(&mut out, t);
						}
						Field::Bare(name, t) => {
							json_string(&mut out, name);
							out.push_str(",3,");
							json_string(&mut out, t);
						}
					}
					out.push(']');
				}
				out.push_str("]]");
			}
			out.push(']');
		}
		out.push_str("],\"sets\":[");
		for (i, set) in parsed.sets.iter().enumerate() {
			if i > 0 {
				out.push(',');
			}
			out.push('[');
			json_number(&mut out, set.x);
			out.push(',');
			json_number(&mut out, set.y);
			out.push(',');
			json_number(&mut out, set.z);
			out.push_str(",[");
			for (l, line) in set.lines.iter().enumerate() {
				if l > 0 {
					out.push(',');
				}
				json_string(&mut out, line);
			}
			out.push_str("]]");
		}
		out.push(']');
	}
	out.push('}');
	Ok(out)
}

fn error_json(text: &str) -> String {
	let mut out = String::from("{\"error\":");
	json_string(&mut out, text);
	out.push('}');
	out
}

fn crop_arg(text: Option<&String>) -> Option<f64> {
	text.and_then(|t| t.trim().parse::<f64>().ok()).filter(|v| v.is_finite())
}

pub fn parse_file(path: &str, crop: Crop, measure: bool) -> String {
	let bytes = match std::fs::read(path) {
		Ok(b) => normalise(b),
		Err(e) => return error_json(&format!("can't read {}: {}", path, e)),
	};
	match parse(&bytes, crop, measure).and_then(|p| to_json(&p, measure)) {
		Ok(json) => json,
		Err(e) => error_json(&e),
	}
}

thread_local! {
	static ANSWER: RefCell<CString> = RefCell::new(CString::default());
}

fn answer(text: String) -> *const c_char {
	ANSWER.with(|cell| {
		*cell.borrow_mut() = CString::new(text.replace('\0', "")).unwrap_or_default();
		cell.borrow().as_ptr()
	})
}

unsafe fn arguments(argc: c_int, argv: *const *const c_char) -> Vec<String> {
	if argv.is_null() || argc <= 0 {
		return Vec::new();
	}
	(0..argc as usize)
		.map(|i| {
			let p = *argv.add(i);
			if p.is_null() {
				String::new()
			} else {
				CStr::from_ptr(p).to_string_lossy().into_owned()
			}
		})
		.collect()
}

fn guarded(call: impl FnOnce() -> String) -> *const c_char {
	match catch_unwind(AssertUnwindSafe(call)) {
		Ok(text) => answer(text),
		Err(_) => answer(error_json("panicked")),
	}
}

/// map_engine_version() -> ENGINE_VERSION
#[no_mangle]
pub unsafe extern "C" fn map_engine_version(_argc: c_int, _argv: *const *const c_char) -> *const c_char {
	answer(ENGINE_VERSION.into())
}

/// map_parse(path, measure, x_lower, x_upper, y_lower, y_upper) -> JSON (see to_json()). measure is "1" to only measure.
/// A crop limit that isn't a finite number is no limit.
#[no_mangle]
pub unsafe extern "C" fn map_parse(argc: c_int, argv: *const *const c_char) -> *const c_char {
	let args = arguments(argc, argv);
	guarded(|| {
		let Some(path) = args.first() else {
			return error_json("no path");
		};
		let measure = args.get(1).map_or(false, |m| m == "1");
		let crop = Crop {
			x_lower: crop_arg(args.get(2)),
			x_upper: crop_arg(args.get(3)),
			y_lower: crop_arg(args.get(4)),
			y_upper: crop_arg(args.get(5)),
		};
		parse_file(path, crop, measure)
	})
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn models_and_grid() {
		let text = b"\"aa\" = (/turf/open/space,/area/space)\n\"ab\" = (/obj/x{dir = 4; name = \"a; b\"},/turf/open/floor{icon_state = \"x\"},/area/a)\n\n(1,1,1) = {\"\naaab\naaaa\n\"}\n";
		let p = parse(text, Crop::default(), false).unwrap();
		assert_eq!(p.key_len, 2);
		assert_eq!(p.models.len(), 2);
		assert_eq!(p.bounds, Some([1.0, 1.0, 1.0, 2.0, 2.0, 1.0]));
		assert_eq!(p.sets[0].lines, vec!["aaab".to_string(), "aaaa".to_string()]);
		let m = split_model(p.models[1].1.as_bytes()).unwrap();
		assert_eq!(m[0].path, "/obj/x");
		assert_eq!(m[0].fields, vec![Field::Number("dir".into(), 4), Field::Text("name".into(), "a; b".into())]);
		assert_eq!(m[2].path, "/area/a");
	}

	#[test]
	fn tgm_model_with_tabs() {
		let text = b"\"a\" = (\n/obj/x{\n\tdir = 8;\n\tpixel_y = -32\n\t},\n/turf/t,\n/area/a)\n(1,1,1) = {\"\na\n\"}\n";
		let p = parse(text, Crop::default(), false).unwrap();
		let m = split_model(p.models[0].1.as_bytes()).unwrap();
		assert_eq!(m[0].fields, vec![Field::Number("dir".into(), 8), Field::Number("pixel_y".into(), -32)]);
	}

	#[test]
	fn crlf() {
		assert_eq!(normalise(b"a\r\nb\r\n".to_vec()), b"a\nb\n".to_vec());
	}
}
