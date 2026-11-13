// Hunting (the plan's foundation/hunt.dm, M3): looking for somebody it's lost. Lose sight of a suspect and an officer used to say so on the
// radio and give up. A player looks: where they were last seen, the rooms they'd have gone on to, the lockers and crates they could be in.
//
// The search (search_for): a belief over the rooms round where they were last seen (the tactical map's rooms, foundation/tactical_map.dm),
// spreading out to the rooms next door as time goes on, more the way they were heading, and dropping for a room once it's been searched.
// In each room it opens the lockers, crates and body bags, nearest the likeliest spot first; seeing them ends it (the arrest, or whatever
// it was, takes over again). How long it keeps at it, and how many places it opens, goes by skill (skill.dm). An apex hunter is also
// steered by the director (apex/director.dm): now and then a clue of roughly where they are, never the tile.
// In the gym (one room, no tactical map) it's the hiding spots round the last sighting, or round the clue.

#define BOT_SEARCH_RANGE 8

/datum/bot_brain
	/// When it last saw somebody it's searching for close to: the director eases off after a close call
	var/search_close_call_at = 0

/// Starts a search for Q, last seen at `last_seen` at `seen_at`. `why`: "arrest" (a major crime), "arrest_minor", "hunt" or "kill".
/datum/bot_brain/proc/start_search(mob/living/Q, turf/last_seen, seen_at, why)
	if(!Q || !last_seen || QDELETED(owner) || owner.stat != CONSCIOUS)
		return FALSE
	var/mob/living/carbon/C = Q
	if(Q.stat != CONSCIOUS || (istype(C) && C.handcuffed))
		return FALSE //caught or down already: nobody to search for (somebody else's arrest, often)
	var/datum/bot_goal/search_for/S = new(Q, last_seen, seen_at, why)
	S.heading_away = get_dir(owner, last_seen)
	if(!assign_goal(S))
		return FALSE
	bot_log(src, "HUNT: lost [Q] - searching from [get_area_name(last_seen, TRUE)] ([why])")
	bot_tally("searches")
	return TRUE

/datum/bot_goal/search_for
	exclusive = TRUE
	never_rests = TRUE
	doing = "searching for somebody"
	var/datum/weakref/quarry_ref
	var/turf/last_seen
	var/seen_at = 0
	var/why
	/// Which way they went: from the hunter to where they were last seen
	var/heading_away = 0
	var/ends_at = 0
	var/spots_left = 0
	/// Hiding spot -> TRUE, opened (or no getting to it)
	var/list/checked = list()
	/// Area -> how likely they're in it
	var/list/belief = list()
	/// Area -> TRUE, been and looked
	var/list/visited = list()
	var/next_spread = 0
	/// Where the director last said they were, roughly (apex/director.dm)
	var/turf/clue
	var/next_clue = 0
	/// The place it's walking to, to look round it
	var/turf/heading_for
	var/obj/spot_going_to
	var/spot_tries = 0
	/// Nowhere left to look, waiting on a clue (apex)
	var/listening = FALSE

/datum/bot_goal/search_for/New(mob/living/Q, turf/T, at, reason)
	. = ..()
	quarry_ref = WEAKREF(Q)
	last_seen = T
	seen_at = at
	why = reason
	lawful = (reason == "arrest_minor" || reason == "hunt")
	target = T

/datum/bot_goal/search_for/resolve_target(datum/bot_brain/bot)
	target = last_seen

/datum/bot_goal/search_for/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/staged())
	return list(S)

/datum/bot_goal/search_for/on_success(datum/bot_brain/bot)
	var/mob/living/carbon/human/Q = quarry_ref?.resolve()
	if(!istype(Q) || Q.stat == DEAD)
		return
	if(why == "arrest" || why == "arrest_minor")
		addtimer(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, begin_arrest), Q), 1)

