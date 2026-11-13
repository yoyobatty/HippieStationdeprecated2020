// Putting the station back: what's been smashed gets fixed, and what's been going on gets taken seriously.
//
//  - Engineers rebuild the windows. Every full window destroyed goes on a list, and whoever's free takes the nearest:
//    the player's way, rods for the grille if that went too (stood on the tile, from the stack's own menu), then glass
//    clicked on the grille. Rods and glass come out of whatever locker or crate has them.
//  - A head of staff who hears the place is going to pieces goes to a communications console and puts the station on
//    blue alert.

/// Major crimes going unanswered before somebody in command raises the alert.
#define BOT_ALERT_MAJOR_CRIMES 2

/// Something smashed that hasn't been put back.
/datum/bot_wreck
	var/turf/where
	var/smashed_at = 0

GLOBAL_LIST_EMPTY(bot_wrecks)

/// A full window destroyed: from obj_destruction(). Anything else that breaks is left for somebody to notice.
/proc/bot_note_wreckage(obj/O)
	var/obj/structure/window/W = O
	if(!istype(W) || !W.fulltile || !length(GLOB.bot_brains))
		return
	var/turf/T = get_turf(W)
	if(!T)
		return
	for(var/datum/bot_wreck/known as anything in GLOB.bot_wrecks)
		if(known.where == T)
			return
	var/datum/bot_wreck/wreck = new
	wreck.where = T
	wreck.smashed_at = world.time
	GLOB.bot_wrecks += wreck

/datum/bot_brain
	var/windows_rebuilt = 0
	/// Wreck -> when it's worth another look.
	var/list/wrecks_blocked

/// The nearest smashed window this bot can walk to and nobody else has in hand.
/datum/bot_brain/proc/pick_wreck()
	var/list/wrecks = list() //wreck -> how far off
	for(var/datum/bot_wreck/wreck as anything in GLOB.bot_wrecks.Copy())
		var/turf/T = wreck.where
		if(locate(/obj/structure/window) in T)
			GLOB.bot_wrecks -= wreck //somebody got to it
			continue
		if(T.z != owner.z || LAZYACCESS(wrecks_blocked, wreck) > world.time || (gym_run && get_area(T) != get_area(owner)))
			continue
		var/obj/structure/grille/G = locate() in T
		if(taken_by_another(G || T))
			continue
		wrecks[wreck] = get_dist(owner, T)
	var/tries = 0
	while(length(wrecks) && tries++ < 3)
		var/datum/bot_wreck/nearest
		for(var/datum/bot_wreck/wreck as anything in wrecks)
			if(!nearest || wrecks[wreck] < wrecks[nearest])
				nearest = wreck
		wrecks -= nearest
		if(can_walk_lawfully_to(nearest.where))
			return nearest
		LAZYSET(wrecks_blocked, nearest, world.time + 5 MINUTES)
	return null

/datum/bot_duty/repair_windows
	name = "fixing the windows"
	jobs = list("Station Engineer", "Chief Engineer")
	interval_min = 300
	interval_max = 900

/datum/bot_duty/repair_windows/try_start(datum/bot_brain/bot)
	if(!length(GLOB.bot_wrecks))
		return FALSE
	var/datum/bot_wreck/wreck = bot.pick_wreck()
	return wreck ? bot.assign_goal(new /datum/bot_goal/repair_window(wreck)) : FALSE

/datum/bot_goal/repair_window
	lawful = TRUE
	exclusive = TRUE
	doing = "fixing a window somebody put in"
	var/datum/bot_wreck/wreck

/datum/bot_goal/repair_window/New(datum/bot_wreck/W)
	. = ..()
	wreck = W

/datum/bot_goal/repair_window/resolve_target(datum/bot_brain/bot)
	var/obj/structure/grille/G = locate() in wreck.where
	target = G || wreck.where

/datum/bot_goal/repair_window/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/repair_window/S = new
	S.steps = list(new /datum/bot_step/get_window_materials(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/rebuild_window())
	return list(S)

/datum/bot_goal/repair_window/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.wrecks_blocked, wreck, world.time + 5 MINUTES)

/datum/bot_goal/repair_window/on_success(datum/bot_brain/bot)
	GLOB.bot_wrecks -= wreck
	bot.windows_rebuilt++
	bot_log(bot, "rebuilt the window at [bot_coord(wreck.where)]")

/datum/bot_strategy/repair_window/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// A stack this bot has on it with at least `amount` left.
/datum/bot_brain/proc/carried_stack(stack_type, amount)
	var/obj/item/stack/S = find_carried_tool(stack_type)
	return S && S.get_amount() >= amount ? S : null

/// Rods if it'll need them, and glass. One trip each at most, and if there's none to be had that's the end of it.
/datum/bot_step/get_window_materials
	var/tried_rods = FALSE
	var/tried_glass = FALSE

