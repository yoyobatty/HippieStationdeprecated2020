// Realistic explosions (the user's picks, 2026-11-13: air and pressure, injuries, structures, look and sound; realism may move the
// ranges; no blast wave in vacuum; lasting injuries). This file is the air.
//
// A blast wave is air being shoved, so the air decides how far it carries:
//  - The air where it goes off scales its reach by the cube root of the pressure (Sachs scaling): a third of an atmosphere takes about
//    a third off. Below BLAST_AIR_FADE kPa it fades out, and below BLAST_AIR_NONE there's no wave at all, only the bomb's own tile and
//    the tiles touching it, hit by the expanding products. Fragments, heat and the flash still go out.
//  - Thinner air on the way costs it reach (blast_thin_air_cost()), so a blast that blows out a window doesn't carry on into space.
//  - A small sealed room makes it harder inside: the gas has nowhere to go and the walls throw the wave back. How much harder is the
//    bomb's size against the room's (blast_confinement()), and only the room and its own walls get it.
//  - The products are hot gas, added to the air round the middle (blast_add_products()): a closet bomb leaves the closet hot and the
//    air pushing out through whatever broke.
//  - The pressure reaches half as far again as the damage, breaking glass and lights there (blast_far.dm).
//
// World param explosion-realism=off for the explosions as they were. The doppler array still hears the bomb's own size.

GLOBAL_VAR_INIT(explosion_realism, world.params["explosion-realism"] != "off")

/// Tiles of reach a blast loses crossing a tile of vacuum it set off in air, on top of the step (times the block weight, 1.5)
#define BLAST_THIN_AIR_COST 2
/// Tiles of room it takes to hold a tile³ of blast at the room's own pressure again
#define BLAST_CONFINE_TILES 10
/// The most a sealed room adds to the blast inside it
#define BLAST_CONFINE_BOOST 0.5
/// Past this many tiles of connected air a room counts as open
#define BLAST_CONFINE_MAX_TILES 1500
/// Glass breaks out to this times the light range (the user's pick, 2026-11-13: 1.5, against 2, to keep a maxcap's sums down)...
#define BLAST_FAR_REACH 1.5
/// ...but no more than this many tiles past it
#define BLAST_FAR_EXTRA_MAX 14
/// Moles of hot gas the products add per tile³ of blast, and the most they ever add
#define BLAST_GAS_PER_YIELD 2
#define BLAST_GAS_MAX 3000
/// How hot the products are once they've spread to the room's pressure. At 900 a medium bomb left a hallway at 395 K, burning
/// everyone out to the edge of the light damage: 600 leaves it about 330 K, and a closet minibomb's closet about 345 K.
#define BLAST_GAS_TEMPERATURE 600
/// The most tiles the products are spread over
#define BLAST_GAS_TILES 80

/// How well the air on a turf carries a blast: 1 for a normal room, more for denser air up to BLAST_AIR_MAX, 0 for vacuum.
/// Walls and anything else without air of their own count as 1: what they block is their explosion_block.
/proc/blast_air_factor(turf/T)
	if(!isopenturf(T) || T.density)
		return 1
	if(isspaceturf(T))
		return 0
	var/datum/gas_mixture/air = T.return_air()
	return blast_air_factor_at(air ? air.return_pressure() : 0)

/// blast_air_factor() for air at this many kilopascals
/proc/blast_air_factor_at(pressure)
	if(pressure <= BLAST_AIR_NONE)
		return 0
	. = min((pressure / ONE_ATMOSPHERE) ** (1 / 3), BLAST_AIR_MAX)
	if(pressure < BLAST_AIR_FADE)
		. *= (pressure - BLAST_AIR_NONE) / (BLAST_AIR_FADE - BLAST_AIR_NONE)

/// What crossing a turf costs a blast that set off in air `start_factor` good, for being thinner than where it started. A blast
/// that set off in thin air has its whole reach scaled down for that already (explosion_realism_ranges()), so the same thin air
/// costs it nothing more.
/proc/blast_thin_air_cost(turf/T, start_factor)
	var/factor = blast_air_factor(T)
	if(factor >= start_factor)
		return 0
	return (min(start_factor, 1) - min(factor, 1)) * BLAST_THIN_AIR_COST

/// Thinner air costs a blast reach, like a wall does. GatherSpiralTurfs() always puts the epicenter first. A maxcap reaches about
/// 4,800 tiles out to where it breaks glass, so space is told by its type and air at least as thick as where it started is passed
/// over on its pressure alone.
/datum/controller/subsystem/explosions/CaculateExplosionBlock(list/affected_turfs)
	. = ..()
	if(!GLOB.explosion_realism || !length(affected_turfs))
		return
	var/list/start = blast_thin_air_start(affected_turfs[1])
	if(!start)
		return //nothing carries it anywhere, which explosion_realism_ranges() has seen to
	var/full = start[1]
	var/as_thick = start[2]
	for(var/turf/open/T in affected_turfs)
		var/cost = blast_thin_air_cost_at(T, full, as_thick)
		if(cost)
			.[T] += cost

/// What blast_thin_air_cost_at() needs to know of where a blast set off: list(its air factor up to 1, the pressure air at least as
/// thick as its is), or null in vacuum, where nothing carries it anywhere
/proc/blast_thin_air_start(turf/epicenter)
	var/start_factor = blast_air_factor(epicenter)
	if(start_factor <= 0)
		return null
	var/datum/gas_mixture/start_air = epicenter.return_air()
	return list(min(start_factor, 1), min(start_air ? start_air.return_pressure() : ONE_ATMOSPHERE, ONE_ATMOSPHERE))

/// What crossing an open turf costs a blast for thinner air than where it set off (blast_thin_air_start())
/proc/blast_thin_air_cost_at(turf/T, full, as_thick)
	if(T.density || !isopenturf(T))
		return 0
	if(isspaceturf(T))
		return full * BLAST_THIN_AIR_COST
	var/datum/gas_mixture/air = T.return_air()
	var/pressure = air ? air.return_pressure() : 0
	if(pressure >= as_thick)
		return 0
	var/thinner = full - min(blast_air_factor_at(pressure), 1)
	return thinner > 0 ? thinner * BLAST_THIN_AIR_COST : 0

/**
 * The blast the air at `epicenter` makes of a bomb this size. Returns a list:
 * dev, heavy, light, flame: the ranges as they come out
 * far: how far the pressure breaks glass, 0 for nowhere
 * air: the air factor where it went off (blast_air_factor())
 * boost: how much harder it is inside the room it went off in
 * confined: turf -> TRUE for that room and its walls, null if it isn't any harder there
 * room: the room's open turfs nearest the middle first, for blast_add_products()
 */
/proc/explosion_realism_ranges(turf/epicenter, dev, heavy, light, flame)
	// a pile going off at once gets the same answer each time in a tick: worked out once (callers only read it)
	var/static/last_key
	var/static/list/last
	var/key = "[epicenter.x],[epicenter.y],[epicenter.z],[dev],[heavy],[light],[flame],[world.time]"
	if(key == last_key)
		return last
	last_key = key
	last = explosion_realism_ranges_sums(epicenter, dev, heavy, light, flame)
	return last

/proc/explosion_realism_ranges_sums(turf/epicenter, dev, heavy, light, flame)
	var/air = blast_air_factor(epicenter)
	var/size = max(dev, heavy, light)
	var/list/room
	var/list/confined
	var/boost = 1
	if(air > 0 && size > 0)
		var/list/found = blast_confinement(epicenter, size)
		boost = found[1]
		confined = found[2]
		room = found[3]
	var/new_dev = dev * air
	var/new_heavy = heavy * air
	var/new_light = light * air
	if(air < 1) //the products still hit what they touch, however thin the air: the bomb's own tile, and the light on the tiles round it
		if(dev >= 1)
			new_dev = max(new_dev, 0.5)
		if(heavy >= 1)
			new_heavy = max(new_heavy, 1)
		if(light >= 2)
			new_light = max(new_light, 1.5)
	var/new_flame = flame * min(air, 1) //a fireball needs air
	var/edge = max(new_dev, new_heavy, new_light)
	var/far = 0
	if(air > 0 && edge >= 1)
		far = min(edge * BLAST_FAR_REACH, edge + BLAST_FAR_EXTRA_MAX)
	return list(new_dev, new_heavy, new_light, new_flame, far, air, boost, confined, room)

