//! Gas reactions on tile air, done by the engine: /datum/gas_mixture/proc/react() and every /datum/gas_reaction's react()
//! (code/modules/atmospherics/gasmixtures/reactions.dm, hippiestation/.../gasmixtures/reactions.dm), each a copy of the DM
//! proc it's named after, in DM's order and 32-bit steps. Nothing in here knows about BYOND.
//!
//! What a reaction does besides changing the air comes back to DM as lists (Effects): hotspot_expose() from the fires, the
//! floor getting wet or frozen (water_vapor_gas_act()/freon_gas_act(), which always say yes on an open turf, so the gas
//! change never waits on them), a tritium fire's chance of a radiation pulse (DM rolls the prob(10)), fusion's light and
//! radiation, a stimulum ball's particle, research points, and what's left in reaction_results["fire"] for the hotspot.
//! A tile where a reaction the engine doesn't know is due goes to DM's react() whole, as before.

use crate::engine::{Config, KIND_FIXED, KIND_SPACE};

/// Which DM reaction a Config::reactions entry is
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Kind {
	Dm,
	NobStop,
	StimBall,
	NobFormation,
	StimFormation,
	FreonForm,
	BzFormation,
	Nitryl,
	HippieFusion,
	WaterVapor,
	Freon,
	NitrousDecomp,
	TritFire,
	PlasmaFire,
	Miaster,
}

impl Kind {
	fn from_code(code: u32) -> Kind {
		match code {
			1 => Kind::NobStop,
			2 => Kind::StimBall,
			3 => Kind::NobFormation,
			4 => Kind::StimFormation,
			5 => Kind::FreonForm,
			6 => Kind::BzFormation,
			7 => Kind::Nitryl,
			8 => Kind::HippieFusion,
			9 => Kind::WaterVapor,
			10 => Kind::Freon,
			11 => Kind::NitrousDecomp,
			12 => Kind::TritFire,
			13 => Kind::PlasmaFire,
			14 => Kind::Miaster,
			_ => Kind::Dm,
		}
	}
}

/// Gas indices (from 0), in the order DM sends them
pub struct Gases {
	pub o2: usize,
	pub n2: usize,
	pub co2: usize,
	pub plasma: usize,
	pub vapor: usize,
	pub n2o: usize,
	pub nitryl: usize,
	pub trit: usize,
	pub bz: usize,
	pub stim: usize,
	pub pluox: usize,
	pub miasma: usize,
	pub nob: usize,
	pub freon: usize,
}

/// The defines the reactions use, in the order DM sends them
pub struct Consts {
	pub min_burn: f32,
	pub upper: f32,
	pub oxygen_rate_base: f32,
	pub super_saturation: f32,
	pub fullburn: f32,
	pub rate_delta: f32,
	pub plasma_energy: f32,
	pub fire_min_exist: f32,
	pub moles_visible: f32,
	pub vapor_freeze: f32,
	pub n2o_energy: f32,
	pub trit_oxyburn_energy: f32,
	pub trit_oxy_factor: f32,
	pub trit_trit_factor: f32,
	pub hydrogen_energy: f32,
	pub trit_rad_min: f32,
	pub nitryl_energy: f32,
	pub carbon_energy: f32,
	pub bz_research_scale: f32,
	pub bz_research_max: f32,
	pub stim_heat_scale: f32,
	pub stim_first_rise: f32,
	pub stim_first_drop: f32,
	pub stim_second_rise: f32,
	pub stim_absolute_drop: f32,
	pub stim_research: f32,
	pub nob_energy: f32,
	pub nob_research: f32,
	pub miasma_research: f32,
	pub stim_ball_amount: f32,
	pub fusion_binding: f32,
	pub fusion_purity: f32,
	pub fusion_max_carbon: f32,
	pub fusion_fused_coefficient: f32,
	pub fusion_catalyst: f32,
	pub fusion_energy: f32,
	pub one_atmosphere: f32,
	pub t0c: f32,
	pub tcmb: f32,
	pub r: f32,
	pub cell_volume: f32,
	pub min_heat_capacity: f32,
}