/datum/bot_step/get_window_materials/execute(datum/bot_brain/bot)
	var/datum/bot_goal/repair_window/G = bot.current_goal
	var/obj/structure/grille/grille = locate() in G.wreck.where
	if((!grille || grille.broken) && !bot.carried_stack(/obj/item/stack/rods, 2))
		if(tried_rods)
			return GOAL_STEP_FAIL
		tried_rods = TRUE
		return fetch(bot, /obj/item/stack/rods)
	if(!bot.carried_stack(/obj/item/stack/sheet/glass, 2))
		if(tried_glass)
			return GOAL_STEP_FAIL
		tried_glass = TRUE
		return fetch(bot, /obj/item/stack/sheet/glass)
	return GOAL_STEP_SUCCESS

/datum/bot_step/get_window_materials/proc/fetch(datum/bot_brain/bot, stack_type)
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = stack_type
	get.lawful = TRUE
	get.doing = "getting supplies for a repair"
	return bot.suspend_goal_for(get) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/datum/bot_step/paced/rebuild_window
	max_clicks = 8

/datum/bot_step/paced/rebuild_window/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/repair_window/G = bot.current_goal
	var/turf/T = G?.wreck?.where
	var/mob/living/carbon/human/H = bot.owner
	if(!T || (locate(/obj/structure/window) in T) || H.incapacitated())
		return FALSE
	var/obj/structure/grille/grille = locate() in T
	if(!grille)
		var/obj/item/stack/rods/rods = bot.carried_stack(/obj/item/stack/rods, 2)
		if(get_turf(H) != T || !rods || !bot.ready_in_hand(rods))
			return FALSE
		bot.human_pause(rods)
		usr = H //the stack's menu goes by whoever clicked it
		rods.Topic(null, list("make" = "1", "multiplier" = "1"))
		wait_for = 5
		return TRUE
	if(grille.broken)
		var/obj/item/stack/rods/rods = bot.carried_stack(/obj/item/stack/rods, 1)
		if(!rods)
			return FALSE
		bot.use_tool_on(rods, grille)
		wait_for = 5
		return TRUE
	// The window comes down on the tile: not with the bot stood on it.
	if(get_turf(H) == T)
		for(var/turf/open/next_to in get_adjacent_open_turfs(T))
			if(!is_blocked_turf(next_to, TRUE))
				step_to(H, next_to)
				break
		wait_for = 5
		return TRUE
	var/obj/item/stack/sheet/glass/glass = bot.carried_stack(/obj/item/stack/sheet/glass, 2)
	if(!glass)
		return FALSE
	bot.use_tool_on(glass, grille) //grille/attackby(): a 2 second do_after
	return TRUE

/datum/bot_step/paced/rebuild_window/finish(datum/bot_brain/bot)
	var/datum/bot_goal/repair_window/G = bot.current_goal
	return (locate(/obj/structure/window) in G?.wreck?.where) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Walls
// ---------------------------------------------------------------------------------------------
// The user's ruling (2026-11-13, after the wiki guides review): engineers put back what's been destroyed "back to the map". A wall that's
// gone (blown out, smashed, burnt through, taken apart) goes on a list the moment its tile stops being a wall, and whoever's free takes
// the nearest. The player's way (girders.dm): a girder from two metal sheets with the stack's own menu ("wall girders"), stood on the
// tile; then from beside it two more metal sheets on the girder for a wall, or a plasteel sheet to reinforce the girder and a second to
// finish a reinforced wall. A girder the wall left behind is built on as it is. It's put back as it was, plain or reinforced. A wall
// open to space has usually taken the room's air with it, so it suits up first, as for a hole in the hull; a tile that's gone to space
// itself gets its floor back first (repair_hull.dm).

/// A wall that's been destroyed and not put back.
/datum/bot_lost_wall
	var/turf/where
	/// What it's put back as: /turf/closed/wall or /turf/closed/wall/r_wall
	var/wall_type
	var/lost_at = 0

GLOBAL_LIST_EMPTY(bot_lost_walls)

/turf/ChangeTurf(path, list/new_baseturfs, flags)
	var/was = istype(src, /turf/closed/wall) ? type : null
	. = ..()
	if(was && length(GLOB.bot_brains) && !istype(., /turf/closed/wall))
		bot_note_lost_wall(., was)

/// What a bot puts back for a wall of this type: plain or reinforced (rusted ones too). Null for anything else (mineral, cult, a
/// shuttle's): nothing a station engineer builds.
/proc/bot_rebuilt_wall_type(path)
	if(ispath(path, /turf/closed/wall/r_wall))
		return path == /turf/closed/wall/r_wall || ispath(path, /turf/closed/wall/r_wall/rust) ? /turf/closed/wall/r_wall : null
	return path == /turf/closed/wall || ispath(path, /turf/closed/wall/rust) ? /turf/closed/wall : null

