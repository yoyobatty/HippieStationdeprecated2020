// Bot Gym scenarios for the human stand-in work of 2026-11-12: how bots type (bot_typing.dm), what they remember and pass on,
// who they like, what they'll do when asked, and how they talk among themselves.

// ---------------------------------------------------------------------------------------------
// Typing
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chat/typing
	time_limit = 10 SECONDS

/// Lines typed by the bot as a style would type them, slips off unless asked for.
/datum/bot_scenario/chat/typing/proc/typed(style, line, in_character = FALSE, slips = 0)
	brain.typing_in_gym = TRUE
	brain.chat_style = style
	brain.typing_shortcuts = list()
	if(style == 3)
		brain.typing_shortcuts = GLOB.bot_typing_shortcuts + GLOB.bot_typing_sloppy_shortcuts
		var/list/keys = list()
		for(var/key in GLOB.bot_typing_shortcuts)
			keys += key
		for(var/key in GLOB.bot_typing_sloppy_shortcuts)
			keys += key
		brain.typing_shortcuts = keys
	brain.typo_chance = slips
	brain.typo_fix_chance = 0
	. = brain.in_own_words(line, in_character)
	log_line("style [style]: \"[line]\" -> \"[.]\"")

/datum/bot_scenario/chat/typing/sloppy
	name = "typing: a sloppy typist types like a player"
	desc = "A sloppy typist's lines come out the way players text: lower case, no full stop or apostrophes, its shortcuts (idk, prob, sec, u, r u), and a short call for help mid-fight in capitals. A careful typist's line comes out as written, and so do code words whatever the style."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")

/datum/bot_scenario/chat/typing/sloppy/check()
	var/list/want = list(
		"I don't know, probably Security." = "idk prob sec",
		"Are you okay?" = "r u ok?",
		";Medbay is quiet for once." = ";med is quiet for once",
		"Thanks, see you later." = "thx cya later",
	)
	for(var/line in want)
		var/got = typed(3, line)
		if(got != want[line])
			fail_reason = "sloppy: \"[line]\" came out \"[got]\", wanted \"[want[line]]\""
			return BOT_GYM_FAIL
	brain.state = BOT_STATE_COMBAT
	var/shout = typed(3, ";Help! Security!")
	brain.state = BOT_STATE_WANDER
	if(shout != ";HELP SEC")
		fail_reason = "a sloppy typist's call for help mid-fight came out \"[shout]\", wanted \";HELP SEC\""
		return BOT_GYM_FAIL
	var/careful = typed(1, "I don't know, probably Security.")
	if(careful != "I don't know, probably Security.")
		fail_reason = "a careful typist's line changed: \"[careful]\""
		return BOT_GYM_FAIL
	var/code = typed(3, "Have you seen the Captain?", TRUE)
	if(findtext(code, "cap ") || findtext(code, " u "))
		fail_reason = "code words were shortened: \"[code]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/chat/typing/slips
	name = "typing: a slip is one word, put right with word*"
	desc = "With a slip certain, a line comes out with exactly one longer word mistyped, and the right spelling of that word follows it as \"word*\" a second or two later, the way players put a typo right."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 8 SECONDS
	var/said
	var/list/heard = list()

/datum/bot_scenario/chat/typing/slips/post_spawn()
	..()
	RegisterSignal(bot, COMSIG_MOB_SAY, PROC_REF(on_say))
	addtimer(CALLBACK(src, PROC_REF(type_it)), 1 SECONDS)

/datum/bot_scenario/chat/typing/slips/proc/on_say(datum/source, list/speech_args)
	SIGNAL_HANDLER
	heard += speech_args[SPEECH_MESSAGE]

/datum/bot_scenario/chat/typing/slips/proc/type_it()
	typed(1, "Somebody should really check the engine before lunch.", FALSE, 100)
	brain.typo_chance = 100
	brain.typo_fix_chance = 100
	said = brain.in_own_words("Somebody should really check the engine before lunch.")
	log_line("typed: \"[said]\"")

