// Doors a bot's ID doesn't open, and what a person does about them instead of forcing them.
//
// A department's front doors want the department's access from both sides, so a visitor who was let in (or
// walked in behind somebody) can't simply walk back out. The way out is the exit button on the wall by the
// doors - an /obj/machinery/button/door carrying the doors' id - which anybody may press. A bot that had gone
// into Medbay to get patched up used to stand at the foyer doors until the shift ended, and was left behind
// when the station was evacuated.
//
//  - the route planner counts such a door as one the bot can get through, when the button is on the bot's side
//    of it (the airlock CanAStarPass() below);
//  - when the bot gets to the door it goes and presses the button rather than trying the door (clear_one_blocker(),
//    bot_items.dm): on the spot if the button is within reach, as a short errand of its own if it's a few steps off.
//
// Only plain open/close buttons for airlocks. Blast doors and shutters are left alone - too many of those hold
// something back (a burn chamber, a slime pen, the engine).

/// Door id -> the wall buttons that work the doors with that id.
GLOBAL_LIST(bot_door_button_cache)
GLOBAL_VAR_INIT(bot_door_button_cache_size, -1)

/proc/bot_buttons_for_door_id(id)
	var/list/buttons = bot_instances_of(/obj/machinery/button/door)
	if(!GLOB.bot_door_button_cache || GLOB.bot_door_button_cache_size != length(buttons))
		var/list/cache = list()
		for(var/obj/machinery/button/door/B as anything in buttons)
			if(QDELETED(B) || !B.id)
				continue
			if(!cache["[B.id]"])
				cache["[B.id]"] = list()
			cache["[B.id]"] += B
		GLOB.bot_door_button_cache = cache
		GLOB.bot_door_button_cache_size = length(buttons)
	return GLOB.bot_door_button_cache["[id]"]

/datum/bot_brain
	/// Door -> how many times this bot has pressed a button for it without it opening.
	var/list/door_button_presses
	/// When it last pressed one.
	var/door_button_pressed_at = 0
	/// The id on the button it pressed, which is the id of every door that button works.
	var/door_button_id
	/// Button -> when it's worth trying to reach it again.
	var/list/door_buttons_out_of_reach
	/// Door -> when this bot first found it busy (somebody else working it), for giving it a moment.
	var/list/busy_doors

/// Whether a shut door would open for this bot's ID, nothing else being in the way.
/datum/bot_brain/proc/door_opens_for_me(obj/machinery/door/D)
	if(D.locked || D.welded || !D.hasPower())
		return FALSE
	return !D.requiresID() || D.allowed(owner)

/// Whether there's a way to A (or to stand beside it) that keeps to doors this bot's ID opens: no hacking, no
/// breaking in, no climbing over the counter.
/datum/bot_brain/proc/can_walk_lawfully_to(atom/A)
	var/turf/T = get_turf(A)
	if(!T || QDELETED(owner))
		return FALSE
	if(get_turf(owner) == T || owner.Adjacent(A))
		return TRUE
	var/obj/item/card/id/id_card = route_card()
	begin_reach_scope()
	. = FALSE
	pathing_no_tailgating = !is_shut_in()
	for(var/turf/D in (list(T) + adjacent_turf_candidates(T)))
		if(length(bot_path_to(D, /turf/proc/Distance_cardinal, /turf/proc/bot_reachable_strict, id_card, !can_path_through_space())))
			. = TRUE
			break
	pathing_no_tailgating = FALSE
	end_reach_scope()

/// Fewer tiles than this to walk to by doors its own ID opens, and the bot is shut in somewhere.
#define BOT_SHUT_IN_TILES 60
/// The look it takes once a minute goes this far for a way back out to a hallway. The Brig and Atmospherics are a lot bigger than
/// 60 tiles: a prisoner let out of a cell, or a visitor when the door's locked behind them, was shut in with room to walk about and
/// never said a word, right up until the shuttle left without them.
#define BOT_SHUT_IN_WIDE_TILES 1500