/// A wall gone from this tile: from ChangeTurf(), the tile as it is now and what it was.
/proc/bot_note_lost_wall(turf/T, was)
	if(T in GLOB.bot_reinforcing)
		return //taken down to its girder to be reinforced (reinforce_wall): not lost
	var/wall_type = bot_rebuilt_wall_type(was)
	if(!wall_type || !T)
		return
	if(T in GLOB.bot_walls_to_reinforce) //put back plain for want of plasteel, and gone again: it was a reinforced wall
		GLOB.bot_walls_to_reinforce -= T
		wall_type = /turf/closed/wall/r_wall
	var/area/A = get_area(T)
	if(!A || istype(A, /area/space) || istype(A, /area/shuttle) || istype(A, /area/science/test_area) || istype(T, /turf/open/space/transit))
		return //out in space, a shuttle, or the toxins range: blown up on purpose
	for(var/datum/bot_lost_wall/known as anything in GLOB.bot_lost_walls)
		if(known.where == T)
			return
	var/datum/bot_lost_wall/W = new
	W.where = T
	W.wall_type = wall_type
	W.lost_at = world.time
	GLOB.bot_lost_walls += W
	bot_tally("walls lost")

/// Holes in the hull round it that nobody's patched: the floor first, as a player does, and the wall after. The bomb that takes a wall
/// leaves a crater beside it, and the way to the wall is across it: Hippie's Teleporter Room, the AI let the Chief Engineer in four times
/// and there was no way to the wall till the holes were patched (wallsboom3, 2026-11-13). Two tiles round, not just beside it: with the
/// hole beside the wall patched, the two beyond it still cut the wall off from the door (wallsboom4).
/proc/bot_beside_breach(turf/T)
	for(var/turf/open/space/S in range(2, T))
		if(S in GLOB.bot_hull_breaches)
			return TRUE
	return FALSE

/datum/bot_brain
	var/walls_rebuilt = 0
	/// Lost wall -> when it's worth another look.
	var/list/lost_walls_blocked
	/// No metal, plasteel or suit to be had: no wall is worth trying before this (as for the hull, repair_hull.dm).
	var/wall_work_blocked_until = 0

/// The nearest lost wall this bot can get to and nobody else has in hand. A tile that's gone to space waits for its floor. One in a room
/// its ID doesn't open is taken with a door to ask the AI for (repair_door_plan).
/datum/bot_brain/proc/pick_lost_wall()
	repair_door_plan = null
	var/list/walls = list() //lost wall -> how far off
	for(var/datum/bot_lost_wall/W as anything in GLOB.bot_lost_walls.Copy())
		var/turf/T = W.where
		if(istype(T, /turf/closed/wall))
			GLOB.bot_lost_walls -= W //somebody put it back
			continue
		if(!isfloorturf(T) || T.z != owner.z || LAZYACCESS(lost_walls_blocked, W) > world.time || (gym_run && !gym_run.in_arena(T))) //its own arena, rooms and all
			continue
		if(taken_by_another(T) || get_dist(owner, T) > 80 || bot_beside_breach(T))
			continue
		walls[W] = get_dist(owner, T)
	var/tries = 0
	while(length(walls) && tries++ < 3)
		var/datum/bot_lost_wall/nearest
		for(var/datum/bot_lost_wall/W as anything in walls)
			if(!nearest || walls[W] < walls[nearest])
				nearest = W
		walls -= nearest
		if(can_walk_lawfully_to(nearest.where))
			return nearest
		repair_door_plan = repair_doorstep(nearest.where)
		if(repair_door_plan)
			return nearest
		LAZYSET(lost_walls_blocked, nearest, world.time + 5 MINUTES)
	return null

/datum/bot_duty/rebuild_walls
	name = "rebuilding the walls"
	jobs = list("Station Engineer", "Chief Engineer")
	interval_min = 300
	interval_max = 900

/datum/bot_duty/rebuild_walls/applies_to(datum/bot_brain/bot)
	return ..() || bot_is_helper(bot) //goals/team_repairs.dm

/datum/bot_duty/rebuild_walls/try_start(datum/bot_brain/bot)
	if(length(GLOB.bot_lost_walls) && world.time >= bot.wall_work_blocked_until)
		var/datum/bot_lost_wall/W = bot.pick_lost_wall()
		if(W)
			return bot.assign_goal(new /datum/bot_goal/rebuild_wall(W, bot.repair_door_plan))
	if(length(GLOB.bot_walls_to_reinforce) && world.time >= bot.reinforce_blocked_until)
		var/turf/T = bot.pick_wall_to_reinforce()
		if(T)
			return bot.assign_goal(new /datum/bot_goal/reinforce_wall(T))
	return FALSE

/datum/bot_goal/rebuild_wall
	lawful = TRUE
	exclusive = TRUE
	braves_bad_air = TRUE //a wall out to space took the room's air: it suits up first (ensure_suit_for_wall)
	doing = "putting a wall back"
	var/datum/bot_lost_wall/lost
	/// No plasteel to be had for a reinforced wall: a plain one for now, to seal it, reinforced later (the user's ruling, 2026-11-13)
	var/make_do = FALSE