const CONSTS: usize = 42;

pub struct NativeReactions {
	/// By Config::reactions index
	pub kinds: Vec<Kind>,
	/// Each reaction's major_gas (react() only looks at reactions whose major gas the air had to start with), usize::MAX for none
	pub major: Vec<usize>,
	pub g: Gases,
	pub c: Consts,
}

impl NativeReactions {
	/// Settings from DM: the reaction count, then (kind code, major gas index from 1 or 0) for each in Config::reactions'
	/// order, the 14 gas indices (from 1) in Gases' order, then the CONSTS constants in Consts' order
	pub fn parse(data: &[f64], cfg: &Config) -> Result<NativeReactions, String> {
		let mut at = 0usize;
		let mut next = |what: &str| -> Result<f64, String> {
			let v = *data.get(at).ok_or_else(|| format!("settings ran out at {what}"))?;
			at += 1;
			Ok(v)
		};
		let count = next("reaction count")? as usize;
		if count != cfg.reactions.len() {
			return Err(format!("{count} reactions, the engine was set up with {}", cfg.reactions.len()));
		}
		let mut kinds = Vec::with_capacity(count);
		let mut major = Vec::with_capacity(count);
		for _ in 0..count {
			kinds.push(Kind::from_code(next("kind")? as u32));
			let m = next("major gas")? as usize;
			major.push(if m == 0 || m > cfg.gases { usize::MAX } else { m - 1 });
		}
		let mut gas = |what: &str| -> Result<usize, String> {
			let i = next(what)? as usize;
			if i == 0 || i > cfg.gases {
				return Err(format!("{what} gas {i} out of 1..{}", cfg.gases));
			}
			Ok(i - 1)
		};
		let g = Gases {
			o2: gas("o2")?,
			n2: gas("n2")?,
			co2: gas("co2")?,
			plasma: gas("plasma")?,
			vapor: gas("water vapor")?,
			n2o: gas("n2o")?,
			nitryl: gas("nitryl")?,
			trit: gas("tritium")?,
			bz: gas("bz")?,
			stim: gas("stimulum")?,
			pluox: gas("pluoxium")?,
			miasma: gas("miasma")?,
			nob: gas("hypernoblium")?,
			freon: gas("freon")?,
		};
		let mut v = [0f32; CONSTS];
		for slot in v.iter_mut() {
			*slot = next("constants")? as f32;
		}
		let c = Consts {
			min_burn: v[0],
			upper: v[1],
			oxygen_rate_base: v[2],
			super_saturation: v[3],
			fullburn: v[4],
			rate_delta: v[5],
			plasma_energy: v[6],
			fire_min_exist: v[7],
			moles_visible: v[8],
			vapor_freeze: v[9],
			n2o_energy: v[10],
			trit_oxyburn_energy: v[11],
			trit_oxy_factor: v[12],
			trit_trit_factor: v[13],
			hydrogen_energy: v[14],
			trit_rad_min: v[15],
			nitryl_energy: v[16],
			carbon_energy: v[17],
			bz_research_scale: v[18],
			bz_research_max: v[19],
			stim_heat_scale: v[20],
			stim_first_rise: v[21],
			stim_first_drop: v[22],
			stim_second_rise: v[23],
			stim_absolute_drop: v[24],
			stim_research: v[25],
			nob_energy: v[26],
			nob_research: v[27],
			miasma_research: v[28],
			stim_ball_amount: v[29],
			fusion_binding: v[30],
			fusion_purity: v[31],
			fusion_max_carbon: v[32],
			fusion_fused_coefficient: v[33],
			fusion_catalyst: v[34],
			fusion_energy: v[35],
			one_atmosphere: v[36],
			t0c: v[37],
			tcmb: v[38],
			r: v[39],
			cell_volume: v[40],
			min_heat_capacity: v[41],
		};
		Ok(NativeReactions { kinds, major, g, c })
	}
}

