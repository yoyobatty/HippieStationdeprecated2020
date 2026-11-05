// A prisoner who's down (in crit, or out cold) or pale from losing blood (examine says "pale skin" under BLOOD_VOLUME_SAFE) goes to
// Medbay, not to a cell, and one an officer sees collapsed in a cell is let out and taken there. A cell is where nobody comes: the
// doctors walk by the doors their ID opens, and neither the Brig's nor a cell's are among them. Prisoners brought in short of blood
// after a fight collapsed in their cells and died there of it, with 11 brute on one of them: 5 of the 18 crit deaths (suffocation
// 80 or more, in good air) in three batches of six shifts were in the Brig. In cuffs in Medbay's lobby, a doctor gets to them.

/datum/bot_brain
	/// Bot Gym: where Medbay is in the arena (the station's is on another level)
	var/turf/gym_medbay_spot

/// Down, or pale from losing blood: wants a doctor, not a cell
/proc/bot_prisoner_needs_medbay(mob/living/carbon/human/H)
	if(!istype(H) || H.stat == DEAD)
		return FALSE
	if(H.health <= 0 || H.stat == UNCONSCIOUS)
		return TRUE
	return H.blood_volume < BLOOD_VOLUME_SAFE && !(NOBLOOD in H.dna?.species?.species_traits)

/proc/bot_in_medbay(atom/A)
	return istype(get_area(A), /area/medical)

/// A bit of floor in Medbay's lobby, or failing that its central room, to leave somebody for a doctor: by doors this bot's ID opens.
/// The nearest first: none of the maps here has a lobby area, and the near side of Medbay Central is where its public entrance is,
/// where the far side is behind doors only Medical opens (picked at random, three tries out of four found no way there).
/datum/bot_brain/proc/medbay_drop_spot()
	if(gym_medbay_spot)
		return gym_medbay_spot
	for(var/area_type in list(/area/medical/medbay/lobby, /area/medical/medbay/central))
		var/area/A = GLOB.areas_by_type[area_type]
		if(!A)
			continue
		var/list/spots = list()
		for(var/turf/open/floor/T in A)
			if(T.z == owner.z && !is_blocked_turf(T, TRUE) && !(locate(/obj/machinery/door) in T))
				spots[T] = get_dist(owner, T)
		for(var/tries in 1 to 4)
			var/turf/nearest
			for(var/turf/T as anything in spots)
				if(!nearest || spots[T] < spots[nearest])
					nearest = T
			if(!nearest)
				break
			spots -= nearest
			if(can_walk_lawfully_to(nearest)) //bot_doors.dm
				return nearest
	return null

/// Off to Medbay with a prisoner who needs a doctor (out of the cell they're in, if they're in one). FALSE if there's no way there.
/datum/bot_brain/proc/start_medevac(mob/living/carbon/human/P, obj/machinery/door_timer/T)
	if(bot_in_medbay(P))
		LAZYSET(failed_brig_targets, P, world.time + 3 MINUTES) //there already: the doctors' turn
		return FALSE
	var/datum/bot_goal/brig_prisoner/medevac/G = new(P, T)
	if(assign_goal(G))
		bot_log(src, "[P] needs a doctor, not a cell - taking them to Medbay")
		return TRUE
	return FALSE

// A kind of escort to the brig, so everything that leaves an escort be (an arrest of the same prisoner seen again, a call, a
// witness) leaves this one be too: as its own goal, an officer seeing its own cuffed prisoner again dropped it and started over, 59
// times in one batch. cell_timer is the cell they're in, if they're in one.
/datum/bot_goal/brig_prisoner/medevac
	doing = "taking a prisoner to Medbay"
	var/turf/drop_spot

/datum/bot_goal/brig_prisoner/medevac/New(mob/living/carbon/human/P, obj/machinery/door_timer/T)
	. = ..()
	target = P
	prisoner = P
	cell_timer = T

/datum/bot_goal/brig_prisoner/medevac/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = target
	if(QDELETED(P) || P.stat == DEAD)
		target = null
		return
	drop_spot = bot.medbay_drop_spot()
	if(!drop_spot)
		bot_log(bot, "no way to Medbay by doors I can open for [P]")
		target = null

/datum/bot_goal/brig_prisoner/medevac/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/medevac/S = new
	var/datum/bot_step/move_to/to_medbay = new
	to_medbay.step_target = drop_spot
	S.steps = list()
	if(cell_timer && !QDELETED(cell_timer) && cell_timer.timing)
		var/datum/bot_step/move_to/to_timer = new
		to_timer.step_target = cell_timer
		S.steps += list(to_timer, new /datum/bot_step/open_cell_for_medic(src))
	S.steps += list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_patient(), to_medbay, new /datum/bot_step/leave_at_medbay(src))
	return list(S)

/datum/bot_goal/brig_prisoner/medevac/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	if(target)
		LAZYSET(bot.failed_brig_targets, target, world.time + 1 MINUTES)

/datum/bot_strategy/medevac/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// The cell's timer stopped, so the door opens: as door_timer's "stop" does it (brigdoors.dm)
/datum/bot_step/open_cell_for_medic
	var/datum/bot_goal/brig_prisoner/medevac/goal

/datum/bot_step/open_cell_for_medic/New(datum/bot_goal/brig_prisoner/medevac/G)
	. = ..()
	goal = G

/datum/bot_step/open_cell_for_medic/execute(datum/bot_brain/bot)
	var/obj/machinery/door_timer/T = goal.cell_timer
	if(!istype(T) || QDELETED(T) || !bot.owner.Adjacent(T))
		return GOAL_STEP_FAIL
	if(!T.timing)
		return GOAL_STEP_SUCCESS
	bot.human_pause(T)
	if(QDELETED(T) || !bot.owner.Adjacent(T) || !T.allowed(bot.owner))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(T)
	bot.telemetry_ui_action(T, "stop")
	T.timer_end(forced = TRUE)
	GLOB.bot_brig_sentences -= T
	bot_log(bot, "opened [T] - [goal.target] is down in there")
	return GOAL_STEP_SUCCESS

/datum/bot_step/leave_at_medbay
	var/datum/bot_goal/brig_prisoner/medevac/goal

/datum/bot_step/leave_at_medbay/New(datum/bot_goal/brig_prisoner/medevac/G)
	. = ..()
	goal = G

/datum/bot_step/leave_at_medbay/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.target
	bot.owner.stop_pulling()
	if(!istype(P) || QDELETED(P))
		return GOAL_STEP_FAIL
	LAZYSET(bot.failed_brig_targets, P, world.time + 3 MINUTES) //the cell once they're seen to
	bot_log(bot, "left [P] in [get_area_name(P, TRUE)] for a doctor")
	bot_tally("prisoners taken to Medbay")
	bot_say(bot.owner, ":m [P.name] is [P.stat == CONSCIOUS ? "white as a sheet" : "down"][P.handcuffed ? " and in cuffs" : ""] - I've brought them to [get_area_name(P, TRUE)]. They need a doctor.")
	return GOAL_STEP_SUCCESS

/// Somebody down in a cell, seen: let out and taken to Medbay
/datum/bot_duty/prisoner_down
	name = "seeing to a prisoner who's collapsed"
	jobs = list("Security Officer", "Warden", "Head of Security")
	tier = BOT_DUTY_URGENT
	priority = 60
	interval_min = 50
	interval_max = 100

/datum/bot_duty/prisoner_down/try_start(datum/bot_brain/bot)
	if(bot.state != BOT_STATE_WANDER)
		return FALSE
	for(var/obj/machinery/door_timer/T in GLOB.bot_brig_sentences)
		if(QDELETED(T) || !T.timing || T.z != bot.owner.z)
			continue
		var/datum/weakref/ref = GLOB.bot_brig_sentences[T]
		var/mob/living/carbon/human/P = ref?.resolve()
		if(!P || P.stat == DEAD || (P.stat == CONSCIOUS && P.health > 0))
			continue
		if(!(P in view(7, bot.owner)) || bot.taken_by_another(P))
			continue
		if(bot.start_medevac(P, T))
			bot_say(bot.owner, ":s [P.name]'s collapsed in [T.name] - getting them to Medbay.")
			return TRUE
	return FALSE