/datum/bot_brain
	/// Set while a route is planned for a stroll or an everyday errand by a bot that's free to come and go: an
	/// airlock its ID doesn't open counts as shut, even stood open (the airlock CanAStarPass() below). A door
	/// somebody else has just walked through shuts again behind whoever follows them in - a clown, a doctor and
	/// two assistants each spent the rest of a shift in a room they'd strolled into that way, and missed the
	/// evacuation shuttle.
	var/pathing_no_tailgating = FALSE
	var/shut_in_checked_at = -1000
	var/shut_in_result = FALSE
	/// The tiles it can still get to, when it's shut in (turf -> TRUE).
	var/list/shut_in_region
	/// Set while is_shut_in() is measuring: nothing counts as a way out that isn't one already.
	var/measuring_shut_in = FALSE
	/// Until when the last wide look stands, for the quick ones in between.
	var/shut_in_wide_until = 0
	/// Set for a route planned by a bot with an emag on business that calls for one: what's shut is only shut until it gets there.
	var/pathing_emag = FALSE

/// Whether the bot is somewhere it can't walk out of by doors its own ID opens: only a few dozen tiles to go to.
/// Then any door that happens to be open is the way out, whoever it belongs to.
/datum/bot_brain/proc/is_shut_in(wide = FALSE)
	if(!wide && (world.time < shut_in_checked_at + 30 || world.time < shut_in_wide_until))
		return shut_in_result
	shut_in_checked_at = world.time
	shut_in_result = FALSE
	var/turf/start = get_turf(owner)
	if(!start)
		return FALSE
	var/obj/item/card/id/id_card = route_card()
	var/simulated_only = !can_path_through_space()
	var/was = pathing_no_tailgating
	pathing_no_tailgating = TRUE
	measuring_shut_in = TRUE
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/at = 1
	var/roomy = FALSE
	var/limit = wide ? BOT_SHUT_IN_WIDE_TILES : BOT_SHUT_IN_TILES
	var/area/last_area = start.loc
	if(wide && (istype(last_area, /area/hallway) || istype(last_area, /area/maintenance)))
		roomy = TRUE
	while(at <= length(queue) && !roomy)
		var/turf/T = queue[at++]
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(T, d)
			if(!next || seen[next] || !T.bot_reachable_strict(owner, next, id_card, simulated_only))
				continue
			seen[next] = TRUE
			queue += next
			if(length(queue) >= limit)
				roomy = TRUE
				break
			if(wide && next.loc != last_area)
				last_area = next.loc
				if(istype(last_area, /area/hallway)) //not maintenance: there's a closet of it off the Brig that goes nowhere
					roomy = TRUE
					break
	pathing_no_tailgating = was
	measuring_shut_in = FALSE
	shut_in_result = !roomy
	shut_in_region = roomy ? null : seen
	shut_in_wide_until = (wide && !roomy) ? world.time + 70 SECONDS : 0
	return shut_in_result

/// For a bot that's shut in behind a blast door or a shutter: the button for it, if that's in with the bot and the
/// bot may press it. Not for anybody at large - too many of those doors are holding something back.
/datum/bot_brain/proc/shutter_button_in_reach(obj/machinery/door/poddoor/P)
	if(!shut_in_result || !shut_in_region || !P.id || LAZYACCESS(door_button_presses, P) >= 4)
		return null
	for(var/obj/machinery/button/door/B as anything in bot_buttons_for_door_id(P.id))
		if(QDELETED(B) || B.z != P.z || B.normaldoorcontrol || B.panel_open || (B.stat & (NOPOWER|BROKEN)))
			continue
		var/turf/at = get_turf(B)
		var/within = shut_in_region[at]
		if(!within)
			for(var/turf/beside as anything in get_adjacent_open_turfs(at))
				if(shut_in_region[beside])
					within = TRUE
					break
		if(within && B.allowed(owner))
			return B
	return null

/// A shut blast door counts as a way through for a bot shut in behind it with the button (see above).
/obj/machinery/door
	astar_always_asks = TRUE //open, it can still be one the bot won't tailgate through

/obj/machinery/door/poddoor/CanAStarPass(ID, to_dir, caller)
	. = ..()
	if(.)
		return
	var/mob/living/carbon/human/H = caller
	if(!istype(H) || !H.bot_brain || H.bot_brain.measuring_shut_in || !H.bot_brain.shut_in_result)
		return
	return H.bot_brain.shutter_button_in_reach(src) ? TRUE : FALSE

#undef BOT_SHUT_IN_TILES

/// "[REF(button)]|[side of its door]" -> when to try it from that side again. A button somebody couldn't get to from one side of
/// its door is the map's: Medbay's on MetaStation is behind the reception desk, and each of 40 bots had to fail at it in person,
/// up to three times a shift - 107 give-ups in one 30 minute shift, every one a bot stood at the doors not getting in.
GLOBAL_LIST_EMPTY(bot_door_buttons_out_of_reach)

