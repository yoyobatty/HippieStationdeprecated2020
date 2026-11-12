// Space ruins: what an explorer who isn't a miner goes for (the user's ruling, 2026-11-04: Lavaland is the miners', the rest go to the
// space ruins). The way a player does it:
//
//  - EVA access from the HoP, the same as anybody asks for access (bot_hopping.dm), and the suit out of EVA storage: the suit, its helmet
//    and the mask from a suit storage unit, the emergency tank into the suit's storage, and a jetpack on the back, switched on. The
//    backpack's left beside the unit to be picked up again after: a jetpack goes where the backpack goes.
//  - Out through the EVA airlock and across space to the edge of the map that leads to the ruin's level (space_transition.dm: every
//    space level's edges lead to its neighbours'), and over. Then to the ruin, a look round and one of each thing worth having
//    (paced/loot_ruin, goals/exploring.dm), and back the same way, to EVA, where the jetpack comes off and the backpack goes back on.
//  - Risk and reward as on Lavaland: hurt, short of air, the shuttle called or the trip running long, and it heads home.

/// How long a trip out to a space ruin goes on.
/// How long into the shift before anybody heads out for a space ruin.
#define BOT_SPACE_SETTLE_IN (10 MINUTES)
#define BOT_SPACE_TRIP (15 MINUTES)
/// A route won't go this far: past it, the flight's done in legs.
#define BOT_SPACE_LEG 150

/datum/bot_brain
	/// The backpack left in EVA for the jetpack.
	var/datum/weakref/stashed_bag
	/// Back from a trip out: the jetpack comes off and the backpack goes back on (take_back_bag()). Not before: the swap was undone
	/// the moment the suit-up finished, and done again, a dozen times over.
	var/back_from_space = FALSE
	var/next_eva_access_ask = 0

/// The direction of the edge of level `from_z` to cross first on the way to level `to_z`, over as many levels as it takes, or 0 if there's
/// no way there. Space levels are a grid of neighbours (space_transition.dm); a ruin two levels over is two crossings.
/proc/bot_edge_dir_to(from_z, to_z)
	if(from_z == to_z)
		return 0
	var/datum/space_level/start = SSmapping.z_list[from_z]
	if(!start)
		return 0
	var/list/first_dir = list() //level -> the edge of from_z its route starts across
	var/list/queue = list()
	for(var/d in start.neigbours)
		var/datum/space_level/N = start.neigbours[d]
		if(N && N != start && !first_dir[N])
			first_dir[N] = text2num(d)
			queue += N
	var/at = 1
	while(at <= length(queue))
		var/datum/space_level/L = queue[at++]
		if(L.z_value == to_z)
			return first_dir[L]
		for(var/d in L.neigbours)
			var/datum/space_level/N = L.neigbours[d]
			if(N && N != start && !first_dir[N])
				first_dir[N] = first_dir[L]
				queue += N
	return 0

/// How many edges there are to cross from level `from_z` to level `to_z`, or 0 if there's no way.
/proc/bot_levels_between(from_z, to_z)
	var/datum/space_level/start = SSmapping.z_list[from_z]
	if(!start || from_z == to_z)
		return 0
	var/list/hops = list()
	hops[start] = 0
	var/list/queue = list(start)
	var/at = 1
	while(at <= length(queue))
		var/datum/space_level/L = queue[at++]
		if(L.z_value == to_z)
			return hops[L]
		for(var/d in L.neigbours)
			var/datum/space_level/N = L.neigbours[d]
			if(N && isnull(hops[N]))
				hops[N] = hops[L] + 1
				queue += N
	return 0

/// Where on level z a flight towards its `dir` edge crosses over: the first tile of that edge's band, level with `near`.
/proc/bot_edge_crossing(z, dir, atom/near)
	var/x = clamp(near.x, TRANSITIONEDGE + 3, world.maxx - TRANSITIONEDGE - 3)
	var/y = clamp(near.y, TRANSITIONEDGE + 3, world.maxy - TRANSITIONEDGE - 3)
	switch(dir)
		if(NORTH)
			y = world.maxy - TRANSITIONEDGE
		if(SOUTH)
			y = 1 + TRANSITIONEDGE
		if(EAST)
			x = world.maxx - TRANSITIONEDGE
		if(WEST)
			x = 1 + TRANSITIONEDGE
	return locate(x, y, z)

/datum/bot_brain/proc/has_eva_access()
	var/obj/item/card/id/C = owner.get_idcard(TRUE)
	return C && (ACCESS_EVA in C.GetAccess())

/// An unexplored space ruin on a level that an edge of this one leads straight to, nobody's death trap. The nearest to where it'd come in.
/datum/bot_brain/proc/space_ruin_to_explore()
	var/obj/effect/landmark/ruin/best
	var/best_dist
	for(var/obj/effect/landmark/ruin/R as anything in GLOB.ruin_landmarks)
		if(QDELETED(R) || GLOB.bot_ruins_explored[R] || bot_ruin_deadly(R) || !SSmapping.level_trait(R.z, ZTRAIT_SPACE_RUINS))
			continue
		var/hops = bot_levels_between(owner.z, R.z)
		if(!hops || hops > 2 || !bot_ruin_spot(R))
			continue //more than two levels over is further than a tank of air goes
		var/dist = hops * 1000 + get_dist(locate(owner.x, owner.y, R.z), R)
		if(!best || dist < best_dist)
			best = R
			best_dist = dist
	return best

/// The nearest suit storage unit with a space suit, helmet and all, that it can walk to.
/datum/bot_brain/proc/eva_suit_storage()
	var/obj/machinery/suit_storage_unit/best
	for(var/obj/machinery/suit_storage_unit/standard_unit/U as anything in bot_instances_of(/obj/machinery/suit_storage_unit/standard_unit))
		if(QDELETED(U) || U.z != owner.z || !istype(U.suit, /obj/item/clothing/suit/space) || !istype(U.helmet, /obj/item/clothing/head/helmet/space) || U.locked || (U.stat & (BROKEN|NOPOWER)))
			continue
		if(best && get_dist(owner, U) >= get_dist(owner, best))
			continue
		if(can_walk_lawfully_to(U))
			best = U
	return best

/// The jetpack on it, if there is one.
/datum/bot_brain/proc/worn_jetpack()
	var/obj/item/tank/jetpack/J = owner.back
	// Its own, on it: a back slot once still named a jetpack somebody else had taken, and switching it on from there was a runtime
	return (istype(J) && J.loc == owner) ? J : null

/// How much of a full charge of gas a jetpack has left, out of 1. Without gas it doesn't push, and somebody with an empty one out in
/// space drifts: an explorer on its second trip on the same jetpack was left adrift past the station's edge until its air ran out.
/proc/bot_jetpack_fuel(obj/item/tank/jetpack/J)
	if(!J?.air_contents)
		return 0
	var/full = (6 * ONE_ATMOSPHERE) * J.volume / (R_IDEAL_GAS_EQUATION * T20C) //jetpack.dm's own fill
	return full ? J.air_contents.total_moles() / full : 0

#define BOT_JETPACK_SET_OUT 0.5
#define BOT_JETPACK_TURN_BACK 0.25