/// Its skill's patience (skill.dm): how long, and how many places it opens
/datum/bot_goal/search_for/proc/start_looking(datum/bot_brain/bot)
	var/minor = why == "arrest_minor"
	if(bot.is_apex())
		ends_at = world.time + (minor ? 60 SECONDS : 150 SECONDS)
		spots_left = minor ? 6 : 30
	else if(bot.skill_at_least(BOT_SKILL_MID))
		ends_at = world.time + (minor ? 40 SECONDS : 90 SECONDS)
		spots_left = minor ? 4 : 12
	else
		ends_at = world.time + (minor ? 20 SECONDS : 40 SECONDS)
		spots_left = minor ? 1 : 3
	var/area/A = get_area(last_seen)
	belief[A] = 1
	next_spread = world.time + 5 SECONDS
	add_destination_priors(bot)

/datum/bot_goal/search_for/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	var/mob/living/Q = quarry_ref?.resolve()
	var/mob/living/carbon/C = Q
	if(!Q || Q.stat == DEAD || (istype(C) && C.handcuffed))
		return GOAL_STEP_FAIL
	if(!ends_at)
		start_looking(bot)
	var/turf/their_turf = get_turf(Q)
	if(isturf(Q.loc) && (Q in view(BOT_SIGHT_RANGE, bot.owner)))
		bot.stop_pursuit()
		bot_log(bot, "HUNT: found [Q] in [get_area_name(Q, TRUE)]")
		bot_tally("found somebody being searched for")
		bot.search_close_call_at = world.time
		return GOAL_STEP_SUCCESS
	if(their_turf && their_turf.z == bot.owner.z && get_dist(their_turf, bot.owner) <= 3)
		bot.search_close_call_at = world.time //right by them and didn't know it
	if(world.time > ends_at)
		bot_log(bot, "HUNT: gave up looking for [Q]")
		return GOAL_STEP_FAIL
	if(++step.actions > 115)
		step.actions = 0 //the staged step's own count: a search goes on as long as its patience
	bot.director_clue(src, Q) //apex/director.dm
	if(world.time >= next_spread)
		next_spread = world.time + 5 SECONDS
		spread_belief(bot)
	var/mob/living/carbon/human/H = bot.owner
	// The next place they could be in, near where they most likely are
	if(spots_left > 0)
		var/obj/spot = spot_going_to
		if(!spot || QDELETED(spot) || checked[spot])
			spot = next_spot(bot)
			spot_going_to = spot
			spot_tries = 0
		if(spot)
			if(!H.Adjacent(spot))
				if(++spot_tries > 12)
					checked[spot] = TRUE //no getting to it
					return step.again(bot, 2)
				if(bot.pursue_target != spot)
					bot.pursue(spot, "follow", force = TRUE)
				return step.again(bot, 5)
			bot.stop_pursuit()
			checked[spot] = TRUE
			spots_left--
			bot_log(bot, "HUNT: checking [spot] for [Q]")
			open_spot(bot, spot)
			return step.again(bot, 5)
	// Nothing left to open round here: on to the likeliest room it hasn't been to
	var/turf/here = get_turf(H)
	if(heading_for && get_dist(here, heading_for) > 1 && !visited[get_area(heading_for)])
		if(bot.pursue_target != heading_for)
			bot.pursue(heading_for, "follow", force = TRUE)
		return step.again(bot, 5)
	if(heading_for)
		visited[get_area(heading_for)] = TRUE
		belief[get_area(heading_for)] *= 0.1
	heading_for = next_place(bot)
	if(!heading_for)
		// An apex hunter listens out for them (apex/director.dm) for as long as its patience lasts; anybody else has run out of ideas
		if(bot.is_apex())
			if(!listening)
				listening = TRUE
				bot_log(bot, "HUNT: nowhere left to look for [Q] - listening out for them")
			bot.stop_pursuit()
			return step.again(bot, 10)
		bot_log(bot, "HUNT: nowhere left to look for [Q]")
		return GOAL_STEP_FAIL
	listening = FALSE
	bot.pursue(heading_for, "follow", force = TRUE)
	return step.again(bot, 5)

/// Where somebody running would be going (mid skill and up): hurt, to Medbay; wanted, into maintenance to lie low; with the shuttle in,
/// to Departures. The rooms of that kind near the last sighting start a little likely.
/datum/bot_goal/search_for/proc/add_destination_priors(datum/bot_brain/bot)
	var/mob/living/Q = quarry_ref?.resolve()
	var/datum/tactical_map/M = tactical_map(bot.owner.z)
	if(!Q || !M || !bot.skill_at_least(BOT_SKILL_MID))
		return
	var/list/kinds = list()
	if(Q.health < Q.maxHealth * 0.6)
		kinds += /area/medical
	if(why == "arrest" || why == "arrest_minor" || why == "hunt")
		kinds += /area/maintenance
	if(SSshuttle.emergency?.mode == SHUTTLE_DOCKED)
		kinds += /area/hallway/secondary/exit
	if(!length(kinds))
		return
	for(var/area/A as anything in M.links)
		if(!is_type_in_list(A, kinds))
			continue
		var/turf/centre = M.centre_of(A)
		if(centre && get_dist(centre, last_seen) <= 40)
			belief[A] += 0.3
/datum/bot_goal/search_for/proc/search_centre()
	return clue || last_seen

/// The nearest unopened hiding spot round the likeliest spot: lockers, crates, body bags, morgue trays
/datum/bot_goal/search_for/proc/next_spot(datum/bot_brain/bot)
	var/turf/centre = search_centre()
	var/obj/best
	var/best_dist
	for(var/obj/O in range(BOT_SEARCH_RANGE, centre))
		if(checked[O] || !bot_hiding_spot(O))
			continue
		var/dist = get_dist(O, centre)
		if(!best || dist < best_dist)
			best = O
			best_dist = dist
	return best

/proc/bot_hiding_spot(obj/O)
	var/obj/structure/closet/C = O
	if(istype(C))
		return !C.opened && !C.wall_mounted
	var/obj/structure/bodycontainer/B = O
	return istype(B) && B.connected && B.connected.loc == B //a morgue tray that's in

/datum/bot_goal/search_for/proc/open_spot(datum/bot_brain/bot, obj/spot)
	var/obj/structure/closet/C = spot
	if(istype(C))
		if(!bot.open_closet(C) && (C.locked || C.welded))
			bot_log(bot, "HUNT: [C] won't open")
		return
	bot.use_atom(spot) //a morgue tray rolls out

/// The rooms round where they were last seen get likelier as time goes on, more the way they were heading
/datum/bot_goal/search_for/proc/spread_belief(datum/bot_brain/bot)
	var/datum/tactical_map/M = tactical_map(bot.owner.z)
	if(!M)
		return
	var/list/next = list()
	for(var/area/A as anything in belief)
		var/w = belief[A]
		next[A] += w * 0.75
		for(var/area/N as anything in M.neighbours(A))
			var/turf/centre = M.centre_of(N)
			var/bias = 1
			if(heading_away && centre && last_seen)
				var/d = get_dir(last_seen, centre)
				bias = (d & heading_away) ? 1.5 : 0.7
			next[N] += w * 0.25 * bias * (visited[N] ? 0.1 : 1)
	belief = next

/// The likeliest room it hasn't looked round yet: a floor tile at its middle
/datum/bot_goal/search_for/proc/next_place(datum/bot_brain/bot)
	var/datum/tactical_map/M = tactical_map(bot.owner.z)
	if(!M)
		return null
	if(clue && !visited[get_area(clue)])
		return clue
	var/area/best
	for(var/area/A as anything in belief)
		if(visited[A] || !belief[A])
			continue
		if(!best || belief[A] > belief[best])
			best = A
	return best ? M.centre_of(best) : null

/datum/bot_goal/hunt/on_success(datum/bot_brain/bot)
	. = ..()
	var/mob/living/mark = mark_ref?.resolve()
	if(mark && mark.stat != DEAD && !(mark in view(BOT_SIGHT_RANGE, bot.owner)))
		addtimer(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, start_search), mark, last_seen, seen_at, "hunt"), 2)

#undef BOT_SEARCH_RANGE
