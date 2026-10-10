// Bot Gym scenarios for talking (bot_chatter.dm). A stand-in crew member with nobody driving it (C)
// does the asking; the bot is given no goal and judged on what it says and does about it.

/datum/bot_scenario/chat
	time_limit = 20 SECONDS
	var/mob/living/carbon/human/visitor

/datum/bot_scenario/chat/issue_goal()
	return

/datum/bot_scenario/chat/post_spawn()
	visitor = stand_in(first_marker("C"), "Casey Visitor")
	visitor.setDir(get_dir(visitor, bot))

/datum/bot_scenario/proc/stand_in(turf/T, name)
	var/mob/living/carbon/human/H = new(T)
	H.real_name = name
	H.name = name
	H.equipOutfit(/datum/outfit/bot_gym)
	return H

/datum/bot_scenario/chat/proc/visitor_says(line)
	if(result != BOT_GYM_PENDING || QDELETED(visitor))
		return
	log_line("visitor: \"[line]\"")
	visitor.say(line)

/// The lines the bot has spoken so far, read back out of its transcript.
/datum/bot_scenario/chat/proc/spoken()
	. = list()
	for(var/line in transcript)
		var/at = findtext(line, "said \"")
		if(!at)
			continue
		var/rest = copytext(line, at + 6)
		. += copytext(rest, 1, findtext(rest, "\""))

/datum/bot_scenario/chat/asked_what_doing
	name = "chat: says what it's up to when asked by name"
	desc = "A crew member two tiles away asks the bot by its first name what it's doing. It answers the question - not a stock \"you called?\" - after about as long as the answer takes to type."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	var/asked_at

/datum/bot_scenario/chat/asked_what_doing/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/chat/asked_what_doing/proc/ask()
	asked_at = world.time
	visitor_says("Hey [bot.first_name()], what are you doing?")

/datum/bot_scenario/chat/asked_what_doing/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/lines = spoken()
	if(!length(lines))
		return BOT_GYM_PENDING
	if(lines[1] in GLOB.bot_name_called_lines)
		fail_reason = "answered its name but not the question: \"[lines[1]]\""
		return BOT_GYM_FAIL
	if(world.time - asked_at < 5)
		fail_reason = "answered in [(world.time - asked_at) / 10]s - nobody types that fast"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/chat/not_meant_for_it
	name = "chat: stays out of talk that isn't for it"
	desc = "Two crew members talk to each other next to the bot, without its name. It doesn't chip in."
	layout = list(
		"#######",
		"#B.CN.#",
		"#######")
	time_limit = 12 SECONDS
	var/mob/living/carbon/human/bystander

/datum/bot_scenario/chat/not_meant_for_it/post_spawn()
	..()
	bystander = stand_in(first_marker("N"), "Robin Bystander")
	visitor.setDir(EAST)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "I think the engine is running fine now."), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Anyway, I should get back to work."), 6 SECONDS)

/datum/bot_scenario/chat/not_meant_for_it/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/lines = spoken()
	if(length(lines))
		fail_reason = "butted in with \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/not_meant_for_it/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/chat/tags_along
	name = "chat: comes along when asked, until thanked"
	desc = "A crew member says \"follow me\" and walks down the corridor. The bot agrees, keeps up, and goes back to its own business when told thanks."
	layout = list(
		"###############",
		"#B.C.........G#",
		"###############")
	time_limit = 40 SECONDS
	var/thanked = FALSE

/datum/bot_scenario/chat/tags_along/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Follow me."), 1 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(walk_on)), 4 SECONDS)

/datum/bot_scenario/chat/tags_along/proc/walk_on()
	if(result != BOT_GYM_PENDING || QDELETED(visitor))
		return
	if(get_turf(visitor) == first_marker("G"))
		return
	visitor.setDir(EAST)
	step(visitor, EAST)
	addtimer(CALLBACK(src, PROC_REF(walk_on)), 4)

/datum/bot_scenario/chat/tags_along/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(get_turf(visitor) != first_marker("G"))
		return BOT_GYM_PENDING
	if(!thanked)
		if(get_dist(bot, visitor) > 2)
			return BOT_GYM_PENDING //still catching up
		if(!istype(brain.current_goal, /datum/bot_goal/tag_along))
			fail_reason = "ended up beside them without ever agreeing to come"
			return BOT_GYM_FAIL
		thanked = TRUE
		visitor.setDir(get_dir(visitor, bot))
		visitor_says("Thanks, that's all.")
		return BOT_GYM_PENDING
	if(brain.state == BOT_STATE_WANDER && !brain.current_goal)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/small_talk
	name = "chat: two bots make small talk"
	desc = "One bot says something to the bot standing next to it, and gets an answer a moment later - one line each, not a stock reply on top."
	layout = list(
		"######",
		"#B.C.#",
		"######")
	var/datum/bot_brain/friend

/datum/bot_scenario/chat/small_talk/post_spawn()
	..()
	friend = new(visitor)
	friend.gym_run = src
	friend.gym_scripted = TRUE
	addtimer(CALLBACK(src, PROC_REF(open_up)), 2 SECONDS)

/datum/bot_scenario/chat/small_talk/proc/open_up()
	if(result == BOT_GYM_PENDING && !QDELETED(visitor))
		brain.make_small_talk(visitor)

/datum/bot_scenario/chat/small_talk/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/lines = spoken()
	if(length(lines) < 2)
		return BOT_GYM_PENDING
	if(length(lines) > 2)
		fail_reason = "[length(lines)] lines for one exchange: [jointext(lines, " / ")]"
		return BOT_GYM_FAIL
	// Give a stray extra reply a few seconds to turn up before calling it clean.
	if(world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	return BOT_GYM_PASS