/// Out to explore and not a miner (goals/exploring.dm): access, the suit, then off.
/datum/bot_brain/proc/try_space_ruin()
	// Not straight off the shuttle: four bots set off for EVA in the first three minutes of a played round, a doctor and the cook among them.
	if(!gym_run && world.time < SSticker.round_start_time + BOT_SPACE_SETTLE_IN)
		return FALSE
	var/obj/effect/landmark/ruin/R = space_ruin_to_explore()
	if(!R)
		explore_blocked_until = world.time + 10 MINUTES
		pick_pursuit("no space ruins in reach")
		return FALSE
	// Nothing to fly on that a way into EVA would get: no asking for the access. On Meta, with no AI, explorers left their cards at
	// the HoP's door for EVA access every ten minutes, for a trip there was no making.
	if(!worn_jetpack() && !jetpack_to_hope_for())
		explore_blocked_until = world.time + 10 MINUTES
		pick_pursuit("no jetpack to be had")
		return FALSE
	if(!has_eva_access())
		if(world.time < next_eva_access_ask)
			return FALSE
		next_eva_access_ask = world.time + 10 MINUTES
		if(!bot_find_card_granter(owner)) //nobody to give it: it doesn't go, and keeps its card
			explore_blocked_until = world.time + 10 MINUTES
			pick_pursuit("nobody to give me EVA access")
			return FALSE
		return assign_goal(new /datum/bot_goal/job_transfer/access(list(ACCESS_EVA), "EVA"))
	var/suited = in_plain_space_suit() || istype(owner.wear_suit, /obj/item/clothing/suit/space/hardsuit)
	var/obj/item/tank/jetpack/pack = worn_jetpack()
	if(pack && bot_jetpack_fuel(pack) < BOT_JETPACK_SET_OUT)
		bot_log(src, "[pack] is nearly empty - not going out on it")
		explore_blocked_until = world.time + 10 MINUTES
		return FALSE
	// No jetpack to be had: not suited up for nothing.
	if(!pack && !nearest_free_jetpack())
		explore_blocked_until = world.time + 10 MINUTES
		pick_pursuit("no jetpack to be had")
		return FALSE
	if(!suited || !pack)
		var/obj/machinery/suit_storage_unit/U = suited ? null : eva_suit_storage()
		if(!suited && !U)
			explore_blocked_until = world.time + 10 MINUTES
			pick_pursuit("no space suit to be had")
			return FALSE
		return assign_goal(new /datum/bot_goal/space_suit_up(U || owner))
	if(!exploring_since)
		bot_say(owner, pick(";Going out on an EVA, gonna check out a ruin.", "Off out into space for a bit. Back soon.", ";Anyone want anything from out there? Heading to a space ruin."))
	return assign_goal(new /datum/bot_goal/explore_ruin/space(R))

// ---------------------------------------------------------------------------------------------
// Suiting up
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/space_suit_up
	lawful = TRUE
	exclusive = TRUE
	doing = "suiting up for an EVA"

/datum/bot_goal/space_suit_up/New(atom/where)
	. = ..()
	target = where

/datum/bot_goal/space_suit_up/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list()
	if(istype(target, /obj/machinery/suit_storage_unit))
		S.steps += new /datum/bot_step/move_to()
		S.steps += new /datum/bot_step/space_suit_on()
	S.steps += new /datum/bot_step/paced/jetpack_on()
	return list(S)

/datum/bot_goal/space_suit_up/on_give_up(datum/bot_brain/bot)
	bot.explore_blocked_until = world.time + 10 MINUTES //no suit or no jetpack to be had: another time

/datum/bot_goal/space_suit_up/on_success(datum/bot_brain/bot)
	var/datum/bot_duty/explore/duty = bot_duty_of(/datum/bot_duty/explore)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/// The unit's door, then the mask, the suit and the helmet out of it, a click each, and on.
/datum/bot_step/space_suit_on/execute(datum/bot_brain/bot)
	var/obj/machinery/suit_storage_unit/U = bot.current_goal?.target
	if(!istype(U) || QDELETED(U) || !bot.owner.Adjacent(U))
		return GOAL_STEP_FAIL
	bot.human_pause(U)
	bot.owner.face_atom(U)
	if(!U.state_open)
		bot.telemetry_ui_action(U, "door")
		U.open_machine(0)
		U.update_icon()
	for(var/part in list("mask", "suit", "helmet")) //the mask first: there's no getting one on under a space helmet
		var/obj/item/I = U.vars[part]
		if(!I)
			continue
		bot.telemetry_ui_action(U, "dispense [part]")
		U.vars[part] = null
		I.forceMove(U.loc)
		U.update_icon()
		var/slot = part == "suit" ? ITEM_SLOT_OCLOTHING : (part == "helmet" ? ITEM_SLOT_HEAD : ITEM_SLOT_MASK)
		if(bot.try_pickup_target(I))
			bot.wear(I, slot)
	if(!bot.in_plain_space_suit())
		bot_log(bot, "couldn't get the space suit and helmet on: wearing [bot.owner.wear_suit || "no suit"] and [bot.owner.head || "nothing on my head"], holding [english_list(bot.owner.held_items)]")
		return GOAL_STEP_FAIL
	bot.tank_out_of_bag()
	return GOAL_STEP_SUCCESS

/// The internals tank into the suit's storage, where the valve's in reach without the bag (which is about to come off for a jetpack).
/datum/bot_brain/proc/tank_out_of_bag()
	if(eva_tank() || owner.s_store)
		return
	for(var/obj/item/tank/internals/T in owner.GetAllContents()) //the survival box's, in the bag
		if(bot_tank_breathable(T) && ready_in_hand(T))
			equip_displacing(T, ITEM_SLOT_SUITSTORE)
			return

/// A jetpack lying about EVA, walked over to, the backpack off and left beside it, the jetpack on the back and switched on.
/datum/bot_step/paced/jetpack_on
	max_clicks = 30
	var/done = FALSE
	var/next_case_ask = 0
	var/case_asks = 0

/datum/bot_step/paced/jetpack_on/start(datum/bot_brain/bot)
	done = FALSE
	case_asks = 0
	return TRUE

/datum/bot_step/paced/jetpack_on/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	var/obj/item/tank/jetpack/J = bot.worn_jetpack()
	if(J)
		if(!J.on)
			bot.human_pause(J)
			J.cycle(H)
		done = J.on
		return FALSE
	if(bot.pursuing_kind)
		wait_for = 5
		return TRUE
	J = bot.nearest_free_jetpack()
	if(!J)
		bot_log(bot, "no jetpack to be had")
		return FALSE
	if(!H.Adjacent(J))
		var/obj/machinery/door/window/W = locate() in get_turf(J)
		var/turf/front = W ? get_step(W, W.dir) : null
		if(W && get_turf(H) == front && W.density)
			if(!W.allowed(H))
				// Asked twice and still shut: no jetpack, and no trip. Four explorers on Meta asked the AI every twenty seconds for four
				// minutes after it had said the case was for heads of staff.
				if(case_asks >= 2 && world.time >= next_case_ask)
					GLOB.bot_jetpack_cases_refused[REF(W)] = world.time + 15 MINUTES
					bot_log(bot, "nobody's opening [W] - no jetpack, then")
					if(prob(50))
						bot_say(H, pick("Never mind the jetpack, then.", "Guess I'm not going out after all.", "Fine, staying in."))
					return FALSE
				if(world.time >= next_case_ask)
					case_asks++
					next_case_ask = world.time + 30 SECONDS
					bot_say(H, ";AI, open the [W.name] in EVA, please, I'm going out on an EVA.")
				wait_for = 10
				return TRUE
			bot_log(bot, "opening [W] for [J]")
			bot.human_pause(W)
			W.open()
			wait_for = 5
			return TRUE
		bot.pursue((W && front) ? front : J, "follow", force = TRUE)
		wait_for = 5
		return TRUE
	// Into the hand and no further: picking it up the usual way (stow_item(), bot_items.dm) has the game find it a slot of its own,
	// and that took the space suit off.
	// Into the hand and no further: picking it up the usual way (stow_item(), bot_items.dm) has the game find it a slot of its own.
	bot.human_pause(J)
	if(!bot.ready_in_hand(J))
		bot_log(bot, "couldn't get [J] into a hand: holding [english_list(H.held_items)]")
		return FALSE
	bot_log(bot, "picked up [J]")
	bot.tank_out_of_bag()
	var/obj/item/bag = H.back
	if(bag)
		bot.human_pause(bag)
		H.dropItemToGround(bag)
		bot.stashed_bag = WEAKREF(bag)
		bot_log(bot, "left [bag] here for the jetpack")
	if(!bot.wear(J, ITEM_SLOT_BACK))
		bot_log(bot, "couldn't get [J] on my back: back [H.back], holding [english_list(H.held_items)]")
		return FALSE
	wait_for = 3
	return TRUE //switched on next click

/// Jetpack cases nobody would open for an explorer (REF) -> until when nobody else asks.
GLOBAL_LIST_EMPTY(bot_jetpack_cases_refused)

