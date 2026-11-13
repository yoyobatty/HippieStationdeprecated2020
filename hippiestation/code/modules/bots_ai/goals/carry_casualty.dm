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

/// The same, from a radio call that got out (bot_radio.dm)
/proc/bot_note_stranded_ref(datum/weakref/W)
	bot_note_stranded(W?.resolve())

/// A doctor's given up on getting to somebody who called for one (answer_call/on_give_up(), bot_requests.dm).
/proc/bot_note_stranded(mob/living/carbon/human/who)
	if(istype(who) && who.stat != DEAD)
		GLOB.bot_stranded_casualties[WEAKREF(who)] = world.time

/// Casualties already asked about on the radio: weakref -> when.
GLOBAL_LIST_EMPTY(bot_stranded_asked)

/// A doctor on its round has found somebody down that it can't get to. Nobody had called: three engineers shot unconscious in Box's
/// laser room never said a word, the doctors gave up on getting to them 52 times in the shift ("no way to them from here"), and
/// they lay there twenty minutes until they died. It asks for them to be brought out, the same as for a call it can't answer.
/datum/bot_brain/proc/cant_reach_casualty(mob/living/carbon/human/H)
	if(!istype(H) || QDELETED(H) || H.stat == DEAD || H.stat == CONSCIOUS || bot_in_medbay(H))
		return
	bot_note_stranded(H)
	var/datum/weakref/W = WEAKREF(H)
	if(world.time < GLOB.bot_stranded_asked[W] + 3 MINUTES)
		return //somebody's said so already
	for(var/datum/weakref/old as anything in GLOB.bot_stranded_asked)
		if(world.time > GLOB.bot_stranded_asked[old] + BOT_STRANDED_FOR)
			GLOB.bot_stranded_asked -= old
	GLOB.bot_stranded_asked[W] = world.time
	bot_log(src, "can't get to [H] in [get_area_name(H, TRUE)] - asking for them to be brought out")
	bot_tally("casualties asked for")
	if(!gym_scripted)
		var/where = get_area_name(H, TRUE)
		say_after_typing(";" + pick("[H.first_name()]'s down in [where] and I can't get in there. Can somebody with access bring them out to Medbay?", "Somebody's down in [where] and it's not a door I can open. Whoever can, bring them to Medbay?", "I can't get to [H.first_name()] in [where]. Can anyone in there drag them out to Medbay?"))

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

// ---------------------------------------------------------------------------------------------
// "Help", from somebody down
// ---------------------------------------------------------------------------------------------
// The user, cuffed and in crit after losing to a nanosuit, crawled into maintenance saying "help" to three bots in turn. One answered
// "What's wrong?" at most, and they all walked on (2026-11-13). Somebody on the floor asking for help gets it: whoever's free takes hold
// of them and gets them to Medbay's door; whoever's on something it can't drop calls Medical to them, and they're on the list for
// anybody bringing casualties out (bring_casualty_out above).

/// Down: on the floor and badly hurt, or past standing at all
/proc/bot_down_and_hurt(mob/living/carbon/human/H)
	if(!istype(H) || H.stat == DEAD)
		return FALSE
	if(H.stat != CONSCIOUS || H.health <= 0)
		return TRUE
	return !(H.mobility_flags & MOBILITY_STAND) && H.health < H.maxHealth * 0.5

/datum/bot_brain
	/// REF(casualty) -> when it can next answer them (heard_cry_for_help())
	var/list/cries_answered

