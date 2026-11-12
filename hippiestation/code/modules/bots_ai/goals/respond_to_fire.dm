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

/// Not a firefighter's fire: radioed in, once a place, and kept clear of (the flames are a hazard on its routes, bot_hazards.dm). The
/// place is the fire's, not where the bot's stood looking at it: that's what the engineers hearing it go to (heard_of_fire()).
/datum/bot_brain/proc/report_fire(area/A)
	next_fire_report_time = world.time + 30 SECONDS
	if(!A || world.time < GLOB.bot_fire_reports[A])
		return
	if(!can_radio())
		if(try_fire_alarm(A, TRUE))
			GLOB.bot_fire_reports[A] = world.time + 2 MINUTES
		return
	GLOB.bot_fire_reports[A] = world.time + 2 MINUTES
	var/where = get_area_name(A, TRUE)
	bot_say(owner, ";[pick("Fire in [where]!", "There's a fire in [where], engineering!", "Fire! [where]!", "We've got a fire in [where].")]")
	bot_tally("reported a fire")

/// Whether a line with ";" goes anywhere: a headset on, and switched on.
/datum/bot_brain/proc/can_radio()
	var/obj/item/radio/R = owner.ears
	return istype(R) && R.on

/// A working fire alarm in that room it can stand at without standing in flames, the nearest.
/datum/bot_brain/proc/room_fire_alarm(area/A)
	var/turf/here = get_turf(owner)
	var/obj/machinery/firealarm/best
	var/best_dist
	for(var/obj/machinery/firealarm/F as anything in bot_instances_of(/obj/machinery/firealarm))
		if(QDELETED(F) || get_area(F) != A || F.buildstage != 2 || !F.is_operational())
			continue
		if(!heat_proof() && bot_tile_burns(get_turf(F)))
			continue
		var/dist = get_dist(here, F)
		if(!best || dist < best_dist)
			best = F
			best_dist = dist
	return best

/// Off to the room's fire alarm: to pull it (a fire seen with no radio to call it in) or reset it (the fire it put out).
/datum/bot_brain/proc/try_fire_alarm(area/A, pulling)
	if(!A || A.fire == pulling) //going already, or reset already
		return FALSE
	var/datum/bot_goal/fire_alarm/G = new
	G.room = A
	G.pulling = pulling
	if(!pulling)
		G.doing = "resetting the fire alarm"
	return assign_goal(G)

/// Flames in that room that are somebody's to put out.
/proc/bot_area_burning(area/A)
	for(var/obj/effect/hotspot/H as anything in SSair.hotspots)
		if(!QDELETED(H) && H.loc?.loc == A && !bot_fire_meant_to_burn(H.loc))
			return TRUE
	return FALSE

/// A fire put out: the next it knows of, else the room's fire alarm reset now that it's out. Left on, it shuts the room's firelocks
/// every ten seconds and stays on every alert console.
/datum/bot_brain/proc/after_fire_round(area/fought)
	if(try_fire_response_round())
		return TRUE
	if(fought && fought.fire && !bot_area_burning(fought))
		return try_fire_alarm(fought, FALSE)
	return FALSE

/// Somebody who sees a fire and has no radio to call it in pulls the room's fire alarm, as a person does: it goes up on every station
/// alert console, which is where the engineers read it (goals/check_alert_console.dm). Both fires in a six-shift test were seen only by
/// crew with no headset on, and no engineer heard of either. The engineer who puts a fire out resets it.
/datum/bot_goal/fire_alarm
	lawful = TRUE
	doing = "pulling the fire alarm"
	var/area/room
	var/pulling = TRUE

/datum/bot_goal/fire_alarm/resolve_target(datum/bot_brain/bot)
	if(room && room.fire != pulling)
		target = bot.room_fire_alarm(room)

/datum/bot_goal/fire_alarm/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/fire_alarm())

/datum/bot_strategy/fire_alarm/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/work_fire_alarm())

/datum/bot_strategy/fire_alarm/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/work_fire_alarm/execute(datum/bot_brain/bot)
	var/datum/bot_goal/fire_alarm/G = bot.current_goal
	var/obj/machinery/firealarm/F = G?.target
	if(!istype(G) || !istype(F) || QDELETED(F) || !bot.owner.Adjacent(F))
		return GOAL_STEP_FAIL
	if(G.room.fire != G.pulling) //nobody's beaten it to it: a hand on it pulls it, or resets it when it's going
		bot.use_atom(F)
		bot_log(bot, "[G.pulling ? "pulled" : "reset"] the fire alarm in [G.room.name]")
	return GOAL_STEP_SUCCESS

#define FIRE_KNOWN_FOR (5 MINUTES)

/datum/bot_brain
	/// Area -> world.time it's forgotten: where this bot knows there's a fire, from seeing it, an alert console or what it heard.
	/// Nothing else sends it to one. Every engineer and atmos tech used to know of every fire on the station: an atmos tech
	/// having a drink 105 tiles away set off for a scientist's toxins burn 5 seconds after it was lit.
	var/list/fires_known

/datum/bot_brain/proc/learn_of_fire(area/A, how)
	if(!A)
		return
	if(!knows_of_fire_in(A))
		bot_log(src, "knows of a fire in [A.name]: [how]")
	LAZYINITLIST(fires_known)
	fires_known[A] = world.time + FIRE_KNOWN_FOR

/datum/bot_brain/proc/knows_of_fire_in(area/A)
	var/until = LAZYACCESS(fires_known, A)
	return until && world.time < until

