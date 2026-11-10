// Somebody down where no doctor can get to them.
//
// A doctor's ID opens Medbay and the hallways. Called to Engineering, the lab or the Cargo office, it answers "Coming", finds the
// department's door shut to it, says "I can't get to you", and that was the end of it: an engineer shot down in Meta's engine
// room called for a medic, was told that, and lay there for half an hour until the suffocation finished what the burns began,
// with the rest of Engineering walking past. What people do is bring them out. The doctor asks for that now, and whoever hears it
// and can walk to the casualty by their own doors (the people who work there, mostly) takes hold of them once they're down, drags
// them to Medbay's door, and says so. The doctors take it from there (escort_to_sleeper, goals/treat_patient.dm).
//
// Only somebody a doctor has said it can't reach, and only once they're past walking there themselves: the walking wounded take
// themselves (seek_medbay_healing), and anybody a doctor can get to is the doctor's.

/// How long after a doctor says it can't get to somebody they're still looked out for.
#define BOT_STRANDED_FOR (10 MINUTES)
/// How far off somebody will come from to bring a casualty out.
#define BOT_CARRY_REACH 45

/// People a doctor has said it can't get to: weakref -> when it said so.
GLOBAL_LIST_EMPTY(bot_stranded_casualties)

/// A doctor's given up on getting to somebody who called for one (answer_call/on_give_up(), bot_requests.dm).
/proc/bot_note_stranded(mob/living/carbon/human/who)
	if(istype(who) && who.stat != DEAD)
		GLOB.bot_stranded_casualties[WEAKREF(who)] = world.time

/datum/bot_duty/bring_casualty_out
	name = "bringing somebody out for the doctors"
	tier = BOT_DUTY_URGENT
	priority = 45
	interval_min = 50
	interval_max = 120

/datum/bot_duty/bring_casualty_out/try_start(datum/bot_brain/bot)
	if(!length(GLOB.bot_stranded_casualties))
		return FALSE
	if(bot.owner.incapacitated() || bot.owner.handcuffed || bot.is_in_active_cell(bot.owner))
		return FALSE
	var/turf/spot
	for(var/datum/weakref/W as anything in GLOB.bot_stranded_casualties.Copy())
		var/mob/living/carbon/human/H = W.resolve()
		if(QDELETED(H) || H.stat == DEAD || world.time > GLOB.bot_stranded_casualties[W] + BOT_STRANDED_FOR || bot_in_medbay(H))
			GLOB.bot_stranded_casualties -= W
			continue
		if(H == bot.owner || H.stat == CONSCIOUS || !isturf(H.loc) || H.z != bot.owner.z || get_dist(bot.owner, H) > BOT_CARRY_REACH)
			continue //still on their feet: they can walk there
		if(H.pulledby || H.buckled || bot.taken_by_another(H) || (bot.gym_run && get_area(H) != get_area(bot.owner)))
			continue
		if(!bot.can_walk_lawfully_to(H))
			continue
		spot = spot || bot.medbay_drop_spot() //goals/security_medevac.dm
		if(!spot)
			return FALSE
		return bot.assign_goal(new /datum/bot_goal/carry_casualty(H, spot))
	return FALSE

/datum/bot_goal/carry_casualty
	lawful = TRUE
	exclusive = TRUE //one to a casualty
	doing = "getting somebody to Medbay"
	var/turf/drop_spot

/datum/bot_goal/carry_casualty/New(mob/living/carbon/human/H, turf/spot)
	. = ..()
	target = H
	drop_spot = spot

/datum/bot_goal/carry_casualty/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = target
	if(QDELETED(H) || H.stat == DEAD || H.stat == CONSCIOUS || !isturf(H.loc) || !drop_spot)
		target = null

/datum/bot_goal/carry_casualty/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/escort/S = new(drop_spot)
	var/datum/bot_step/move_to/to_medbay = new
	to_medbay.step_target = drop_spot
	// To them, hold of them (the medipen first if it has one, as grab_patient does), to Medbay's door, and set down
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_patient(), to_medbay, new /datum/bot_step/set_casualty_down())
	return list(S)

/datum/bot_goal/carry_casualty/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()

/// At Medbay's door: let go of them, and a word to the doctors.
/datum/bot_step/set_casualty_down/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.current_goal?.target
	if(QDELETED(H))
		return GOAL_STEP_FAIL
	if(bot.owner.pulling != H && !bot.owner.Adjacent(H))
		return GOAL_STEP_FAIL //lost them on the way
	bot.owner.stop_pulling()
	GLOB.bot_stranded_casualties -= WEAKREF(H)
	bot_log(bot, "brought [H] out to Medbay for the doctors")
	bot_tally("casualties brought to Medbay")
	if(H.stat != DEAD && !bot.gym_scripted)
		bot.say_after_typing(";Medbay, I've brought [H.first_name()] to your door. [pick("They're in a bad way.", "They need a doctor now.", "Somebody see to them.")]")
	return GOAL_STEP_SUCCESS

#undef BOT_STRANDED_FOR
#undef BOT_CARRY_REACH
