// Self-preservation: ANY bot patches itself up when hurt, instead of only ever treating
// OTHERS (goals/treat_patient.dm, Doctor/CMO-only) while ignoring its own wounds - a real
// crew member reaches for a bandage on themselves the same as for anyone else. Reuses
// every generic medical proc treat_patient.dm already built (patient_needs_treatment(),
// get_medical_supplies(), pick_treatment_item(), aim_at_worst_wound(),
// restock_medical_supplies(), find_reachable_healing_machine()) with the bot's own owner
// passed in as the "patient" - none of those were ever actually restricted to Doctor/CMO,
// just called that way by try_medical_round() (job-gated) up to now. Every job runs this
// check (see handle_wander(), bot_brain.dm) - an engineer bandaging a burn from a bad
// wire is exactly as normal as a doctor doing the same.
//
// Three tiers, escalating only as far as actually needed:
// 1. self_treat - patch up with whatever's already carried (fast, no travel).
// 2. Still carrying nothing - restock_medical_supplies() grabs more from wherever's
//    NEAREST (acquire_item_type.dm picks nearest-reachable, not station-wide-random) -
//    very often the bot's own department, since that's usually where it got hurt in the
//    first place, giving "check for department healing first" for free without needing a
//    separate area-restricted search.
// 3. Nearest-supply search comes up completely empty and the bot's still hurt - head to
//    Medbay specifically and climb into a sleeper/cryo cell, the same real destination
//    escort_to_sleeper.dm (treat_patient.dm) sends an incapacitated PATIENT to, just
//    self-admitted instead of dragged in by someone else. Mirrors load_patient()'s exact
//    MouseDrop_T approach, which deliberately never closes the machine afterward - an open
//    sleeper/cryo cell doesn't container_resist on movement (relaymove()/Exited() in both
//    sleeper.dm and cryo.dm gate on `!state_open`), so the bot can walk itself back out
//    for ordinary duty the instant something else needs it, without any extra eject logic.

/// Healing medicine still in somebody's blood, working (goals/chem_lab.dm's kinds: tricordrazine, the fluorides, styptic, silver sulf...).
/proc/bot_healing_in_blood(mob/living/L)
	for(var/datum/reagent/R in L.reagents?.reagent_list)
		if(R.volume >= 1 && bot_chem_kind(R.type) == "heal")
			return TRUE
	return FALSE

/datum/bot_brain/proc/try_self_heal_round()
	if(!patient_needs_treatment(owner) || bot_healing_in_blood(owner))
		return FALSE //a pill or a patch it took is still at work: another on top does nothing more
	// In a hardsuit or a firesuit, a bandage does nothing (clothing_in_the_way(), treat_patient.dm) and there may be no
	// patch to stick on over it. The suit isn't coming off out here: medbay's sleeper works through anything.
	aim_at_worst_wound(owner)
	if(clothing_in_the_way(owner) && !pick_treatment_item(owner, TRUE))
		return nanosuit_on() ? patch_up() : try_seek_medbay_healing() //goals/robust.dm
	// Nothing on it to use, and it looked for some only a few minutes ago: straight to Medbay, not another look.
	if(world.time < no_medical_supplies_until && !pick_treatment_item(owner))
		return try_seek_medbay_healing()
	return assign_goal(new /datum/bot_goal/self_heal())

// Same immediate-rechain idea as continue_medical_round() - finish treating one wound,
// check immediately whether more's needed (another item, a restock, or a trip to Medbay)
// instead of waiting out the normal wander pace.
/datum/bot_brain/proc/continue_self_heal_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_self_heal_round)), TRUE)

/datum/bot_goal/self_heal/resolve_target(datum/bot_brain/bot)
	if(!bot.patient_needs_treatment(bot.owner))
		return
	target = bot.owner

/datum/bot_goal/self_heal/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/self_treat())

/datum/bot_goal/self_heal/on_success(datum/bot_brain/bot)
	bot.continue_self_heal_round()

