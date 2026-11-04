// A doctor's look round Medbay's machines, first thing in every medical round (try_medical_round(), goals/treat_patient.dm).
//
// Somebody who dies in a sleeper or a cryo cell stays in it: the cloning round only looks for bodies on the floor, and nothing ever
// opened the machine. In a played round the Warden and a traitor both died in Medbay's sleepers and were still there at the end,
// with two doctors on shift. A person going round checks each one: the dead come out to be cloned, the patched up get sent on
// their way, and the machine's free for the next one.

/// Patched up enough to be let out of a sleeper or a cryo cell.
#define BOT_SLEEPER_DONE 0.9

/// A sleeper or cryo cell with somebody in it who's finished with it: dead, or as good as new.
/datum/bot_brain/proc/find_machine_to_empty()
	var/best
	var/best_dist
	for(var/machine_type in list(/obj/machinery/sleeper, /obj/machinery/atmospherics/components/unary/cryo_cell))
		for(var/obj/machinery/M as anything in bot_instances_of(machine_type))
			if(QDELETED(M) || M.z != owner.z || M.state_open || M.panel_open || taken_by_another(M))
				continue
			var/mob/living/carbon/human/H = M.occupant
			if(!istype(H) || (H.stat != DEAD && H.health < H.maxHealth * BOT_SLEEPER_DONE))
				continue
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

#undef BOT_SLEEPER_DONE
