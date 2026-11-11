// The shift gone bad: three or more of the crew dead (bot_shift_gone_bad(), goals/robust.dm) and whoever did it still about. In the user's
// Captain round (2026-11-10) the Captain killed twenty of the crew one at a time, and the rest went on asking for arcade partners, going
// exploring and reading out research. "Who's alive?" and "who's killing everyone?" on Common got no answer at all. The user's ruling: panic.
// No small talk or idle errands, people hide or group up, and those questions get answered, even telling the killer "you are".

/// Whoever last hurt each of the dead, as the radio's been shouting it and a forensic scan would turn it up: name -> bodies. Counted now and then.
GLOBAL_LIST_EMPTY(bot_body_counts)
GLOBAL_VAR_INIT(bot_body_counts_at, 0)
/// Who asked "who's killing everyone?" (REF) -> when somebody last answered them, so one does and not the whole station
GLOBAL_LIST_EMPTY(bot_killer_answered)
/// "Who's alive?": a few answer each asker, not everybody. REF -> until when, and how many have
GLOBAL_LIST_EMPTY(bot_alive_answers_until)
GLOBAL_LIST_EMPTY(bot_alive_answers)

/// Only the bodies in `only_in`, if it's given (a Bot Gym arena: names repeat from one arena to the next), counted fresh.
/proc/bot_body_counts(area/only_in)
	if(!only_in && world.time < GLOB.bot_body_counts_at)
		return GLOB.bot_body_counts
	var/list/counts = list()
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(!H.mind?.assigned_role || !H.last_assailant || H.last_assailant == H.real_name || (only_in && get_area(H) != only_in))
			continue
		counts[H.last_assailant] = (counts[H.last_assailant] || 0) + 1
	if(!only_in)
		GLOB.bot_body_counts_at = world.time + 10 SECONDS
		GLOB.bot_body_counts = counts
	return counts

/// Whoever has the most of the crew's bodies to their name (two at least) and is still up and about, not in cuffs; failing that, somebody
/// Security wants for murder. Only in `only_in`, if it's given (a Bot Gym arena).
/proc/bot_known_killer(area/only_in)
	var/list/counts = bot_body_counts(only_in)
	var/mob/living/carbon/human/best
	var/best_count = 1
	for(var/name in counts)
		if(counts[name] <= best_count)
			continue
		for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
			if(H.real_name == name && H.stat != DEAD && !H.handcuffed && (!only_in || get_area(H) == only_in))
				best = H
				best_count = counts[name]
				break
	if(best)
		return best
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/datum/bot_wanted/W = GLOB.bot_security_wanted[ref]
		var/mob/living/carbon/human/H = ref.resolve()
		if(H && W?.crime == "Murder" && H.stat != DEAD && !H.handcuffed && (!only_in || get_area(H) == only_in))
			return H
	return null

/// The killer at large, when it's that kind of shift. A Bot Gym bot counts only the bodies in its own arena.
/datum/bot_brain/proc/massacre_killer()
	if(!gym_run)
		return bot_shift_gone_bad() ? bot_known_killer() : null
	var/area/A = get_area(owner)
	var/dead = 0
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(get_area(H) == A && H.mind?.assigned_role)
			dead++
	return dead >= 3 ? bot_known_killer(A) : null

/// "Who's killing everyone?" and "who's alive?", from somebody who isn't a bot (bot_chatter.dm on_heard_speech()). TRUE if it answered, or
/// somebody else just has.
/datum/bot_brain/proc/answer_massacre_question(mob/living/talker, lower_msg, radio_freq)
	var/msg = replacetext(lower_msg, "&#39;", "'")
	var/prefix = radio_freq ? ";" : ""
	if(bot_text_has_any(msg, list("who's killing", "whos killing", "who is killing", "who's doing this", "whos doing this", "who did this", "who killed", "who's the killer", "whos the killer", "who's murdering", "whos murdering")))
		var/asker = REF(talker)
		if(world.time < (GLOB.bot_killer_answered[asker] || -1000) + 10 SECONDS)
			return TRUE
		GLOB.bot_killer_answered[asker] = world.time
		var/mob/living/carbon/human/killer = bot_known_killer(gym_run ? get_area(owner) : null)
		if(!killer)
			say_after_typing(prefix + pick("No idea. Stay in groups.", "Don't know. Keep your eyes open.", "Haven't seen who."))
		else if(killer == talker)
			say_after_typing(prefix + pick("You are!", "YOU are, [killer.first_name()]!", "It's you, you psycho!", "You! Everybody, it's [killer.name]!"))
		else
			say_after_typing(prefix + pick("[killer.name]! Last I heard, [get_area_name(killer, TRUE)].", "It's [killer.name]. Stay away from them.", "[killer.name]'s the one. Keep clear."))
		bot_log(src, "asked who's doing the killing: [killer || "nobody known"]")
		return TRUE
	if(bot_text_has_any(msg, list("who's alive", "whos alive", "who is alive", "anyone alive", "anybody alive", "anyone left", "anybody left", "who's left", "whos left")))
		var/asker = REF(talker)
		if(world.time > GLOB.bot_alive_answers_until[asker])
			GLOB.bot_alive_answers_until[asker] = world.time + 15 SECONDS
			GLOB.bot_alive_answers[asker] = 0
		if(GLOB.bot_alive_answers[asker] >= 3)
			return TRUE
		GLOB.bot_alive_answers[asker] += 1
		var/mob/living/carbon/human/killer = bot_known_killer(gym_run ? get_area(owner) : null)
		if(killer && killer == talker) //not telling the killer where it is
			say_after_typing(prefix + pick("Not telling you.", "Why, so you can finish us off?", "Stay away from us, [talker.first_name()]."))
		else
			say_after_typing(prefix + pick("Me. [get_area_name(owner, TRUE)].", "[owner.first_name()] here, [get_area_name(owner, TRUE)].", "Still here. [get_area_name(owner, TRUE)]."))
		return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Sticking together