/// What it's putting up: the wall that was there, or a plain one for now
/datum/bot_goal/rebuild_wall/proc/wanted_type()
	return make_do ? /turf/closed/wall : lost.wall_type

/datum/bot_goal/rebuild_wall/New(datum/bot_lost_wall/W, list/door_plan)
	. = ..()
	lost = W
	set_door_plan(door_plan)

/datum/bot_goal/rebuild_wall/resolve_target(datum/bot_brain/bot)
	target = isfloorturf(lost?.where) ? lost.where : null

/datum/bot_goal/rebuild_wall/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/rebuild_wall/S = new
	S.steps = list(new /datum/bot_step/ensure_suit_for_wall(), new /datum/bot_step/get_wall_materials()) + steps_in() + list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/rebuild_wall())
	return list(S)

/datum/bot_goal/rebuild_wall/door_reason()
	return "put a wall back"

/datum/bot_goal/rebuild_wall/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.lost_walls_blocked, lost, world.time + 5 MINUTES)

/datum/bot_goal/rebuild_wall/on_success(datum/bot_brain/bot)
	GLOB.bot_lost_walls -= lost
	bot.walls_rebuilt++
	bot_tally("walls rebuilt")
	if(make_do)
		GLOB.bot_walls_to_reinforce |= lost.where
		bot_tally("walls put back plain for want of plasteel")
		bot_log(bot, "rebuilt the wall at [bot_coord(lost.where)] plain, for want of plasteel: to be reinforced")
		return
	bot_log(bot, "rebuilt the [lost.wall_type == /turf/closed/wall/r_wall ? "reinforced " : ""]wall at [bot_coord(lost.where)]")

/// The sheet the girder takes next, and how many: two metal for a plain wall; plasteel to reinforce it, and plasteel to finish.
/// Null for a girder that's been knocked loose or isn't a station girder: nothing an engineer builds on as it is.
/datum/bot_goal/rebuild_wall/proc/next_sheet(obj/structure/girder/G)
	if(!G)
		return /obj/item/stack/sheet/metal //the girder first
	if(G.type != /obj/structure/girder && G.type != /obj/structure/girder/reinforced)
		return null
	switch(G.state)
		if(GIRDER_REINF, GIRDER_REINF_STRUTS)
			return make_do ? /obj/item/stack/sheet/metal : /obj/item/stack/sheet/plasteel //metal on any girder makes a plain wall (girders.dm)
		if(GIRDER_NORMAL)
			return wanted_type() == /turf/closed/wall/r_wall ? /obj/item/stack/sheet/plasteel : /obj/item/stack/sheet/metal
	return null

/// What it has to have on it before it sets off: list(sheet type = how many), from what's on the tile now.
/datum/bot_goal/rebuild_wall/proc/sheets_needed()
	var/reinforced = wanted_type() == /turf/closed/wall/r_wall
	var/obj/structure/girder/G = locate() in lost.where
	if(!G)
		return reinforced ? list(/obj/item/stack/sheet/metal = 2, /obj/item/stack/sheet/plasteel = 2) : list(/obj/item/stack/sheet/metal = 4)
	var/sheet = next_sheet(G)
	if(!sheet)
		return null
	if(sheet == /obj/item/stack/sheet/metal)
		return list(/obj/item/stack/sheet/metal = 2)
	return list(/obj/item/stack/sheet/plasteel = G.state == GIRDER_REINF ? 1 : 2)

/datum/bot_strategy/rebuild_wall/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// Into a suit first if the air at the tile's gone, as for any work in vacuum (goals/gear_up_eva.dm). One try.
/datum/bot_step/ensure_suit_for_wall
	var/tried = FALSE

/datum/bot_step/ensure_suit_for_wall/execute(datum/bot_brain/bot)
	var/turf/open/T = bot.current_goal?.target
	if(bot.is_eva_ready() || (istype(T) && bot.turf_air_is_breathable(T)))
		return GOAL_STEP_SUCCESS
	if(tried)
		bot_log(bot, "no suit to be had for the wall at [bot_coord(T)] - leaving it")
		bot.wall_work_blocked_until = world.time + 5 MINUTES
		return GOAL_STEP_FAIL
	tried = TRUE
	return bot.suspend_goal_for(new /datum/bot_goal/gear_up_for_eva()) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// The sheets it takes, fetched once each: metal, and plasteel for a reinforced wall. None to be had is the end of it for a while.
/datum/bot_step/get_wall_materials
	var/list/tried