/datum/bot_scenario/chat/typing/slips/check()
	if(!said)
		return BOT_GYM_PENDING
	var/list/was = splittext("Somebody should really check the engine before lunch.", " ")
	var/list/now = splittext(said, " ")
	if(length(was) != length(now))
		fail_reason = "the slip changed the words: \"[said]\""
		return BOT_GYM_FAIL
	var/wrong
	for(var/i in 1 to length(was))
		if(was[i] != now[i])
			if(wrong)
				fail_reason = "more than one word mistyped: \"[said]\""
				return BOT_GYM_FAIL
			wrong = was[i]
	if(!wrong)
		fail_reason = "no slip with a certain chance: \"[said]\""
		return BOT_GYM_FAIL
	for(var/line in heard)
		if(cmptext(line, "[wrong]*")) //say() puts a capital on it
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// What it saw, and what it was told (bot_memory.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chat/memory
	time_limit = 20 SECONDS
	var/mob/living/carbon/human/killer
	var/mob/living/carbon/human/victim
	var/asked_at
	/// Lines said before the question: the transcript has every bot's in the arena
	var/said_before = 0

/datum/bot_scenario/chat/memory/post_spawn()
	..()
	killer = stand_in(first_marker("K"), "Kim Killer")
	victim = stand_in(first_marker("Y"), "Yuri Victim")
	addtimer(CALLBACK(src, PROC_REF(the_killing)), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(ask)), 6 SECONDS)

/datum/bot_scenario/chat/memory/proc/the_killing()
	if(QDELETED(victim) || QDELETED(killer))
		return
	log_line("Kim kills Yuri")
	victim.last_assailant = killer.real_name
	victim.last_assailant_at = world.time
	victim.death()

/datum/bot_scenario/chat/memory/proc/ask()
	asked_at = world.time
	said_before = length(spoken())
	visitor_says("Hey [bot.first_name()], who killed Yuri?")

/// The first thing it said after it was asked.
/datum/bot_scenario/chat/memory/proc/answer()
	if(!asked_at)
		return null
	var/list/lines = spoken()
	for(var/i in length(lines) to said_before + 1 step -1)
		var/line = lines[i]
		if(findtext(line, "Kim") || findtext(line, "idea") || findtext(line, "see") || findtext(line, "saw") || findtext(line, "know") || findtext(line, "there"))
			return line
	return null

/datum/bot_scenario/chat/memory/saw_it
	name = "memory: says who killed somebody it saw killed, and that it saw it"
	desc = "Kim kills Yuri in front of the bot. Asked who killed Yuri, it names Kim and says it saw it, instead of taking the question for news of a death."
	layout = list(
		"#########",
		"#B.C.K.Y#",
		"#########")

/datum/bot_scenario/chat/memory/saw_it/check()
	var/line = answer()
	if(!line)
		return BOT_GYM_PENDING
	if(findtext(line, "Kim") && (findtext(line, "saw") || findtext(line, "there")))
		return BOT_GYM_PASS
	fail_reason = "answered \"[line]\""
	return BOT_GYM_FAIL

/datum/bot_scenario/chat/memory/didnt_see
	name = "memory: doesn't know who killed somebody behind a wall"
	desc = "Kim kills Yuri in the next room. Asked who did it, the bot says it doesn't know, and names nobody: no omniscience."
	layout = list(
		"###########",
		"#B.C.#K..Y#",
		"###########")

/datum/bot_scenario/chat/memory/didnt_see/check()
	var/line = answer()
	if(!line)
		return BOT_GYM_PENDING
	if(findtext(line, "Kim"))
		fail_reason = "named the killer it never saw: \"[line]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/chat/memory/heard_it
	name = "memory: passes on who did it, and who it heard it from"
	desc = "Alex sees Kim kill Yuri in the next room, comes over and makes small talk with the bot. Asked who killed Yuri, the bot names Kim and says Alex told it."
	layout = list(
		"############",
		"#B.CH#A.K.Y#",
		"############")
	time_limit = 25 SECONDS
	var/mob/living/carbon/human/witness

/datum/bot_scenario/chat/memory/heard_it/post_spawn()
	witness = second_bot(first_marker("A"), "Alex Witness")
	witness.bot_brain.sociability = 0.9
	..()
	addtimer(CALLBACK(src, PROC_REF(come_over)), 4 SECONDS)

