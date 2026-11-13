// Driving a mech, and taking one to Lavaland's ruins (the user's ask, 2026-11-09: low-pop players "going to ruins/Lava land in a mech to
// get rare items"; the Ripley itself comes from Robotics, goals/mech_build.dm).
//
//  - Driving: a bot in an exosuit walks its route the same, the exosuit stepping instead of its legs (relaymove(), what a pilot's keys
//    do). Doors open for the pilot's ID as for anyone (the exosuit bumps them).
//  - Down: a quiet-shift explorer bound for Lavaland (goals/low_pop.dm) with the Ripley free in Robotics climbs in, drives it aboard the
//    mining shuttle while it's in, and gets out; then rides down with it the usual way (goals/exploring.dm).
//  - Out there: in again, driven to the ruin, out to look round it (hands are wanted for that), back in, and driven back to park it by
//    the dock, for next time. Its armour takes what the goliaths and the watchers have for somebody on foot.

/// How far from the dock a parked exosuit still counts as the one down here to use.
#define BOT_MECH_PARK_RANGE 20
/// How far out it'll drive for a ruin.
#define BOT_MECH_RUIN_RANGE 200

/// The exosuit it's in, or null.
/datum/bot_brain/proc/in_mech()
	var/obj/mecha/M = owner.loc
	return istype(M) ? M : null

/datum/bot_brain/bot_step_towards(turf/next_node)
	var/obj/mecha/M = in_mech()
	if(!M)
		return ..()
	var/turf/here = get_turf(M)
	if(!here || next_node.z != here.z || get_dist(here, next_node) > 1 || bot_turf_is_deadly(next_node))
		return FALSE
	var/d = get_dir(here, next_node)
	// Still moving from the last step, or from the drill (its own wait): a moment's wait, as a pilot's key is held down. Pressed early it
	// counted as stuck, and the walk gave up on Lavaland in 26 of 34 refusals.
	var/wait = M.can_move - world.time
	if(wait > 0 && wait <= 2 SECONDS)
		addtimer(CALLBACK(src, PROC_REF(mech_step_later), M, d), wait + 1) //not a sleep: pursue() steps from inside the brain's tick
		return TRUE
	M.setDir(d) //facing it first, so the press is a step and not a turn (a turn costs a step's wait of its own)
	. = M.relaymove(owner, d)
	if(!. && world.time >= next_mech_step_note)
		next_mech_step_note = world.time + 5 SECONDS
		bot_log(src, "MECH: [M] wouldn't step to [bot_coord(next_node)]: [M.can_move >= world.time ? "still moving" : (!M.has_charge(M.step_energy_drain) ? "no charge ([M.get_charge()])" : (M.state ? "maintenance" : "blocked: [next_node.density ? "wall" : "something on it"]"))]")

/datum/bot_brain/proc/mech_step_later(obj/mecha/M, d)
	if(QDELETED(M) || owner?.loc != M)
		return
	M.setDir(d)
	M.relaymove(owner, d)

/// Climbs in: the climb takes a few seconds (MouseDrop_T's do_after); TRUE once it's in.
/datum/bot_brain/proc/climb_into_mech(obj/mecha/M)
	if(in_mech() == M)
		return TRUE
	if(QDELETED(M) || M.occupant || !owner.Adjacent(M) || in_mech())
		return FALSE
	telemetry_ui_action(M, "climb in")
	M.MouseDrop_T(owner, owner)
	if(M.occupant != owner)
		bot_log(src, "MECH: couldn't get into [M]")
		return FALSE
	bot_log(src, "MECH: in [M]")
	return TRUE

/datum/bot_brain/proc/climb_out_of_mech()
	var/obj/mecha/M = in_mech()
	if(!M)
		return TRUE
	telemetry_ui_action(M, "eject")
	M.go_out()
	bot_log(src, "MECH: out of [M]")
	return !in_mech()