// Only reachable once self_treat's own step has already tried restocking and come up
// empty (see that step's execute() below) - still hurt with nothing left to treat with.
// Escalate to Medbay instead of just leaving the bot to limp around injured for the rest
// of the round.
/datum/bot_goal/self_heal/on_give_up(datum/bot_brain/bot)
	if(bot.patient_needs_treatment(bot.owner))
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, try_seek_medbay_healing)))

/datum/bot_strategy/self_treat/New()
	. = ..()
	steps = list(new /datum/bot_step/self_treat())

/datum/bot_strategy/self_treat/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_brain
	/// Until when there's no point looking for bandages again: it looked, and there were none to be had.
	var/no_medical_supplies_until = 0

/datum/bot_step/self_treat
	// One-shot per strategy attempt, same idea as treat_patient's own tried_restock - a
	// station with nothing left to restock from shouldn't burn a fresh suspend cycle
	// (goal_suspend_count) on every single re-check while still treating itself.
	var/tried_restock = FALSE
	/// Applications in a row that did nothing - see treat_patient's step. This one once ran for 25 minutes.
	var/useless_clicks = 0

/datum/bot_step/self_treat/execute(datum/bot_brain/bot)
	if(!bot.patient_needs_treatment(bot.owner))
		return GOAL_STEP_SUCCESS //nothing left to do
	bot.aim_at_worst_wound(bot.owner)
	var/obj/item/clothing/covering = bot.clothing_in_the_way(bot.owner)
	var/obj/item/I = bot.pick_treatment_item(bot.owner, !!covering)
	if(covering && !I)
		bot_log(bot, "can't bandage myself through [covering]")
		return GOAL_STEP_FAIL //on_give_up() sends it to medbay
	if(!I)
		if(!tried_restock)
			tried_restock = TRUE
			if(bot.restock_medical_supplies(bot_needs_antitox(bot.owner)))
				bot_log(bot, "hurt and out of medical supplies - going to restock")
				return GOAL_STEP_PENDING
		bot_log(bot, "hurt and nothing reachable to restock medical supplies with")
		bot.no_medical_supplies_until = world.time + 5 MINUTES
		return GOAL_STEP_FAIL
	var/hurt_before = bot.owner.getBruteLoss() + bot.owner.getFireLoss() + bot.owner.getToxLoss()
	var/dose_before = I.reagents?.total_volume
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot_log(bot, "treating myself with [I]")
	// Unlike treating ANOTHER patient (treat_patient.dm's own step, which heals
	// synchronously - stack/medical/attack()'s do_mob channel only triggers when M ==
	// user), self-application always goes through that channel (a real few-second "you
	// begin applying..." delay) - use_item_on() yields for that real time internally
	// (melee_attack_chain() -> attack() -> do_mob(), mobs.dm) before returning, same as
	// defibrillate()/paddles.attack() elsewhere in this system.
	bot.use_item_on(I, bot.owner)
	if(!bot.patient_needs_treatment(bot.owner))
		return GOAL_STEP_SUCCESS
	// A pill or a patch works as it goes, not on the spot: three in a row, no less hurt the moment after each, used to be "this isn't
	// doing anything for me" and a give-up, 87 times in three long shifts, with three patches gone each time.
	if(istype(I, /obj/item/reagent_containers))
		// Unless it never went in: the same patch still full in hand. That was a "success", nothing in the blood the moment after, and
		// another go at once: 263 in one second for one bot (tools/bot_gym/hollow_goals.py, 2026-11-22). Medbay, then.
		if(!QDELETED(I) && !isnull(dose_before) && I.reagents && I.reagents.total_volume >= dose_before && !bot_healing_in_blood(bot.owner))
			bot_log(bot, "[I] didn't go in")
			bot.no_medical_supplies_until = world.time + 2 MINUTES
			return GOAL_STEP_FAIL
		bot_log(bot, "[I]'s in - it'll work as it goes")
		return GOAL_STEP_SUCCESS
	useless_clicks = (bot.owner.getBruteLoss() + bot.owner.getFireLoss() + bot.owner.getToxLoss() < hurt_before) ? 0 : useless_clicks + 1
	if(useless_clicks >= 3)
		bot_log(bot, "this isn't doing anything for me")
		return GOAL_STEP_FAIL
	addtimer(CALLBACK(src, PROC_REF(continue_self_treat), bot), CLICK_CD_MELEE)
	return GOAL_STEP_PENDING