/// Which side of a door `from` is on, as one of the four directions.
/proc/bot_door_side(turf/doorway, turf/from)
	var/dx = from.x - doorway.x
	var/dy = from.y - doorway.y
	if(abs(dx) >= abs(dy))
		return dx >= 0 ? EAST : WEST
	return dy >= 0 ? NORTH : SOUTH

/// The wall button this bot could open `door` with, coming at it from `from`: one that works that door, that this
/// bot may press, on the same side of the door as `from` and no more than a few steps away.
/datum/bot_brain/proc/door_button_for(obj/machinery/door/airlock/door, turf/from)
	if(!door.id_tag || !from)
		return null
	if(LAZYACCESS(door_button_presses, door) >= 4)
		return null //pressed it and pressed it: it isn't going to
	var/turf/doorway = get_turf(door)
	var/turf/beyond = get_step(doorway, get_dir(from, doorway))
	if(!doorway || !beyond)
		return null
	for(var/obj/machinery/button/door/B as anything in bot_buttons_for_door_id(door.id_tag))
		if(QDELETED(B) || B.z != doorway.z || !B.normaldoorcontrol || B.specialfunctions != OPEN || B.panel_open || (B.stat & (NOPOWER|BROKEN)))
			continue
		if(LAZYACCESS(door_buttons_out_of_reach, B) > world.time || GLOB.bot_door_buttons_out_of_reach["[REF(B)]|[bot_door_side(doorway, from)]"] > world.time)
			continue
		var/near = (B.x - from.x) ** 2 + (B.y - from.y) ** 2
		if(near > 36 || near >= (B.x - beyond.x) ** 2 + (B.y - beyond.y) ** 2)
			continue //the other side of the door, or too far off to be this door's
		if(!B.allowed(owner))
			continue
		return B
	return null

/// A shut airlock this bot's ID doesn't open counts as a way through all the same when there's a button for it on
/// the side the bot is coming from. `to_dir` is the way back from the door towards whoever is asking.
/obj/machinery/door/airlock/CanAStarPass(obj/item/card/id/ID, to_dir, caller)
	. = ..()
	var/mob/living/carbon/human/H = caller
	if(!istype(H) || !H.bot_brain)
		return
	if(H.bot_brain.pathing_emag && !H.bot_brain.measuring_shut_in)
		return . || (!welded && hasPower() && !(obj_flags & EMAGGED) && (!istype(src, /obj/machinery/door/airlock/external) || H.bot_brain.op_team)) //it stays open: not onto space, unless it's an operative in a hardsuit coming in from it
	if(.)
		// Stood open, and not one this bot's ID opens: no following somebody in (pathing_no_tailgating). The doors it
		// has just opened itself are another matter - that's what the button was for. This was missing, so nobody
		// without Medbay access could walk through the Medbay doors they'd opened with the exit button: 1 try in 9 got out.
		if(!density && H.bot_brain.pathing_no_tailgating && !emergency && !unres_sides && requiresID() && !check_access(ID) && !H.bot_brain.pressed_button_for(src))
			return FALSE
		return
	if(!id_tag || locked || welded || !to_dir || !hasPower())
		return
	return H.bot_brain.door_button_for(src, get_step(src, to_dir)) ? TRUE : FALSE

/// The card it'll swipe at a door, if it's out on business that calls for one.
/datum/bot_brain/proc/emag_for_doors()
	return current_goal?.breaks_in ? find_carried_tool(/obj/item/card/emag) : null

/// At a door that doesn't open for it. TRUE if the card's gone through it: the door breaks, opens, and stays that way.
/datum/bot_brain/proc/swipe_door(obj/machinery/door/airlock/A)
	var/obj/item/card/emag/E = emag_for_doors()
	if(!E || !istype(A) || A.welded || !A.hasPower() || (A.obj_flags & EMAGGED) || (istype(A, /obj/machinery/door/airlock/external) && !op_team))
		return FALSE
	bot_log(src, "[A] doesn't open for me - swiping [E] at it")
	use_item_on(E, A)
	put_away(E)
	return TRUE

/// Whether this bot has just pressed the button that works this door.
/datum/bot_brain/proc/pressed_button_for(obj/machinery/door/airlock/door)
	return door_button_id && door.id_tag == door_button_id && world.time < door_button_pressed_at + 10 SECONDS

/// Presses a door's button, the one click.
/datum/bot_brain/proc/press_door_button(obj/machinery/button/door/B)
	door_button_id = B.id
	door_button_pressed_at = world.time
	use_atom(B)
	door_button_pressed_at = world.time

/// Nobody going about their day opens an external door onto a vacuum with no suit on. A bot's ID opens most of them, and
/// assistants on a stroll went straight out onto the platforms outside the hull, on every map that has them.
/obj/machinery/door/airlock/external/CanAStarPass(obj/item/card/id/ID, to_dir, caller)
	. = ..()
	var/mob/living/carbon/human/H = caller
	if(!. || !to_dir || !istype(H) || !H.bot_brain?.pathing_no_tailgating)
		return
	var/turf/far_side = get_step(src, turn(to_dir, 180))
	if((is_mining_level(z) || bot_aboard_mining_shuttle(H)) && H.bot_brain.ready_for_lavaland())
		return //no vacuum outside this one, just thin air and a mask and a tank do for that (goals/mining.dm), or it's the way off the shuttle
	if(!H.bot_brain.turf_air_is_breathable(far_side) && !H.bot_brain.is_space_protected_without_boots())
		return FALSE

/// At a door that wants the button pressed. TRUE if that's in hand (pressed, or on the way to it).
/datum/bot_brain/proc/press_button_for_door(obj/machinery/button/door/B, obj/machinery/door/D)
	LAZYINITLIST(door_button_presses)
	if(owner.Adjacent(B))
		door_button_presses[D]++
		bot_log(src, "[D] isn't one my ID opens - pressing [B]")
		press_door_button(B)
		return TRUE
	if(istype(current_goal, /datum/bot_goal/press_door_button) || istype(suspended_goal, /datum/bot_goal/press_door_button))
		return FALSE //already on exactly that errand, and it isn't working
	bot_log(src, "[D] isn't one my ID opens - going over to [B]")
	return suspend_goal_for(new /datum/bot_goal/press_door_button(B, D))

/// Walks over to a door's button, presses it, and goes through.
/datum/bot_goal/press_door_button
	lawful = TRUE
	doing = "letting myself through a door"
	var/obj/machinery/door/door
	var/turf/far_side
	/// Which side of the door the bot set out from
	var/side

/datum/bot_goal/press_door_button/New(obj/machinery/button/door/B, obj/machinery/door/D)
	. = ..()
	target = B
	door = D

/datum/bot_goal/press_door_button/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || QDELETED(door))
		target = null
		return
	var/turf/doorway = get_turf(door)
	far_side = get_step(doorway, get_dir(get_turf(bot.owner), doorway))
	side = bot_door_side(doorway, get_turf(bot.owner))

/// A button the bot couldn't get to: on the other side of a counter, as Medbay's is on some maps, where it's for the
/// officer on the desk. Not one to plan a route by for a while.
/datum/bot_goal/press_door_button/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.door_buttons_out_of_reach, target, world.time + 10 MINUTES)
		if(side) // and everybody else's, from that side: the counter in the way isn't going anywhere
			GLOB.bot_door_buttons_out_of_reach["[REF(target)]|[side]"] = world.time + 15 MINUTES

/datum/bot_goal/press_door_button/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/press_door_button/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/press_door_button())
	if(isopenturf(far_side) && !far_side.density)
		var/datum/bot_step/move_to/through = new
		through.step_target = far_side
		S.steps += through
	return list(S)

/datum/bot_strategy/press_door_button/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/paced/press_door_button
	max_clicks = 3

/datum/bot_step/paced/press_door_button/start(datum/bot_brain/bot)
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/press_door_button/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/press_door_button/G = bot.current_goal
	var/obj/machinery/button/door/B = G?.target
	if(!istype(G) || QDELETED(B) || QDELETED(G.door) || !bot.owner.Adjacent(B))
		return FALSE
	if(!G.door.density || G.door.operating)
		return FALSE //open, or opening
	LAZYINITLIST(bot.door_button_presses)
	bot.door_button_presses[G.door]++
	bot.press_door_button(B)
	wait_for = 12 //the button takes a second to come back up, and the door a moment to move
	clicks++
	return TRUE

/datum/bot_step/paced/press_door_button/finish(datum/bot_brain/bot)
	var/datum/bot_goal/press_door_button/G = bot.current_goal
	if(!istype(G) || QDELETED(G.door))
		return GOAL_STEP_FAIL
	if(G.door.density && !G.door.operating)
		return GOAL_STEP_FAIL
	LAZYREMOVE(bot.door_button_presses, G.door)
	return GOAL_STEP_SUCCESS
