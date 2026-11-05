// A prisoner who's down (in crit, or out cold) or pale from losing blood (examine says "pale skin" under BLOOD_VOLUME_SAFE) goes to
// Medbay, not to a cell, and one an officer sees collapsed in a cell is let out and taken there. A cell is where nobody comes: the
// doctors walk by the doors their ID opens, and neither the Brig's nor a cell's are among them. Prisoners brought in short of blood
// after a fight collapsed in their cells and died there of it, with 11 brute on one of them: 5 of the 18 crit deaths (suffocation
// 80 or more, in good air) in three batches of six shifts were in the Brig. In cuffs in Medbay's lobby, a doctor gets to them.

/datum/bot_brain
	/// Bot Gym: where Medbay is in the arena (the station's is on another level)
	var/turf/gym_medbay_spot
	/// Bot Gym: where a prisoner's kept in the Brig for a doctor, in the arena
	var/turf/gym_brig_spot
	/// Prisoners it's kept in the Brig for a doctor: who -> when
	var/list/brig_care_tried

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
	S.steps += list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_patient())
	S.steps += list(to_medbay, new /datum/bot_step/leave_at_medbay(src), new /datum/bot_step/paced/guard_in_medbay(src))
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
	var/brought = bot.owner.pulling == P
	bot.owner.stop_pulling()
	if(!istype(P) || QDELETED(P) || !brought || get_dist(bot.owner, P) > 1)
		return GOAL_STEP_FAIL //lost hold of them on the way
	bot_log(bot, "brought [P] to [get_area_name(P, TRUE)] for a doctor, and staying with them")
	bot_tally("prisoners taken to Medbay")
	bot_say(bot.owner, ":m [P.name] is [P.stat == CONSCIOUS ? "white as a sheet" : "down"][P.handcuffed ? " and in cuffs" : ""] - I've brought them to [get_area_name(P, TRUE)]. They need a doctor. I'll wait with them.")
	return GOAL_STEP_SUCCESS

/// With them in Medbay until they've been seen to, then back to the Brig. The user's ruling (2026-11-05), "Stay with them": the
/// Warden left the janitor, a traitor, cuffed in Medbay and went to eat, and the user, not knowing he was a prisoner, uncuffed him.
/datum/bot_step/paced/guard_in_medbay
	max_clicks = 20
	var/datum/bot_goal/brig_prisoner/medevac/goal
	var/until = 0
	var/seen_to = FALSE

/datum/bot_step/paced/guard_in_medbay/New(datum/bot_goal/brig_prisoner/medevac/G)
	. = ..()
	goal = G

/datum/bot_step/paced/guard_in_medbay/start(datum/bot_brain/bot)
	until = world.time + 4 MINUTES
	return TRUE

/datum/bot_step/paced/guard_in_medbay/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.target
	if(!istype(P) || QDELETED(P) || P.stat == DEAD || world.time > until)
		return FALSE
	if(!bot_prisoner_needs_medbay(P) && bot_bleed_rate(P) <= 0)
		seen_to = TRUE
		return FALSE
	if(get_dist(bot.owner, P) > 2)
		bot.pursue(P, "follow", force = TRUE)
	wait_for = 30
	return TRUE

/datum/bot_step/paced/guard_in_medbay/finish(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.target
	if(!istype(P) || QDELETED(P))
		return GOAL_STEP_SUCCESS
	if(seen_to && P.handcuffed)
		bot_log(bot, "[P]'s been seen to - back to the Brig with them")
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, start_brig_escort), P))
	else
		LAZYSET(bot.failed_brig_targets, P, world.time + 3 MINUTES) //the cell once they're seen to
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Kept in the Brig
// ---------------------------------------------------------------------------------------------

// The user's ruling, 2026-11-05: Security heals its own prisoners, and the dangerous ones never leave it. "Bringing more violent
// prisoners and suspected/real traitors outside of sec could be disastrous, especially if another traitor wishes to collab. Med
// should come to heal or just drop off supplies." One who needs a doctor is kept just inside Security's front door with the officer
// by them, patched where it can be, and Medical is called and let in there (bot_requests.dm answer_call, the door). Anybody else
// is still taken to Medbay, with the officer staying until they've been seen to.

/// Wanted for hurting people or for something major: the ones that don't leave Security
/proc/bot_prisoner_dangerous(mob/living/carbon/human/H)
	var/datum/bot_wanted/W = bot_get_wanted_entry(H)
	return W && (W.severity >= BOT_CRIME_MAJOR || bot_crime_is_violent(W.crime))

/// Just inside Security's front door, out of the doorway: where a doctor let in gets to them first
/datum/bot_brain/proc/brig_care_spot()
	if(gym_brig_spot)
		return gym_brig_spot
	var/obj/machinery/door/airlock/door = find_front_door("security")
	if(!door)
		return null
	for(var/direction in GLOB.cardinals)
		var/turf/T = get_step(door, direction)
		if(!isopenturf(T) || bot_department_of(get_area(T)) != "security" || is_blocked_turf(T, TRUE))
			continue
		var/turf/further = get_step(T, direction)
		if(isopenturf(further) && bot_department_of(get_area(further)) == "security" && !is_blocked_turf(further, TRUE))
			T = further
		if(can_walk_lawfully_to(T))
			return T
	return null