/// A working Ripley nobody's in, in Robotics, or left by the station's mining dock (somebody who missed the shuttle with it).
/datum/bot_brain/proc/free_ripley_in_robotics()
	var/obj/docking_port/stationary/dock = bot_mining_dock(my_z())
	for(var/obj/mecha/working/ripley/R in GLOB.mechas_list)
		if(QDELETED(R) || R.occupant || R.z != my_z() || R.obj_integrity <= R.max_integrity / 2 || taken_by_another(R))
			continue
		if(in_robotics(R) || (dock && get_dist(R, dock) <= BOT_MECH_PARK_RANGE && !bot_aboard_mining_shuttle(R)))
			return R
	return null

/// A Ripley nobody's in, on this Lavaland near the dock (parked by somebody who brought it down), or aboard the shuttle here.
/datum/bot_brain/proc/lavaland_mech()
	var/obj/docking_port/stationary/dock = bot_mining_dock(my_z())
	for(var/obj/mecha/working/ripley/R in GLOB.mechas_list)
		if(QDELETED(R) || R.occupant || R.z != my_z() || R.obj_integrity < R.max_integrity / 2 || taken_by_another(R))
			continue
		// Half a cell at least: drilling through the rock runs one down, and two of the three drives that gave up in the rock last
		// time stopped there with it flat, the pilot on foot among the goliaths. There's no charging it on Lavaland.
		if(!R.cell || R.cell.charge < R.cell.maxcharge * 0.5)
			continue
		if(bot_aboard_mining_shuttle(R) || (dock && get_dist(R, dock) <= BOT_MECH_PARK_RANGE))
			return R
	return null

/// A floor tile aboard the shuttle with nothing in the way, for an exosuit to stand on.
/proc/bot_shuttle_parking()
	var/obj/docking_port/mobile/M = bot_mining_shuttle()
	if(!M)
		return null
	for(var/area/A as anything in M.shuttle_areas)
		for(var/turf/open/floor/T in A)
			if(T.density || (locate(/obj/mecha) in T) || (locate(/obj/machinery) in T))
				continue
			var/blocked = FALSE
			for(var/atom/movable/AM in T)
				if(AM.density)
					blocked = TRUE
					break
			if(!blocked)
				return T
	return null

/datum/bot_duty/explore/try_start(datum/bot_brain/bot)
	if(bot.state == BOT_STATE_GOAL && bot.current_goal)
		return ..()
	if(!bot.is_miner() && bot.low_pop_lavaland() && bot.mech_trip_step())
		return TRUE
	return ..()

/// A mech's part in a quiet-shift Lavaland trip, if there's one to do now: TRUE if it's started on it.
/datum/bot_brain/proc/mech_trip_step()
	if(bot_storm_over(my_z()))
		return FALSE
	if(on_lavaland())
		if(explore_time_up())
			return FALSE
		var/obj/mecha/working/ripley/R = lavaland_mech()
		var/obj/effect/landmark/ruin/ruin = R && mech_ruin_to_explore(R)
		return ruin ? assign_goal(new /datum/bot_goal/mech_ruin_trip(R, ruin)) : FALSE
	if(!is_station_level(my_z()) || pursuit != BOT_PURSUIT_EXPLORE || world.time < explore_blocked_until || world.time < mech_down_tried_until)
		return FALSE
	// The Ripley's behind Robotics' doors: robotics access along with the mining, from the HoP, the way anybody borrowing it would.
	var/obj/mecha/working/ripley/waiting = free_ripley_in_robotics()
	var/obj/item/card/id/card = route_card()
	if(waiting && in_robotics(waiting) && !(ACCESS_ROBOTICS in card?.access) && world.time >= next_explore_access_ask && bot_find_card_granter(owner))
		next_explore_access_ask = world.time + 10 MINUTES
		var/list/wanted = list(ACCESS_ROBOTICS)
		var/names = "robotics"
		if(!has_mining_access())
			wanted += list(ACCESS_MINING, ACCESS_MINING_STATION, ACCESS_MAILSORTING)
			names = "mining and robotics"
		bot_log(src, "MECH: asking for [names] access, for the Ripley")
		return assign_goal(new /datum/bot_goal/job_transfer/access(wanted, names))
	// Only once it's ready to go down itself (the access, the kit, the mask and tank: the duty sees to those first), and the shuttle's in.
	if(!has_mining_access() || !ready_for_lavaland() || !find_carried_tool(/obj/item/gun/energy/kinetic_accelerator) || !bot_mining_shuttle_at("mining_home"))
		return FALSE
	for(var/obj/mecha/working/ripley/aboard in GLOB.mechas_list)
		if(bot_aboard_mining_shuttle(aboard))
			return FALSE //one's going down already
	var/obj/mecha/working/ripley/R = free_ripley_in_robotics()
	if(!R || !can_walk_lawfully_to(R))
		return FALSE
	mech_down_tried_until = world.time + 15 MINUTES
	return assign_goal(new /datum/bot_goal/take_mech_down(R))

