// The kitchen's cold room (MetaStation, Donut, MetaLake: KITCHEN_COLDROOM_ATMOS, -80 C) is cold, not airless. A player nips in for the
// meat and out again, and breathes a little frost doing it (a point or so of burn a breath, lungs.dm). Bots took the cold for no air
// (turf_air_is_breathable() wants it warmer than the lungs' first cold level): every cook on Meta stood at the door, 107 times in
// four shifts, and the kitchen never got its meat.
//
// Now air that's only cold, and not so cold a breath does real harm, is somewhere to go for something and come straight back out of:
// half a minute, then it gets out whatever's left to do. It puts its mask on going in, if it has one (emergency_internals()).

/// How long a trip into cold air can last before it gets out, done or not.
#define BOT_COLD_TRIP (30 SECONDS)
/// Colder than this is no quick trip (lungs.dm's cold_level_3 is 120 K).
#define BOT_COLD_FLOOR 150

/datum/bot_brain
	/// When it went into cold air, this time.
	var/cold_trip_since = 0

/// Air that's fine but for being cold, and not so cold a breath of it does much harm.
/datum/bot_brain/proc/turf_air_just_cold(turf/open/T)
	if(!istype(T))
		return FALSE
	var/datum/gas_mixture/air = T.return_air()
	var/obj/item/organ/lungs/lungs = owner.getorganslot(ORGAN_SLOT_LUNGS)
	if(!air || !lungs || air.temperature >= lungs.cold_level_1_threshold || air.temperature < BOT_COLD_FLOOR)
		return FALSE
	var/total = air.total_moles()
	if(!total)
		return FALSE
	var/per_mole = air.return_pressure() / total
	if(air.moles[/datum/gas/oxygen] * per_mole < lungs.safe_oxygen_min)
		return FALSE
	if(lungs.safe_toxins_max && air.moles[/datum/gas/plasma] * per_mole > lungs.safe_toxins_max)
		return FALSE
	if(lungs.safe_co2_max && air.moles[/datum/gas/carbon_dioxide] * per_mole > lungs.safe_co2_max)
		return FALSE
	return air.moles[/datum/gas/bz] * per_mole <= lungs.BZ_trip_balls_min

/// Somewhere only cold is somewhere it can go for something, while it's warm enough itself.
/datum/bot_brain/in_bad_air(atom/A)
	. = ..()
	if(!. || owner.bodytemperature < BODYTEMP_COLD_DAMAGE_LIMIT + 10)
		return
	var/turf/T = get_turf(A)
	if(isopenturf(T))
		return !turf_air_just_cold(T)
	for(var/turf/open/next_to in get_adjacent_open_turfs(T)) //a wall fitting: the floor by it
		if(turf_air_just_cold(next_to))
			return FALSE

/// In cold air on an errand: half a minute before it gets out, errand or not.
/datum/bot_brain/get_out_of_bad_air()
	if(!in_the_flames() && turf_air_just_cold(get_turf(owner)))
		if(!cold_trip_since)
			cold_trip_since = world.time
		if(state == BOT_STATE_GOAL && world.time < cold_trip_since + BOT_COLD_TRIP && owner.bodytemperature >= BODYTEMP_COLD_DAMAGE_LIMIT)
			return
	else
		cold_trip_since = 0
	return ..()

#undef BOT_COLD_TRIP
#undef BOT_COLD_FLOOR