/datum/bot_step/self_treat/proc/continue_self_treat(datum/bot_brain/bot)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return //goal moved on (succeeded/failed/replaced) while we were waiting - don't act on stale state
	var/result = execute(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

// ============================================================
// Medbay escalation: nothing reachable to self-treat with anywhere - go get into a real
// healing machine instead of just staying hurt.
// ============================================================

/datum/bot_brain/proc/try_seek_medbay_healing()
	if(!patient_needs_treatment(owner) || bot_shuttle_boarding()) //the shuttle's got a first aid kit: Medbay's a walk away from it
		return FALSE
	maybe_call_medic() //bot_requests.dm - and sets off for Medbay regardless: whichever of them gets there first
	return assign_goal(new /datum/bot_goal/seek_medbay_healing())

/datum/bot_goal/seek_medbay_healing
	var/atom/machine_target

/datum/bot_goal/seek_medbay_healing/resolve_target(datum/bot_brain/bot)
	if(!bot.patient_needs_treatment(bot.owner))
		return
	// Already resting in one - let it keep healing there instead of hopping to another;
	// find_reachable_healing_machine() would skip this exact one anyway once its own
	// occupant var is filled (both finders check `if(S.occupant): continue`), which used
	// to send the bot straight back out looking for a SECOND empty machine instead of
	// just sitting still in the one it's already in.
	if(istype(bot.owner.loc, /obj/machinery/sleeper) || istype(bot.owner.loc, /obj/machinery/atmospherics/components/unary/cryo_cell))
		return
	var/atom/M = bot.find_reachable_healing_machine(bot.owner, TRUE)
	if(!M)
		return
	target = bot.owner
	machine_target = M

/datum/bot_goal/seek_medbay_healing/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/self_admit(machine_target))

/datum/bot_goal/seek_medbay_healing/on_success(datum/bot_brain/bot)
	// Loops back to self_heal instead of straight to try_next_wander_candidate() - once
	// actually at Medbay there's often loose supplies reachable too, and a fresh self_heal
	// check naturally does nothing at all (patient_needs_treatment() false) the instant
	// the injection's done its job, same "recheck, only act if still needed" idea used
	// throughout this system.
	bot.continue_self_heal_round()

/datum/bot_strategy/self_admit
	var/atom/machine_target

/datum/bot_strategy/self_admit/New(atom/M)
	. = ..()
	machine_target = M
	var/datum/bot_step/move_to/to_machine = new()
	to_machine.step_target = M
	steps = list(to_machine, new /datum/bot_step/load_self(M))

/datum/bot_strategy/self_admit/is_feasible(datum/bot_brain/bot)
	return machine_target && !QDELETED(machine_target)

/datum/bot_step/load_self
	var/atom/machine_target

/datum/bot_step/load_self/New(atom/M)
	. = ..()
	machine_target = M

