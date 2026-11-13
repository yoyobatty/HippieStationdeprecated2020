// Threat reading (the plan's foundation/threat_read.dm, M2): what a bot sees about to hurt it, and what it does about it. Every bot reads
// threats; the skill dial (skill.dm) sets how often it notices, each look at its own reaction time (human_limits.dm): a low-skill bot some
// of the time, a robust one most of the time, apex every time.
//
//  - Stood by a fuel tank in a fight with somebody holding a gun, or with the one it's fighting dragging a tank up to it: it gets away from
//    the tank. A shot into one is a blast on the tiles beside it (foundation/tactics.dm), and a bot stood there was a free kill.
//  - A plasma canister let go in the room: it gets out before the air goes (below).
//  - A gun on it and nothing to shoot back with: out of the line of fire, round a corner, and it waits for them there (below).

/datum/bot_brain
	var/next_tank_look = 0
	/// Getting away from a tank until then: the rest of the fight waits
	var/tank_dodge_until = 0

/// Whether it notices this time (above)
/datum/bot_brain/proc/notices_threat()
	return prob(is_apex() ? 100 : (skill_at_least(BOT_SKILL_MID) ? 70 : 30))

/proc/bot_holds_gun(mob/living/L)
	for(var/obj/item/gun/G in L?.held_items)
		return TRUE
	return FALSE

/// From handle_combat() (bot_brain.dm). TRUE while it's getting away from a tank.
/datum/bot_brain/proc/mind_the_tank(mob/living/foe)
	if(world.time < tank_dodge_until)
		return TRUE
	if(world.time < next_tank_look || !foe)
		return FALSE
	// The one it's fighting dragging a tank up to it (foundation/tactics.dm's opener, from the other side), or holding a gun with it stood by one
	var/obj/structure/reagent_dispensers/fueltank/tank = foe.pulling
	var/dragged = istype(tank) && get_dist(owner, tank) <= 4
	if(!dragged)
		tank = bot_holds_gun(foe) ? bot_fuel_tank_near(owner, 2) : null
	if(!tank)
		return FALSE
	next_tank_look = world.time + perception_delay() + 2 SECONDS
	if(!notices_threat())
		return FALSE
	var/turf/away = furthest_open_floor_from(tank, dragged ? bot_tank_clear(tank) : max(bot_tank_clear(tank) - 2, 4))
	if(!away)
		return FALSE
	bot_log(src, "THREAT: [dragged ? "[foe] is dragging [tank] up to me" : "stood by [tank] with [foe] holding a gun"] - getting away from it")
	bot_tally("got away from a fuel tank")
	tank_dodge_until = world.time + 2 SECONDS
	combat_chase(away)
	return TRUE

// ---------------------------------------------------------------------------------------------
// A plasma canister let go in the room
// ---------------------------------------------------------------------------------------------
// Somebody's opened a canister of plasma (or tritium) with nothing on its port: the room will be poison and fuel in moments. It gets out
// before the air goes, not after (the bad-air reflexes, goals/refill_internals.dm, only start once it's breathing it). Not with its own
// internals on.

/datum/bot_brain
	var/next_canister_look = 0

/// From process() (bot_brain.dm), every second or so. TRUE if it's off.
/datum/bot_brain/proc/notice_open_canister()
	if(world.time < next_canister_look || owner.internal || istype(current_goal, /datum/bot_goal/run_from))
		return FALSE
	// Not a saboteur at its own canister (goals/sabotage.dm): it opened it, and has it to light. In the full gym the two plasma sabotage
	// scenarios had their saboteurs run from what they'd just opened.
	if(istype(current_goal, /datum/bot_goal/sabotage_plasma) || istype(suspended_goal, /datum/bot_goal/sabotage_plasma))
		return FALSE
	next_canister_look = world.time + 3 SECONDS
	var/turf/here = get_turf(owner)
	if(!here)
		return FALSE
	for(var/obj/machinery/portable_atmospherics/canister/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister))
		if(QDELETED(C) || !C.valve_open || C.holding || C.z != here.z || get_dist(C, here) > 6 || !bot_movable_volatile(C))
			continue
		if(!(C in view(BOT_SIGHT_RANGE, owner)) || !notices_threat())
			continue
		bot_log(src, "THREAT: [C] is letting plasma out into the room - getting out before the air goes")
		bot_tally("got out of a plasma leak")
		state_before_combat = null
		drop_goals("plasma pouring out of [C]")
		return assign_goal(new /datum/bot_goal/run_from/gas(C))
	return FALSE

/// Out of the room the gas is filling: through the doors it opens, as far off as a few hundred tiles of floor go (run_from's own spots keep
/// to floor without a door, and from a canister in the middle of a room that was the far corner of the same room).
/datum/bot_goal/run_from/gas
	doing = "getting out of a gas leak"

/datum/bot_goal/run_from/gas/resolve_target(datum/bot_brain/bot)
	var/atom/foe = foe_ref?.resolve()
	target = foe ? bot.furthest_reachable_from(foe, 10) : null

/// The floor it can walk to by the doors its ID opens (bot_reachable_strict()) that's furthest from A: the first one `enough` off, or the
/// furthest there is within 400 tiles.
/datum/bot_brain/proc/furthest_reachable_from(atom/A, enough)
	var/turf/start = get_turf(owner)
	var/turf/from = get_turf(A)
	if(!start || !from)
		return null
	var/obj/item/card/id/id_card = route_card()
	var/simulated_only = !can_path_through_space()
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/at = 1
	var/turf/best
	var/best_dist = get_dist(start, from)
	while(at <= length(queue) && length(queue) < 400)
		var/turf/T = queue[at++]
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(T, d)
			if(!next || seen[next] || !T.bot_reachable_strict(owner, next, id_card, simulated_only))
				continue
			seen[next] = TRUE
			queue += next
			var/dist = get_dist(next, from)
			if(dist > best_dist)
				best = next
				best_dist = dist
				if(dist >= enough)
					return best
	return best

// ---------------------------------------------------------------------------------------------
// A gun on it, and nothing to shoot back with
// ---------------------------------------------------------------------------------------------
// In a fight with somebody holding a gun, a few tiles off, with no gun of its own: a robust player doesn't run at them across open floor,
// it gets out of their line of fire, round the nearest corner that doesn't take it further from them, and waits there for them to come
// to it (close enough to hit) or to come out where it can rush them. A low-skill bot does what it always did: runs, or charges.
// At most fifteen seconds there; then the fight goes on as it would have.

/datum/bot_brain
	/// Where it's taken cover from a gun, and until when it holds it
	var/turf/cover_spot
	var/cover_until = 0
	var/datum/weakref/cover_from_ref

/// A tile it can walk to within a few steps that the shooter has no line to, no further from them than it is now: the nearest.
/datum/bot_brain/proc/cover_from(mob/living/shooter)
	var/turf/start = get_turf(owner)
	var/turf/them = get_turf(shooter)
	if(!start || !them)
		return null
	var/limit = get_dist(start, them)
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/list/depth = list(0)
	var/at = 1
	while(at <= length(queue))
		var/turf/T = queue[at]
		var/steps = depth[at++]
		if(T != start && !bot_clear_line(T, shooter) && get_dist(T, them) <= limit)
			return T
		if(steps >= 5)
			continue
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(T, d)
			if(!next || seen[next] || next.density || isspaceturf(next) || is_blocked_turf(next, TRUE) || bot_turf_is_deadly(next))
				continue
			seen[next] = TRUE
			queue += next
			depth += steps + 1
	return null

/// From handle_combat() (bot_brain.dm). TRUE while it's in cover, or getting to it.
/datum/bot_brain/proc/mind_the_gun(mob/living/foe)
	var/mob/living/held_on = cover_from_ref?.resolve()
	if(held_on == foe && world.time < cover_until && cover_spot)
		if(get_dist(owner, foe) <= 1 || !bot_holds_gun(foe))
			cover_until = 0 //they've come to it, or put the gun away: the fight's on
			return FALSE
		if(get_turf(owner) != cover_spot)
			combat_chase(cover_spot)
		else
			stop_pursuit()
			owner.face_atom(foe)
		return TRUE
	if(!skill_at_least(BOT_SKILL_MID) || !bot_holds_gun(foe) || find_usable_gun() || get_dist(owner, foe) < 3)
		return FALSE
	if(!bot_clear_line(get_turf(owner), foe) || (cover_until && world.time < cover_until + 10 SECONDS))
		return FALSE //out of their line already, or it's had its wait in cover
	if(!notices_threat())
		return FALSE
	var/turf/spot = cover_from(foe)
	if(!spot)
		return FALSE
	bot_log(src, "THREAT: [foe] has a gun on me and I've nothing to shoot back with - into cover at [bot_coord(spot)]")
	bot_tally("took cover from a gun")
	cover_spot = spot
	cover_from_ref = WEAKREF(foe)
	cover_until = world.time + 15 SECONDS
	combat_chase(spot)
	return TRUE