/datum/bot_step/get_wall_materials/execute(datum/bot_brain/bot)
	var/datum/bot_goal/rebuild_wall/G = bot.current_goal
	var/list/needed = istype(G) && G.sheets_needed()
	if(!needed)
		bot_log(bot, "can't build on what's left of the wall at [bot_coord(G?.lost?.where)]")
		return GOAL_STEP_FAIL
	for(var/sheet_type in needed)
		if(bot.carried_stack(sheet_type, needed[sheet_type]))
			continue
		if(LAZYFIND(tried, sheet_type))
			if(sheet_type == /obj/item/stack/sheet/plasteel && !G.make_do)
				G.make_do = TRUE
				bot_log(bot, "no plasteel to be had for the reinforced wall at [bot_coord(G.lost.where)]: a plain one for now, to seal it")
				return execute(bot) //what a plain wall takes
			var/obj/item/stack/sheet/S = sheet_type
			bot_log(bot, "not enough [initial(S.name)] to be had for the wall at [bot_coord(G.lost.where)]")
			bot.wall_work_blocked_until = world.time + 5 MINUTES
			return GOAL_STEP_FAIL
		LAZYADD(tried, sheet_type)
		var/datum/bot_goal/acquire_item_type/get = new
		get.item_type = sheet_type
		get.lawful = TRUE
		get.doing = "getting what it takes to put a wall back"
		if(bot.suspend_goal_for(get))
			return GOAL_STEP_PENDING
		return execute(bot) //none it can get to ("no way into where the plasteel is", MetaStation): tried, and on from there
	return GOAL_STEP_SUCCESS

/// Stood on the tile for the girder, then from beside it a sheet at a time on the girder.
/datum/bot_step/paced/rebuild_wall
	max_clicks = 8

/datum/bot_step/paced/rebuild_wall/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/rebuild_wall/G = bot.current_goal
	var/turf/T = G?.lost?.where
	var/mob/living/carbon/human/H = bot.owner
	if(!T || !isfloorturf(T) || H.incapacitated())
		return FALSE
	var/obj/structure/girder/girder = locate() in T
	if(!girder)
		if(get_turf(H) != T)
			if(!H.Adjacent(T) || is_blocked_turf(T, TRUE))
				return FALSE
			step_to(H, T)
			wait_for = 5
			return TRUE
		var/obj/item/stack/sheet/metal/metal = bot.carried_stack(/obj/item/stack/sheet/metal, 2)
		if(!metal || !bot.ready_in_hand(metal))
			return FALSE
		var/index = 0
		for(var/i in 1 to length(metal.recipes))
			var/datum/stack_recipe/R = metal.recipes[i]
			if(istype(R) && R.result_type == /obj/structure/girder)
				index = i
				break
		if(!index)
			return FALSE
		bot.human_pause(metal)
		if(QDELETED(metal) || H.get_active_held_item() != metal || get_turf(H) != T)
			return FALSE
		usr = H //the menu goes by whoever clicked it
		metal.Topic(null, list("make" = "[index]", "multiplier" = "1")) //"wall girders": four seconds, on the tile it's stood on
		wait_for = 5
		return TRUE
	// The wall comes up on the tile: not with the bot stood on it.
	if(get_turf(H) == T)
		for(var/turf/open/next_to in get_adjacent_open_turfs(T))
			if(!is_blocked_turf(next_to, TRUE))
				step_to(H, next_to)
				break
		wait_for = 5
		return TRUE
	if(!H.Adjacent(girder))
		return FALSE
	if(locate(/mob/living) in T)
		wait_for = 10 //somebody in the way of it
		return TRUE
	var/sheet_type = G.next_sheet(girder)
	var/obj/item/stack/sheet/S = sheet_type && bot.carried_stack(sheet_type, sheet_type == /obj/item/stack/sheet/metal ? 2 : 1)
	if(!S || !bot.ready_in_hand(S))
		return FALSE
	H.face_atom(girder)
	bot.use_tool_on(S, girder) //girder/attackby(): four to six seconds
	return TRUE

/datum/bot_step/paced/rebuild_wall/finish(datum/bot_brain/bot)
	var/datum/bot_goal/rebuild_wall/G = bot.current_goal
	return istype(G?.lost?.where, /turf/closed/wall) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Reinforcing a wall put back plain
// ---------------------------------------------------------------------------------------------
// A reinforced wall put back plain for want of plasteel (the user's ruling, 2026-11-13: "plain wall for now") is reinforced once there's
// plasteel to be had, as a player does it: the plating sliced off with a lit welder, which brings the wall down to its girder, then a
// plasteel sheet to reinforce the girder and a second to finish. Not on the hull: a girder doesn't hold air, and the room would go out
// through it for the half minute it takes. A wall on the hull stays plain.

GLOBAL_LIST_EMPTY(bot_walls_to_reinforce)
/// Walls a bot has taken down to the girder to reinforce: not lost (bot_note_lost_wall())
GLOBAL_LIST_EMPTY(bot_reinforcing)

/datum/bot_brain
	/// No plasteel or welder to be had: no wall is worth reinforcing before this
	var/reinforce_blocked_until = 0
	/// Wall -> when it's worth another look
	var/list/reinforce_blocked

/// Space beside it: a wall on the hull.
/proc/bot_wall_on_hull(turf/T)
	for(var/direction in GLOB.cardinals)
		if(istype(get_step(T, direction), /turf/open/space))
			return TRUE
	return FALSE