// Mirrors load_patient() (treat_patient.dm) exactly, just with the bot dragging ITSELF
// onto the machine instead of a patient it's pulling - MouseDrop_T(over_object, user)
// doesn't require the two to differ (a conscious player can self-admit into a sleeper the
// same way), and deliberately never calls close_machine() afterward, same as
// load_patient() - see this file's header comment for why that matters.
/datum/bot_step/load_self/execute(datum/bot_brain/bot)
	if(QDELETED(machine_target))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(machine_target))
		return GOAL_STEP_FAIL
	if(istype(machine_target, /obj/machinery/sleeper))
		var/obj/machinery/sleeper/S = machine_target
		if(S.occupant)
			return (S.occupant == bot.owner) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
		S.MouseDrop_T(bot.owner, bot.owner)
		if(S.occupant != bot.owner)
			return GOAL_STEP_FAIL
		bot_log(bot, "climbed into [S] to treat myself")
		S.inject_chem(pick(/datum/reagent/medicine/bicaridine, /datum/reagent/medicine/kelotane), bot.owner)
		return GOAL_STEP_SUCCESS
	if(istype(machine_target, /obj/machinery/atmospherics/components/unary/cryo_cell))
		var/obj/machinery/atmospherics/components/unary/cryo_cell/C = machine_target
		if(C.occupant)
			return (C.occupant == bot.owner) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
		if(!C.state_open)
			C.open_machine()
		C.MouseDrop_T(bot.owner, bot.owner)
		// cryo.dm's MouseDrop_T only takes somebody who can't stand, so a bot on its feet never got in (a clone with sixty cloning
		// damage stood beside the cell, 2026-11-10). It climbs in and pulls the lid down itself, where a player would ask a doctor.
		if(C.occupant != bot.owner && bot.owner.Adjacent(C))
			C.close_machine(bot.owner)
		if(C.occupant != bot.owner)
			return GOAL_STEP_FAIL
		bot_log(bot, "climbed into [C] to treat myself")
		C.on = TRUE
		C.update_icon()
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

// ============================================================
// Bad mutations. A rad storm (round-14.43.45) left the crew with Spatial Instability, Tourette's and the like, and two of them
// blinked into space and suffocated without ever doing a thing about it. Anybody who's felt "the space around you twists sickeningly"
// knows something's wrong, and the cure is mutadone: Genetics keeps a bottle of pills. It fetches one if its own doors reach them,
// and failing that goes to Medbay and asks Medical, and a doctor brings one. With Spatial Instability (a blink is 10 to 15 tiles,
// any way) it keeps away from the hull till then. The user's ruling (2026-11-14): both.
// ============================================================

/proc/bot_bad_mutations(mob/living/carbon/human/H)
	. = list()
	if(!istype(H) || !H.dna)
		return
	for(var/datum/mutation/human/M as anything in H.dna.mutations)
		if(M.quality == NEGATIVE)
			. += M

/proc/bot_mutadone_in_blood(mob/living/L)
	return L.reagents && L.reagents.get_reagent_amount(/datum/reagent/medicine/mutadone) >= 1

/// A mutadone pill on it: in a hand, a pocket, the bag, or a bottle of them in any of those.
/proc/bot_carried_mutadone(mob/living/carbon/human/H)
	for(var/obj/item/reagent_containers/pill/P in H.GetAllContents())
		if(P.reagents?.get_reagent_amount(/datum/reagent/medicine/mutadone) >= 1)
			return P
	return null

/// How much of what's within a blink of here (10 to 15 tiles) is space, 0 to 1.
/proc/bot_space_within_blink(turf/T)
	var/space = 0
	var/total = 0
	for(var/turf/S in range(13, T))
		total++
		if(isspaceturf(S))
			space++
	return total ? space / total : 0

/datum/bot_brain
	/// When it may next go looking for mutadone itself, rather than asking Medical
	var/next_mutadone_fetch = 0

/datum/bot_brain/proc/try_cure_mutation()
	if(bot_carried_mutadone(owner))
		return assign_goal(new /datum/bot_goal/take_mutadone())
	if(world.time >= next_mutadone_fetch)
		next_mutadone_fetch = world.time + 3 MINUTES
		var/datum/bot_goal/acquire_item_type/mutadone/G = new()
		if(assign_goal(G))
			bot_log(src, "a bad mutation - going for mutadone")
			bot_say(owner, pick("Ugh, something's not right with me. Mutadone.", "I feel wrong. Need mutadone.", "That storm's done something to me..."))
			return TRUE
	// None it can get to itself: Medbay, where the doctors are, and the radio
	if(!bot_in_medbay(owner))
		var/turf/T = medbay_drop_spot()
		if(T && assign_goal(new /datum/bot_goal/walk_up_to(T)))
			bot_log(src, "a bad mutation, and no mutadone of my own to get - off to Medbay")
			return TRUE
	var/where = get_area_name(owner, TRUE)
	return call_for(/datum/bot_request_kind/medical, pick("Anyone got mutadone? I've picked up a bad mutation, I'm in [where].", "Medical, could I get some mutadone in [where]? Something's wrong with my genes.", "Need mutadone in [where], please."), "mutadone")

/datum/bot_duty/cure_mutation
	name = "getting rid of a bad mutation"
	tier = BOT_DUTY_URGENT
	priority = 60
	interval_min = 20
	interval_max = 45

/datum/bot_duty/cure_mutation/try_start(datum/bot_brain/bot)
	if(!length(bot_bad_mutations(bot.owner)) || bot_mutadone_in_blood(bot.owner))
		return FALSE
	return bot.try_cure_mutation()

/datum/bot_goal/acquire_item_type/mutadone
	item_type = /obj/item/storage/pill_bottle/mutadone
	lawful = TRUE
	doing = "getting some mutadone"

/datum/bot_goal/acquire_item_type/mutadone/on_success(datum/bot_brain/bot)
	if(length(bot_bad_mutations(bot.owner)))
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/take_mutadone()), TRUE)

/// One pill of it, swallowed, and the bottle left where it was found for the next one.
/datum/bot_goal/take_mutadone
	doing = "taking mutadone"

/datum/bot_goal/take_mutadone/resolve_target(datum/bot_brain/bot)
	target = bot_carried_mutadone(bot.owner) ? bot.owner : null

/datum/bot_goal/take_mutadone/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/self_treat/S = new
	S.steps = list(new /datum/bot_step/feed_mutadone())
	return list(S)

/// A mutadone pill out of the bottle and into somebody: itself (target is its own owner), or a patient a doctor's stood by.
/datum/bot_step/feed_mutadone

/datum/bot_step/feed_mutadone/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/who = bot.current_goal?.target
	if(!istype(who) || !bot.owner.Adjacent(who))
		return GOAL_STEP_FAIL
	var/obj/item/reagent_containers/pill/P = bot_carried_mutadone(bot.owner)
	if(!P)
		return GOAL_STEP_FAIL
	var/obj/item/storage/pill_bottle/bottle = istype(P.loc, /obj/item/storage/pill_bottle) ? P.loc : null
	if(bottle && !SEND_SIGNAL(bottle, COMSIG_TRY_STORAGE_TAKE, P, bot.owner.drop_location()))
		return GOAL_STEP_FAIL
	if(!(P in bot.owner.held_items) && !bot.owner.put_in_hands(P))
		return GOAL_STEP_FAIL
	bot.use_item_on(P, who)
	if(!QDELETED(P) && P.loc == bot.owner)
		return GOAL_STEP_FAIL //it didn't go down
	bot_log(bot, who == bot.owner ? "took a mutadone pill" : "gave [who] a mutadone pill")
	// The bottle stays where it came from, for whoever's next: the patient's own trip picked it up, into a hand or the bag
	if(who == bot.owner && bottle && (bottle in bot.owner.GetAllContents()))
		if(bottle.loc == bot.owner) //a hand, a pocket
			bot.owner.dropItemToGround(bottle)
		else if(isitem(bottle.loc))
			SEND_SIGNAL(bottle.loc, COMSIG_TRY_STORAGE_TAKE, bottle, bot.owner.drop_location())
		bot_log(bot, "left [bottle] [isturf(bottle.loc) ? "where it was" : "in [bottle.loc]"]")
	return GOAL_STEP_SUCCESS