/datum/bot_brain
	var/mech_down_tried_until = 0
	var/next_mech_step_note = 0

/// The nearest ruin down here nobody's been through that the exosuit can drive to: further out than on foot (BOT_EXPLORE_RANGE), the
/// exosuit being quicker and harder to kill, but the same deadly ones left alone.
/datum/bot_brain/proc/mech_ruin_to_explore(obj/mecha/M)
	var/list/candidates = list()
	for(var/obj/effect/landmark/ruin/R as anything in GLOB.ruin_landmarks)
		if(QDELETED(R) || R.z != my_z() || GLOB.bot_ruins_explored[R] || bot_ruin_deadly(R))
			continue
		var/dist = get_dist(M, R)
		if(dist <= BOT_MECH_RUIN_RANGE)
			candidates[R] = dist
	sortTim(candidates, GLOBAL_PROC_REF(cmp_numeric_asc), TRUE)
	var/tries = 0
	for(var/obj/effect/landmark/ruin/R as anything in candidates)
		var/turf/spot = bot_ruin_spot(R)
		if(spot && (bot_mech_drill(M) || can_walk_lawfully_to(spot))) //with a drill, the rock between is a tunnel, as with a pick on foot
			return R
		if(++tries >= 3)
			break
	bot_log(src, "MECH: no ruin to drive to: [length(candidates)] within [BOT_MECH_RUIN_RANGE] tiles, none with a way there")
	return null

// ---------------------------------------------------------------------------------------------
// Down: the Ripley aboard the shuttle
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/take_mech_down
	lawful = TRUE
	exclusive = TRUE
	doing = "taking the Ripley down to the mine"

/datum/bot_goal/take_mech_down/New(obj/mecha/M)
	. = ..()
	target = M

/datum/bot_goal/take_mech_down/resolve_target(datum/bot_brain/bot)
	var/obj/mecha/M = target
	if(QDELETED(M) || (M.occupant && M.occupant != bot.owner))
		target = null

/datum/bot_goal/take_mech_down/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/drive_mech_aboard())
	return list(S)

/datum/bot_goal/take_mech_down/on_give_up(datum/bot_brain/bot)
	bot.climb_out_of_mech()

/datum/bot_goal/take_mech_down/on_success(datum/bot_brain/bot)
	bot_tally("ripleys taken down to Lavaland")
	if(prob(60))
		bot_say(bot.owner, pick(";Taking the Ripley down to Lavaland.", "Borrowing the Ripley. I'll bring it back. Probably.", ";Ripley's on the mining shuttle, heading down."))

/// In, along to the shuttle while it's in, onto a free tile aboard, and out.
/datum/bot_step/drive_mech_aboard
	var/turf/parking
	var/tries = 0

