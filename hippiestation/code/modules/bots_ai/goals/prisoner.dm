// In a cell: what a person does with the time. Bots used to carry on with their rounds from behind the glass, every errand
// failing at the door, and paced the cell for the whole sentence. A person sits it out: a word now and then, how long's left.
//
// The user's ruling: traitors and hotheads try the cell when nobody's watching. Out of hiding with a tool (the butt's where people
// keep what they don't want found, and a lazy officer doesn't look there), at the window with it, and gone. Security sees the
// smashing like anybody's (bot_witness.dm) and goes after them again.

/datum/bot_brain
	var/next_cell_word = 0
	var/next_escape_try = 0

/// The timer of the cell it's locked in, if it is.
/datum/bot_brain/proc/my_cell_timer()
	var/turf/here = get_turf(owner)
	for(var/obj/machinery/door_timer/T as anything in bot_instances_of(/obj/machinery/door_timer))
		if(T.timing && T.z == here?.z && (here in bot_get_cell_interior(T)))
			return T
	return null

/// The sort that tries the cell: a traitor, a hothead, a bold one who doesn't play it straight.
/datum/bot_brain/proc/escape_minded()
	return bot_traitor || temper >= 0.7 || (nerve >= 0.75 && playstyle != BOT_STYLE_NORMAL)

/// An officer who'd see it: on its feet, looking this way.
/proc/bot_officer_watching(mob/living/carbon/human/H)
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(!QDELETED(B.owner) && B.owner.stat == CONSCIOUS && B.owner.z == H.z && get_dist(B.owner, H) <= 7 && (H in view(7, B.owner)))
			return TRUE
	return FALSE

/// Something to go at the window with: in its hands, or out of where it hid it.
/datum/bot_brain/proc/escape_tool()
	for(var/obj/item/I in owner.held_items)
		if(I.force >= 5)
			return I
	var/obj/item/organ/butt/B = owner.getorgan(/obj/item/organ/butt)
	var/datum/component/storage/S = B?.GetComponent(/datum/component/storage)
	if(!S)
		return null
	for(var/obj/item/I in S.contents())
		if(I.force >= 5 && S.remove_from_storage(I, get_turf(owner)))
			owner.put_in_hands(I)
			bot_log(src, "got [I] out from where it was hidden")
			return I
	return null

/// A window of the cell's, to break out through: one from the inside, and not the door.
/proc/bot_cell_window(obj/machinery/door_timer/T)
	for(var/turf/inside as anything in bot_get_cell_interior(T))
		for(var/direction in GLOB.cardinals)
			var/turf/next = get_step(inside, direction)
			for(var/obj/structure/window/W in next)
				if(!QDELETED(W) && W.fulltile)
					return W
	return null

/// Locked in: TRUE, it's doing its time (handle_wander(), bot_brain.dm).
/datum/bot_brain/proc/do_time()
	var/obj/machinery/door_timer/T = my_cell_timer()
	if(!T)
		return FALSE
	if(escape_minded() && world.time >= next_escape_try)
		next_escape_try = world.time + rand(90 SECONDS, 180 SECONDS)
		if(!bot_officer_watching(owner))
			var/obj/structure/window/W = bot_cell_window(T)
			var/obj/item/tool = W && escape_tool()
			if(tool && assign_goal(new /datum/bot_goal/break_out(W, tool)))
				bot_log(src, "trying [W] with [tool]")
				bot_tally("escape attempts")
				return TRUE
	if(world.time >= next_cell_word && prob(25))
		next_cell_word = world.time + rand(1 MINUTES, 3 MINUTES)
		var/minutes = max(1, round((T.timer_duration - (world.time - T.activation_time)) / (1 MINUTES)))
		bot_say(owner, mood_pick(list("[minutes] more minute\s. I can do this.", "Could be worse. At least it's quiet in here."), list("How long have I got? [minutes] minute\s?", "This is ridiculous.", "I want a lawyer.", "Anyone got a deck of cards?"), list("Let me out of here!", "This is shitcurity at its finest.", "I didn't do anything!", "You'll regret this.")))
	// Up and down the cell now and then, the way anybody does with time to kill: prisoners stood on one tile for minutes at a time.
	if(world.time >= next_cell_pace && !owner.buckled)
		next_cell_pace = world.time + rand(20 SECONDS, 50 SECONDS)
		var/area/cell = get_area(owner)
		var/list/room = list()
		for(var/turf/open/F in get_adjacent_open_turfs(owner))
			if(get_area(F) == cell && !is_blocked_turf(F, TRUE) && !(locate(/obj/machinery/door) in F) && !bot_turf_is_deadly(F))
				room += F
		if(length(room))
			step_to(owner, pick(room))
			return TRUE
	idle_fidget()
	return TRUE

/datum/bot_brain
	var/next_cell_pace = 0

/datum/bot_goal/break_out
	doing = "trying the cell window"
	var/obj/item/tool

/datum/bot_goal/break_out/New(obj/structure/window/W, obj/item/I)
	. = ..()
	target = W
	tool = I

/datum/bot_goal/break_out/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || QDELETED(tool))
		target = null

/datum/bot_goal/break_out/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/break_out/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/break_out())
	return list(S)

/datum/bot_strategy/break_out/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// At the window with it until it goes, or somebody's watching.
/datum/bot_step/paced/break_out
	max_clicks = 150
	/// Blows struck: a window that doesn't give (a shuttle's) is given up on.
	var/hits = 0

/datum/bot_step/paced/break_out/start(datum/bot_brain/bot)
	hits = 0
	return TRUE

/datum/bot_step/paced/break_out/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/break_out/G = bot.current_goal
	var/obj/structure/window/W = G?.target
	if(!istype(G) || QDELETED(W) || QDELETED(G.tool) || !bot.owner.Adjacent(W) || bot.owner.incapacitated() || ++hits > 120)
		return FALSE
	if(bot_officer_watching(bot.owner))
		bot_log(bot, "somebody's watching: left the window alone")
		return FALSE
	if(bot.owner.get_active_held_item() != G.tool && !bot.ready_in_hand(G.tool))
		return FALSE
	bot.owner.a_intent = INTENT_HARM
	bot.owner.face_atom(W)
	G.tool.melee_attack_chain(bot.owner, W)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	wait_for = CLICK_CD_MELEE
	return TRUE

/datum/bot_step/paced/break_out/finish(datum/bot_brain/bot)
	var/datum/bot_goal/break_out/G = bot.current_goal
	bot.owner.a_intent = INTENT_HELP
	if(istype(G) && QDELETED(G.target))
		bot_log(bot, "broke out of the cell")
		bot_tally("broke out")
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL
