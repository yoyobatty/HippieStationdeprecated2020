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