/// How much harder a blast of this size is in the room it set off in. Floods out through the air from the epicenter to see how
/// much room the gas has. Returns list(boost, turf -> TRUE for the room and its walls or null, the room's open turfs in order).
/proc/blast_confinement(turf/epicenter, size)
	var/yield = size ** 3
	// a room big enough that the products raise its pressure by less than 2% is as good as open
	var/enough = min(BLAST_CONFINE_MAX_TILES, CEILING(yield / (BLAST_CONFINE_TILES * 0.02), 1))
	var/list/reached = list()
	reached[epicenter] = TRUE
	var/list/room = list(epicenter)
	var/at = 1
	while(at <= length(room) && length(room) < enough)
		var/turf/T = room[at++]
		for(var/turf/A as anything in T.atmos_adjacent_turfs)
			if(!reached[A])
				reached[A] = TRUE
				room += A
	if(length(room) >= enough)
		return list(1, null, room)
	var/rise = yield / (length(room) * BLAST_CONFINE_TILES)
	var/boost = 1 + min(rise, 1) * BLAST_CONFINE_BOOST
	// the room's own walls, windows and shut doors take it too
	var/list/confined = reached.Copy()
	for(var/turf/T as anything in room)
		for(var/direction in GLOB.cardinals)
			var/turf/side = get_step(T, direction)
			if(side && !reached[side])
				confined[side] = TRUE
	return list(boost, confined, room)

/// Adds the bomb's products to the air round the middle, hot: up to BLAST_GAS_TILES of `room` (nearest first, from
/// blast_confinement()) share them.
/proc/blast_add_products(list/room, size)
	if(!length(room))
		return
	var/moles = min((size ** 3) * BLAST_GAS_PER_YIELD, BLAST_GAS_MAX)
	if(moles < 1)
		return
	var/list/tiles = list()
	var/want = clamp(round(size * size), 1, BLAST_GAS_TILES)
	for(var/turf/open/T in room)
		if(!isspaceturf(T) && T.air)
			tiles += T
			if(length(tiles) >= want)
				break
	if(!length(tiles))
		return
	var/each = moles / length(tiles)
	for(var/turf/open/T as anything in tiles)
		var/datum/gas_mixture/air = T.air
		var/old_capacity = air.heat_capacity()
		var/old_temperature = air.temperature
		air.assert_gases(/datum/gas/nitrogen, /datum/gas/carbon_dioxide)
		air.moles[/datum/gas/nitrogen] += each * 0.6
		air.moles[/datum/gas/carbon_dioxide] += each * 0.4
		var/new_capacity = air.heat_capacity()
		if(new_capacity > 0)
			air.temperature = (old_capacity * old_temperature + (new_capacity - old_capacity) * BLAST_GAS_TEMPERATURE) / new_capacity
		SSair.add_to_active(T)

/// One line for the logs on what the air made of it, or "" for an ordinary blast in an ordinary room
/proc/explosion_realism_note(list/real)
	var/air = real[6]
	var/boost = real[7]
	var/list/notes = list()
	if(air <= 0)
		notes += "in vacuum: no blast wave"
	else if(abs(air - 1) > 0.02)
		notes += "air x[round(air, 0.01)]"
	if(boost > 1.01)
		notes += "confined x[round(boost, 0.01)] in [length(real[9])] tiles"
	if(real[5])
		notes += "glass to [round(real[5], 0.1)]"
	return length(notes) ? " ([jointext(notes, ", ")])" : ""

#undef BLAST_THIN_AIR_COST
#undef BLAST_CONFINE_TILES
#undef BLAST_CONFINE_BOOST
#undef BLAST_CONFINE_MAX_TILES
#undef BLAST_FAR_REACH
#undef BLAST_FAR_EXTRA_MAX
#undef BLAST_GAS_PER_YIELD
#undef BLAST_GAS_MAX
#undef BLAST_GAS_TEMPERATURE
#undef BLAST_GAS_TILES
