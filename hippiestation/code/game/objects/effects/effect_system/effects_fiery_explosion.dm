#define FIERY_EXPLOSION_MAX_RANGE 14
#define FIERY_EXPLOSION_MAX_STEPS 255 // absolute limit on how far a fuel-fed front can travel
#define FIERY_EXPLOSION_MAX_TILES 1200 // absolute limit on how many turfs a fuel-fed front can burn
#define FIERY_EXPLOSION_STEP_DELAY 1 // deciseconds between each ring of the flame front
#define FIERY_EXPLOSION_MIN_OXYGEN 2 // moles of oxygen a turf needs for the flame front to enter it
#define FIERY_EXPLOSION_CONFINEMENT_BOOST 1.5 // extra power and burn damage multiplier when the space is completely sealed
#define FIERY_EXPLOSION_FUEL_REFERENCE 10 // moles of plasma (or equivalent) on a turf that count as one unit of fuel
#define FIERY_EXPLOSION_MAX_FUEL_FACTOR 4
#define FIERY_EXPLOSION_MAX_OXYGEN_FACTOR 2.5 // oxygen relative to a normal tile of air, so this is a bit over half of a pure oxygen tile
#define FIERY_EXPLOSION_MAX_INTENSITY 6
#define FIERY_EXPLOSION_FUEL_REACH 2 // extra turfs of reach each unit of fuel gives the front
#define FIERY_EXPLOSION_SUSTAIN_FUEL 2 // moles of plasma (or equivalent) on a turf for it to be a flammable mixture that keeps the front going by itself
#define FIERY_EXPLOSION_SUSTAIN_REACH 2 // turfs the front can still travel past a flammable turf, however little range it had left
#define FIERY_EXPLOSION_FUEL_BLAST 1 // blast power each unit of fuel adds on its own, before oxygen and confinement
#define FIERY_EXPLOSION_FLASH_BURN 0.6 // fraction of a turf's fuel the front burns off at once, the rest is left to ignite

/// Flammable gases and how much each mole counts for. Anything that isn't listed here won't fuel the front.
GLOBAL_LIST_INIT(fiery_explosion_fuels, list(/datum/gas/plasma = 1, /datum/gas/tritium = 2))

/**
  * A fireball that races outwards from the epicenter through open turfs that have enough oxygen.
  *
  * It doesn't need any plasma. Every turf the front enters burns off part of its oxygen into carbon dioxide,
  * gets a quick blast of heat and sets fire to whatever is standing in it, then the flame dies out at once.
  * Walls and closed doors stop the front, and so do turfs without enough oxygen. Any plasma it passes through
  * will catch and burn like normal.
  *
  * What the air holds decides how hard each turf burns. Oxygen is what lets the flame exist at all, and the
  * more of it there is compared with a normal room, the more fiercely it burns, up to about 2.5 times.
  * Flammable gas (plasma and tritium) is fuel: it makes the turf burn much harder, adds a blast wave of its
  * own even at power 0, and lets the front carry on well past the range, as far as the fuel goes. A turf with
  * at least FIERY_EXPLOSION_SUSTAIN_FUEL of fuel is a flammable mixture that keeps the front alive by itself,
  * however far out it is, so a gas leak that fills a house will take the whole house with it. Fuel-fed fronts
  * are capped at FIERY_EXPLOSION_MAX_STEPS turfs out and FIERY_EXPLOSION_MAX_TILES turfs in total.
  *
  * Behind the front, blasted debris is thrown as missiles that hit hard, and blasted SMES units, APCs and exposed
  * cables discharge as arc flashes.
  *
  * It scorches the floors and walls it passes, darkening them with soot that can be cleaned off, and burning
  * floor tiles. It's also worse in a confined space: the tighter the room or corridor, compared with how much
  * open air the fireball could have spread into, the more it boosts both power and burn damage, up to
  * 1 + FIERY_EXPLOSION_CONFINEMENT_BOOST times in a sealed closet.
  *
  * Arguments:
  * * epicenter - where the fireball starts
  * * range - how many turfs the front can travel on its own, capped at FIERY_EXPLOSION_MAX_RANGE. Fuel extends it.
  * * power - how hard the blast wave behind the flames hits, 0 is flames only. It falls off towards the edge.
  *   Around 1 gives light structures and machines a chance to take damage and shoves items and people back a couple
  *   of tiles near the centre. Around 3 breaks windows and heavily damages machines, and throws things much further.
  *   From about 5 it can devastate structures near the centre.
  * * flame_temperature - what objects, mobs, smoke and chem piles are exposed to as the front passes
  * * burn_damage - burn damage to mobs at the epicenter, falling off towards the edge
  * * oxygen_consumption - fraction of each turf's oxygen that turns into carbon dioxide
  * * air_temperature - the air on each turf is heated to at least this, and cools off normally afterwards
  */
/proc/fiery_explosion(atom/epicenter, range = 6, power = 0, flame_temperature = 1200, burn_damage = 20, oxygen_consumption = 0.5, air_temperature = 450)
	var/turf/origin = get_turf(epicenter)
	if(!origin)
		return
	var/datum/fiery_explosion/explosion = new(origin, clamp(range, 1, FIERY_EXPLOSION_MAX_RANGE), max(power, 0), flame_temperature, burn_damage, oxygen_consumption, air_temperature)
	explosion.start()