// ---------------------------------------------------------------------------------------------

/datum/bot_brain
	/// When it last got to somebody to stick with, and until when it's done with that for a while (the duty below)
	var/group_up_since = 0
	var/group_up_rest_until = 0

/// Two of the crew near it, up and about, not the killer: safety in numbers. One will do if there's hardly anybody left.
/datum/bot_brain/proc/with_company(mob/living/carbon/human/killer)
	var/found = 0
	for(var/mob/living/carbon/human/H in view(4, owner))
		if(H == owner || H == killer || H.stat != CONSCIOUS || !H.mind?.assigned_role)
			continue
		if(++found >= 2)
			return TRUE
	return found && bot_crew_standing(owner.z, gym_run ? get_area(owner) : null) <= 4

/// How many of the crew are up and about on this level
/proc/bot_crew_standing(z, area/only_in)
	. = 0
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H.z == z && H.stat == CONSCIOUS && H.mind?.assigned_role && (!only_in || get_area(H) == only_in))
			. += 1

/// The best spot to join others at: next to whoever has the most company, not near the killer, and not too far.
/datum/bot_brain/proc/group_to_join(mob/living/carbon/human/killer)
	var/turf/best
	var/best_score
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H == owner || H == killer || H.z != owner.z || H.stat != CONSCIOUS || !H.mind?.assigned_role || !isturf(H.loc))
			continue
		if(gym_run && get_area(H) != get_area(owner))
			continue
		var/dist = get_dist(owner, H)
		if(dist > 60 || (killer && get_dist(H, killer) <= 7))
			continue
		var/company = 0
		for(var/mob/living/carbon/human/other in range(3, H))
			if(other != H && other != owner && other != killer && other.stat == CONSCIOUS)
				company++
		var/score = company * 10 - dist
		if(!best || score > best_score)
			best = get_turf(H)
			best_score = score
	return best

/datum/bot_duty/group_up
	name = "sticking together"
	tier = BOT_DUTY_URGENT
	priority = 60
	interval_min = 15
	interval_max = 30

/datum/bot_duty/group_up/try_start(datum/bot_brain/bot)
	if(world.time < bot.group_up_rest_until || bot.is_security_job() || bot.bot_traitor || bot.op_team || bot.gone_loud() || bot.fights_back_now())
		return FALSE
	if(bot.state == BOT_STATE_COMBAT || istype(bot.current_goal, /datum/bot_goal/group_up))
		return FALSE
	var/mob/living/carbon/human/killer = bot.massacre_killer()
	if(!killer || killer == bot.owner)
		return FALSE
	if(bot.with_company(killer))
		bot.group_up_since = world.time
		bot.holding_duty = src
		bot_log(bot, "staying with the others while [killer] is about")
		return FALSE
	var/datum/bot_goal/group_up/G = new()
	G.killer = WEAKREF(killer)
	return bot.assign_goal(G)

/// Stays with them while the killer's about, three minutes at a time; then a couple of minutes for what can't wait.
/datum/bot_duty/group_up/keep_holding(datum/bot_brain/bot)
	var/mob/living/carbon/human/killer = bot.massacre_killer()
	if(killer && bot.state != BOT_STATE_COMBAT && world.time < bot.group_up_since + 3 MINUTES && bot.with_company(killer))
		return TRUE
	bot.group_up_rest_until = world.time + 2 MINUTES
	return FALSE

/datum/bot_goal/group_up
	doing = "getting to the others"
	var/datum/weakref/killer

/datum/bot_goal/group_up/resolve_target(datum/bot_brain/bot)
	target = bot.group_to_join(killer?.resolve())
	if(target && !bot.can_walk_lawfully_to(target))
		target = null

/datum/bot_goal/group_up/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/group_up/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

/datum/bot_goal/group_up/on_success(datum/bot_brain/bot)
	bot.group_up_since = world.time
	bot.holding_duty = bot_duty_of(/datum/bot_duty/group_up)
	bot_log(bot, "with the others now")
	if(prob(40))
		bot_say(bot.owner, pick("Stick together, everyone.", "Safer with you lot.", "Mind if I stay here?", "Nobody goes off alone."))

/datum/bot_strategy/group_up/is_feasible(datum/bot_brain/bot)
	return TRUE
