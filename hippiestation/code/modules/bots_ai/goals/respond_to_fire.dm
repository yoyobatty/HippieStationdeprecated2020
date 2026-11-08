// Fire response: an Atmospheric Technician/Station Engineer/Chief Engineer puts out an
// active fire (SSair.hotspots, LINDA_fire.dm) with a fire extinguisher - the real
// mechanic behind a player spraying one (extinguisher.dm's afterattack(), a RANGED spray
// that lands water/firefighting foam on a target turf from up to `power` tiles away, not
// a melee-range interaction).
//
// Own safety comes first, and it is NOT the same guarantee for every hardsuit - confirmed
// via source read (hardsuit.dm): the Atmospherics hardsuit AND the Chief Engineer's
// "elite" hardsuit both set heat_protection + max_heat_protection_temperature =
// FIRE_IMMUNITY_MAX_TEMP_PROTECT (full heat immunity, get_heat_protection(), human/
// life.dm) on both their suit and helmet pieces - but the PLAIN Station Engineer hardsuit
// sets NEITHER var at all. resistance_flags = FIRE_PROOF (every one of these suits has
// it) only protects the SUIT ITSELF from being destroyed - it says nothing about the
// WEARER taking heat damage, a completely separate mechanic. An Atmos Tech or CE can walk
// right up to a fire; a Station Engineer bot in the exact same "fireproof"-sounding
// hardsuit would take real burn damage doing that.
//
// bot_is_heat_immune_to() (below) queries the bot's ACTUAL worn gear at runtime
// (get_heat_protection(), not a per-job assumption) - so this is correct automatically
// regardless of which specific hardsuit a bot ends up wearing, without needing to special-
// case any particular job here. Since the extinguisher is ranged regardless, there's no
// reason an unprotected bot should ever stand next to the fire at all - spray from a safe
// distance and let the water travel in.

#define FIRE_IMMUNE_SPRAY_RANGE 1 //full heat immunity - close enough to be efficient
#define FIRE_UNPROTECTED_SPRAY_RANGE 4 //no heat protection at all - stay outside the flame, near the edge of the extinguisher's own reach (power=5, extinguisher.dm) instead of standing in it

/datum/bot_brain/proc/is_fire_response_job()
	var/role = work_role()
	return role == "Station Engineer" || role == "Chief Engineer" || role == "Atmospheric Technician"

/datum/bot_brain/proc/bot_is_heat_immune_to(temperature)
	return owner.get_heat_protection(temperature) >= 1

/datum/bot_brain
	/// heat_proof(), as of heat_proof_at: route planning asks it once for every burning tile it looks at
	var/heat_proof_cached = FALSE
	var/heat_proof_at = -1
	/// Before it says anything about a fire again
	var/next_fire_report_time = 0

/// Area -> world.time somebody last radioed a fire there, so a corridor full of crew watching one burn isn't a radio full of them.
GLOBAL_LIST_EMPTY(bot_fire_reports)

/// Not a firefighter's fire: radioed in, once a place, and kept clear of (the flames are a hazard on its routes, bot_hazards.dm).
/datum/bot_brain/proc/report_fire()
	next_fire_report_time = world.time + 30 SECONDS
	var/area/A = get_area(owner)
	if(!A || world.time < GLOB.bot_fire_reports[A])
		return
	GLOB.bot_fire_reports[A] = world.time + 2 MINUTES
	var/where = get_area_name(owner, TRUE)
	bot_say(owner, ";[pick("Fire in [where]!", "There's a fire in [where], engineering!", "Fire! [where]!", "We've got a fire in [where].")]")
	bot_tally("reported a fire")

/// Dressed for fire: an atmos or CE hardsuit, a firesuit and helmet, a nanosuit. The engineering hardsuit isn't, and an engineer in
/// one burnt to death in a player's fire.
/datum/bot_brain/proc/heat_proof()
	if(heat_proof_at != world.time)
		heat_proof_at = world.time
		heat_proof_cached = owner.get_thermal_protection() >= FIRE_IMMUNITY_MAX_TEMP_PROTECT
	return heat_proof_cached

/// Whether a tile would burn somebody with no heat protection: flames on it, or air hot enough to hurt.
/proc/bot_tile_burns(turf/open/T)
	if(!istype(T))
		return FALSE
	if(T.active_hotspot)
		return TRUE
	var/datum/gas_mixture/air = T.air
	return air && air.temperature > BODYTEMP_HEAT_DAMAGE_LIMIT

/// Flames or burning air on either side of a shut firelock. It's shut because of them, and prising it open lets the fire through to
/// whoever did it: an engineer went through two that way to fetch an extinguisher from inside the fire.
/proc/bot_fire_behind(obj/machinery/door/firedoor/F)
	if(bot_tile_burns(get_turf(F)))
		return TRUE
	for(var/direction in GLOB.cardinals)
		if(bot_tile_burns(get_step(F, direction)))
			return TRUE
	return FALSE

/// Standing in flames or air that burns: out of it first, whatever it was doing. Rolling on the floor in them is how it ends (that's
/// try_put_self_out()), and an engineer that had caught light stood in a burning corridor for fourteen seconds before going back into
/// the fire for an extinguisher, and died there.
/datum/bot_brain/proc/try_escape_flames()
	var/turf/open/here = owner.loc
	if(!istype(here) || owner.buckled || !bot_tile_burns(here) || heat_proof())
		return FALSE
	if(pursuing_kind == "flames" && pursue_target && !bot_tile_burns(get_turf(pursue_target)))
		return TRUE //on its way out
	var/turf/open/out = bot_way_out_of_fire(here)
	if(!out)
		return FALSE
	bot_log(src, "in the flames at [bot_coord(here)], getting out to [bot_coord(out)]")
	bot_tally("got out of a fire")
	if(get_dist(here, out) <= 1)
		owner.Move(out, get_dir(here, out))
	else
		pursue(out, "flames", force = TRUE)
	return TRUE

/// The nearest floor that doesn't burn, the way the air goes: a fire's air reaches wherever a person can walk, near enough.
/proc/bot_way_out_of_fire(turf/open/from)
	var/list/seen = list()
	seen[from] = TRUE
	var/list/frontier = list(from)
	for(var/depth in 1 to 8)
		var/list/next = list()
		for(var/turf/open/T as anything in frontier)
			for(var/turf/open/N as anything in T.atmos_adjacent_turfs)
				if(seen[N])
					continue
				seen[N] = TRUE
				if(isspaceturf(N) || is_blocked_turf(N, TRUE))
					continue
				if(!bot_tile_burns(N))
					return N
				next += N
		frontier = next
	return null

// True the instant a fire is actually in front of the bot, not just "on the station
// somewhere" - view() is BYOND's line-of-sight-aware range check (unlike range()/
// orange(), it respects walls/opacity the way a real player's vision does), so this
// only fires for a fire the bot could genuinely see right now. Checked every tick in
// handle_wander() (bot_brain.dm), ahead of and independent from the timer-gated
// try_fire_response_round() below - a bot standing right next to a fire that just
// started has no business waiting out next_fire_check_time's normal 5-15s pace before
// reacting, the same way a real person notices flames in front of them immediately.
/datum/bot_brain/proc/can_see_active_fire()
	// No fire anywhere near: no look round for one. A view() a tick for every bot came to 112 us a call, 4 seconds a shift.
	var/list/fires = SSair.hotspots
	if(!length(fires))
		return FALSE
	var/turf/here = get_turf(owner)
	if(!here)
		return FALSE
	if(length(fires) < 60)
		var/near = FALSE
		for(var/obj/effect/hotspot/F as anything in fires)
			if(F.z == here.z && get_dist(F, here) <= 7)
				near = TRUE
				break
		if(!near)
			return FALSE
	for(var/obj/effect/hotspot/H in view(7, owner))
		if(!QDELETED(H))
			return TRUE
	return FALSE

/datum/bot_brain/proc/find_active_fire()
	var/turf/bot_turf = get_turf(owner)
	var/obj/effect/hotspot/best
	var/best_dist
	for(var/obj/effect/hotspot/H in SSair.hotspots)
		if(QDELETED(H))
			continue
		var/turf/T = get_turf(H)
		if(!T || T.z != owner.z)
			continue
		var/dist = get_dist(bot_turf, T)
		if(!best || dist < best_dist)
			best = H
			best_dist = dist
	return best

/datum/bot_brain/proc/find_extinguisher_cabinet()
	var/turf/bot_turf = get_turf(owner)
	var/obj/structure/extinguisher_cabinet/best
	var/best_dist
	for(var/obj/structure/extinguisher_cabinet/C as anything in bot_instances_of(/obj/structure/extinguisher_cabinet))
		if(!C.stored_extinguisher)
			continue
		var/turf/T = get_turf(C)
		if(!T || T.z != owner.z)
			continue
		if(!heat_proof() && (bot_tile_burns(T) || bot_tile_burns(get_step(T, C.dir)))) //where you'd stand to open it
			continue
		var/dist = get_dist(bot_turf, T)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

// A turf `range` tiles out from the fire, in whatever direction the bot's currently
// approaching from - not full pathfinding-aware, but pursue() (bot_movement.dm) already
// routes to the nearest REACHABLE point near any target it can't stand exactly on, so an
// unreachable exact tile here still resolves to somewhere safely nearby in practice.
/datum/bot_brain/proc/find_safe_spray_turf(turf/fire_turf, range)
	var/turf/bot_turf = get_turf(owner)
	if(!fire_turf || !bot_turf)
		return null
	// Floor it can stand on that sees the fire, out of the flames, as far back as the extinguisher reaches, on its own side. Straight
	// back along the way it came was often a wall or the middle of the fire: in a plasma flood in Hippie's Bar the engineers gave up on
	// every fire they tried, and four of the crew burned.
	var/turf/best
	var/best_score
	for(var/turf/open/T in view(range, fire_turf))
		if(T == fire_turf || isspaceturf(T) || T.active_hotspot || is_blocked_turf(T, TRUE))
			continue
		var/score = get_dist(T, bot_turf) + (range - get_dist(T, fire_turf)) * 2
		if(!best || score < best_score)
			best = T
			best_score = score
	return best || get_ranged_target_turf(fire_turf, get_dir(fire_turf, bot_turf) || SOUTH, range)

/datum/bot_brain/proc/try_fire_response_round()
	if(!is_fire_response_job())
		return FALSE
	// Alight, or already burnt half to death: somebody else's fire to fight. An engineer at half health and still burning went back
	// for an extinguisher, then to fix the cable in the same fire.
	if(owner.on_fire || owner.health < owner.maxHealth * 0.5)
		return FALSE
	return assign_goal(new /datum/bot_goal/fight_fire())

// Same immediate-rechain idea as continue_contamination_round() (respond_to_
// contamination.dm) - finish one fire, go straight to the next instead of waiting out
// the normal wander pace.
/datum/bot_brain/proc/continue_fire_response_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_fire_response_round)))

/datum/bot_goal/fight_fire
	var/turf/spray_from

/datum/bot_goal/fight_fire/resolve_target(datum/bot_brain/bot)
	var/obj/effect/hotspot/H = bot.find_active_fire()
	if(!H)
		return
	var/turf/fire_turf = get_turf(H)
	if(!fire_turf)
		return
	var/immune = bot.bot_is_heat_immune_to(H.temperature)
	spray_from = bot.find_safe_spray_turf(fire_turf, immune ? FIRE_IMMUNE_SPRAY_RANGE : FIRE_UNPROTECTED_SPRAY_RANGE)
	if(!spray_from)
		return
	target = H

/datum/bot_goal/fight_fire/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/fight_fire(spray_from))

/datum/bot_goal/fight_fire/on_success(datum/bot_brain/bot)
	bot.continue_fire_response_round()

// No on_give_up cooldown - a fire either goes out (on_success) or the bot's still
// actively working it (PENDING, spray_fire's own retry loop) - there's no "this specific
// fire is unreachable forever" failure mode worth remembering the way failed_engine_parts
// does for a stuck singularity generator; a genuinely unreachable fire just gets
// re-evaluated fresh (and likely re-picked, or skipped if truly cut off) next cycle.

/datum/bot_strategy/fight_fire/New(turf/spray_from)
	. = ..()
	var/datum/bot_step/move_to/to_spray_spot = new()
	to_spray_spot.step_target = spray_from
	steps = list(new /datum/bot_step/ensure_extinguisher(), to_spray_spot, new /datum/bot_step/spray_fire())

/datum/bot_strategy/fight_fire/is_feasible(datum/bot_brain/bot)
	return TRUE

// Covers both real-world sources at once - "often found in fire fighting closets or
// extinguisher cabinets": a fast path for the wall-mounted /obj/structure/
// extinguisher_cabinet case (a single attack_hand() click dispenses its stored one
// directly, extinguisher.dm - it's NOT a closet subtype, so acquire_item_type's own
// closet-search tier below would never find one sitting in one), and a fallback through
// the same generic item-fetch machinery every other tool acquisition in this system
// already uses (acquire_item_type.dm) for everything else - loose extinguishers, AND any
// /obj/structure/closet's contents, firefighting closets (utility_closets.dm's
// /obj/structure/closet/firecloset, stocked with a fire suit + mask + tank +
// extinguisher) included, since that search isn't restricted to any specific closet
// subtype. Suspended as a sub-goal rather than searched inline here, same as
// gear_up_eva.dm's own tank-fetch - the outer goal (this fire) resumes automatically
// once it's satisfied.
/datum/bot_step/ensure_extinguisher/execute(datum/bot_brain/bot)
	if(bot.find_carried_tool(/obj/item/extinguisher))
		return GOAL_STEP_SUCCESS
	var/obj/structure/extinguisher_cabinet/C = bot.find_extinguisher_cabinet()
	if(C)
		if(!bot.owner.Adjacent(C))
			bot.pursue(C, "goal", force = TRUE)
			return GOAL_STEP_PENDING
		bot.use_atom(C)
		if(bot.find_carried_tool(/obj/item/extinguisher))
			return GOAL_STEP_SUCCESS
	var/datum/bot_goal/acquire_item_type/sub = new()
	sub.item_type = /obj/item/extinguisher
	if(bot.suspend_goal_for(sub))
		return GOAL_STEP_PENDING
	bot_log(bot, "no fire extinguisher reachable to fight this fire with")
	return GOAL_STEP_FAIL

/datum/bot_step/spray_fire/execute(datum/bot_brain/bot)
	var/obj/effect/hotspot/H = bot.current_goal?.target
	if(!H || QDELETED(H))
		return GOAL_STEP_SUCCESS //already out - someone/something else got it, or it burned itself out
	var/turf/fire_turf = get_turf(H)
	if(!fire_turf)
		return GOAL_STEP_SUCCESS
	var/obj/item/extinguisher/E = bot.find_carried_tool(/obj/item/extinguisher)
	if(!E)
		bot_log(bot, "lost my extinguisher mid-fight somehow")
		return GOAL_STEP_FAIL
	if(E.reagents.total_volume < 1)
		bot_log(bot, "[E] is empty - can't keep fighting this fire")
		return GOAL_STEP_FAIL
	if(E.safety)
		bot.toggle_in_hand(E)
	if(bot.owner.get_active_held_item() != E && !bot.ready_in_hand(E)) //put_in_hands() on one in a pocket left it in the pocket too: a hard delete
		bot_log(bot, "couldn't get [E] into my hand")
		return GOAL_STEP_FAIL
	bot.owner.face_atom(fire_turf)
	bot.telemetry_shortcut("afterattack", E, fire_turf) //telemetry
	E.afterattack(fire_turf, bot.owner, 0) //internally cooldown-gated (last_use, extinguisher.dm) - harmless to call again before it's ready
	return GOAL_STEP_PENDING

#undef FIRE_IMMUNE_SPRAY_RANGE
#undef FIRE_UNPROTECTED_SPRAY_RANGE