/// A doctor answering "anyone got mutadone?": a pill from Genetics' bottle, then to them with it.
/datum/bot_brain/proc/bring_mutadone_to(mob/living/carbon/human/P)
	if(!istype(P) || P.stat == DEAD || !length(bot_bad_mutations(P)))
		return FALSE
	if(bot_carried_mutadone(owner))
		return assign_goal(new /datum/bot_goal/give_mutadone(P))
	var/datum/bot_goal/acquire_item_type/mutadone/for_patient/G = new()
	G.patient = P
	return assign_goal(G)

/datum/bot_goal/acquire_item_type/mutadone/for_patient
	var/mob/living/carbon/human/patient

/datum/bot_goal/acquire_item_type/mutadone/for_patient/on_success(datum/bot_brain/bot)
	if(!QDELETED(patient) && patient.stat != DEAD && length(bot_bad_mutations(patient)))
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/give_mutadone(patient)), TRUE)

/datum/bot_goal/give_mutadone
	lawful = TRUE
	doing = "bringing somebody mutadone"
	var/mob/living/carbon/human/patient

/datum/bot_goal/give_mutadone/New(mob/living/carbon/human/P)
	. = ..()
	patient = P

/datum/bot_goal/give_mutadone/resolve_target(datum/bot_brain/bot)
	if(QDELETED(patient) || patient.stat == DEAD || !length(bot_bad_mutations(patient)) || bot_mutadone_in_blood(patient) || !bot_carried_mutadone(bot.owner))
		return
	target = patient

/datum/bot_goal/give_mutadone/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/self_treat/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/feed_mutadone())
	return list(S)

/// With Spatial Instability: off the hull. A blink goes 10 to 15 tiles any way at all, and from the edge of the station that's
/// as often as not out into space with no suit on. Somewhere further in, till it's cured. A suit on, it's a walk back.
/datum/bot_duty/blink_off_the_hull
	name = "keeping off the hull"
	tier = BOT_DUTY_URGENT
	priority = 70
	interval_min = 15
	interval_max = 30

/datum/bot_duty/blink_off_the_hull/try_start(datum/bot_brain/bot)
	if(!bot.owner.dna || !(locate(/datum/mutation/human/badblink) in bot.owner.dna.mutations) || bot.is_eva_ready())
		return FALSE
	var/turf/here = get_turf(bot.owner)
	if(!here || (!is_station_level(here.z) && !bot.gym_run))
		return FALSE
	var/space_here = bot_space_within_blink(here)
	if(space_here < 0.05)
		return FALSE
	var/turf/inner = bot.further_from_space(space_here)
	if(!inner)
		return FALSE
	bot_log(bot, "Spatial Instability, and [round(space_here * 100)]% of a blink from here is space - moving further in")
	return bot.assign_goal(new /datum/bot_goal/walk_up_to(inner))

/// Somewhere a blink's less likely to end in space than here: Medbay's lobby, or a few spots round about, the least space first.
/datum/bot_brain/proc/further_from_space(space_here)
	var/list/scores = list()
	var/turf/medbay = medbay_drop_spot()
	if(medbay)
		scores[medbay] = bot_space_within_blink(medbay)
	var/list/near = list()
	for(var/turf/open/floor/T in range(20, owner))
		near += T
	for(var/i in 1 to min(8, length(near)))
		var/turf/T = pick_n_take(near)
		if(istype(T.loc, /area/space) || is_blocked_turf(T, TRUE))
			continue
		scores[T] = bot_space_within_blink(T)
	for(var/tries in 1 to 3)
		var/turf/best
		for(var/turf/T as anything in scores)
			if(!best || scores[T] < scores[best])
				best = T
		if(!best || scores[best] > space_here - 0.05)
			return null
		scores -= best
		if(can_walk_lawfully_to(best))
			return best
	return null