/datum/bot_step/drive_mech_aboard/execute(datum/bot_brain/bot)
	var/obj/mecha/M = bot.current_goal?.target
	if(!istype(M) || QDELETED(M))
		return GOAL_STEP_FAIL
	if(bot.in_mech() != M)
		if(!bot.climb_into_mech(M))
			return GOAL_STEP_FAIL
	if(bot_aboard_mining_shuttle(M))
		return bot.climb_out_of_mech() ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(!bot_mining_shuttle_at("mining_home") || ++tries > 3)
		bot.climb_out_of_mech()
		return GOAL_STEP_FAIL
	parking = bot_shuttle_parking()
	if(!parking)
		bot.climb_out_of_mech()
		return GOAL_STEP_FAIL
	// It's just come in: what was found before it docked (no way aboard, region_floods) is out of date. The mech miner drove for it 46 ms
	// after it docked, was told there was no way, and gave the trip up (Bot Shift, 2026-11-12).
	bot.region_floods = null
	// Somebody stood in the doorway: a word, and a moment for them to move. The other miner stood there while the Ripley's driver tried
	// to get past, and the trip was given up (Bot Shift, 2026-11-12).
	for(var/mob/living/carbon/human/H in range(1, get_turf(M)))
		if(H != bot.owner && H.stat == CONSCIOUS && bot_aboard_mining_shuttle(H) != bot_aboard_mining_shuttle(M) && tries <= 3)
			if(tries == 1)
				bot_say(bot.owner, pick("Coming through with the Ripley.", "Mind out, Ripley coming aboard.", "[H.first_name()], shift over, the Ripley's coming on."))
			addtimer(CALLBACK(src, PROC_REF(carry_on), bot, bot.current_goal), 3 SECONDS)
			return GOAL_STEP_PENDING
	return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(parking)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/datum/bot_step/drive_mech_aboard/proc/carry_on(datum/bot_brain/bot, datum/bot_goal/goal)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_goal != goal || !bot.on_this_step(src))
		return
	var/result = execute(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

// ---------------------------------------------------------------------------------------------
// Out there: to a ruin and back in it
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/mech_ruin_trip
	lawful = TRUE
	exclusive = TRUE
	braves_bad_air = TRUE //the cabin's own air, and dressed for it outside (ready_for_lavaland())
	doing = "taking the Ripley out to a ruin"
	var/obj/mecha/mech
	var/obj/effect/landmark/ruin/ruin
	var/turf/parked_at

/datum/bot_goal/mech_ruin_trip/New(obj/mecha/M, obj/effect/landmark/ruin/R)
	. = ..()
	mech = M
	ruin = R
	target = M

/datum/bot_goal/mech_ruin_trip/resolve_target(datum/bot_brain/bot)
	if(QDELETED(mech) || QDELETED(ruin) || (mech.occupant && mech.occupant != bot.owner))
		target = null

/datum/bot_goal/mech_ruin_trip/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/mech_ruin_trip())
	return list(S)

/datum/bot_goal/mech_ruin_trip/on_give_up(datum/bot_brain/bot)
	GLOB.bot_ruins_explored[ruin] = TRUE
	if(bot.in_mech() && bot.on_lavaland())
		return //on its way back in it, a fresh errand will see it home
	bot.climb_out_of_mech()

/datum/bot_goal/mech_ruin_trip/on_success(datum/bot_brain/bot)
	bot_tally("ruins reached in a mech")

/// The trip's stages, one look each: in, to the ruin, out, looting, back in, home to the dock, out.
/datum/bot_step/mech_ruin_trip
	var/stage = "board"
	var/actions = 0
	var/climb_tries = 0
	var/datum/bot_step/paced/loot_ruin/looting

/datum/bot_step/mech_ruin_trip/proc/again(datum/bot_brain/bot, delay = 5)
	addtimer(CALLBACK(src, PROC_REF(carry_on), bot, bot.current_goal), delay)
	return GOAL_STEP_PENDING

/datum/bot_step/mech_ruin_trip/proc/carry_on(datum/bot_brain/bot, datum/bot_goal/goal)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_goal != goal || !bot.on_this_step(src))
		return
	var/result
	try
		result = execute(bot)
	catch(var/exception/e)
		bot_log_exception(bot, "mech_ruin_trip", e)
		result = GOAL_STEP_FAIL
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_step/mech_ruin_trip/execute(datum/bot_brain/bot)
	var/datum/bot_goal/mech_ruin_trip/G = bot.current_goal
	if(!istype(G) || QDELETED(G.mech) || QDELETED(G.ruin) || ++actions > 60)
		return GOAL_STEP_FAIL
	var/turf/spot = bot_ruin_spot(G.ruin)
	switch(stage)
		if("board")
			if(!G.parked_at)
				G.parked_at = get_turf(G.mech)
			if(!bot.climb_into_mech(G.mech))
				return GOAL_STEP_FAIL
			stage = "out"
			bot_log(bot, "MECH: driving [G.mech] to [G.ruin.ruin_template?.name || "a ruin"]")
			return bot.suspend_goal_for(new /datum/bot_goal/drive_to_ruin(G.ruin)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		if("out")
			if(!spot || get_dist(get_turf(bot.owner), spot) > 6)
				var/obj/mecha/M = bot.in_mech()
				if(M?.cell && M.cell.charge < M.cell.maxcharge * 0.25)
					stage = "home" //turned back on a low cell: home to park it, not left in the rock
					return again(bot)
				return GOAL_STEP_FAIL //never got there
			if(bot_storm_over(bot.my_z()))
				stage = "home" //a storm on its way: no getting out in it
				return again(bot)
			bot.climb_out_of_mech()
			stage = "loot"
			looting = new
			looting.start(bot)
			return again(bot)
		if("loot")
			var/clicked = FALSE
			if(!bot_storm_over(bot.my_z()) && looting.clicks < looting.max_clicks)
				try
					clicked = looting.do_click(bot)
				catch(var/exception/e)
					bot_log_exception(bot, "mech_ruin_trip/loot", e)
				looting.clicks++
			if(clicked)
				return again(bot, max(looting.wait_for, 10))
			GLOB.bot_ruins_explored[G.ruin] = TRUE
			stage = "back_in"
			return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(G.mech)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		if("back_in")
			if(!bot.climb_into_mech(G.mech))
				// The climb takes four seconds, and a goliath's tentacle or a watcher's freeze in them stops it: another go.
				if(++climb_tries > 3)
					return GOAL_STEP_FAIL
				if(!bot.owner.Adjacent(G.mech))
					return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(G.mech)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
				return again(bot, 2 SECONDS)
			stage = "home"
			return again(bot)
		if("home")
			if(!bot.in_mech() && !bot.climb_into_mech(G.mech))
				return GOAL_STEP_FAIL
			stage = "park"
			return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(G.parked_at)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		if("park")
			bot.climb_out_of_mech()
			bot_log(bot, "MECH: parked [G.mech] back by the dock")
			return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

#undef BOT_MECH_PARK_RANGE
#undef BOT_MECH_RUIN_RANGE

// ---------------------------------------------------------------------------------------------
// The drill: through the rock, and at whatever's in the way
// ---------------------------------------------------------------------------------------------

/// The drill on an exosuit, if it has one.
/proc/bot_mech_drill(obj/mecha/M)
	return locate(/obj/item/mecha_parts/mecha_equipment/drill) in M?.equipment

/// The drill at something beside it: faced, selected, and the pilot's click (click_action()). The drilling takes its own time.
/datum/bot_brain/proc/mech_drill_at(atom/A)
	var/obj/mecha/M = in_mech()
	var/obj/item/mecha_parts/mecha_equipment/drill/D = bot_mech_drill(M)
	if(!D || !M.Adjacent(A))
		return FALSE
	M.setDir(get_dir(M, A))
	M.selected = D
	telemetry_ui_action(M, "drill [A]")
	INVOKE_ASYNC(M, TYPE_PROC_REF(/obj/mecha, click_action), A, owner)
	return TRUE

/// In a fight from inside an exosuit: the drill if it has one, the fist of it if not. Hands do nothing in there.
/datum/bot_brain/fight_in_reach(mob/living/target)
	var/obj/mecha/M = in_mech()
	if(!M)
		return ..()
	owner.changeNext_move(CLICK_CD_MELEE)
	if(mech_drill_at(target))
		bot_log(src, "MECH: drilling [target]")
		return
	M.setDir(get_dir(M, target))
	M.selected = null
	INVOKE_ASYNC(M, TYPE_PROC_REF(/obj/mecha, click_action), target, owner)
	bot_log(src, "MECH: punching [target] with [M]")

/// To a ruin in the exosuit, the way an explorer crosses Lavaland on foot (goals/exploring.dm's head_for_ruin): straight at it, through
/// the rock with the drill, round the lava.
/datum/bot_goal/drive_to_ruin
	lawful = TRUE
	braves_bad_air = TRUE
	doing = "driving out to a ruin"

/datum/bot_goal/drive_to_ruin/New(obj/effect/landmark/ruin/R)
	. = ..()
	target = R

/datum/bot_goal/drive_to_ruin/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/paced/head_for_ruin/mech())
	return list(S)

