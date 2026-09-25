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

/datum/bot_brain/proc/try_self_heal_round()
	if(!patient_needs_treatment(owner))
		return FALSE
	return assign_goal(new /datum/bot_goal/self_heal())

// Same immediate-rechain idea as continue_medical_round() - finish treating one wound,
// check immediately whether more's needed (another item, a restock, or a trip to Medbay)
// instead of waiting out the normal wander pace.
/datum/bot_brain/proc/continue_self_heal_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_self_heal_round)))

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

/datum/bot_step/self_treat
	// One-shot per strategy attempt, same idea as treat_patient's own tried_restock - a
	// station with nothing left to restock from shouldn't burn a fresh suspend cycle
	// (goal_suspend_count) on every single re-check while still treating itself.
	var/tried_restock = FALSE

/datum/bot_step/self_treat/execute(datum/bot_brain/bot)
	if(!bot.patient_needs_treatment(bot.owner))
		return GOAL_STEP_SUCCESS //nothing left to do
	var/obj/item/I = bot.pick_treatment_item(bot.owner)
	if(!I)
		if(!tried_restock)
			tried_restock = TRUE
			if(bot.restock_medical_supplies())
				bot_log(bot, "hurt and out of medical supplies - going to restock")
				return GOAL_STEP_PENDING
		bot_log(bot, "hurt and nothing reachable to restock medical supplies with")
		return GOAL_STEP_FAIL
	bot.aim_at_worst_wound(bot.owner)
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
	if(!patient_needs_treatment(owner))
		return FALSE
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
	var/atom/M = bot.find_reachable_healing_machine(bot.owner)
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
		if(C.occupant != bot.owner)
			return GOAL_STEP_FAIL
		bot_log(bot, "climbed into [C] to treat myself")
		C.on = TRUE
		C.update_icon()
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL
