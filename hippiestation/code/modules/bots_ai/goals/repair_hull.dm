// Holes in the hull (overnight 2026-11-07: action gaps). Engineers put smashed windows back (goals/repair_damage.dm), but a
// floor blown out to space - a meteor, a bomb, a saboteur's superboom - stayed open for the rest of the round, and the room
// round it with no air.
//
// The player's way: suited up if the air's gone, rods and a floor tile in the bag, stood on the floor beside the hole, a rod
// on the space tile for a lattice and a floor tile on the lattice for plating. Each one is noted as it happens (ChangeTurf
// to space, in the station's rooms, beside a floor), and whoever's free takes the nearest. The air comes back from the
// vents once it's shut.

GLOBAL_LIST_EMPTY(bot_hull_breaches)

/turf/ChangeTurf(path, list/new_baseturfs, flags)
	. = ..()
	// What it became, not what was asked for: a floor scraped away asks for /turf/baseturf_bottom, made space in there.
	if(length(GLOB.bot_brains) && istype(., /turf/open/space))
		bot_note_breach(.)

/// A tile of the station that's just become space, with floor beside it: a hole in the hull.
/proc/bot_note_breach(turf/T)
	if(!istype(T, /turf/open/space) || istype(T, /turf/open/space/transit))
		return
	var/area/A = get_area(T)
	if(!A || istype(A, /area/space) || istype(A, /area/shuttle) || istype(A, /area/solar) || istype(A, /area/science/test_area))
		return //out in space by design, or the toxins range: blown up on purpose
	if(!bot_hull_standing_spot(T))
		return
	GLOB.bot_hull_breaches |= T

/// Floor beside the hole to work from: open, not space, not blocked.
/proc/bot_hull_standing_spot(turf/T)
	for(var/dir in GLOB.cardinals)
		var/turf/open/floor/F = get_step(T, dir)
		if(istype(F) && !is_blocked_turf(F, TRUE))
			return F
	return null

/datum/bot_brain
	var/hull_patched = 0
	/// Breach -> when it's worth another look.
	var/list/breaches_blocked

/// The nearest hole this bot can get to and nobody else is seeing to.
/datum/bot_brain/proc/pick_breach()
	var/list/holes = list() //hole -> how far off
	for(var/turf/T as anything in GLOB.bot_hull_breaches.Copy())
		if(!istype(T, /turf/open/space))
			GLOB.bot_hull_breaches -= T //patched
			continue
		if(T.z != owner.z || LAZYACCESS(breaches_blocked, T) > world.time || (gym_run && get_area(T) != get_area(owner)))
			continue
		if(taken_by_another(T) || get_dist(owner, T) > 80)
			continue
		holes[T] = get_dist(owner, T)
	var/tries = 0
	while(length(holes) && tries++ < 3)
		var/turf/nearest
		for(var/turf/T as anything in holes)
			if(!nearest || holes[T] < holes[nearest])
				nearest = T
		holes -= nearest
		var/turf/spot = bot_hull_standing_spot(nearest)
		if(spot)
			return nearest
		LAZYSET(breaches_blocked, nearest, world.time + 5 MINUTES)
	return null

/datum/bot_duty/patch_hull
	name = "patching the hull"
	jobs = list("Station Engineer", "Chief Engineer", "Atmospheric Technician")
	interval_min = 300
	interval_max = 900

/datum/bot_duty/patch_hull/try_start(datum/bot_brain/bot)
	if(!length(GLOB.bot_hull_breaches))
		return FALSE
	var/turf/hole = bot.pick_breach()
	return hole ? bot.assign_goal(new /datum/bot_goal/patch_hull(hole)) : FALSE

/datum/bot_goal/patch_hull
	lawful = TRUE
	exclusive = TRUE
	braves_bad_air = TRUE //the room round a hole has usually lost its air: it suits up first (ensure_suit_for_hull)
	doing = "patching a hole in the hull"
	var/turf/standing_spot

/datum/bot_goal/patch_hull/New(turf/hole)
	. = ..()
	target = hole

/datum/bot_goal/patch_hull/resolve_target(datum/bot_brain/bot)
	if(!istype(target, /turf/open/space))
		target = null
		return
	standing_spot = bot_hull_standing_spot(target)
	if(!standing_spot)
		target = null

/datum/bot_goal/patch_hull/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/patch_hull/S = new
	var/datum/bot_step/move_to/to_spot = new
	to_spot.step_target = standing_spot
	S.steps = list(new /datum/bot_step/ensure_suit_for_hull(), new /datum/bot_step/get_hull_materials(), to_spot, new /datum/bot_step/paced/patch_hull())
	return list(S)

/datum/bot_goal/patch_hull/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.breaches_blocked, target, world.time + 5 MINUTES)

/datum/bot_goal/patch_hull/on_success(datum/bot_brain/bot)
	GLOB.bot_hull_breaches -= target
	bot.hull_patched++
	bot_tally("hull breaches patched")
	bot_log(bot, "patched the hull at [bot_coord(target)]")

/datum/bot_strategy/patch_hull/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// Into a suit first if the air by the hole has gone, as for any work in vacuum (goals/gear_up_eva.dm). One try.
/datum/bot_step/ensure_suit_for_hull
	var/tried = FALSE

/datum/bot_step/ensure_suit_for_hull/execute(datum/bot_brain/bot)
	var/datum/bot_goal/patch_hull/G = bot.current_goal
	if(bot.is_eva_ready() || (istype(G) && G.standing_spot && bot.turf_air_is_breathable(G.standing_spot)))
		return GOAL_STEP_SUCCESS
	if(tried)
		bot_log(bot, "no suit to be had for the hole at [bot_coord(G?.target)] - leaving it")
		return GOAL_STEP_FAIL
	tried = TRUE
	return bot.suspend_goal_for(new /datum/bot_goal/gear_up_for_eva()) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// A rod and a floor tile (or more). As an engineer does: made from metal sheets with the sheet's own menu, a couple of
/// sheets fetched if it has none; ready-made rods and tiles only if there's no metal to be had. Ready-made ones are rare
/// on a station: looking only for those, 109 of 133 tries in two meteor shifts found none and gave up.
/datum/bot_step/get_hull_materials
	var/tried_metal = FALSE
	var/tried_rods = FALSE
	var/tried_tiles = FALSE

/datum/bot_step/get_hull_materials/execute(datum/bot_brain/bot)
	var/turf/T = bot.current_goal?.target
	var/need_rods = !(locate(/obj/structure/lattice) in T) && !bot.carried_stack(/obj/item/stack/rods, 1)
	if(need_rods && bot.carried_stack(/obj/item/stack/sheet/metal, 1))
		need_rods = !bot.make_from_metal(/obj/item/stack/rods)
	var/need_tiles = !bot.carried_stack(/obj/item/stack/tile/plasteel, 1)
	if(need_tiles && bot.carried_stack(/obj/item/stack/sheet/metal, 1))
		need_tiles = !bot.make_from_metal(/obj/item/stack/tile/plasteel)
	if(!need_rods && !need_tiles)
		return GOAL_STEP_SUCCESS
	// Nothing found for one is no reason not to look for the next.
	if(!tried_metal)
		tried_metal = TRUE
		if(fetch(bot, /obj/item/stack/sheet/metal))
			return GOAL_STEP_PENDING
	if(need_rods && !tried_rods)
		tried_rods = TRUE
		if(fetch(bot, /obj/item/stack/rods))
			return GOAL_STEP_PENDING
	if(need_tiles && !tried_tiles)
		tried_tiles = TRUE
		if(fetch(bot, /obj/item/stack/tile/plasteel))
			return GOAL_STEP_PENDING
	bot_log(bot, "nothing to patch the hull with: no metal, rods or floor tiles to be had")
	return GOAL_STEP_FAIL

/// One lot of `result_type` (rods, floor tiles) from a metal sheet in hand, through the stack's own menu (stack/Topic
/// "make"), and picked up off the floor where it lands.
/datum/bot_brain/proc/make_from_metal(result_type)
	var/obj/item/stack/sheet/metal/M = carried_stack(/obj/item/stack/sheet/metal, 1)
	if(!M || !ready_in_hand(M))
		return FALSE
	var/index = 0
	for(var/i in 1 to length(M.recipes))
		var/datum/stack_recipe/R = M.recipes[i]
		if(istype(R) && R.result_type == result_type)
			index = i
			break
	if(!index)
		return FALSE
	human_pause(M)
	if(QDELETED(M) || owner.get_active_held_item() != M)
		return FALSE
	usr = owner //the menu goes by whoever clicked it
	M.Topic(null, list("make" = "[index]", "multiplier" = "1"))
	var/obj/item/stack/made = locate(result_type) in owner.drop_location()
	if(made && owner.put_in_hands(made))
		put_away(made, allow_equip = FALSE) //in the bag: the other hand's wanted for the next lot
	if(!carried_stack(result_type, 1))
		return FALSE
	var/atom/what = result_type
	bot_log(src, "made [initial(what.name)] from a metal sheet")
	return TRUE

/datum/bot_step/get_hull_materials/proc/fetch(datum/bot_brain/bot, stack_type)
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = stack_type
	get.lawful = TRUE
	get.doing = "getting what it takes to patch the hull"
	return bot.suspend_goal_for(get)

/// From beside it: a rod for the lattice, then a tile on the lattice.
/datum/bot_step/paced/patch_hull
	max_clicks = 6

/datum/bot_step/paced/patch_hull/do_click(datum/bot_brain/bot)
	var/turf/T = bot.current_goal?.target
	var/mob/living/carbon/human/H = bot.owner
	if(!istype(T, /turf/open/space) || H.incapacitated() || !H.Adjacent(T))
		return FALSE
	H.face_atom(T)
	if(!(locate(/obj/structure/lattice) in T))
		var/obj/item/stack/rods/rods = bot.carried_stack(/obj/item/stack/rods, 1)
		if(!rods || !bot.ready_in_hand(rods))
			return FALSE
		bot.use_tool_on(rods, T) //space/attackby(): a lattice
		wait_for = 8
		return TRUE
	var/obj/item/stack/tile/plasteel/tile = bot.carried_stack(/obj/item/stack/tile/plasteel, 1)
	if(!tile || !bot.ready_in_hand(tile))
		return FALSE
	bot.use_tool_on(tile, T) //on the lattice: plating
	wait_for = 8
	return TRUE

/datum/bot_step/paced/patch_hull/finish(datum/bot_brain/bot)
	var/turf/T = bot.current_goal?.target
	return (T && !istype(T, /turf/open/space)) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