/// From inside an exosuit the bot's own x, y and z are 0 (it isn't on the map, the exosuit is): positions go by its turf.
/datum/bot_step/paced/head_for_ruin/mech/start(datum/bot_brain/bot)
	stuck = 0
	looked = FALSE
	trodden = list()
	var/turf/spot = get_turf(bot.current_goal?.target)
	var/turf/here = get_turf(bot.owner)
	return spot && here && here.z == spot.z

/datum/bot_step/paced/head_for_ruin/mech/do_click(datum/bot_brain/bot)
	var/obj/mecha/M = bot.in_mech()
	if(!M)
		return ..()
	var/turf/spot = get_turf(bot.current_goal?.target)
	var/turf/here = get_turf(M)
	if(!spot || !here || bot.owner.incapacitated() || here.z != spot.z)
		return FALSE
	if(get_dist(here, spot) <= 2)
		return FALSE //there
	// A quarter of the cell left and still in the rock: back while it'll still get there (mech_ruin_trip's "out" turns for home).
	if(M.cell && M.cell.charge < M.cell.maxcharge * 0.25)
		bot_log(bot, "MECH: [M]'s cell is down to a quarter - turning back")
		return FALSE
	if(bot.pursuing_kind)
		wait_for = 10
		return TRUE
	if(!looked)
		looked = TRUE
		var/turf/nearest = bot.nearest_walkable_toward(spot)
		if(nearest && get_dist(nearest, spot) < get_dist(here, spot) - 2 && bot.pursue(nearest, "follow", force = TRUE))
			wait_for = 10
			return TRUE
	var/x_off = spot.x - here.x
	var/y_off = spot.y - here.y
	var/major = abs(x_off) >= abs(y_off) ? (x_off > 0 ? EAST : WEST) : (y_off > 0 ? NORTH : SOUTH)
	var/minor = abs(x_off) >= abs(y_off) ? (y_off > 0 ? NORTH : SOUTH) : (x_off > 0 ? EAST : WEST)
	for(var/direction in list(major, minor, turn(major, 90), turn(major, -90)))
		var/turf/next = get_step(here, direction)
		if(!next || bot_turf_is_deadly(next) || istype(next, /turf/closed/mineral/gibtonite))
			continue
		if(ismineralturf(next))
			if(!bot.mech_drill_at(next))
				continue
			wait_for = 10 //the drill's own wait (drill_delay), and the step on
			stuck = 0
			looked = FALSE
			return TRUE
		if(trodden[next] >= 2)
			continue
		if(!next.density && bot.bot_step_towards(next))
			trodden[next] = trodden[next] + 1
			wait_for = 3
			stuck = 0
			looked = FALSE
			return TRUE
	if(++stuck > 5)
		bot_log(bot, "MECH: no way on to the ruin from [bot_coord(here)]")
		return FALSE
	wait_for = 10
	return TRUE

/datum/bot_step/paced/head_for_ruin/mech/finish(datum/bot_brain/bot)
	var/turf/spot = get_turf(bot.current_goal?.target)
	return (spot && get_dist(get_turf(bot.owner), spot) <= 6) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// In a sealed exosuit on its own air tank it breathes the cabin's air: what's outside is nothing to put a mask on for. Not a Ripley: its
/// cockpit is open (enclosed = FALSE, so no air tank at all), and the pilot breathes whatever's outside. Both bot miners in the Ripley
/// suffocated on Lavaland with full tanks on their belts, this having told them the cabin had air (Bot Shift, 2026-11-12).
/datum/bot_brain/mind_air_supply()
	var/obj/mecha/M = in_mech()
	if(M?.use_internal_tank)
		return
	// Out on Lavaland in an open cockpit: on its mask and tank and they stay on, as a miner's do out on the rock. No closing the valve at the
	// base's door and opening it again outside, and no running for air in the thing: short of air, the trip's over (goals/mining_mech.dm).
	if(M && !M.enclosed && on_lavaland())
		if(!owner.internal)
			emergency_internals()
		return
	return ..()

/// The z it's on, from inside an exosuit too (where its own z is 0: it isn't on the map, the exosuit is).
/datum/bot_brain/proc/my_z()
	var/turf/T = get_turf(owner)
	return T?.z
