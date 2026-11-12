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

// ---------------------------------------------------------------------------------------------
// Conversations (bot_threads.dm) and banter (bot_banter.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chat/thread
	time_limit = 40 SECONDS
	var/mob/living/carbon/human/other
	var/mob/living/carbon/human/killer
	var/mob/living/carbon/human/victim

/datum/bot_scenario/chat/thread/post_spawn()
	..()
	other = second_bot(first_marker("A"), "Alex Other")
	brain.threads_in_gym = TRUE
	brain.sociability = 0.9
	killer = stand_in(first_marker("K"), "Kim Killer")
	victim = stand_in(first_marker("Y"), "Yuri Victim")
	brain.thread_topic_wanted = "gossip"
	addtimer(CALLBACK(src, PROC_REF(the_killing)), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(talk)), 4 SECONDS)

/datum/bot_scenario/chat/thread/proc/the_killing()
	victim.last_assailant = killer.real_name
	victim.last_assailant_at = world.time
	victim.death()
	other.forceMove(get_step(bot, EAST)) //Alex was looking the other way: it hears it from the bot
	other.bot_brain.facts = null

/datum/bot_scenario/chat/thread/proc/talk()
	other.bot_brain.facts = null //it saw it too, from where it ended up: it hasn't, for this
	if(!brain.start_thread(other))
		fail_reason = "no conversation started"
		result = BOT_GYM_FAIL

/datum/bot_scenario/chat/thread/gossip
	name = "threads: gossip goes back and forth, and the news passes on"
	desc = "The bot saw Kim kill Yuri. It tells Alex: more than one line each way (a question about it and an answer), and Alex knows it afterwards, from the bot."
	layout = list(
		"##########",
		"#B.A.K.YC#",
		"##########")

/datum/bot_scenario/chat/thread/gossip/check()
	if(length(spoken()) < 3)
		return BOT_GYM_PENDING
	for(var/key in other.bot_brain.facts)
		var/datum/bot_fact/F = other.bot_brain.facts[key]
		if(F.kind == BOT_FACT_KILLED && F.source == bot.real_name)
			return BOT_GYM_PASS
	fail_reason = "three lines, but Alex doesn't know who did it"
	return BOT_GYM_FAIL

/datum/bot_scenario/chat/thread/joined
	var/asked = FALSE
	name = "threads: a player puts in \"who told you?\" and gets an answer"
	desc = "The bot is telling Alex who killed Yuri. The visitor, stood by, asks \"who told you?\": the bot says it saw it itself."
	layout = list(
		"##########",
		"#B.A.K.YC#",
		"##########")
	var/said_before = 0

/datum/bot_scenario/chat/thread/joined/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(put_in)), 7 SECONDS)

/datum/bot_scenario/chat/thread/joined/proc/put_in()
	asked = TRUE
	said_before = length(spoken())
	visitor.forceMove(get_step(other, EAST))
	visitor_says("who told you?")

/datum/bot_scenario/chat/thread/joined/check()
	if(!asked)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	for(var/i in said_before + 1 to length(lines))
		var/line = lines[i]
		if(findtext(line, " to Alex") || findtext(line, " to Gym"))
			continue //the conversation itself, not the answer
		if(findtext(line, "saw it") || findtext(line, "Saw it") || findtext(line, "right there"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/banter
	time_limit = 15 SECONDS

/datum/bot_scenario/chat/banter/joke
	time_limit = 25 SECONDS
	name = "banter: tells a joke when asked, and the punchline after"
	desc = "\"Tell me a joke\": a joke's setup, and its punchline a few seconds later."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")

/datum/bot_scenario/chat/banter/joke/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Hey [bot.first_name()], tell me a joke"), 2 SECONDS)

/datum/bot_scenario/chat/banter/joke/check()
	var/list/lines = spoken()
	if(length(lines) < 2)
		return BOT_GYM_PENDING
	for(var/list/J as anything in GLOB.bot_jokes)
		if(lines[1] == J[1] && lines[2] == J[2])
			return BOT_GYM_PASS
	fail_reason = "said \"[lines[1]]\" then \"[lines[2]]\""
	return BOT_GYM_FAIL

/datum/bot_scenario/chat/banter/flirt_rebuffed
	name = "banter: flirting from somebody it can't stand gets turned down"
	desc = "The visitor punched the bot earlier and now says \"you're cute\". It turns them down instead of saying thanks."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")

/datum/bot_scenario/chat/banter/flirt_rebuffed/post_spawn()
	..()
	brain.regard = list("[visitor.real_name]" = -6)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Hey [bot.first_name()], you're cute"), 2 SECONDS)

/datum/bot_scenario/chat/banter/flirt_rebuffed/check()
	for(var/line in spoken())
		if(line in list("Gross.", "No.", "Not in a million years.", "Get away from me."))
			return BOT_GYM_PASS
		fail_reason = "answered \"[line]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Breaks (bot_hangouts.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chat/break_time
	name = "breaks: sits down for a break and orders a drink"
	desc = "Sent on a break in the arena, the bot walks to the chair, sits, and asks the bartender for a drink out loud."
	layout = list(
		"#########",
		"#B...H.C#",
		"#########")
	time_limit = 30 SECONDS
	var/sat = FALSE
	var/ordered = FALSE

/datum/bot_scenario/chat/break_time/post_spawn()
	..()
	new /obj/structure/chair(first_marker("H"))
	visitor.mind_initialize()
	visitor.mind.assigned_role = "Bartender"
	addtimer(CALLBACK(src, PROC_REF(send_on_break)), 2 SECONDS)

/datum/bot_scenario/chat/break_time/proc/send_on_break()
	if(!brain.go_on_break(arena_area))
		fail_reason = "didn't go"
		result = BOT_GYM_FAIL

/datum/bot_scenario/chat/break_time/check()
	if(!sat)
		if(bot.buckled && brain.on_break())
			sat = TRUE
			log_line("sat down")
			brain.order_at_the_bar(TRUE)
		return BOT_GYM_PENDING
	for(var/line in spoken())
		if(findtext(line, "please") || findtext(line, "Can I get") || findtext(line, "over here"))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Comings and goings (bot_comings.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chat/logoff
	name = "comings: logs off, reads as disconnected, and comes back the same person"
	desc = "Its player leaves for a bit: the body stays and examines as anybody disconnected does (\"a blank, absent-minded stare\"), with no brain on it. When they come back it's the same brain, back at work."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 15 SECONDS
	var/datum/bot_brain/was
	var/stage = 0

/datum/bot_scenario/chat/logoff/post_spawn()
	..()
	bot.key = "bot-gym-logoff-[run_index]" //a live round's bots have one (bot_identity.dm); the gym's don't
	was = brain
	addtimer(CALLBACK(src, PROC_REF(leave)), 2 SECONDS)

/datum/bot_scenario/chat/logoff/proc/leave()
	was.coming_back = TRUE
	was.go_now()

/datum/bot_scenario/chat/logoff/check()
	switch(stage)
		if(0)
			if(bot.bot_brain || !was.logged_off)
				return BOT_GYM_PENDING
			var/seen = jointext(bot.examine(visitor), " ")
			if(!findtext(seen, "absent-minded stare"))
				fail_reason = "logged off, but examines as \"[seen]\""
				return BOT_GYM_FAIL
			log_line("logged off, and looks it")
			stage = 1
			was.log_back_on()
			return BOT_GYM_PENDING
		if(1)
			if(bot.bot_brain != was || was.logged_off || !(was in GLOB.bot_brains))
				fail_reason = "didn't come back as itself"
				return BOT_GYM_FAIL
			return BOT_GYM_PASS

/datum/bot_scenario/chat/ghost
	name = "ghosts: a dead bot's ghost says who killed it, and goes when it's brought back"
	desc = "Kim kills the bot. Its ghost floats up beside the body, holding no mind, and the line it says in deadchat names Kim. Revived, the ghost is gone."
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 20 SECONDS
	var/mob/dead/observer/bot_ghost/spook
	var/revived = FALSE

/datum/bot_scenario/chat/ghost/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(die)), 2 SECONDS)

/datum/bot_scenario/chat/ghost/proc/die()
	bot.last_assailant = "Kim Killer"
	bot.last_assailant_at = world.time
	bot.death()
	brain.make_ghost() //the gym doesn't ghost on its own: other arenas' deaths would fill deadchat
	spook = brain.ghost

/datum/bot_scenario/chat/ghost/check()
	if(!spook)
		return BOT_GYM_PENDING
	if(!revived)
		if(spook.mind)
			fail_reason = "the ghost holds the mind: cloning would find it"
			return BOT_GYM_FAIL
		var/line = spook.death_line()
		if(!findtext(line, "Kim"))
			fail_reason = "its death line doesn't name the killer: \"[line]\""
			return BOT_GYM_FAIL
		log_line("ghost says \"[line]\"")
		revived = TRUE
		bot.revive(full_heal = TRUE)
		return BOT_GYM_PENDING
	return QDELETED(spook) ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Nuclear operatives, the crew's side (goals/nuke_defence.dm). Station-wide: operatives seen and red alert are the station's.
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/nukies
	station_wide = TRUE
	time_limit = 40 SECONDS
	var/mob/living/carbon/human/op
	var/obj/item/disk/nuclear/disk

/datum/bot_scenario/nukies/issue_goal()
	return

/datum/bot_scenario/nukies/named_spot(lower_msg)
	return findtext(lower_msg, "brig") ? first_marker("Q") : null

/datum/bot_scenario/nukies/post_spawn()
	brain.gym_scripted = FALSE
	op = stand_in(first_marker("O"), "Oscar Operative")
	op.equip_to_slot_or_del(new /obj/item/clothing/suit/space/hardsuit/syndi(op), ITEM_SLOT_OCLOTHING)
	GLOB.bot_ops_seen_at = world.time

/datum/bot_scenario/nukies/proc/make_disk(atom/where)
	disk = new(get_turf(where))
	qdel(disk.GetComponent(/datum/component/stationloving)) //it would take itself back to the station, off the gym's z-level
	return disk

/datum/bot_scenario/nukies/release_run()
	GLOB.bot_ops_seen_at = 0
	GLOB.bot_disk_recoverer = null
	return ..()

/datum/bot_scenario/nukies/hole_up
	name = "nukies: whoever has the disk holes up in the Brig, away from the operative"
	desc = "Operatives have been seen and the bot has the disk. It goes to the Brig and stays, instead of wandering about or going for the operative."
	layout = list(
		"##############",
		"#B..........Q#",
		"#.....#####..#",
		"#O....#......#",
		"##############")

/datum/bot_scenario/nukies/hole_up/post_spawn()
	..()
	make_disk(bot)
	if(!SEND_SIGNAL(bot.back, COMSIG_TRY_STORAGE_INSERT, disk, bot, TRUE))
		bot.put_in_inactive_hand(disk)

/datum/bot_scenario/nukies/hole_up/check()
	if(get_dist(bot, first_marker("Q")) <= 2 && brain.find_carried_tool(/obj/item/disk/nuclear))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/nukies/off_the_body
	name = "nukies: an officer takes the disk off the dead Captain"
	desc = "The Captain lies dead with the disk in a pocket and an operative's about. The officer goes over and takes it off the body."
	job = "Security Officer"
	layout = list(
		"##############",
		"#B.......K...#",
		"######.#######",
		"#O...........#",
		"##############")
	var/mob/living/carbon/human/captain

/datum/bot_scenario/nukies/off_the_body/post_spawn()
	..()
	captain = stand_in(first_marker("K"), "Cap Tain")
	captain.mind_initialize()
	captain.mind.assigned_role = "Captain"
	make_disk(captain)
	captain.equip_to_slot_or_del(disk, ITEM_SLOT_LPOCKET)
	captain.death()

/datum/bot_scenario/nukies/off_the_body/check()
	if(brain.find_carried_tool(/obj/item/disk/nuclear))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/nukies/guard
	name = "nukies: an officer keeps close to whoever has the disk"
	desc = "Operatives are about and the Captain has the disk, across the room. The officer goes and stays near the Captain."
	job = "Security Officer"
	layout = list(
		"################",
		"#B...........K.#",
		"#######.########",
		"#O.............#",
		"################")
	var/mob/living/carbon/human/captain
	var/near_since = 0

/datum/bot_scenario/nukies/guard/post_spawn()
	..()
	captain = stand_in(first_marker("K"), "Cap Tain")
	captain.mind_initialize()
	captain.mind.assigned_role = "Captain"
	make_disk(captain)
	captain.equip_to_slot_or_del(disk, ITEM_SLOT_LPOCKET)

/datum/bot_scenario/nukies/guard/check()
	if(get_dist(bot, captain) <= 4)
		if(!near_since)
			near_since = world.time
		else if(world.time > near_since + 8 SECONDS)
			return BOT_GYM_PASS //and stayed
		return BOT_GYM_PENDING
	near_since = 0
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// The wizard (goals/wizard.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/wizard_kit
	time_limit = 15 SECONDS
	layout = list(
		"###########",
		"#.........#",
		"#....B....#",
		"#.........#",
		"###########")

/datum/bot_scenario/wizard_kit/issue_goal()
	return

/datum/bot_scenario/wizard_kit/post_spawn()
	brain.bot_wizard = TRUE
	bot.equip_to_slot_or_del(new /obj/item/clothing/head/wizard(bot), ITEM_SLOT_HEAD)

/datum/bot_scenario/wizard_kit/blink_away
	name = "wizard: hurt, it takes its staff out of the bag and blinks away"
	desc = "A hurt wizard with blink and its staff in the bag. Blink needs the staff in hand here (staff_req), so it gets it out, and blinks."
	var/turf/start
	var/obj/item/staff/staff

/datum/bot_scenario/wizard_kit/blink_away/post_spawn()
	..()
	bot.equip_to_slot_or_del(new /obj/item/clothing/suit/wizrobe(bot), ITEM_SLOT_OCLOTHING)
	staff = new(bot)
	if(!SEND_SIGNAL(bot.back, COMSIG_TRY_STORAGE_INSERT, staff, bot, TRUE))
		qdel(staff)
	bot.mind.AddSpell(new /obj/effect/proc_holder/spell/targeted/turf_teleport/blink(null))
	bot.adjustBruteLoss(bot.maxHealth * 0.6)
	start = get_turf(bot)
	addtimer(CALLBACK(brain, TYPE_PROC_REF(/datum/bot_brain, wizard_escape)), 2 SECONDS)

/datum/bot_scenario/wizard_kit/blink_away/check()
	if(get_turf(bot) != start)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/wizard_kit/robe_back
	name = "wizard: robe off and on the floor, it puts it back on"
	desc = "The wizard's robe has been taken off and dropped beside it. It picks it up and puts it on again before anything else."
	var/obj/item/clothing/suit/wizrobe/robe

/datum/bot_scenario/wizard_kit/robe_back/post_spawn()
	..()
	robe = new(get_step(bot, EAST))

/datum/bot_scenario/wizard_kit/robe_back/check()
	if(bot.wear_suit == robe)
		return BOT_GYM_PASS
	brain.wizard_get_dressed()
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// The cult, from the crew's side (goals/cult_response.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/cult_seen
	time_limit = 25 SECONDS

/datum/bot_scenario/cult_seen/issue_goal()
	return

/datum/bot_scenario/cult_seen/rune_called_in
	name = "cult: a rune outside the Chapel gets called in"
	desc = "Somebody's drawn an offer rune in the room. The bot sees it and says so on the radio, with where."
	layout = list(
		"#########",
		"#B...R..#",
		"#########")

/datum/bot_scenario/cult_seen/rune_called_in/post_spawn()
	brain.gym_scripted = FALSE
	new /obj/effect/rune/convert(first_marker("R"))

/datum/bot_scenario/cult_seen/rune_called_in/check()
	if(bot_transcript_said("saw a rune"))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/cult_seen/chaplain_breaks
	time_limit = 50 SECONDS //the duty looks every 10-20 s: once for the rod, once for the rune
	name = "chaplain: breaks a reported rune with the null rod"
	desc = "A rune's been reported. The Chaplain, null rod on a table (the first Chaplain of a shift has none of its own), gets it, walks over and breaks the rune."
	job = "Chaplain"
	layout = list(
		"#########",
		"#B.....R#",
		"#########")
	var/obj/effect/rune/rune

/datum/bot_scenario/cult_seen/chaplain_breaks/post_spawn()
	brain.gym_scripted = FALSE
	var/obj/item/nullrod/rod = new(get_step(bot, EAST))
	brain.note_seen(rod, get_turf(rod)) //bot_knowledge.dm: it knows where the Chapel keeps it
	rune = new /obj/effect/rune/convert(first_marker("R"))
	GLOB.bot_runes_reported[REF(rune)] = world.time
	GLOB.bot_runes_to_clean += WEAKREF(rune)

/datum/bot_scenario/cult_seen/chaplain_breaks/check()
	return QDELETED(rune) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/cult_seen/holy_water
	name = "chaplain: makes a cuffed cultist drink holy water"
	desc = "A cultist the Chaplain saw with a cult dagger is cuffed in the room. The Chaplain, with a flask of holy water, goes over and makes them drink it."
	job = "Chaplain"
	layout = list(
		"#########",
		"#B....K.#",
		"#########")
	kit_hands = list(/obj/item/reagent_containers/food/drinks/bottle/holywater)
	var/mob/living/carbon/human/cultist

/datum/bot_scenario/cult_seen/holy_water/post_spawn()
	brain.gym_scripted = FALSE
	cultist = stand_in(first_marker("K"), "Kel Cultist")
	cultist.mind_initialize()
	var/datum/antagonist/cult/C = new
	C.ignore_implant = TRUE //a stand-in has nobody home to convert (is_convertable_to_cult())
	cultist.mind.add_antag_datum(C)
	cultist.handcuffed = new /obj/item/restraints/handcuffs(cultist)
	cultist.update_handcuffed()
	brain.learn_fact(BOT_FACT_CONTRABAND, cultist, null, "here", "ritual dagger")

/datum/bot_scenario/cult_seen/holy_water/check()
	if(cultist.reagents?.has_reagent(/datum/reagent/water/holywater))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/wizard_kit/keeps_range
	name = "wizard: a spell nearly ready, it waits at range instead of walking in to punch"
	desc = "The wizard's magic missile has a few seconds left to recharge and its target stands five tiles off. It holds where it is and casts when it's ready, rather than walking up and punching."
	layout = list(
		"###########",
		"#B.......V#",
		"###########")
	time_limit = 12 SECONDS
	var/mob/living/carbon/human/victim
	var/obj/effect/proc_holder/spell/targeted/projectile/magic_missile/missile
	var/closest = 99

/datum/bot_scenario/wizard_kit/keeps_range/post_spawn()
	..()
	bot.equip_to_slot_or_del(new /obj/item/clothing/suit/wizrobe(bot), ITEM_SLOT_OCLOTHING)
	victim = stand_in(get_step(get_step(first_marker("V"), WEST), WEST), "Vic Target")
	missile = new(null)
	bot.mind.AddSpell(missile)
	missile.charge_counter = missile.charge_max - 40 //four seconds to go
	brain.assign_goal(new /datum/bot_goal/traitor_kill/robust/wizard(null, victim))

/datum/bot_scenario/wizard_kit/keeps_range/check()
	closest = min(closest, get_dist(bot, victim))
	if(closest <= 1)
		fail_reason = "walked up to them"
		return BOT_GYM_FAIL
	if(world.time > start_time + 10 SECONDS)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/nukies/loose_disk
	name = "nukies: a disk lying out of sight, with nobody to know where, is left alone"
	desc = "The disk lies behind a wall in the next room and an operative's about. The officer can't know where it is, so it doesn't go for it, and asking where the disk is (on the floor, in a bag, in the nuke) reads nothing off it that isn't there: the first build read a name off the disk, 500 bot exceptions in the nuke batches."
	job = "Security Officer"
	layout = list(
		"##############",
		"#B.....#....D#",
		"########.#####",
		"#O...........#",
		"##############")
	time_limit = 12 SECONDS

/datum/bot_scenario/nukies/loose_disk/post_spawn()
	..()
	make_disk(first_marker("D"))

/datum/bot_scenario/nukies/loose_disk/check()
	if(brain.knows_where_disk_is(disk)) //the disk itself as what it's in, as it is lying about
		fail_reason = "knew where a disk out of sight was"
		return BOT_GYM_FAIL
	var/obj/item/storage/box/B = new(get_turf(disk))
	disk.forceMove(B)
	var/knew = brain.knows_where_disk_is(B)
	disk.forceMove(get_turf(B))
	qdel(B)
	if(knew)
		fail_reason = "knew where a box out of sight was"
		return BOT_GYM_FAIL
	if(istype(brain.current_goal, /datum/bot_goal/recover_disk))
		fail_reason = "went for a disk it couldn't know about"
		return BOT_GYM_FAIL
	return world.time > start_time + 10 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/nukies/shut_in
	name = "nukies: the disk shut in a locker in sight is left alone"
	desc = "The disk is in a shut, locked brig locker across the room and an operative's about. Nobody could know it's in there, so the officer doesn't go for it: the first build took it out through the locker's door (Cell 4 Locker, nuke batches 2026-11-12)."
	job = "Security Officer"
	layout = list(
		"##############",
		"#B......Z....#",
		"########.#####",
		"#O...........#",
		"##############")
	time_limit = 18 SECONDS
	var/obj/structure/closet/secure_closet/brig/locker

/datum/bot_scenario/nukies/shut_in/post_spawn()
	..()
	locker = new(first_marker("Z"))
	make_disk(locker)
	disk.forceMove(locker)

/datum/bot_scenario/nukies/shut_in/check()
	if(bot_outermost_holder(disk) == bot)
		fail_reason = "took the disk out through a shut locker"
		return BOT_GYM_FAIL
	if(istype(brain.current_goal, /datum/bot_goal/recover_disk))
		fail_reason = "went for a disk shut in a locker"
		return BOT_GYM_FAIL
	return world.time > start_time + 15 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/nukies/shut_in/release_run()
	QDEL_NULL(locker)
	return ..()

/datum/bot_scenario/nukies/in_the_nuke
	name = "nukies: the disk comes out of the operatives' nuke through its panel"
	desc = "The operatives' nuke stands across the room with the disk in it. The officer goes over and ejects the disk with the panel, so the nuke has no disk in it any more: the first build picked it straight out and the nuke still counted it as in (auth), so an operative could arm it with no disk."
	job = "Security Officer"
	layout = list(
		"##############",
		"#B......N....#",
		"########.#####",
		"#O...........#",
		"##############")
	time_limit = 30 SECONDS
	var/obj/machinery/nuclearbomb/syndicate/nuke

/datum/bot_scenario/nukies/in_the_nuke/post_spawn()
	..()
	nuke = new(first_marker("N"))
	make_disk(nuke)
	disk.forceMove(nuke)
	nuke.auth = disk
	nuke.update_ui_mode()

/datum/bot_scenario/nukies/in_the_nuke/check()
	if(bot_outermost_holder(disk) != bot)
		return BOT_GYM_PENDING
	if(nuke.auth)
		fail_reason = "took the disk but the nuke still has it in"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/nukies/in_the_nuke/release_run()
	QDEL_NULL(nuke)
	return ..()