/datum/bot_brain/proc/start_brig_care(mob/living/carbon/human/P, obj/machinery/door_timer/T)
	var/datum/bot_goal/brig_prisoner/brig_care/G = new(P, T)
	if(assign_goal(G))
		LAZYSET(brig_care_tried, P, world.time)
		bot_log(src, "[P] needs a doctor and isn't leaving Security - keeping them by the front door for Medical")
		return TRUE
	return FALSE

/datum/bot_goal/brig_prisoner/brig_care
	doing = "keeping a hurt prisoner in the Brig for a doctor"
	var/turf/care_spot
	var/patched = 0

/datum/bot_goal/brig_prisoner/brig_care/New(mob/living/carbon/human/P, obj/machinery/door_timer/T)
	. = ..()
	target = P
	prisoner = P
	cell_timer = T

/datum/bot_goal/brig_prisoner/brig_care/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = target
	if(QDELETED(P) || P.stat == DEAD)
		target = null
		return
	care_spot = bot.brig_care_spot()
	if(!care_spot && bot_department_of(get_area(P)) == "security")
		care_spot = get_turf(P)
	if(!care_spot)
		bot_log(bot, "nowhere in Security to keep [P] for a doctor")
		target = null

/datum/bot_goal/brig_prisoner/brig_care/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/medevac/S = new
	var/datum/bot_step/move_to/to_spot = new
	to_spot.step_target = care_spot
	S.steps = list()
	if(cell_timer && !QDELETED(cell_timer) && cell_timer.timing) //collapsed in a cell: out of it first
		var/datum/bot_step/move_to/to_timer = new
		to_timer.step_target = cell_timer
		S.steps += list(to_timer, new /datum/bot_step/open_cell_for_medic(src))
	S.steps += list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_patient(), to_spot, new /datum/bot_step/paced/brig_care_wait(src))
	return list(S)

/datum/bot_goal/brig_prisoner/brig_care/on_success(datum/bot_brain/bot)
	..()
	if(!QDELETED(prisoner) && prisoner.stat != DEAD && prisoner.handcuffed)
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, start_brig_escort), prisoner)) //to the cell

/// Waiting with them for a doctor: Medical called once, what bleeds patched, until they've been seen to or it's been a while
/datum/bot_step/paced/brig_care_wait
	max_clicks = 12
	var/datum/bot_goal/brig_prisoner/brig_care/goal
	var/until = 0

/datum/bot_step/paced/brig_care_wait/New(datum/bot_goal/brig_prisoner/brig_care/G)
	. = ..()
	goal = G

/datum/bot_step/paced/brig_care_wait/start(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.target
	if(!istype(P) || QDELETED(P))
		return FALSE
	until = world.time + 4 MINUTES
	var/datum/bot_request_kind/medical/kind = locate() in GLOB.bot_request_kinds
	if(kind)
		var/datum/bot_request/R = bot_new_request(kind, P, FREQ_MEDICAL, get_turf(P)) //the prisoner's the patient, not the officer
		bot_offer_request(R)
	bot_say(bot.owner, ":m [P.name] is [P.stat == CONSCIOUS ? "white as a sheet" : "down"] in cuffs in [get_area_name(P, TRUE)], just inside the front door. Can a doctor come? I'll let you in.")
	bot_tally("prisoners kept in the Brig for a doctor")
	return TRUE

/datum/bot_step/paced/brig_care_wait/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.target
	if(!istype(P) || QDELETED(P) || P.stat == DEAD || world.time > until)
		return FALSE
	if(!bot_prisoner_needs_medbay(P) && bot_bleed_rate(P) <= 0)
		bot_log(bot, "[P]'s been seen to")
		return FALSE
	if(goal.patched < 8 && bot_bleed_rate(P) > 0 && bot.owner.Adjacent(P))
		bot.aim_at_worst_wound(P) //treat_patient.dm
		var/obj/item/I = bot.pick_treatment_item(P)
		if(I)
			goal.patched++
			bot_log(bot, "patching up [P] with [I] while we wait")
			bot.use_item_on(I, P)
			return TRUE
	// A doctor at the door: let in, if it's in reach
	for(var/obj/machinery/door/airlock/D in range(1, bot.owner))
		if(!D.density || D.operating || !D.allowed(bot.owner))
			continue
		for(var/mob/living/carbon/human/doc in range(1, D))
			if(doc != bot.owner && doc != P && doc.stat == CONSCIOUS && (doc.mind?.assigned_role in list("Medical Doctor", "Chief Medical Officer", "Paramedic")))
				bot_log(bot, "letting [doc] in for [P]")
				bot.use_atom(D)
				wait_for = 20
				return TRUE
	if(get_dist(bot.owner, P) > 1)
		bot.pursue(P, "follow", force = TRUE)
	wait_for = 30
	return TRUE

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
		if(bot_prisoner_dangerous(P)) //not out of Security: seen to here
			var/tried = LAZYACCESS(bot.brig_care_tried, P)
			if((!tried || world.time > tried + 5 MINUTES) && bot.start_brig_care(P, T))
				bot_say(bot.owner, ":s [P.name]'s collapsed in [T.name] - getting them out for a doctor.")
				return TRUE
			continue
		if(bot.start_medevac(P, T))
			bot_say(bot.owner, ":s [P.name]'s collapsed in [T.name] - getting them to Medbay.")
			return TRUE
	return FALSE