/// A fire that's meant to be there: in a burn chamber (toxins, the incinerator, the supermatter's), on its engine floor. The rooms
/// round them are the same areas, and a fire on their floor is somebody's to put out. Two engineers hacked four doors, the last the
/// toxins chamber's bolted airlock, to spray a scientist's burn through the glass until the round ended.
/proc/bot_fire_meant_to_burn(turf/T)
	return istype(T, /turf/open/floor/engine) && bot_air_meant_to_be_bad(T)

/// Words that put a fire somewhere: "Fire in the Bar!", "the bar's on fire", "Medbay is burning".
GLOBAL_LIST_INIT(bot_fire_words, list("fire", "fires", "burning", "ablaze", "flames"))

/// A burning place a line names, or null: an area on fire whose own name is in it ("Fire in Aft Primary Hallway!", what bots radio),
/// the longest such, else a place word ("fire in the bar"), the nearest place by that name to `near`.
/proc/bot_fire_place_named(lower_msg, turf/near)
	var/area/best
	var/best_len = 0
	var/list/checked = list()
	for(var/obj/effect/hotspot/H as anything in SSair.hotspots)
		var/area/A = get_area(H)
		if(!A || checked[A])
			continue
		checked[A] = TRUE
		var/name = lowertext(format_text(A.name))
		if(length(name) > best_len && findtext(lower_msg, name))
			best = A
			best_len = length(name)
	return best || bot_area_named(lower_msg, near)

/// A fire called in, by anybody (bots too), to its face or over the radio: where it is, now known. "Fire!" said beside it with no
/// place is where whoever said it is standing.
/datum/bot_brain/proc/heard_of_fire(mob/living/talker, lower_msg, radio_freq)
	if(!is_fire_responder() || !length(SSair.hotspots) || !bot_text_has_any(lower_msg, GLOB.bot_fire_words))
		return
	var/area/where = bot_fire_place_named(lower_msg, get_turf(radio_freq ? owner : talker))
	if(!where && !radio_freq)
		where = get_area(talker)
	if(where)
		learn_of_fire(where, radio_freq ? "heard it on the radio from [talker]" : "told by [talker]")
		next_fire_check_time = min(next_fire_check_time, world.time + rand(10, 30)) //a moment to take it in, not the 5-15 s look round

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
	// Air that's hot with no flames in it, on its tank and dressed for that heat (a fire suit and helmet, goals/refill_internals.dm
	// kit_up_for_air()): nothing burns. bot_tile_burns() counts hot air as well as flames, and heat_proof() asks for the immunity to
	// flames that a fire suit and helmet don't give.
	if(!here.active_hotspot && owner.internal && kept_from_heat(here.return_air().temperature))
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
/// A fire in sight that's somebody's to put out (not a burn chamber's), or null. Where each one it sees is, it now knows.
/datum/bot_brain/proc/can_see_active_fire()
	// No fire anywhere near: no look round for one. A view() a tick for every bot came to 112 us a call, 4 seconds a shift.
	var/list/fires = SSair.hotspots
	if(!length(fires))
		return null
	var/turf/here = get_turf(owner)
	if(!here)
		return null
	if(length(fires) < 60)
		var/near = FALSE
		for(var/obj/effect/hotspot/F as anything in fires)
			if(F.z == here.z && get_dist(F, here) <= 7 && !bot_fire_meant_to_burn(F.loc))
				near = TRUE
				break
		if(!near)
			return null
	var/obj/effect/hotspot/seen
	for(var/obj/effect/hotspot/H in view(7, owner))
		if(QDELETED(H) || bot_fire_meant_to_burn(H.loc))
			continue
		learn_of_fire(get_area(H), "saw it")
		if(!seen)
			seen = H
	return seen

/// The nearest fire it knows of (seen, read off an alert console or heard of), or null.
/datum/bot_brain/proc/find_active_fire()
	if(!LAZYLEN(fires_known))
		return null
	for(var/area/A as anything in fires_known.Copy())
		if(fires_known[A] < world.time)
			fires_known -= A
	if(!length(fires_known))
		fires_known = null
		return null
	var/turf/bot_turf = get_turf(owner)
	var/obj/effect/hotspot/best
	var/best_dist
	for(var/obj/effect/hotspot/H in SSair.hotspots)
		if(QDELETED(H))
			continue
		var/turf/T = get_turf(H)
		if(!T || T.z != owner.z || !knows_of_fire_in(T.loc) || bot_fire_meant_to_burn(T))
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
	if(!is_fire_responder()) //goals/team_repairs.dm: helpers too
		return FALSE
	// Alight, or already burnt half to death: somebody else's fire to fight. An engineer at half health and still burning went back
	// for an extinguisher, then to fix the cable in the same fire.
	if(owner.on_fire || owner.health < owner.maxHealth * 0.5)
		return FALSE
	if(!length(SSair.hotspots) || !LAZYLEN(fires_known)) //none it knows of: no goal to find that out
		return FALSE
	return assign_goal(new /datum/bot_goal/fight_fire())

// Same immediate-rechain idea as continue_contamination_round() (respond_to_
// contamination.dm) - finish one fire, go straight to the next instead of waiting out
// the normal wander pace.
/datum/bot_brain/proc/continue_fire_response_round(area/fought)
	continue_goal_chain(CALLBACK(src, PROC_REF(after_fire_round), fought))

/datum/bot_goal/fight_fire
	var/turf/spray_from
	/// The room the fire's in, for its alarm once it's out
	var/area/fire_area

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
	fire_area = get_area(fire_turf)
	bot_log(bot, "going to put out the fire in [get_area_name(fire_turf)] at [bot_coord(fire_turf)], from [bot_coord(spray_from)]")

/datum/bot_goal/fight_fire/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/fight_fire(spray_from))

/datum/bot_goal/fight_fire/on_success(datum/bot_brain/bot)
	bot.continue_fire_response_round(fire_area)

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
#undef FIRE_KNOWN_FOR