/// What reactions did besides changing the air, for DM, in the order the tiles were done
#[derive(Default)]
pub struct Effects {
	/// Every tile the engine reacted: (tile, reaction_results["fire"])
	pub reacted: Vec<(u32, f32)>,
	/// hotspot_expose(temperature, CELL_VOLUME) where it would make a hotspot
	pub expose: Vec<(u32, f32)>,
	/// reaction_results["fire"] when each of those was exposed: a new hotspot sizes itself from it there and then, before a
	/// later fire on the tile sets it again
	pub expose_fire: Vec<f32>,
	pub wet: Vec<u32>,
	pub frozen: Vec<u32>,
	/// A tritium fire that might pulse radiation (DM rolls prob(10)): (tile, energy released)
	pub trit_radiation: Vec<(u32, f32)>,
	/// Hippie fusion: (tile, energy released)
	pub fusion: Vec<(u32, f32)>,
	/// A stimulum ball: (tile, angle)
	pub stim_ball: Vec<(u32, f32)>,
	pub research: f64,
}

impl Effects {
	pub fn clear(&mut self) {
		self.reacted.clear();
		self.expose.clear();
		self.expose_fire.clear();
		self.wet.clear();
		self.frozen.clear();
		self.trit_radiation.clear();
		self.fusion.clear();
		self.stim_ball.clear();
		self.research = 0.0;
	}
}

pub enum Outcome {
	/// No reaction's requirements were met
	Nothing,
	/// The engine did it (whether or not anything changed)
	Done,
	/// A reaction the engine doesn't know is due: DM's react() does the tile
	Dm,
}

/// One tile's react(). `moles` and `temperature` are changed in place.
#[allow(clippy::too_many_arguments)]
pub fn react_tile(nr: &NativeReactions, cfg: &Config, kind: u32, tile: u32, hotspot: bool, moles: &mut [f64], temperature: &mut f64, fx: &mut Effects) -> Outcome {
	let g = &nr.g;
	let c = &nr.c;
	let n = moles.len();
	let mut m = [0f32; 64];
	for i in 0..n {
		m[i] = moles[i] as f32;
	}
	let hc = |m: &[f32; 64]| -> f32 {
		if kind == KIND_SPACE {
			return cfg.heat_capacity_vacuum as f32;
		}
		let mut total = 0f32;
		for i in 0..n {
			total += m[i] * cfg.specific_heat[i] as f32;
		}
		if total == 0.0 && kind != KIND_FIXED {
			cfg.heat_capacity_vacuum as f32
		} else {
			total
		}
	};
	let total_moles = |m: &[f32; 64]| -> f32 { m[..n].iter().sum() };
	let quantize = |v: f32| -> f32 {
		let a = cfg.molar_accuracy as f32;
		(v / a + 0.5).floor() * a
	};

	// What react() starts from: the gases there, the temperature and thermal energy it checks requirements against
	let mut present = 0u64;
	for i in 0..n {
		if m[i] != 0.0 {
			present |= 1 << i;
		}
	}
	let start_t = *temperature as f32;
	let start_energy = start_t * hc(&m);
	let due = |k: usize, m: &[f32; 64]| -> bool {
		let major = nr.major[k];
		if major == usize::MAX || present & (1 << major) == 0 {
			return false;
		}
		let r = &cfg.reactions[k];
		if (r.min_temperature != 0.0 && (start_t as f64) < r.min_temperature) || (r.min_energy != 0.0 && (start_energy as f64) < r.min_energy) {
			return false;
		}
		r.gases.iter().all(|&(gas, need)| m[gas] != 0.0 && m[gas] as f64 >= need)
	};
	// Anything DM has to do itself: the whole tile goes to DM, untouched
	let mut any = false;
	for k in 0..cfg.reactions.len() {
		if due(k, &m) {
			if nr.kinds[k] == Kind::Dm {
				return Outcome::Dm;
			}
			any = true;
		}
	}
	if !any {
		return Outcome::Nothing;
	}

	let mut t = start_t;
	let mut fire = 0f32;
	let mut hotspot = hotspot;
	let expose = |t: f32, fire: f32, m: &[f32; 64], hotspot: &mut bool, fx: &mut Effects| {
		// plasmafire/tritfire's "let the floor know", and what hotspot_expose() checks before it makes a hotspot
		if t > c.fire_min_exist && !*hotspot && m[g.o2] >= 0.5 && (m[g.plasma] > 0.5 || m[g.trit] > 0.5) && t > c.min_burn {
			fx.expose.push((tile, t));
			fx.expose_fire.push(fire);
			*hotspot = true;
		}
	};
	for k in 0..cfg.reactions.len() {
		if !due(k, &m) {
			continue;
		}
		match nr.kinds[k] {
			Kind::Dm => continue, // made due by an earlier reaction here: DM's react() would have had it only if it was due from the start
			Kind::NobStop => break,
			Kind::StimBall => {
				let old = hc(&m);
				let ratio = if m[g.nitryl] != 0.0 { m[g.vapor] / m[g.nitryl] } else { 0.0 };
				let angle = 180.0 * (ratio.to_radians()).cos() + 180.0; // DM's cos() takes degrees
				let stim_used = (c.stim_ball_amount / m[g.plasma]).min(m[g.stim]);
				let pluox_used = (c.stim_ball_amount / m[g.plasma]).min(m[g.pluox]);
				let energy = stim_used * c.stim_heat_scale;
				fx.stim_ball.push((tile, angle));
				m[g.co2] += 4.0 * pluox_used;
				m[g.n2] += 8.0 * stim_used;
				m[g.pluox] -= pluox_used;
				m[g.stim] -= stim_used;
				m[g.plasma] *= 0.5;
				if energy != 0.0 {
					let new = hc(&m);
					if new > c.min_heat_capacity {
						t = ((t * old + energy) / new).max(c.tcmb);
					}
				}
			}
			Kind::NobFormation => {
				let old = hc(&m);
				let nob = ((m[g.n2] + m[g.trit]) / 100.0).min(m[g.trit] / 10.0).min(m[g.n2] / 20.0);
				let taken = nob * (c.nob_energy / m[g.bz].max(1.0));
				if m[g.trit] - 10.0 * nob < 0.0 || m[g.n2] - 20.0 * nob < 0.0 {
					continue;
				}
				m[g.trit] -= 10.0 * nob;
				m[g.n2] -= 20.0 * nob;
				m[g.nob] += nob;
				fx.research += (nob * c.nob_research) as f64;
				if nob != 0.0 {
					let new = hc(&m);
					if new > c.min_heat_capacity {
						t = ((t * old - taken) / new).max(c.tcmb);
					}
				}
			}
			Kind::StimFormation => {
				let old = hc(&m);
				let hs = (t / c.stim_heat_scale).min(m[g.trit]).min(m[g.plasma]).min(m[g.nitryl]);
				let e = hs + c.stim_first_rise * hs.powi(2) - c.stim_first_drop * hs.powi(3) + c.stim_second_rise * hs.powi(4)
					- c.stim_absolute_drop * hs.powi(5);
				if m[g.trit] - hs < 0.0 || m[g.plasma] - hs < 0.0 || m[g.nitryl] - hs < 0.0 {
					continue;
				}
				m[g.stim] += hs / 10.0;
				m[g.trit] -= hs;
				m[g.plasma] -= hs;
				m[g.nitryl] -= hs;
				fx.research += (c.stim_research * e.max(0.0)) as f64;
				if e != 0.0 {
					let new = hc(&m);
					if new > c.min_heat_capacity {
						t = ((t * old + e) / new).max(c.tcmb);
					}
				}
			}
			Kind::FreonForm => {
				let old = hc(&m);
				let he = (t / (c.fire_min_exist * 10.0)).min(m[g.plasma]).min(m[g.co2]).min(m[g.bz]);
				let used = he * 100.0;
				if m[g.plasma] - he * 1.5 < 0.0 || m[g.co2] - he * 0.75 < 0.0 || m[g.bz] - he * 0.25 < 0.0 {
					continue;
				}
				m[g.plasma] -= he * 1.5;
				m[g.co2] -= he * 0.75;
				m[g.bz] -= he * 0.25;
				m[g.freon] += he * 2.5;
				if used > 0.0 {
					let new = hc(&m);
					if new > c.min_heat_capacity {
						t = ((t * old - used) / new).max(c.tcmb);
					}
				}
			}
			Kind::BzFormation => {
				let pressure = total_moles(&m) * c.r * t / c.cell_volume;
				let old = hc(&m);
				let eff = (1.0 / ((pressure / (0.1 * c.one_atmosphere)) * (m[g.plasma] / m[g.n2o]).max(1.0))).min(m[g.n2o]).min(m[g.plasma] / 2.0);
				let energy = 2.0 * eff * c.carbon_energy;
				if m[g.n2o] - eff < 0.0 || m[g.plasma] - 2.0 * eff < 0.0 || energy <= 0.0 {
					continue;
				}
				m[g.bz] += eff;
				if eff == m[g.n2o] {
					m[g.bz] -= pressure.min(1.0);
					m[g.o2] += pressure.min(1.0);
				}
				m[g.n2o] -= eff;
				m[g.plasma] -= 2.0 * eff;
				fx.research += (eff * eff * c.bz_research_scale).min(c.bz_research_max) as f64;
				let new = hc(&m);
				if new > c.min_heat_capacity {
					t = ((t * old + energy) / new).max(c.tcmb);
				}
			}
			Kind::Nitryl => {
				let old = hc(&m);
				let he = (t / (c.fire_min_exist * 100.0)).min(m[g.o2]).min(m[g.n2]);
				let used = he * c.nitryl_energy;
				if m[g.o2] - he < 0.0 || m[g.n2] - he < 0.0 {
					continue;
				}
				m[g.o2] -= he;
				m[g.n2] -= he;
				m[g.nitryl] += he * 2.0;
				if used > 0.0 {
					let new = hc(&m);
					if new > c.min_heat_capacity {
						t = ((t * old - used) / new).max(c.tcmb);
					}
				}
			}
			Kind::HippieFusion => {
				let start = t;
				let energy = t * hc(&m);
				let total = total_moles(&m);
				if (m[g.plasma] + m[g.co2]) / total < c.fusion_purity || energy < c.fusion_binding {
					continue;
				}
				let impurity = (m[g.plasma] + m[g.co2]) / total;
				let ratio = (m[g.co2] / m[g.plasma]).min(c.fusion_max_carbon);
				let mut fused = (c.fusion_fused_coefficient * (energy / c.fusion_binding) * impurity * ratio).max(0.0);
				fused = fused.min(m[g.plasma]).min(m[g.co2] / c.fusion_catalyst);
				let catalysed = (fused * c.fusion_catalyst).max(0.0);
				let oxygen = catalysed;
				let nitrogen = fused - oxygen;
				let released = ((catalysed + fused) - (oxygen + nitrogen)) * c.fusion_energy;
				m[g.plasma] -= fused;
				m[g.co2] -= catalysed;
				m[g.o2] += oxygen;
				m[g.n2] += nitrogen;
				if released > 0.0 {
					let now = hc(&m);
					if now > c.min_heat_capacity {
						t = start + (released / now).max(c.tcmb);
					}
					fx.fusion.push((tile, released));
				}
			}
			Kind::WaterVapor => {
				if t <= c.vapor_freeze {
					fx.frozen.push(tile);
				} else {
					fx.wet.push(tile);
					m[g.vapor] -= c.moles_visible;
				}
			}
			Kind::Freon => {
				let needed = m[g.n2] * 0.05;
				if needed != 0.0 && hc(&m) > c.min_heat_capacity && t <= c.t0c - 5.0 {
					m[g.freon] -= c.moles_visible;
					m[g.n2] -= needed;
					fx.frozen.push(tile);
					t = (t - (500.0 / hc(&m)).max(c.tcmb)).max(c.tcmb);
				}
			}
			Kind::NitrousDecomp => {
				let old = hc(&m);
				let burned = (0.00002 * (t - 0.00001 * t * t)).max(0.0) * m[g.n2o];
				m[g.n2o] -= burned;
				if burned != 0.0 {
					let energy = c.n2o_energy * burned;
					m[g.o2] += burned / 2.0;
					m[g.n2] += burned;
					let new = hc(&m);
					if new > c.min_heat_capacity {
						t = (t * old + energy) / new;
					}
				}
			}
			Kind::TritFire => {
				let old = hc(&m);
				fire = 0.0;
				let burned;
				if m[g.o2] < m[g.trit] || c.trit_oxyburn_energy > t * old {
					burned = m[g.o2] / c.trit_oxy_factor;
					m[g.trit] -= burned;
				} else {
					burned = m[g.trit] * c.trit_trit_factor;
					m[g.trit] -= m[g.trit] / c.trit_trit_factor;
					m[g.o2] -= m[g.trit];
				}
				let mut energy = 0f32;
				if burned != 0.0 {
					energy = c.hydrogen_energy * burned;
					if burned > c.trit_rad_min {
						fx.trit_radiation.push((tile, energy));
					}
					m[g.vapor] += burned / c.trit_oxy_factor;
					fire += burned;
				}
				if energy > 0.0 {
					let new = hc(&m);
					if new > c.min_heat_capacity {
						t = (t * old + energy) / new;
					}
				}
				expose(t, fire, &m, &mut hotspot, fx);
			}
			Kind::PlasmaFire => {
				let old = hc(&m);
				fire = 0.0;
				let mut energy = 0f32;
				let scale = if t > c.upper { 1.0 } else { (t - c.min_burn) / (c.upper - c.min_burn) };
				if scale > 0.0 {
					let oxygen_rate = c.oxygen_rate_base - scale;
					let plasma = m[g.plasma];
					let oxygen = m[g.o2];
					let super_saturated = oxygen / plasma > c.super_saturation;
					let mut rate = if oxygen > plasma * c.fullburn {
						(plasma * scale) / c.rate_delta
					} else {
						(scale * (oxygen / c.fullburn)) / c.rate_delta
					};
					if rate > c.min_heat_capacity {
						rate = rate.min(plasma).min(oxygen / oxygen_rate);
						m[g.plasma] = quantize(plasma - rate);
						m[g.o2] = quantize(oxygen - rate * oxygen_rate);
						if super_saturated {
							m[g.trit] += rate;
						} else {
							m[g.co2] += rate;
						}
						energy += c.plasma_energy * rate;
						fire += rate * (1.0 + oxygen_rate);
					}
				}
				if energy > 0.0 {
					let new = hc(&m);
					if new > c.min_heat_capacity {
						t = (t * old + energy) / new;
					}
				}
				expose(t, fire, &m, &mut hotspot, fx);
			}
			Kind::Miaster => {
				if m[g.vapor] != 0.0 && m[g.vapor] / total_moles(&m) > 0.1 {
					continue;
				}
				let cleaned = m[g.miasma].min(20.0 + (t - c.fire_min_exist - 70.0) / 20.0);
				m[g.miasma] -= cleaned;
				m[g.o2] += cleaned;
				t += cleaned * 0.002;
				fx.research += (cleaned * c.miasma_research) as f64;
			}
		}
	}
	for i in 0..n {
		moles[i] = m[i] as f64;
	}
	*temperature = t as f64;
	fx.reacted.push((tile, fire));
	Outcome::Done
}