/// The nearest jetpack lying about on this level that nobody else is after and it can walk to.
/datum/bot_brain/proc/nearest_free_jetpack()
	var/obj/item/tank/jetpack/best
	for(var/obj/item/tank/jetpack/J as anything in bot_instances_of(/obj/item/tank/jetpack))
		if(QDELETED(J) || !isturf(J.loc) || J.z != owner.z || taken_by_another(J) || get_dist(owner, J) > 60 || bot_jetpack_fuel(J) < BOT_JETPACK_SET_OUT || !knows_of(J)) //what it knows of (bot_knowledge.dm)
			continue
		var/obj/machinery/door/window/shut_in = locate() in get_turf(J)
		if(shut_in?.density && !shut_in.allowed(owner) && GLOB.bot_jetpack_cases_refused[REF(shut_in)] > world.time)
			continue
		if(best && get_dist(owner, J) >= get_dist(owner, best))
			continue
		// Behind a shut case, it's the case that says: a way to the tile in front of it is no way to the jetpack. Meta's rack is behind
		// a windoor for heads of staff, and with no AI to ask, every explorer took a suit out of EVA's units, walked up to the case and
		// found "no jetpack to be had" there (the tile it had counted on was the one it now stood on), three times a shift. A suit
		// storage unit beside the rack, once somebody had opened it, counted as a way to it too, through the window.
		if((shut_in && shut_in.density) ? jetpack_case_front(J) : can_walk_lawfully_to(J))
			best = J
	return best

/// Whether there's a jetpack lying about that getting into EVA could get it: one it knows of, with gas in it, and not in a case its
/// ID doesn't open with nobody to ask (no AI, or the AI's said no). No routes looked for: this is asked before it has the access.
/datum/bot_brain/proc/jetpack_to_hope_for()
	for(var/obj/item/tank/jetpack/J as anything in bot_instances_of(/obj/item/tank/jetpack))
		if(QDELETED(J) || !isturf(J.loc) || J.z != owner.z || bot_jetpack_fuel(J) < BOT_JETPACK_SET_OUT || !knows_of(J))
			continue
		if(gym_run && get_area(J) != get_area(owner))
			continue //in the Bot Gym every arena is on the one z-level: another one's jetpack is no jetpack to this bot
		var/obj/machinery/door/window/shut_in = locate() in get_turf(J)
		if(shut_in && shut_in.density && !shut_in.allowed(owner) && (GLOB.bot_jetpack_cases_refused[REF(shut_in)] > world.time || !(locate(/datum/bot_silicon/ai) in GLOB.bot_silicons)))
			continue
		return TRUE
	return FALSE

/// Where to stand to open the case a jetpack's in: on Meta they're on a rack behind a windoor, which no route reaches through. Null if
/// it isn't in one, or its ID won't open it, or there's no getting to the front of it.
/datum/bot_brain/proc/jetpack_case_front(obj/item/tank/jetpack/J)
	var/obj/machinery/door/window/W = locate() in get_turf(J)
	if(!W || (!W.allowed(owner) && !(locate(/datum/bot_silicon/ai) in GLOB.bot_silicons)))
		return null //Meta's case is for heads of staff: without the access, it's the AI that can open it, if there is one
	var/turf/front = get_step(W, W.dir)
	return (front && can_walk_lawfully_to(front)) ? front : null

/datum/bot_step/paced/jetpack_on/finish(datum/bot_brain/bot)
	return done ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Out and back
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/explore_ruin/space
	doing = "exploring a ruin out in space"
	/// The level it set out from, to come back to, and where it was when it did.
	var/home_z
	var/turf/set_out_from
	/// The jetpack's gas when it set out, and whether it's turned for home on it.
	var/fuel_at_start = 0
	var/turned_back = FALSE

/datum/bot_goal/explore_ruin/space/resolve_target(datum/bot_brain/bot)
	home_z = home_z || bot.owner.z
	set_out_from = set_out_from || get_turf(bot.owner)
	target = QDELETED(ruin) ? null : bot_ruin_spot(ruin)

/datum/bot_goal/explore_ruin/space/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/explore_ruin/S = new
	S.steps = list(new /datum/bot_step/paced/fly_to_ruin(), new /datum/bot_step/paced/loot_ruin(), new /datum/bot_step/paced/fly_home())
	return list(S)

/// Across to the ruin's level and up to the ruin, a leg at a time, the route through space with the jetpack running.
/datum/bot_step/paced/fly_to_ruin
	max_clicks = 300
	/// Whether it's tried the last bit, inside: close by is outside the hull of a ruin that's a station, and there's nothing to see.
	var/went_in = FALSE

/datum/bot_step/paced/fly_to_ruin/start(datum/bot_brain/bot)
	var/datum/bot_goal/explore_ruin/space/G = bot.current_goal
	if(!istype(G) || !G.ruin || !bot.can_path_through_space())
		bot_log(bot, "not fit to go out: [bot.can_path_through_space() ? "no ruin" : "can't cross space as I am"]")
		return FALSE
	bot.exploring_since = bot.exploring_since || world.time
	went_in = FALSE
	G.fuel_at_start = bot_jetpack_fuel(bot.worn_jetpack())
	return TRUE

/datum/bot_step/paced/fly_to_ruin/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/explore_ruin/space/G = bot.current_goal
	var/turf/spot = get_turf(G?.target)
	if(!spot || bot.space_trip_over())
		return FALSE
	var/turf/here = get_turf(bot.owner)
	if(bot.pursuing_kind)
		wait_for = 10
		return TRUE
	if(here.z == spot.z && get_dist(here, spot) <= 6)
		if(went_in || get_dist(here, spot) <= 1)
			return FALSE //there, or as near as it gets
		went_in = TRUE
		if(bot.pursue(spot, "follow", force = TRUE))
			wait_for = 10
			return TRUE
		return FALSE
	var/turf/leg = bot.space_leg_toward(spot)
	if(!leg || !bot.pursue(leg, "follow", force = TRUE))
		bot_log(bot, "no way across space to [bot_coord(leg || spot)]")
		return FALSE
	wait_for = 10
	return TRUE

/// Got there or not, the trip goes on to the way home: a bot that gave up out there was left adrift on another level, breathing its tank
/// dry.
/datum/bot_step/paced/fly_to_ruin/finish(datum/bot_brain/bot)
	var/turf/spot = get_turf(bot.current_goal?.target)
	if(!spot || spot.z != bot.owner.z || get_dist(bot.owner, spot) > 6)
		bot_log(bot, "couldn't get to the ruin - heading back")
	return GOAL_STEP_SUCCESS

/// The next leg towards `spot`: on another level, to the edge that leads there; on this one, the spot, or a leg's length along the way.
/datum/bot_brain/proc/space_leg_toward(turf/spot)
	var/turf/here = get_turf(owner)
	if(here.z != spot.z)
		var/dir = bot_edge_dir_to(here.z, spot.z)
		return dir ? bot_edge_crossing(here.z, dir, here) : null
	if(get_dist(here, spot) <= BOT_SPACE_LEG)
		return spot
	var/list/line = getline(here, spot)
	return line[BOT_SPACE_LEG]

/// Time to turn back: hurt, short of air, the shuttle called, or out too long.
/datum/bot_brain/proc/space_trip_over()
	if(bot_going_home_soon() || owner.health < owner.maxHealth * 0.6 || owner.getOxyLoss() > 20 || low_air_stay_in)
		return TRUE
	// Half the gas it set out with gone, and it turns round, as a diver does with air: the way back is as long as the way out. Two
	// explorers who'd gone two levels over turned at a quarter and were left adrift on the way home.
	var/obj/item/tank/jetpack/J = worn_jetpack()
	var/datum/bot_goal/explore_ruin/space/trip = current_goal
	var/turn_at = max(BOT_JETPACK_TURN_BACK, istype(trip) && trip.fuel_at_start ? trip.fuel_at_start / 2 : 0)
	if(J && istype(trip) && !trip.turned_back && bot_jetpack_fuel(J) < turn_at)
		trip.turned_back = TRUE
		bot_log(src, "half the jetpack's gas gone - turning back")
		return TRUE
	if(istype(trip) && trip.turned_back)
		return TRUE
	return exploring_since && world.time > exploring_since + BOT_SPACE_TRIP

/// Back across to the level it came from and in to EVA, where the backpack is.
/datum/bot_step/paced/fly_home
	max_clicks = 300

/datum/bot_step/paced/fly_home/do_click(datum/bot_brain/bot)
	var/home_z = bot.space_home_z()
	var/obj/item/bag = bot.stashed_bag?.resolve()
	var/datum/bot_goal/explore_ruin/space/trip = bot.current_goal
	var/datum/bot_goal/space_return/back = bot.current_goal
	var/turf/home = get_turf(bag) || (istype(trip) ? trip.set_out_from : null) || (istype(back) ? back.set_out_from : null) || get_turf(bot.eva_suit_storage())
	if((!home || home.z != home_z) && home_z)
		home = locate(world.maxx / 2, world.maxy / 2, home_z)
	var/turf/here = get_turf(bot.owner)
	if(!home || (here.z == home.z && get_dist(here, home) <= 1))
		return FALSE
	if(bot.pursuing_kind)
		wait_for = 10
		return TRUE
	var/turf/leg = bot.space_leg_toward(home)
	if(!leg || !bot.pursue(leg, "follow", force = TRUE))
		bot_log(bot, "no way back across space to [bot_coord(leg || home)]")
		return FALSE
	wait_for = 10
	return TRUE

/// The level it set out from, whichever goal's taking it home.
/datum/bot_brain/proc/space_home_z()
	var/datum/bot_goal/explore_ruin/space/trip = current_goal
	if(istype(trip))
		return trip.home_z
	var/datum/bot_goal/space_return/back = current_goal
	return istype(back) ? back.home_z : null

/datum/bot_step/paced/fly_home/finish(datum/bot_brain/bot)
	var/home_z = bot.space_home_z()
	if(home_z && bot.owner.z == home_z && !isspaceturf(get_turf(bot.owner)))
		bot.back_from_space = TRUE
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

/datum/bot_goal/explore_ruin/space/on_give_up(datum/bot_brain/bot)
	..()
	bot.back_from_space = TRUE //whatever came of it, the jetpack comes off once it's back aboard
	if(bot.owner.z != home_z || isspaceturf(get_turf(bot.owner)))
		var/datum/bot_goal/space_return/back = new
		back.home_z = home_z
		back.set_out_from = set_out_from
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), back))

/// Out in space with the trip given up: back aboard, before the tank runs out. Failing that, a call for help with where it is.
/datum/bot_goal/space_return
	never_rests = TRUE
	braves_bad_air = TRUE
	doing = "getting back aboard"
	var/home_z
	var/turf/set_out_from
	var/tries = 0

/datum/bot_goal/space_return/resolve_target(datum/bot_brain/bot)
	target = bot.owner

/datum/bot_goal/space_return/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/explore_ruin/S = new
	S.steps = list(new /datum/bot_step/paced/fly_home())
	return list(S)

/datum/bot_goal/space_return/on_give_up(datum/bot_brain/bot)
	if(++tries <= 2 && (bot.owner.z != home_z || isspaceturf(get_turf(bot.owner))))
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), src))
		return
	bot_say(bot.owner, ";Help, I'm stuck out in space! [get_area_name(bot.owner, TRUE)], [bot.owner.x], [bot.owner.y].")

/// Back aboard with a jetpack on and the backpack still where it was left: the jetpack off and down, and the backpack back on.
/datum/bot_brain/proc/take_back_bag()
	var/obj/item/bag = stashed_bag?.resolve()
	var/obj/item/tank/jetpack/J = worn_jetpack()
	if(!back_from_space || isspaceturf(get_turf(owner)))
		return FALSE
	if(!bag || !J || !isturf(bag.loc) || bag.z != owner.z)
		stashed_bag = null
		back_from_space = FALSE
		return FALSE
	if(!owner.Adjacent(bag))
		return pursue(bag, "item", force = TRUE)
	if(J.on)
		J.cycle(owner)
	human_pause(J)
	owner.dropItemToGround(J)
	if(try_pickup_target(bag))
		wear(bag, ITEM_SLOT_BACK)
	stashed_bag = null
	back_from_space = FALSE
	bot_log(src, "back in [bag], the jetpack left in EVA")
	return TRUE

#undef BOT_SPACE_TRIP
#undef BOT_SPACE_SETTLE_IN
#undef BOT_SPACE_LEG
#undef BOT_JETPACK_SET_OUT
#undef BOT_JETPACK_TURN_BACK
