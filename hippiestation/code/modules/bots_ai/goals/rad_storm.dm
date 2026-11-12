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
			return rad_shelter_spot(nearest, W)
	return null

/// Somewhere to stand a few steps in from the doorway that nobody's stood on: the furthest in of what's within three steps of the tile just
/// inside. That tile is where the next one in walks into whoever got there first and swaps them out into the doorway: two officers
/// sheltering by one maintenance door put each other back out that way, and ran back in twenty times each in one storm (bugs1112base run1).
/datum/bot_brain/proc/rad_shelter_spot(turf/just_inside, datum/weather/rad_storm/W)
	var/list/reached = list(just_inside)
	var/list/steps_in = list()
	steps_in[just_inside] = 0
	var/turf/spot = just_inside
	var/spot_free = !(locate(/mob/living/carbon/human) in just_inside)
	var/at = 1
	while(at <= length(reached))
		var/turf/inner = reached[at++]
		if(steps_in[inner] >= 3)
			continue
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(inner, d)
			if(!isopenturf(next) || !isnull(steps_in[next]) || !is_type_in_list(next.loc, W.protected_areas) || is_blocked_turf(next, TRUE) || (locate(/obj/machinery/door) in next))
				continue
			steps_in[next] = steps_in[inner] + 1
			reached += next
			if(!(locate(/mob/living/carbon/human) in next) && (!spot_free || steps_in[next] > steps_in[spot]))
				spot = next
				spot_free = TRUE
	return spot

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

/// Under cover: it stays from this moment (keep_holding() below), as a miner does out of an ash storm (goals/mining.dm). The hold used to
/// wait for the duty's next look, a few seconds on, and a stroll or a pick-up had it back out of the door before then: an officer just into
/// the tunnels went for a jumpsuit lying in the Prison Wing within the second (bugs1112base run1).
/datum/bot_goal/rad_shelter/on_success(datum/bot_brain/bot)
	bot.holding_duty = bot_duty_of(/datum/bot_duty/rad_shelter)

/// What a bot sheltering from the storm still gets up for (assign_goal(), bot_goals.dm): out of air it can't breathe, away from somebody,
/// a bomb's timer, the shuttle leaving, patching itself up where it stands, and anything in this same stretch of tunnel. Where a trip to a
/// sleeper goes is the sleeper, not the bot it names; anything else that only names the bot doesn't say where it walks it.
/datum/bot_brain/proc/rad_storm_errand_ok(datum/bot_goal/goal)
	if(istype(goal, /datum/bot_goal/rad_shelter) || istype(goal, /datum/bot_goal/run_from) || istype(goal, /datum/bot_goal/seek_air) || istype(goal, /datum/bot_goal/refill_internals) || istype(goal, /datum/bot_goal/self_heal) || istype(goal, /datum/bot_goal/evacuate) || istype(goal, /datum/bot_goal/defuse_bomb))
		return TRUE
	var/atom/goes_to = goal.target
	var/datum/bot_goal/seek_medbay_healing/healing = goal
	if(istype(healing))
		goes_to = healing.machine_target
	if(!goes_to || goes_to == owner)
		return FALSE
	return get_area(goes_to) == get_area(owner)

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