/// The nearest wall put back plain that it can get to and nobody else is at.
/datum/bot_brain/proc/pick_wall_to_reinforce()
	var/turf/best
	for(var/turf/T as anything in GLOB.bot_walls_to_reinforce.Copy())
		if(!istype(T, /turf/closed/wall) || istype(T, /turf/closed/wall/r_wall))
			GLOB.bot_walls_to_reinforce -= T //reinforced, or gone again (a lost wall again: bot_note_lost_wall())
			continue
		if(T.z != owner.z || (gym_run && !gym_run.in_arena(T)) || LAZYACCESS(reinforce_blocked, T) > world.time || taken_by_another(T) || bot_wall_on_hull(T) || get_dist(owner, T) > 80)
			continue
		if(!best || get_dist(owner, T) < get_dist(owner, best))
			best = T
	if(best && !can_walk_lawfully_to(best))
		LAZYSET(reinforce_blocked, best, world.time + 5 MINUTES)
		return null
	return best

/datum/bot_goal/reinforce_wall
	lawful = TRUE
	exclusive = TRUE
	doing = "reinforcing a wall"

/datum/bot_goal/reinforce_wall/New(turf/T)
	. = ..()
	target = T

/datum/bot_goal/reinforce_wall/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/rebuild_wall/S = new
	S.steps = list(new /datum/bot_step/get_reinforce_materials(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/reinforce_wall())
	return list(S)

/datum/bot_goal/reinforce_wall/on_give_up(datum/bot_brain/bot)
	var/turf/T = target
	if(!T)
		return
	GLOB.bot_reinforcing -= T
	if(!istype(T, /turf/closed/wall))
		bot_note_lost_wall(T, /turf/closed/wall/r_wall) //left at its girder: a reinforced wall lost, for whoever's next
	else
		LAZYSET(bot.reinforce_blocked, T, world.time + 10 MINUTES)

/datum/bot_goal/reinforce_wall/on_success(datum/bot_brain/bot)
	GLOB.bot_reinforcing -= target
	GLOB.bot_walls_to_reinforce -= target
	bot_tally("walls reinforced")
	bot_log(bot, "reinforced the wall at [bot_coord(target)]")

/// Two plasteel sheets and a welder, fetched once each. None to be had is the end of reinforcing for a while.
/datum/bot_step/get_reinforce_materials
	var/list/tried

/datum/bot_step/get_reinforce_materials/execute(datum/bot_brain/bot)
	var/list/needed = list(/obj/item/stack/sheet/plasteel = 2, /obj/item/weldingtool = 1)
	for(var/thing in needed)
		if(ispath(thing, /obj/item/stack) ? bot.carried_stack(thing, needed[thing]) : bot.find_carried_tool(thing))
			continue
		if(LAZYFIND(tried, thing))
			bot_log(bot, "nothing to reinforce the wall at [bot_coord(bot.current_goal?.target)] with: no [thing == /obj/item/weldingtool ? "welder" : "plasteel"] to be had")
			bot.reinforce_blocked_until = world.time + 10 MINUTES
			return GOAL_STEP_FAIL
		LAZYADD(tried, thing)
		var/datum/bot_goal/acquire_item_type/get = new
		get.item_type = thing
		get.lawful = TRUE
		get.doing = "getting what it takes to reinforce a wall"
		if(bot.suspend_goal_for(get))
			return GOAL_STEP_PENDING
		return execute(bot)
	return GOAL_STEP_SUCCESS

/// The wall cut down to its girder with the welder, from beside it; then the plasteel on the girder, a sheet at a time.
/datum/bot_step/paced/reinforce_wall
	max_clicks = 6

/datum/bot_step/paced/reinforce_wall/do_click(datum/bot_brain/bot)
	var/turf/T = bot.current_goal?.target
	var/mob/living/carbon/human/H = bot.owner
	if(!T || istype(T, /turf/closed/wall/r_wall) || H.incapacitated())
		return FALSE
	if(istype(T, /turf/closed/wall))
		if(!H.Adjacent(T) || bot_wall_on_hull(T))
			return FALSE
		var/obj/item/weldingtool/W = bot.find_carried_tool(/obj/item/weldingtool)
		if(!W || !bot.ready_in_hand(W))
			return FALSE
		bot.equip_welding_eye_protection()
		if(!W.isOn())
			bot.toggle_in_hand(W)
		if(!W.isOn())
			return FALSE
		GLOB.bot_reinforcing |= T
		H.face_atom(T)
		bot.use_tool_on(W, T) //wall/try_decon(): ten seconds slicing the plating off, down to its girder
		if(!QDELETED(W) && W.isOn() && H.is_holding(W))
			bot.toggle_in_hand(W) //off again before it goes in the bag
		return TRUE
	var/obj/structure/girder/G = locate() in T
	if(!G || !H.Adjacent(G))
		return FALSE
	var/obj/item/stack/sheet/plasteel/P = bot.carried_stack(/obj/item/stack/sheet/plasteel, 1)
	if(!P || !bot.ready_in_hand(P))
		return FALSE
	H.face_atom(G)
	bot.use_tool_on(P, G) //girder/attackby(): reinforced (six seconds), then finished (five)
	return TRUE

/datum/bot_step/paced/reinforce_wall/finish(datum/bot_brain/bot)
	return istype(bot.current_goal?.target, /turf/closed/wall/r_wall) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// A repair behind a door its ID doesn't open
// ---------------------------------------------------------------------------------------------
// The user's ruling (2026-11-13): an engineer who has to get into a room its ID doesn't open for a repair asks the AI over the radio to
// open up, as a player does ("AI, open this door please, I need to put a wall back in the Teleporter Room"), and waits at the door. The AI
// keeps the heads' rooms, the teleporter, the vault and the like shut to all but command (bot_ai_restricted_area(), goals/silicon.dm), so
// a repair in one of those is left for the Chief Engineer. Walls here, holes in the hull (repair_hull.dm) the same way.

/datum/bot_goal
	/// Where it asks the AI for a door from, for a repair in a room its ID doesn't open; null when it can walk there
	var/turf/ask_door_step
	var/datum/weakref/ask_door_ref

/datum/bot_brain
	/// What the last pick of a repair (pick_lost_wall(), pick_breach()) found for getting in: list(floor outside, door), or null
	var/list/repair_door_plan

/// Takes a way in found by repair_doorstep(): the door's its way through once it's open.
/datum/bot_goal/proc/set_door_plan(list/door_plan)
	if(!length(door_plan))
		return
	ask_door_step = door_plan[1]
	ask_door_ref = WEAKREF(door_plan[2])
	let_in_on_errand = TRUE //bot_doors.dm

/// The steps that get it in: to the door, and asking for it. None when it can walk there.
/datum/bot_goal/proc/steps_in()
	if(!ask_door_step)
		return list()
	var/datum/bot_step/move_to/to_door = new
	to_door.step_target = ask_door_step
	return list(to_door, new /datum/bot_step/paced/ask_ai_for_door())

/// What it tells the AI the door's for: "I need to [this] in [the room]".
/datum/bot_goal/proc/door_reason()
	return "fix something"

/// An AI up and able to work the doors.
/proc/bot_ai_can_open_doors()
	for(var/mob/living/silicon/ai/AI as anything in GLOB.ai_list)
		if(AI.stat != DEAD && !AI.control_disabled)
			return TRUE
	return FALSE

/// For a repair in a room this bot's ID doesn't open: list(the floor outside, the door) to ask to be let in from, or null. The nearest
/// door into the room from outside it, six tried at most. Whether it's the AI it asks or somebody with access is for the asking.
/datum/bot_brain/proc/repair_doorstep(turf/site)
	if(!site)
		return null
	var/area/room = get_area(site)
	var/list/spots = list() //floor outside -> list(door, how far it is from the repair)
	for(var/obj/machinery/door/airlock/D as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(QDELETED(D) || D.z != site.z || get_dist(D, site) > 30 || istype(D, /obj/machinery/door/airlock/external) || D.welded || !D.hasPower())
			continue
		for(var/direction in GLOB.cardinals)
			var/turf/inside = get_step(D, direction)
			var/turf/outside = get_step(D, turn(direction, 180))
			if(get_area(inside) != room || !isopenturf(outside) || get_area(outside) == room || is_blocked_turf(outside, TRUE))
				continue
			spots[outside] = list(D, get_dist(D, site))
	var/tries = 0
	while(length(spots) && tries++ < 6)
		var/turf/nearest
		for(var/turf/T as anything in spots)
			if(!nearest || spots[T][2] < spots[nearest][2])
				nearest = T
		var/obj/machinery/door/airlock/D = spots[nearest][1]
		spots -= nearest
		if(can_walk_lawfully_to(nearest))
			return list(nearest, D)
	return null

/// At the door: asks the AI over the radio, with what it's for, and waits for the door to open. Twice at most, a little apart, then it
/// gives the job up for now. Nothing opening a while after the first (or no radio to ask on), it presses the door's request as well, which
/// reaches the AI by the door's own wiring (press_door_request(), bot_radio.dm): a strict AI asks what for, and the second ask on the radio
/// is the answer. Once it opens, that door is its way in on this errand (let_in_door_now(), bot_doors.dm).
/// Then somebody with access (the user's ruling, 2026-11-13: "call a head to let in"): for a room the AI keeps to command, or with no AI
/// about, straight away; otherwise once the AI's had its chance. It's the call to be let in (let_out, bot_requests.dm), and whoever's ID
/// opens the door comes over and opens it.
/datum/bot_step/paced/ask_ai_for_door
	max_clicks = 4
	var/until = 0
	var/started = 0
	var/asked_at = -INFINITY
	var/asks = 0
	var/pressed = FALSE
	var/called = FALSE

/datum/bot_step/paced/ask_ai_for_door/start(datum/bot_brain/bot)
	until = world.time + 70 SECONDS
	started = world.time
	asked_at = -INFINITY
	asks = 0
	pressed = FALSE
	called = FALSE
	return TRUE

/datum/bot_step/paced/ask_ai_for_door/do_click(datum/bot_brain/bot)
	var/obj/machinery/door/airlock/D = bot.current_goal?.ask_door_ref?.resolve()
	if(world.time > until || !D || QDELETED(D) || !D.density)
		return FALSE
	var/area/room = get_area(bot.current_goal.target)
	var/what = bot.current_goal.door_reason()
	var/ai_will = bot_ai_can_open_doors() && (!bot_ai_restricted_area(room) || (bot.owner.mind?.assigned_role in GLOB.command_positions))
	if(!called && (!ai_will || world.time > started + 35 SECONDS))
		called = TRUE
		until = max(until, world.time + 90 SECONDS) //somebody walking over from wherever they are
		bot.call_for(/datum/bot_request_kind/let_out, pick(
			"Can somebody with access let me into [room?.name || "here"]? I need to [what] in there.",
			"Anyone with access to [room?.name || "this room"]? Could you let me into it, I need to [what] in there.",
			"Engineering here, at the door to [room?.name || "this room"]. Can someone let me into it? I need to [what]."), list(D))
		wait_for = 10
		return TRUE
	if(!ai_will)
		wait_for = 10
		return TRUE
	var/radio = bot.radio_works()
	if(!pressed && (asks || !radio) && world.time > asked_at + 12 SECONDS)
		pressed = TRUE
		bot.press_door_request()
		wait_for = 10
		return TRUE
	if(radio && asks < 2 && world.time > asked_at + 30 SECONDS)
		asked_at = world.time
		asks++
		bot.say_after_typing(pick(
			";AI, open this door please, I need to [what] in [room?.name || "there"].",
			";AI, door please. Engineering, here to [what] in [room?.name || "there"].",
			";AI, could you open up for me? I need to [what] in [room?.name || "there"]."))
	wait_for = 10
	return TRUE

/datum/bot_step/paced/ask_ai_for_door/finish(datum/bot_brain/bot)
	var/obj/machinery/door/airlock/D = bot.current_goal?.ask_door_ref?.resolve()
	if(D && !QDELETED(D) && !D.density)
		bot.let_in_door = REF(D)
		bot.let_in_until = world.time + 20 SECONDS
		bot_log(bot, "[D] opened for it: in to [bot.current_goal?.target]")
		return GOAL_STEP_SUCCESS
	bot_log(bot, "asked to be let in at [D || "the door"] for [bot.current_goal?.target] and nobody did")
	return GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// The alert
// ---------------------------------------------------------------------------------------------

/// Major crimes on the books whose culprit is still walking about.
/proc/bot_crimes_at_large()
	. = 0
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/datum/bot_wanted/W = GLOB.bot_security_wanted[ref]
		var/mob/living/M = ref.resolve()
		if(M && M.stat != DEAD && W.severity >= BOT_CRIME_MAJOR)
			.++

/datum/bot_duty/raise_alert
	name = "raising the alert"
	jobs = list("Captain", "Head of Security", "Head of Personnel")
	tier = BOT_DUTY_URGENT
	interval_min = 300
	interval_max = 600

/datum/bot_duty/raise_alert/try_start(datum/bot_brain/bot)
	if(GLOB.security_level != SEC_LEVEL_GREEN || bot_crimes_at_large() < BOT_ALERT_MAJOR_CRIMES)
		return FALSE
	return bot.find_comms_console() ? bot.assign_goal(new /datum/bot_goal/raise_alert()) : FALSE

/datum/bot_goal/raise_alert
	lawful = TRUE
	doing = "on my way to put us on alert"

/datum/bot_goal/raise_alert/resolve_target(datum/bot_brain/bot)
	target = bot.find_comms_console()

/datum/bot_goal/raise_alert/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/raise_alert/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/raise_alert())
	return list(S)

/datum/bot_strategy/raise_alert/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// At the console, the alert level buttons, with the ID that lets it.
/datum/bot_step/raise_alert/execute(datum/bot_brain/bot)
	var/obj/machinery/computer/communications/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || !bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	bot.human_pause(C)
	if(QDELETED(C) || !bot.owner.Adjacent(C) || (C.stat & (BROKEN|NOPOWER)) || GLOB.security_level != SEC_LEVEL_GREEN)
		return GOAL_STEP_FAIL
	bot.owner.face_atom(C)
	bot.telemetry_ui_action(C, "set alert level")
	set_security_level(SEC_LEVEL_BLUE)
	bot_log(bot, "put the station on blue alert: [bot_crimes_at_large()] major crimes at large")
	bot_say(bot.owner, ";Blue alert. All crew report anything suspicious to security.")
	return GOAL_STEP_SUCCESS

#undef BOT_ALERT_MAJOR_CRIMES