/datum/fiery_explosion
	var/turf/origin
	var/range
	var/power
	var/flame_temperature
	var/burn_damage
	var/oxygen_consumption
	var/air_temperature
	var/pressure = 1 // multiplier for how confined the space is
	var/list/seen = list() // turfs the front has already been queued for
	var/list/reach = list() // how many more turfs the front can travel after reaching each turf
	var/list/blasted = list() // blocked turfs (full windows, closed doors, walls) the blast has already hit
	var/list/singed = list() // walls that have already been scorched
	var/list/arced = list() // power equipment that has already discharged

/datum/fiery_explosion/New(turf/origin, range, power, flame_temperature, burn_damage, oxygen_consumption, air_temperature)
	src.origin = origin
	src.range = range
	src.power = power
	src.flame_temperature = flame_temperature
	src.burn_damage = burn_damage
	src.oxygen_consumption = oxygen_consumption
	src.air_temperature = air_temperature

/datum/fiery_explosion/proc/start()
	var/list/measurement = measure_confinement()
	var/confinement = measurement["confinement"]
	pressure = 1 + confinement * FIERY_EXPLOSION_CONFINEMENT_BOOST
	var/base_power = power
	power *= pressure
	burn_damage *= pressure
	playsound(origin, 'sound/effects/explosion1.ogg', 100, TRUE, range * 2)
	screen_shockwave(origin, range, 3 + power * 3)
	var/summary = "range [range], power [base_power] x[round(pressure, 0.01)] = [power], [round(confinement * 100)]% confined ([measurement["reached"]] of [measurement["open_area"]] tiles reachable)"
	log_game("A fiery explosion ([summary]) took place at [AREACOORD(origin)].")
	message_admins("A fiery explosion ([summary]) took place at [AREACOORD(origin)].")
	seen[origin] = TRUE
	reach[origin] = range
	advance(list(origin), 0)

/// Floods out from the origin the way the front will, ignoring oxygen, to see how much of the open air around
/// it is actually there. Returns a list with the "confinement" from 0 for completely open space up to 1 for a
/// sealed closet, plus the "reached" and "open_area" tile counts it was worked out from.
/datum/fiery_explosion/proc/measure_confinement()
	var/list/reached = list()
	reached[origin] = TRUE
	var/list/frontier = list(origin)
	for(var/step in 1 to range)
		var/list/next = list()
		for(var/turf/T in frontier)
			for(var/thing in T.GetAtmosAdjacentTurfs())
				if(reached[thing])
					continue
				reached[thing] = TRUE
				next += thing
		frontier = next
		if(!frontier.len)
			break
	var/open_area = 2 * range * (range + 1) + 1 // the turfs the front could reach in the open with no walls at all
	return list("confinement" = clamp(1 - reached.len / open_area, 0, 1), "reached" = reached.len, "open_area" = open_area)

/// Burns every turf in the current ring of the front, then queues the next ring.
/datum/fiery_explosion/proc/advance(list/frontier, step)
	var/list/next = list()
	for(var/turf/T in frontier)
		var/list/tile = burn(T, step)
		if(!tile)
			continue // no oxygen or a solid turf, the front dies here
		// How far the front can still go from here: it loses a turf per step and gains from any fuel it burned through
		var/remaining = reach[T] - 1 + tile["extension"]
		if(tile["sustained"])
			remaining = max(remaining, FIERY_EXPLOSION_SUSTAIN_REACH)
		if(remaining <= 0 || step >= FIERY_EXPLOSION_MAX_STEPS)
			continue
		var/list/open_adjacent = T.GetAtmosAdjacentTurfs()
		if(seen.len < FIERY_EXPLOSION_MAX_TILES)
			for(var/thing in open_adjacent)
				var/turf/adjacent = thing
				if(seen[adjacent])
					continue
				seen[adjacent] = TRUE
				reach[adjacent] = remaining
				next += adjacent
		// The flames can't enter turfs that block air, like walls, full windows and closed doors
		for(var/direction in GLOB.cardinals)
			var/turf/blocked = get_step(T, direction)
			if(!blocked || (blocked in open_adjacent))
				continue
			if(isclosedturf(blocked) && !singed[blocked])
				singed[blocked] = TRUE
				singe(blocked, clamp(tile["intensity"], 0, 1))
			if(tile["power"] > 0 && !blasted[blocked])
				// but the blast still hits them
				blasted[blocked] = TRUE
				blast_blocked(blocked, tile["power"])
				// If the blast destroyed whatever was blocking air, the flames carry on through the gap
				if(isopenturf(blocked) && !seen[blocked] && T.CanAtmosPass(blocked))
					seen[blocked] = TRUE
					reach[blocked] = remaining
					next += blocked
	if(next.len)
		addtimer(CALLBACK(src, PROC_REF(advance), next, step + 1), 0)

/// Burns a single turf. Returns null if the flame front can't get in, otherwise a list with how hard the turf burned:
/// "intensity" (multiplier on burn damage), "power" (blast power), "extension" (extra turfs of reach it gives the front)
/// and "sustained" (whether it's a flammable enough mixture to keep the front going by itself).
/datum/fiery_explosion/proc/burn(turf/T, step)
	var/turf/open/O = T
	if(!istype(O) || !O.air)
		return null
	var/datum/gas_mixture/air = O.air
	var/oxygen = air.moles[/datum/gas/oxygen] || 0
	if(oxygen < FIERY_EXPLOSION_MIN_OXYGEN)
		return null

	// What the air holds decides how hard this turf burns
	var/raw_fuel = 0
	var/weighted_fuel = 0
	for(var/gas in GLOB.fiery_explosion_fuels)
		var/moles = air.moles[gas] || 0
		raw_fuel += moles
		weighted_fuel += moles * GLOB.fiery_explosion_fuels[gas]
	var/oxygen_factor = clamp(oxygen / MOLES_O2STANDARD, 0.25, FIERY_EXPLOSION_MAX_OXYGEN_FACTOR)
	var/fuel_factor = clamp(weighted_fuel / FIERY_EXPLOSION_FUEL_REFERENCE, 0, FIERY_EXPLOSION_MAX_FUEL_FACTOR)
	var/falloff = max(1 - step / (range + 1), 0)
	var/intensity = clamp((falloff + fuel_factor) * oxygen_factor, 0, FIERY_EXPLOSION_MAX_INTENSITY)
	var/local_power = power * intensity + fuel_factor * oxygen_factor * FIERY_EXPLOSION_FUEL_BLAST * pressure
	var/extension = round(fuel_factor * FIERY_EXPLOSION_FUEL_REACH + max(oxygen_factor - 1, 0) * 0.5)

	// Burn some of the oxygen into carbon dioxide, and flash-burn some of the fuel with it
	var/oxygen_used = oxygen * oxygen_consumption
	if(raw_fuel > 0)
		var/fuel_burned = min(raw_fuel * FIERY_EXPLOSION_FLASH_BURN, oxygen * 0.5)
		var/burn_fraction = fuel_burned / raw_fuel
		for(var/gas in GLOB.fiery_explosion_fuels)
			if(air.moles[gas])
				air.moles[gas] -= air.moles[gas] * burn_fraction
		oxygen_used = min(oxygen_used + fuel_burned, oxygen)
	air.moles[/datum/gas/oxygen] -= oxygen_used
	air.assert_gas(/datum/gas/carbon_dioxide)
	air.moles[/datum/gas/carbon_dioxide] += oxygen_used
	air.temperature = max(air.temperature, min(air_temperature * (1 + fuel_factor * 0.5), 1000))
	air.garbage_collect()
	SSair.add_to_active(O)

	new /obj/effect/temp_visual/fire(O)
	singe(O, clamp(intensity, 0, 1))
	var/damage = burn_damage * intensity
	var/tile_flame_temperature = flame_temperature * (1 + fuel_factor * 0.25)
	for(var/thing in O.contents.Copy()) // copied since blasting things can delete them
		var/atom/movable/AM = thing
		if(QDELETED(AM) || istype(AM, /obj/effect/temp_visual))
			continue
		AM.fire_act(tile_flame_temperature, 100)
		if(QDELETED(AM))
			continue
		if(isliving(AM))
			var/mob/living/L = AM
			L.adjustFireLoss(damage)
		if(local_power > 0)
			blast(AM, local_power)
	for(var/obj/effect/decal/cleanable/chempile/C in O)
		C.reagents?.expose_temperature(tile_flame_temperature, 0.6)
	O.hotspot_expose(tile_flame_temperature, 50) // catches any plasma left in the air, otherwise does nothing
	return list("intensity" = intensity, "power" = local_power, "extension" = extension, "sustained" = (weighted_fuel >= FIERY_EXPLOSION_SUSTAIN_FUEL))

/// Scorches a floor or wall: soot that darkens it more the closer it is to the centre (washable), plus burnt floor tiles.
/datum/fiery_explosion/proc/singe(turf/T, falloff)
	var/shade = round(200 - 130 * falloff)
	T.add_atom_colour(rgb(shade, shade, shade), WASHABLE_COLOUR_PRIORITY)
	if(isfloorturf(T) && prob(70 * falloff))
		T.burn_tile()

/// Hits the structures and machines on a turf the flames couldn't enter.
/datum/fiery_explosion/proc/blast_blocked(turf/T, local_power)
	for(var/thing in T.contents.Copy())
		var/atom/movable/AM = thing
		if(!QDELETED(AM) && (istype(AM, /obj/structure) || istype(AM, /obj/machinery)))
			blast(AM, local_power)

/// The blast wave: damages structures and machines and throws loose things and people away from the epicenter.
/// The actual work lives in the global blast_atom() (effects_blast.dm) so other things, like a weapon, can reuse it.
/datum/fiery_explosion/proc/blast(atom/movable/AM, local_power)
	blast_atom(AM, local_power, origin, arced)