/datum/bot_scenario/chat/memory/heard_it/ask()
	addtimer(CALLBACK(src, PROC_REF(ask_now)), 4 SECONDS) //after the chat

/datum/bot_scenario/chat/memory/heard_it/proc/ask_now()
	asked_at = world.time
	said_before = length(spoken())
	visitor_says("Hey [bot.first_name()], who killed Yuri?")

/datum/bot_scenario/chat/memory/heard_it/proc/come_over()
	if(QDELETED(witness))
		return
	witness.forceMove(first_marker("H"))
	log_line("Alex comes over and chats")
	witness.bot_brain.make_small_talk(bot)

/datum/bot_scenario/chat/memory/heard_it/check()
	var/line = answer()
	if(!line)
		return BOT_GYM_PENDING
	if(findtext(line, "Kim") && findtext(line, "Alex"))
		return BOT_GYM_PASS
	fail_reason = "answered \"[line]\""
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// Friends (bot_social.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chat/friends
	time_limit = 15 SECONDS

/datum/bot_scenario/chat/friends/backs_a_friend
	name = "friends: a timid bot steps in when its friend is attacked"
	desc = "A bot with little nerve (0.3) sees Gus punch Frankie, its friend. Somebody that timid stays out of a stranger's fight; for a friend it steps in."
	layout = list(
		"#########",
		"#B.C.G.F#",
		"#########")
	var/mob/living/carbon/human/griefer
	var/mob/living/carbon/human/friend

/datum/bot_scenario/chat/friends/backs_a_friend/post_spawn()
	..()
	brain.nerve = 0.3
	griefer = stand_in(first_marker("G"), "Gus Griefer")
	friend = stand_in(first_marker("F"), "Frankie Friend")
	brain.regard = list("Frankie Friend" = 6)
	addtimer(CALLBACK(src, PROC_REF(punch)), 2 SECONDS)

/datum/bot_scenario/chat/friends/backs_a_friend/proc/punch()
	log_line("Gus punches Frankie")
	bot_record_aggression(griefer, friend)
	bot_crew_witness_combat(griefer, friend, "punched", null)

/datum/bot_scenario/chat/friends/backs_a_friend/check()
	if(brain.attacker == griefer)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/friends/opinion
	name = "friends: says what it thinks of somebody, and why"
	desc = "Gus punched the bot earlier. Asked what it thinks of Gus, it says it can't stand him and why, rather than \"Beats me.\""
	layout = list(
		"#########",
		"#B.C.G..#",
		"#########")
	var/mob/living/carbon/human/griefer

/datum/bot_scenario/chat/friends/opinion/post_spawn()
	..()
	griefer = stand_in(first_marker("G"), "Gus Griefer")
	brain.regard = list("Gus Griefer" = -6)
	brain.regard_why = list("Gus Griefer" = "punched me")
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Hey [bot.first_name()], what do you think of Gus?"), 2 SECONDS)

/datum/bot_scenario/chat/friends/opinion/check()
	for(var/line in spoken())
		if(findtext(line, "punched"))
			return BOT_GYM_PASS
		fail_reason = "answered \"[line]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Favours (bot_favours.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chat/favour
	time_limit = 25 SECONDS

/// "the annex" is the Q marker
/datum/bot_scenario/chat/favour/named_spot(lower_msg)
	return findtext(lower_msg, "annex") ? first_marker("Q") : null

/datum/bot_scenario/chat/favour/proc/ask(line)
	visitor_says("Hey [bot.first_name()], [line]")

/datum/bot_scenario/chat/favour/guide
	name = "favours: shows somebody the way, and waits when they fall behind"
	desc = "Asked to take the visitor to the annex, the bot sets off, stops and calls them on when they don't follow, and only goes the rest of the way once they've caught up."
	layout = list(
		"####################",
		"#CB...............Q#",
		"####################")
	time_limit = 40 SECONDS
	var/hurried = FALSE
	var/caught_up = FALSE

/datum/bot_scenario/chat/favour/guide/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(ask), "take me to the annex?"), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(catch_up)), 14 SECONDS)