/// From on_heard_speech() (bot_chatter.dm), said to its face. TRUE if it's taken it as a cry for help and done something about it.
/datum/bot_brain/proc/heard_cry_for_help(mob/living/carbon/human/H, lower_msg)
	if(!bot_down_and_hurt(H) || get_dist(owner, H) > BOT_SIGHT_RANGE || !(H in view(BOT_SIGHT_RANGE, owner)))
		return FALSE
	// In crit all that comes out is a whisper, garbled past a step away: anything from somebody that far gone is a call for help
	if(H.stat == CONSCIOUS && !bot_text_has_any(lower_msg, list("help", "halp", "medic", "doctor", "dying", "save me", "please")))
		return FALSE
	if(bot_traitor || op_team || bot_wizard || gone_loud() || owner.incapacitated() || owner.handcuffed || (state == BOT_STATE_COMBAT && attacker == H))
		return FALSE
	if(world.time < LAZYACCESS(cries_answered, REF(H)))
		return TRUE //it's heard them, and it's on it or it's said so
	LAZYSET(cries_answered, REF(H), world.time + 30 SECONDS)
	owner.face_atom(H)
	// Somebody dangerous in Security's cuffs: theirs to see to (the user's ruling, 2026-11-05: violent prisoners don't leave Security)
	if(H.handcuffed && bot_prisoner_dangerous(H))
		call_help_for(H, ":s [H.first_name()]'s down in cuffs in [get_area_name(H, TRUE)] and needs a doctor.")
		bot_say(owner, pick("Security's coming for you.", "Hang on, I've told Security."))
		return TRUE
	// Free to: hold of them and to Medbay's door
	var/turf/spot = medbay_drop_spot() //goals/security_medevac.dm
	if(spot && !H.pulledby && !taken_by_another(H) && !bot_in_medbay(H) && state != BOT_STATE_COMBAT && state != BOT_STATE_ARREST && can_walk_lawfully_to(H))
		if(state == BOT_STATE_GOAL && current_goal && bot_goal_can_wait(current_goal))
			drop_goals("[H] is down and asking for help")
		if(state != BOT_STATE_GOAL && H.stat != CONSCIOUS && assign_goal(new /datum/bot_goal/carry_casualty(H, spot)))
			bot_log(src, "[H] is down and asked for help - taking them to Medbay")
			bot_tally("cries for help answered")
			bot_say(owner, pick("Hang on, I've got you.", "Okay, okay. Let's get you to Medbay.", "I've got you, hold on."))
			return TRUE
	// Otherwise the doctors are told, and anybody bringing casualties out can come for them
	call_help_for(H, ";" + pick("Medical! [H.first_name()]'s down in [get_area_name(H, TRUE)] and needs a doctor!", "Doctor to [get_area_name(H, TRUE)], [H.first_name()]'s in a bad way!"))
	bot_say(owner, pick("Hang on, I've called Medical.", "Medical's coming. Hold on.", "Stay with me, help's coming."))
	bot_tally("cries for help answered")
	return TRUE

/// An errand that can be put down for somebody dying in front of it: a break, or an everyday job. Not its own air or wounds, a run for it,
/// the shuttle, or somebody else it's seeing to.
/proc/bot_goal_can_wait(datum/bot_goal/G)
	if(!G || G.exclusive)
		return FALSE
	var/static/list/never = list(/datum/bot_goal/run_from, /datum/bot_goal/seek_air, /datum/bot_goal/refill_internals, /datum/bot_goal/self_heal, 		/datum/bot_goal/seek_medbay_healing, /datum/bot_goal/evacuate, /datum/bot_goal/carry_casualty)
	if(is_type_in_list(G, never))
		return FALSE
	return G.off_duty || G.lawful

/// A call for them on the radio, once a minute between everybody
/datum/bot_brain/proc/call_help_for(mob/living/carbon/human/H, line)
	var/datum/weakref/W = WEAKREF(H)
	if(world.time < GLOB.bot_stranded_asked[W] + 1 MINUTES)
		return
	GLOB.bot_stranded_asked[W] = world.time
	bot_log(src, "calling for help for [H]: [line]")
	var/said_at = world.time
	bot_say(owner, line)
	bot_radio_then(owner, said_at, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_note_stranded_ref), W)) //bot_radio.dm: on the list if it got out

#undef BOT_STRANDED_FOR
#undef BOT_CARRY_REACH
