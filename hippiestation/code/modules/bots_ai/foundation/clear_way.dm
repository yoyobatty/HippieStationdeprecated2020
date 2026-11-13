// Clearing the way (the user's case, 2026-11-13: "a maint pathway with 2 moveable structures that get them stuck").
//
// A one-wide maintenance corridor with a locker and a canister in it. No route went through either: bot_can_astar_pass_permissive()
// (bot_pathing_permissive.dm) passes only what can be climbed or broken, so the errand ended in "no path". And a bot that did walk into one
// pushed it into the next, where it jams (PushAM()'s step() fails on a dense tile, living.dm), and bumped it until it gave up. A player
// pulls the first one back into a doorway or a side passage and pushes the other along, or climbs the crates, or opens the lockers and walks
// through them.
//
//  1. route_through_movables(): when no other route search found a way, one more lets a dense structure that isn't fixed down
//     (bot_movable_obstacle(), movables.dm) be a way through, at a cost each (BOT_MOVABLE_PATH_PENALTY). Lawful errands still force nothing.
//  2. clear_way_past(): walking that route the bot meets the first of them (clear_one_blocker(), bot_items.dm, once opening and climbing have
//     had their go). plan_clear_way() searches its moves in a box round the blockade: walk, push, pull back a step, climb, open. The goal
//     is a tile of the route beyond the blockade with none of them left on the way on.
//  3. run_clear_way(): the moves done one at a time, each checked. Anything that doesn't go as planned ends it, and the route is planned
//     again from where it is.
//
// The skill dial (skill.dm): below BOT_SKILL_MID a bot only opens, climbs and pushes, and doesn't think it through for long; when that isn't
// enough it says so on the radio and goes round. From BOT_SKILL_MID it pulls things back out of the way too and looks further; apex furthest.

/// Moves' costs, in tenths of a second about (a climb is two seconds and a stun)
#define CW_WALK 2
#define CW_PUSH 3
#define CW_PULL 3
#define CW_OPEN 5
#define CW_CLIMB 12
/// At most this many of them in the plan; any others in the box stay where they are
#define CW_MAX_MOVABLES 4
/// How far along the route the box reaches
#define CW_WINDOW 24
/// Tiles round the route and the bot in the box
#define CW_PAD 4
/// The box's widest side
#define CW_MAX_SIDE 29

#define CW_ACT_WALK 1
#define CW_ACT_PUSH 2
#define CW_ACT_PULL 3
#define CW_ACT_CLIMB 4
#define CW_ACT_OPEN 5

/datum/bot_brain
	/// The route search in progress lets structures that could be moved out of the way through (route_through_movables())
	var/pathing_through_movables = FALSE
	var/clearing_way = FALSE
	/// Blocker -> until when it isn't tried again, having been no way past
	var/list/clear_way_failed
	var/next_stuck_call = 0

// ---------------------------------------------------------------------------------------------
// 1. The route
// ---------------------------------------------------------------------------------------------

/// Whether a walk that found no way at all looks for one past things that could be moved. Not a stroll: somebody out for a walk who
/// finds the way blocked goes somewhere else.
/datum/bot_brain/proc/can_route_through_movables()
	return pursuing_kind && pursuing_kind != "wander" && !in_mech()

/// do_repath()'s last pass (bot_movement.dm), in the order it tries the destination and the tiles beside it.
/datum/bot_brain/proc/route_through_movables(turf/destination, list/adjacent_candidates, adjacent_first, obj/item/card/id/id_card)
	var/atom/my_target = pursue_target
	var/my_kind = pursuing_kind
	var/list/tries = adjacent_first ? (adjacent_candidates + destination) : (list(destination) + adjacent_candidates)
	for(var/turf/T as anything in tries)
		var/list/path = try_path_through_movables(T, id_card)
		if(pursue_target != my_target || pursuing_kind != my_kind)
			return null
		if(length(path))
			bot_log(src, "the only way to [destination] is past things in the way that could be moved")
			return path
	return null

/datum/bot_brain/proc/try_path_through_movables(turf/dest, obj/item/card/id/id_card)
	pathing_through_movables = TRUE
	var/lawful = pursuit_is_lawful()
	pathing_climb_only = lawful //on its everyday business: past them, and nothing forced
	// nor over the furniture, unless it's hemmed in by it, as the climbing pass (do_repath()): an officer taking a prisoner to a cell was routed
	// over the Brig's front desk this way and climbed it 38 times (Bot Shift found1 run3)
	pathing_allow_climb = !lawful || is_hemmed_in()
	pathing_no_tailgating = lawful && !is_shut_in() //nor in through a door somebody left open, as pass 1 (bot_doors.dm)
	var/list/path = bot_path_to(dest, /turf/proc/bot_weighted_distance, /turf/proc/bot_reachable_permissive, id_card, !can_path_through_space())
	pathing_no_tailgating = FALSE
	pathing_allow_climb = TRUE
	pathing_climb_only = FALSE
	pathing_through_movables = FALSE
	bot_log_verbose(src, "  pass 4 (past things that could be moved) to [dest] @ [bot_coord(dest)]: [length(path) ? "[length(path)] nodes" : "no path"]")
	if(length(path) && path_crosses_bad_air(path))
		return null
	return path

// ---------------------------------------------------------------------------------------------
// 2. The plan
// ---------------------------------------------------------------------------------------------

/// Called by clear_one_blocker() (bot_items.dm) for a movable structure in the way that opening and climbing didn't get it past. TRUE if
/// it got past.
/datum/bot_brain/proc/clear_way_past(obj/first)
	if(clearing_way || !current_path || !length(current_path) || in_mech())
		return FALSE
	if(LAZYACCESS(clear_way_failed, first) > world.time)
		return FALSE
	clearing_way = TRUE
	. = FALSE
	var/list/plan
	try
		plan = plan_clear_way(first)
		if(plan)
			. = run_clear_way(plan)
	catch(var/exception/e)
		bot_log_exception(src, "clear_way_past", e)
	clearing_way = FALSE
	if(!QDELETED(owner) && owner.pulling && bot_movable_obstacle(owner.pulling, owner))
		owner.stop_pulling()
	if(.)
		bot_tally("got past things in the way")
		return
	if(LAZYLEN(clear_way_failed) > 20)
		clear_way_failed.Cut()
	LAZYSET(clear_way_failed, first, world.time + 30 SECONDS)
	if(!plan)
		say_stuck_behind(first)

/// No way past that it can see: it says so, now and then, as a player does in maintenance.
/datum/bot_brain/proc/say_stuck_behind(obj/first)
	if(world.time < next_stuck_call || gone_loud())
		return
	next_stuck_call = world.time + 5 MINUTES
	bot_log(src, "stuck behind [first] with no way past it I can see - saying so")
	bot_tally("stuck behind things in the way")
	bot_say(owner, pick(";Can't get through [get_area_name(owner, TRUE)], there's [first.name] in the way.", \
		";Anyone got a way round? [capitalize(first.name)] blocking the way in [get_area_name(owner, TRUE)].", \
		";Stuck in [get_area_name(owner, TRUE)], something's blocking the way."))

/// How many states the search may open, by skill
/datum/bot_brain/proc/clear_way_budget()
	if(is_apex())
		return 15000
	return skill_at_least(BOT_SKILL_MID) ? 4000 : 400

/// The moves past the blockade starting at `first` (on the route's next tile): a list of list(action, dir, movable), or null.
/datum/bot_brain/proc/plan_clear_way(obj/first)
	var/turf/here = get_turf(owner)
	if(!here)
		return null
	var/z = here.z
	// The route ahead, and a box round it and the bot no wider than CW_MAX_SIDE
	var/list/route = list(here)
	var/x0 = here.x
	var/x1 = here.x
	var/y0 = here.y
	var/y1 = here.y
	for(var/i in 1 to min(length(current_path), CW_WINDOW))
		var/turf/T = current_path[i]
		if(!T || T.z != z)
			break
		var/nx0 = min(x0, T.x)
		var/nx1 = max(x1, T.x)
		var/ny0 = min(y0, T.y)
		var/ny1 = max(y1, T.y)
		if(nx1 - nx0 + 1 + CW_PAD * 2 > CW_MAX_SIDE || ny1 - ny0 + 1 + CW_PAD * 2 > CW_MAX_SIDE)
			break
		x0 = nx0
		x1 = nx1
		y0 = ny0
		y1 = ny1
		route += T
	x0 = max(1, x0 - CW_PAD)
	y0 = max(1, y0 - CW_PAD)
	x1 = min(world.maxx, x1 + CW_PAD)
	y1 = min(world.maxy, y1 + CW_PAD)
	var/w = x1 - x0 + 1
	var/h = y1 - y0 + 1
	var/n = w * h
	var/list/tiles = new /list(n)
	for(var/i in 1 to n)
		tiles[i] = locate(x0 + (i - 1) % w, y0 + round((i - 1) / w), z)
	var/list/route_at = new /list(n) //box index -> place on the route (1 = where it stands), or null
	for(var/r in 1 to length(route))
		var/turf/T = route[r]
		route_at[(T.x - x0) + (T.y - y0) * w + 1] = r

	// What could move: the ones on the route first, in order, then the nearest others in the box
	var/list/movables = list()
	var/last_blocked = 0
	for(var/r in 2 to length(route))
		for(var/obj/O in route[r])
			if(length(movables) < CW_MAX_MOVABLES && bot_movable_obstacle(O, owner))
				movables += O
				last_blocked = r
	if(!(first in movables))
		return null //not on the way on after all
	if(length(movables) < CW_MAX_MOVABLES)
		var/list/near = list()
		for(var/obj/O in range(CW_PAD, first))
			if(O.density && !(O in movables) && O.x >= x0 && O.x <= x1 && O.y >= y0 && O.y <= y1 && bot_movable_obstacle(O, owner))
				near[O] = get_dist(O, first)
		sortTim(near, GLOBAL_PROC_REF(cmp_numeric_asc), TRUE)
		for(var/obj/O as anything in near)
			if(length(movables) >= CW_MAX_MOVABLES)
				break
			movables += O
	var/k = length(movables)
	var/list/ignore = list()
	for(var/obj/O as anything in movables)
		ignore[O] = TRUE

	// What each could have done to it
	var/pulls = skill_at_least(BOT_SKILL_MID)
	var/list/can_push = new /list(k)
	var/list/can_pull = new /list(k)
	var/list/can_climb = new /list(k)
	var/list/can_open = new /list(k)
	var/list/start = new /list(k + 2)
	start[1] = (here.x - x0) + (here.y - y0) * w + 1
	for(var/j in 1 to k)
		var/obj/O = movables[j]
		start[j + 1] = (O.x - x0) + (O.y - y0) * w + 1
		can_push[j] = bot_can_push(O, owner)
		can_pull[j] = pulls && bot_can_pull(O, owner)
		var/obj/structure/S = O
		can_climb[j] = istype(S) && S.climbable
		var/obj/structure/closet/C = O
		can_open[j] = istype(C) && !C.opened && !C.welded && !C.dense_when_open && (!C.locked || (C.secure && !C.broken && C.allowed(owner)))
	start[k + 2] = 0 //open lockers, a bit each

	// Which way the bot can step from each tile, and which way one of them can be moved, with the ones in the plan left out
	var/obj/item/card/id/id_card = route_card()
	var/simulated_only = !can_path_through_space()
	var/list/walk_bits = new /list(n)
	var/list/move_bits = new /list(n)
	for(var/i in 1 to n)
		var/turf/T = tiles[i]
		var/wb = 0
		var/mb = 0
		if(T && !T.density)
			for(var/d in GLOB.cardinals)
				var/j = cw_next(i, d, w, h)
				if(!j)
					continue
				var/turf/N = tiles[j]
				if(cw_link_ok(T, N, ignore, FALSE, id_card, simulated_only))
					wb |= d
				if(cw_link_ok(T, N, ignore, TRUE, id_card, simulated_only))
					mb |= d
		walk_bits[i] = wb
		move_bits[i] = mb
	CHECK_TICK

	// The search: cheapest first, by buckets of cost
	var/budget = clear_way_budget()
	var/start_key = jointext(start, ",")
	var/list/best = list()
	best[start_key] = 0
	var/list/parent = list()
	var/list/state_of = list()
	state_of[start_key] = start
	var/list/buckets = list(list(start_key))
	var/cost_at = 1
	var/opened = 0
	var/goal_key
	while(cost_at <= length(buckets))
		var/list/bucket = buckets[cost_at]
		if(!length(bucket))
			cost_at++
			continue
		var/key = bucket[length(bucket)]
		bucket.len--
		if(best[key] != cost_at - 1)
			continue //reached cheaper since
		var/list/S = state_of[key]
		if(cw_is_goal(S, k, route_at, last_blocked))
			goal_key = key
			break
		if(++opened > budget)
			break
		if(!(opened % 200))
			CHECK_TICK
		var/b = S[1]
		var/open_mask = S[k + 2]
		var/b_under = cw_occupant(S, k, b) //a crate it's climbed on to
		for(var/d in GLOB.cardinals)
			if(!(walk_bits[b] & d))
				continue
			var/nb = cw_next(b, d, w, h)
			var/j = cw_occupant(S, k, nb)
			if(!j || (open_mask & (1 << j)))
				// a free tile (or an open locker): walk, or walk dragging one of them along behind
				cw_try(S.Copy(), CW_ACT_WALK, d, 0, nb, 0, 0, cost_at - 1 + CW_WALK, key, best, parent, state_of, buckets)
				if(!b_under && !j)
					for(var/d2 in GLOB.cardinals)
						if(d2 == d)
							continue
						var/q = cw_next(b, d2, w, h)
						var/jp = q && cw_occupant(S, k, q)
						if(!jp || !can_pull[jp] || (open_mask & (1 << jp)) || !(move_bits[q] & turn(d2, 180)))
							continue
						cw_try(S.Copy(), CW_ACT_PULL, d, jp, nb, jp, b, cost_at - 1 + CW_PULL, key, best, parent, state_of, buckets)
				continue
			if(can_push[j])
				var/nn = (move_bits[nb] & d) ? cw_next(nb, d, w, h) : 0
				if(nn && nn != b && !cw_occupant(S, k, nn))
					cw_try(S.Copy(), CW_ACT_PUSH, d, j, nb, j, nn, cost_at - 1 + CW_PUSH, key, best, parent, state_of, buckets)
			if(can_climb[j])
				cw_try(S.Copy(), CW_ACT_CLIMB, d, j, nb, 0, 0, cost_at - 1 + CW_CLIMB, key, best, parent, state_of, buckets)
			if(can_open[j] && !b_under)
				var/list/opened_state = S.Copy()
				opened_state[k + 2] = open_mask | (1 << j)
				cw_try(opened_state, CW_ACT_OPEN, d, j, b, 0, 0, cost_at - 1 + CW_OPEN, key, best, parent, state_of, buckets)
	bot_log(src, "CLEAR WAY: [k] in the way of the route ([english_list(movables)]), searched [opened] states: [goal_key ? "a way past at cost [best[goal_key]]" : "no way past"]")
	if(!goal_key)
		return null
	var/list/plan = list()
	var/at = goal_key
	while(parent[at])
		var/list/link = parent[at]
		var/list/act = link[2]
		plan.Insert(1, list(list(act[1], act[2], act[3] ? movables[act[3]] : null)))
		at = link[1]
	return plan

/// The box index one step `d` from i, or 0 off the box.
/datum/bot_brain/proc/cw_next(i, d, w, h)
	var/x = (i - 1) % w
	var/y = round((i - 1) / w)
	switch(d)
		if(NORTH)
			return y + 1 < h ? i + w : 0
		if(SOUTH)
			return y > 0 ? i - w : 0
		if(EAST)
			return x + 1 < w ? i + 1 : 0
		if(WEST)
			return x > 0 ? i - 1 : 0
	return 0

/// Which of them is on box tile i in state S, or 0
/datum/bot_brain/proc/cw_occupant(list/S, k, i)
	for(var/j in 1 to k)
		if(S[j + 1] == i)
			return j
	return 0

/// Stood on the route past where the last of them was, with none of them (shut) on the route ahead.
/datum/bot_brain/proc/cw_is_goal(list/S, k, list/route_at, last_blocked)
	var/r = route_at[S[1]]
	if(!r || r <= last_blocked)
		return FALSE
	var/open_mask = S[k + 2]
	for(var/j in 1 to k)
		if(open_mask & (1 << j))
			continue
		var/rj = route_at[S[j + 1]]
		if(rj && rj >= r)
			return FALSE
	return TRUE

/// One move from state S: the bot to nb, and movable j (if any) to its new tile; kept if it's the cheapest way to that state yet.
/datum/bot_brain/proc/cw_try(list/S, action, d, act_movable, nb, j, to_tile, cost, from_key, list/best, list/parent, list/state_of, list/buckets)
	S[1] = nb
	if(j)
		S[j + 1] = to_tile
	var/key = jointext(S, ",")
	var/had = best[key]
	if(!isnull(had) && had <= cost)
		return
	best[key] = cost
	parent[key] = list(from_key, list(action, d, act_movable))
	state_of[key] = S
	if(length(buckets) < cost + 1)
		buckets.len = cost + 1
	var/list/bucket = buckets[cost + 1]
	if(!bucket)
		bucket = list()
		buckets[cost + 1] = bucket
	bucket += key

/// Whether the bot (or, `for_movable`, something pushed or dragged) gets from `from` to the tile beside it, leaving out what's in `ignore`.
/// The bot's rules are bot_reachable_strict()'s (bot_pathing_permissive.dm); a thing moved opens no doors and goes nowhere a person stands.
/datum/bot_brain/proc/cw_link_ok(turf/from, turf/dest, list/ignore, for_movable, obj/item/card/id/id_card, simulated_only)
	if(!dest || dest.density)
		return FALSE
	if(bot_turf_is_deadly(dest) || bot_turf_has_active_field(dest))
		return FALSE
	if(!for_movable)
		if(GLOB.bot_hazard_turfs[dest] && bot_steps_into_hazard(from, dest, owner))
			return FALSE
		if(simulated_only && SSpathfinder.space_type_cache[dest.type] && !bot_turf_crossable_without_boots(dest, owner))
			return FALSE
	var/adir = get_dir(from, dest)
	if(locate(/obj/structure/window) in from)
		for(var/obj/structure/window/W in from)
			if(!W.CanAStarPass(id_card, adir))
				return FALSE
	if(locate(/obj/machinery/door/window) in from)
		for(var/obj/machinery/door/window/W in from)
			if(!W.CanAStarPass(id_card, adir))
				return FALSE
	var/rdir = turn(adir, 180)
	for(var/atom/movable/AM as anything in dest)
		if(ignore[AM])
			continue
		if(isobj(AM))
			var/obj/O = AM
			if(for_movable)
				if(O.density && (istype(O, /obj/machinery/door) || !O.CanAStarPass(null, rdir)))
					return FALSE
			else if((O.density || O.astar_always_asks) && !O.CanAStarPass(id_card, rdir, owner))
				return FALSE
		else if(isliving(AM) && AM != owner)
			var/mob/living/L = AM
			if(L.density && (for_movable || L.buckled || bot_parked_mule(L)))
				return FALSE
	return TRUE

// ---------------------------------------------------------------------------------------------
// 3. Doing it
// ---------------------------------------------------------------------------------------------

/// The plan's moves, one at a time, each checked. TRUE if it got to the end of them.
/datum/bot_brain/proc/run_clear_way(list/plan)
	var/expected_kind = pursuing_kind
	var/atom/expected_target = pursue_target
	var/list/said = list()
	for(var/list/act in plan)
		said += cw_describe(act)
	bot_log(src, "CLEAR WAY: [jointext(said, ", ")]")
	// A moment to see it: longer for somebody who doesn't do this often
	sleep(is_apex() ? rand(2, 4) : (skill_at_least(BOT_SKILL_MID) ? rand(4, 8) : rand(8, 15)))
	for(var/list/act in plan)
		if(QDELETED(owner) || owner.incapacitated() || pursuing_kind != expected_kind || pursue_target != expected_target)
			bot_log(src, "CLEAR WAY: stopped partway ([QDELETED(owner) ? "gone" : (owner.incapacitated() ? "can't move" : "something else came up")])")
			return FALSE
		if(!cw_do(act))
			bot_log(src, "CLEAR WAY: [cw_describe(act)] didn't work - planning again from here")
			return FALSE
	return TRUE

/datum/bot_brain/proc/cw_describe(list/act)
	var/obj/O = act[3]
	switch(act[1])
		if(CW_ACT_WALK)
			return "step [dir2text(act[2])]"
		if(CW_ACT_PUSH)
			return "push [O] [dir2text(act[2])]"
		if(CW_ACT_PULL)
			return "pull [O] stepping [dir2text(act[2])]"
		if(CW_ACT_CLIMB)
			return "climb [O]"
		if(CW_ACT_OPEN)
			return "open [O]"
	return "?"

/// One move. TRUE if it went as planned.
/datum/bot_brain/proc/cw_do(list/act)
	var/d = act[2]
	var/obj/O = act[3]
	var/turf/here = get_turf(owner)
	var/turf/ahead = get_step(here, d)
	if(!ahead || (O && QDELETED(O)))
		return FALSE
	var/action = act[1]
	if(action != CW_ACT_PULL && owner.pulling)
		owner.stop_pulling()
	switch(action)
		if(CW_ACT_WALK)
			for(var/try_step in 1 to 5) //a door opens as it's walked into, and takes a moment
				if(bot_step_towards(ahead) || get_turf(owner) == ahead)
					break
				sleep(3)
			. = get_turf(owner) == ahead
		if(CW_ACT_PUSH)
			if(get_turf(O) != ahead)
				return FALSE
			var/turf/beyond = get_step(ahead, d)
			human_pause(O)
			owner.face_atom(O)
			bot_step_towards(ahead) //walking into it is the push (PushAM(), living.dm)
			. = get_turf(O) == beyond && get_turf(owner) == ahead
		if(CW_ACT_PULL)
			if(owner.pulling != O)
				if(get_dist(owner, O) > 1)
					return FALSE
				human_pause(O)
				owner.start_pulling(O)
				if(owner.pulling != O)
					return FALSE
			bot_step_towards(ahead)
			. = get_turf(owner) == ahead && get_turf(O) == here
		if(CW_ACT_CLIMB)
			if(get_turf(O) != ahead)
				return FALSE
			clear_one_blocker(O) //its climbing (bot_items.dm): the stun waited out and anything dropped picked back up
			. = get_turf(owner) == ahead
		if(CW_ACT_OPEN)
			var/obj/structure/closet/C = O
			if(!istype(C) || get_dist(owner, C) > 1)
				return FALSE
			human_pause(C)
			. = open_closet(C) && !C.density
			return
	if(.)
		sleep(max(1, owner.movement_delay()))

#undef CW_WALK
#undef CW_PUSH
#undef CW_PULL
#undef CW_OPEN
#undef CW_CLIMB
#undef CW_MAX_MOVABLES
#undef CW_WINDOW
#undef CW_PAD
#undef CW_MAX_SIDE
#undef CW_ACT_WALK
#undef CW_ACT_PUSH
#undef CW_ACT_PULL
#undef CW_ACT_CLIMB
#undef CW_ACT_OPEN
