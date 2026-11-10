// A doctor's look round Medbay's machines, first thing in every medical round (try_medical_round(), goals/treat_patient.dm).
//
// Somebody who dies in a sleeper or a cryo cell stays in it: the cloning round only looks for bodies on the floor, and nothing ever
// opened the machine. In a played round the Warden and a traitor both died in Medbay's sleepers and were still there at the end,
// with two doctors on shift. A person going round checks each one: the dead come out to be cloned, the patched up get sent on
// their way, and the machine's free for the next one.

/// Patched up enough to be let out of a sleeper or a cryo cell.
#define BOT_SLEEPER_DONE 0.9

/// Dead, or as good as new: who a doctor going round lets out of a sleeper (below), so nobody like that is put in one either
/// (escort_to_sleeper, treat_patient.dm).
/proc/bot_sleeper_done_with(mob/living/carbon/human/H)
	return H.stat == DEAD || H.health >= H.maxHealth * BOT_SLEEPER_DONE

/// A sleeper or cryo cell with somebody in it who's finished with it: dead, or as good as new.
/datum/bot_brain/proc/find_machine_to_empty()
	var/best
	var/best_dist
	for(var/machine_type in list(/obj/machinery/sleeper, /obj/machinery/atmospherics/components/unary/cryo_cell))
		for(var/obj/machinery/M as anything in bot_instances_of(machine_type))
			if(QDELETED(M) || M.z != owner.z || M.state_open || M.panel_open || taken_by_another(M))
				continue
			var/mob/living/carbon/human/H = M.occupant
			if(!istype(H))
				continue
			if(H.stat != DEAD && H.health < H.maxHealth * BOT_SLEEPER_DONE && !(istype(M, /obj/machinery/sleeper) && bot_sleeper_dose(M, H)))
				continue //not done, and nothing more the machine can give them just now
			if(gym_run && get_area(M) != get_area(owner))
				continue
			var/dist = get_dist(owner, M)
			if(dist > 40 || !can_walk_lawfully_to(M))
				continue
			if(!best || dist < best_dist)
				best = M
				best_dist = dist
	return best

/datum/bot_goal/empty_machine
	lawful = TRUE
	exclusive = TRUE
	doing = "checking on the sleepers"

/datum/bot_goal/empty_machine/resolve_target(datum/bot_brain/bot)
	target = bot.find_machine_to_empty()

/datum/bot_goal/empty_machine/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/empty_machine/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/empty_machine())
	return list(S)

/datum/bot_goal/empty_machine/on_success(datum/bot_brain/bot)
	bot.continue_medical_round() //a body out of it is the cloning round's next

/datum/bot_strategy/empty_machine/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// The button that opens it, and a word to whoever comes out of it alive.
/datum/bot_step/empty_machine/execute(datum/bot_brain/bot)
	var/obj/machinery/M = bot.current_goal?.target
	if(!istype(M) || QDELETED(M) || !bot.owner.Adjacent(M))
		return GOAL_STEP_FAIL
	var/mob/living/carbon/human/H = M.occupant
	if(!istype(H))
		return GOAL_STEP_SUCCESS
	bot.human_pause(M)
	if(QDELETED(M) || M.occupant != H || !bot.owner.Adjacent(M))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(M)
	// Still being seen to: a dose of what they need off the sleeper's panel, as a doctor going round does.
	if(H.stat != DEAD && H.health < H.maxHealth * BOT_SLEEPER_DONE)
		var/obj/machinery/sleeper/S = M
		var/chem = istype(S) ? bot_sleeper_dose(S, H) : null
		if(chem && S.inject_chem(chem, bot.owner))
			var/datum/reagent/R = chem
			bot.telemetry_ui_action(S, "inject")
			bot_log(bot, "gave [H] [initial(R.name)] in [S]")
		return GOAL_STEP_SUCCESS
	bot.telemetry_ui_action(M, "eject")
	M.open_machine()
	if(M.occupant == H)
		return GOAL_STEP_FAIL
	if(H.stat == DEAD)
		bot_log(bot, "took [H]'s body out of [M]")
		bot_tally("bodies out of sleepers")
	else
		bot_log(bot, "let [H] out of [M], patched up")
		bot_say(bot.owner, pick("You're good to go.", "All patched up. Off you go.", "There, good as new.", "That's you done."))
	return GOAL_STEP_SUCCESS

/// The sleeper's medicine for whoever's in it, by what's worst with them: epinephrine for somebody in crit (the one it gives whatever
/// their state), pentetic acid against radiation and antitoxin for poisoning once the sleeper's upgraded for them, something for their
/// breathing, then bicaridine or kelotane, the worse first. Null if it's in them already or the sleeper doesn't do it. A doctor used to
/// put in bicaridine or kelotane at random, whatever was wrong.
/proc/bot_sleeper_dose(obj/machinery/sleeper/S, mob/living/carbon/human/H)
	if(!istype(S) || !istype(H) || H.stat == DEAD || !H.reagents)
		return null
	var/list/wanted = list()
	if(H.health <= 0)
		wanted += /datum/reagent/medicine/epinephrine
	if(bot_needs_blood(H)) //goals/give_blood.dm: saline, which a sleeper stocks now (prototype_chems.dm)
		wanted += /datum/reagent/medicine/salglu_solution
	if(H.radiation > RAD_MOB_SAFE)
		wanted += /datum/reagent/medicine/pen_acid
	if(H.getToxLoss() > 20)
		wanted += /datum/reagent/medicine/antitoxin
	if(H.getOxyLoss() > 30)
		wanted += list(/datum/reagent/medicine/perfluorodecalin, /datum/reagent/medicine/salbutamol)
	var/burn_first = H.getFireLoss() > H.getBruteLoss()
	if(burn_first && H.getFireLoss() > 15)
		wanted += /datum/reagent/medicine/kelotane
	if(H.getBruteLoss() > 15)
		wanted += /datum/reagent/medicine/bicaridine
	if(!burn_first && H.getFireLoss() > 15)
		wanted += /datum/reagent/medicine/kelotane
	for(var/chem in wanted)
		if((chem in S.available_chems) && H.reagents.get_reagent_amount(chem) < 5 && S.chem_allowed(chem))
			return chem
	return null

#undef BOT_SLEEPER_DONE
