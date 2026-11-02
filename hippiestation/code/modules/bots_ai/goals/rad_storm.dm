// Radiation storms. There's forty seconds' warning (weather/telegraph()), and everybody who's played before runs for maintenance:
// the tunnels, the emergency closets and the shuttles are the only places it doesn't reach. Out in it, it's 20 rads two times in
// five every couple of seconds and a mutation on top. A griefed shift that rolled one lost 8 of 24, every one of them still at work.

/datum/weather/rad_storm
	/// Whether anybody's said so on the radio yet.
	var/bots_warned = FALSE

/// The storm on its way to, or blowing through, this level.
/proc/bot_rad_storm(z_level)
	for(var/datum/weather/rad_storm/W in SSweather.processing)
		if((z_level in W.impacted_z_levels) && (W.stage == STARTUP_STAGE || W.stage == MAIN_STAGE))
			return W
	return null

/datum/bot_brain/proc/out_in_rads(datum/weather/rad_storm/W)
	return !is_type_in_list(get_area(owner), W.protected_areas)

/// Just inside the nearest door to somewhere the storm doesn't reach.
/datum/bot_brain/proc/find_rad_shelter(datum/weather/rad_storm/W)
	var/list/found = list() //turf -> how far off
	for(var/obj/machinery/door/airlock/A as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(QDELETED(A) || A.z != owner.z || A.welded || A.locked || get_dist(owner, A) > 60)
			continue
		for(var/d in GLOB.cardinals)
			var/turf/T = get_step(A, d)
			if(isopenturf(T) && is_type_in_list(T.loc, W.protected_areas) && !is_blocked_turf(T, TRUE))
				found[T] = get_dist(owner, T)
	var/tries = 0
	while(length(found) && tries++ < 6)
		var/turf/nearest
		for(var/turf/T as anything in found)
			if(!nearest || found[T] < found[nearest])
				nearest = T
		found -= nearest
		if(can_walk_lawfully_to(nearest))
			return nearest
	return null

/datum/bot_goal/rad_shelter
	lawful = TRUE
	doing = "getting out of the radiation"

/datum/bot_goal/rad_shelter/resolve_target(datum/bot_brain/bot)
	var/datum/weather/rad_storm/W = bot_rad_storm(bot.owner.z)
	if(W)
		target = bot.find_rad_shelter(W)

/datum/bot_goal/rad_shelter/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

/datum/bot_duty/rad_shelter
	name = "sheltering from the radiation"
	tier = BOT_DUTY_URGENT
	priority = 190
	interval_min = 20
	interval_max = 40
	interrupts = TRUE

/datum/bot_duty/rad_shelter/should_interrupt(datum/bot_brain/bot)
	var/datum/weather/rad_storm/W = bot_rad_storm(bot.owner.z)
	return W && !istype(bot.current_goal, /datum/bot_goal/rad_shelter) && bot.out_in_rads(W)

/datum/bot_duty/rad_shelter/try_start(datum/bot_brain/bot)
	var/datum/weather/rad_storm/W = bot_rad_storm(bot.owner.z)
	if(!W)
		return FALSE
	if(!bot.out_in_rads(W))
		bot.holding_duty = src
		return FALSE
	if(!W.bots_warned)
		W.bots_warned = TRUE
		bot_news("we've just had a rad storm")
		bot_say(bot.owner, ";[pick("Radiation storm! Everybody into maintenance!", "Rad storm, get to maint!", "Storm's coming, get in the tunnels!")]")
	if(bot.assign_goal(new /datum/bot_goal/rad_shelter()))
		bot_tally("ran for shelter")
		return TRUE
	return FALSE

/datum/bot_duty/rad_shelter/keep_holding(datum/bot_brain/bot)
	var/datum/weather/rad_storm/W = bot_rad_storm(bot.owner.z)
	return W && !bot.out_in_rads(W)