/datum/bot_scenario/chat/favour/guide/proc/catch_up()
	if(QDELETED(visitor) || QDELETED(bot))
		return
	caught_up = TRUE
	log_line("visitor catches up, and follows from here on")
	visitor.forceMove(get_step(bot, WEST))
	walk_to(visitor, bot, 1, 2)

/datum/bot_scenario/chat/favour/guide/release_run()
	if(visitor)
		walk(visitor, 0)
	return ..()

/datum/bot_scenario/chat/favour/guide/check()
	for(var/line in spoken())
		if(findtext(line, "keep up") || findtext(line, "This way") || findtext(line, "Over here") || findtext(line, "coming?"))
			hurried = TRUE
	if(get_dist(bot, first_marker("Q")) <= 1)
		if(!caught_up)
			fail_reason = "got there and left the visitor behind"
			return BOT_GYM_FAIL
		if(!hurried)
			fail_reason = "never called them on"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/favour/bring
	name = "favours: brings over a tool it has when asked"
	desc = "The visitor, four tiles off, asks for a wrench. The bot has one in its bag: it walks over and sets it down by them."
	layout = list(
		"#########",
		"#B...C..#",
		"#########")
	kit_backpack = list(/obj/item/wrench)

/datum/bot_scenario/chat/favour/bring/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(ask), "bring me a wrench?"), 2 SECONDS)

/datum/bot_scenario/chat/favour/bring/check()
	for(var/turf/T in range(1, visitor))
		if(locate(/obj/item/wrench) in T)
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/favour/not_for_you
	name = "favours: won't fetch for somebody it can't stand"
	desc = "The visitor punched the bot earlier. Asked for its wrench, it says no and keeps it."
	layout = list(
		"#########",
		"#B...C..#",
		"#########")
	kit_backpack = list(/obj/item/wrench)
	time_limit = 12 SECONDS

/datum/bot_scenario/chat/favour/not_for_you/post_spawn()
	..()
	brain.regard = list("[visitor.real_name]" = -6)
	addtimer(CALLBACK(src, PROC_REF(ask), "bring me a wrench?"), 2 SECONDS)

/datum/bot_scenario/chat/favour/not_for_you/check()
	if(!brain.find_carried_tool(/obj/item/wrench))
		fail_reason = "handed it over"
		return BOT_GYM_FAIL
	if(length(spoken()) && world.time > start_time + 9 SECONDS)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/favour/for_a_friend
	name = "favours: a shy bot still fetches for a friend"
	desc = "A bot that keeps to itself (sociability 0.1) won't run errands for strangers, but its friend asks for its wrench and gets it."
	layout = list(
		"#########",
		"#B...C..#",
		"#########")
	kit_backpack = list(/obj/item/wrench)

/datum/bot_scenario/chat/favour/for_a_friend/post_spawn()
	..()
	brain.sociability = 0.1
	brain.regard = list("[visitor.real_name]" = 6)
	addtimer(CALLBACK(src, PROC_REF(ask), "bring me a wrench?"), 2 SECONDS)

/datum/bot_scenario/chat/favour/for_a_friend/check()
	for(var/turf/T in range(1, visitor))
		if(locate(/obj/item/wrench) in T)
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/favour/call_sec
	name = "favours: asked to call Security, it radios for them"
	desc = "\"Call security!\" to its face: it gets on the radio and asks for Security where the visitor is."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 12 SECONDS

/datum/bot_scenario/chat/favour/call_sec/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(ask), "call security!"), 2 SECONDS)

/datum/bot_scenario/chat/favour/call_sec/check()
	for(var/line in spoken())
		if(copytext(line, 1, 2) == ";" && findtext(line, "Security"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/favour/stay
	name = "favours: told to wait here, it waits until told it can go"
	desc = "\"Wait here\": the bot takes on waiting there, and drops it when the visitor says it can go."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 15 SECONDS
	var/waited = FALSE

/datum/bot_scenario/chat/favour/stay/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(ask), "wait here."), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(ask), "ok you can go."), 8 SECONDS)

/datum/bot_scenario/chat/favour/stay/check()
	if(istype(brain.current_goal, /datum/bot_goal/favour/stay))
		waited = TRUE
		return BOT_GYM_PENDING
	if(waited && world.time > start_time + 9 SECONDS)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING
