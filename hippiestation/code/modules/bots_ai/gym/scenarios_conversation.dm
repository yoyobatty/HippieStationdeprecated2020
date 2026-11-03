// Talking back (bot_conversation.dm). The same set-up as scenarios_chat.dm: a stand-in nobody's driving does the talking.

/datum/bot_scenario/chat/insulted
	name = "chat: a short-tempered bot insulted to its face warns, then shoves"
	desc = "Somebody right next to it calls it names, three times. A bot with a short fuse answers the first, warns at the next, and shoves after that."
	layout = list(
		"######",
		"#.BC.#",
		"######")
	var/bot_temper = 0.9

/datum/bot_scenario/chat/insulted/post_spawn()
	..()
	brain.temper = bot_temper
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "You're an idiot, [bot.first_name()]."), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Shut up, moron."), 5 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "You're useless, [bot.first_name()]."), 8 SECONDS)

/datum/bot_scenario/chat/insulted/proc/shoved()
	for(var/line in spoken())
		if(line in list("That's it.", "Say that again.", "Keep it up."))
			return TRUE
	return FALSE

/datum/bot_scenario/chat/insulted/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return shoved() ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chat/insulted/calm
	name = "chat: an easygoing bot insulted to its face never shoves"
	desc = "The same three insults at a bot with a long fuse. It answers, and lets it go."
	bot_temper = 0.15

/datum/bot_scenario/chat/insulted/calm/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(shoved())
		fail_reason = "shoved somebody for words: [english_list(spoken())]"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/insulted/calm/on_timeout()
	if(!length(spoken()))
		fail_reason = "said nothing back"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/chat/where_is_captain
	name = "chat: asked where the Captain is, it says where the Captain works"
	desc = "The Captain is out of sight in the next room. Asked where the Captain is, the bot can't see them, so it says where they'd be: the Bridge."
	layout = list(
		"#########",
		"#B.C#.K.#",
		"#########")
	var/mob/living/carbon/human/captain

/datum/bot_scenario/chat/where_is_captain/post_spawn()
	..()
	captain = stand_in(first_marker("K"), "Avery Captain")
	captain.mind_initialize()
	captain.mind.assigned_role = "Captain"
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Hey [bot.first_name()], where's the captain?"), 2 SECONDS)

/datum/bot_scenario/chat/where_is_captain/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/lines = spoken()
	if(!length(lines))
		return BOT_GYM_PENDING
	if(!findtext(lines[1], "Bridge"))
		fail_reason = "answered \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
