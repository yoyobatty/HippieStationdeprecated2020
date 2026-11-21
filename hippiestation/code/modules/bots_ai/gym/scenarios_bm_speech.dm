// Bot gym scenarios from the 2026-11-21 bot audit, speech area.

// ---------------------------------------------------------------------------------------------
// The user's own lines
// ---------------------------------------------------------------------------------------------

/// What the user said in the rounds they played (data/logs/2026/11/*/game.log, SAY: Yoyobatty/), said to somebody stood in front of them,
/// one every 6 s. Short, unaddressed, lower case: "hey", "wait", "gg", "sec", "mining?". Each line is judged by reading the run's
/// transcript (data/bot_gym/transcripts/): what came back, and whether somebody who heard it would have said that. It passes on 2/3 answered,
/// as the other sweeps do; the transcript is the measure.
/datum/bot_scenario/chat/sweep/user_lines
	name = "speech: the user's own lines, face to face (1)"
	desc = "Lines the user typed to bots in played rounds. Read the transcript."
	lines = list("hey", "yo", "hi", "help", "wait", "gg", "stop", "cap", "sorry", "ok", "oh shit", "medic", "help me", "yes", "traitor", "thanks", "security", "look", "hop", "hey peter", "you ok?", "why", "where are you", "sup bitches", "stop!", "security help", "please", "nice", "my pda", "let me out")

/datum/bot_scenario/chat/sweep/user_lines/two
	name = "speech: the user's own lines, face to face (2)"
	lines = list("let me in", "come", "chill", "can you", "back off", "you stuck?", "you suck", "you so cute", "you need healing", "you guys fucking suck", "you attacked me first", "wtf", "wow", "why you following me?", "why me?", "why arrest me?", "who's killing everyone?", "who's alive?", "where's my order?", "where's max?", "where you going", "where is everyone", "what you up to", "what can you do?", "what are you growing?", "truce?", "traitor's dead?", "they assaulted me", "thanks for telling me", "team?")

/datum/bot_scenario/chat/sweep/user_lines/three
	name = "speech: the user's own lines, face to face (3)"
	lines = list("stop running", "stop breaking it", "stay here", "someone come fight me", "she's dead!", "science", "security?", "sec is traitor", "mining?", "going mining?", "my bad", "kk", "it was an accident", "im helping", "im coming", "i'm gonna help you, I'm first aid trained", "i need it", "hold still", "hmm, you're right", "hm", "how about you", "got a sec", "give me back my pda", "found jamie", "fire in medbay", "don't kill me", "don't arrest me", "doing toxins?", "can you give me more access?", "I need heals")

/datum/bot_scenario/chat/sweep/user_lines/four
	name = "speech: the user's own lines, face to face (4)"
	job = "Medical Doctor"
	lines = list("I need good drinks", "I need access", "I am security", "I'm captain", "I'm a lawyer", "any antags about?", "anyone alive", "are you stuck", "?", "hey", "I'm poisoned", "heal me", "you need healing", "clone this mna", "I'm hurt", "thanks", "help", "wait", "stop", "gg")

// ---------------------------------------------------------------------------------------------
// Echoes
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/speech_echo
	name = "speech: nobody says what somebody near has just said, on the radio or out loud"
	desc = "Four of them say \":s Responding to a call from Vic in Chemistry.\" in the one second, three of them stood together say \"Cut it out!\" aloud, and one 14 tiles off says that too. The radio line gets said once; aloud, the nearby two keep quiet and the far one still says it. All five officers radioed the same \"Responding to a call\" in the one second round after round (shift batches, 2026-11-16), as only \";\" lines were counted."
	layout = list(
		"#########################",
		"#B.b.c...............d.e#",
		"#########################")
	time_limit = 10 SECONDS
	var/list/crew = list()
	var/judged = FALSE

/datum/bot_scenario/speech_echo/issue_goal()
	return

/datum/bot_scenario/speech_echo/post_spawn()
	crew = list(bot, second_bot(first_marker("b"), "Ray Echo"), second_bot(first_marker("c"), "Kit Echo"), second_bot(first_marker("d"), "Lee Echo"), second_bot(first_marker("e"), "Sam Echo"))
	for(var/mob/living/carbon/human/H in crew)
		if("speech_rules_in_gym" in H.bot_brain.vars)
			H.bot_brain.vars["speech_rules_in_gym"] = TRUE
	addtimer(CALLBACK(src, PROC_REF(say_it)), 2 SECONDS)

/datum/bot_scenario/speech_echo/proc/say_it()
	var/radio_said = 0
	for(var/i in 1 to 4)
		var/mob/living/carbon/human/H = crew[i]
		if(bot_say(H, ":s Responding to a call from Vic Sorrento in Chemistry."))
			radio_said++
	var/near_said = 0
	for(var/i in 1 to 3)
		var/mob/living/carbon/human/H = crew[i]
		if(bot_say(H, "Cut it out!"))
			near_said++
	var/far_said = bot_say(crew[4], "Cut it out!") ? 1 : 0
	log_line("radio said [radio_said] of 4, near [near_said] of 3, far [far_said] of 1")
	if(radio_said != 1)
		fail_reason = "[radio_said] of four said the same radio line in one second"
	else if(near_said != 1)
		fail_reason = "[near_said] of three stood together said the same thing aloud"
	else if(!far_said)
		fail_reason = "the one 14 tiles away kept quiet for somebody out of earshot"
	judged = TRUE

/datum/bot_scenario/speech_echo/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!judged)
		return BOT_GYM_PENDING
	return fail_reason ? BOT_GYM_FAIL : BOT_GYM_PASS

/datum/bot_scenario/duty/no_captain_yet
	name = "speech: minutes into the shift with no Captain seen, the HoP doesn't claim command"
	desc = "Nobody's been in command yet and the shift's a minute old: the Captain's only late to the Bridge. The HoP says nothing, where the HoS took command a few seconds into a shift and the Captain said \"I'm back in command\" ten seconds later (shift batch gen1116f)."
	duty_type = /datum/bot_duty/chain_of_command
	job = "Head of Personnel"
	time_limit = 8 SECONDS
	layout = list(
		"#####",
		"#.B.#",
		"#####")

/datum/bot_scenario/duty/no_captain_yet/post_spawn()
	..()
	GLOB.bot_in_command = null
	if("command_wait_in_gym" in brain.vars)
		brain.vars["command_wait_in_gym"] = TRUE

/datum/bot_scenario/duty/no_captain_yet/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("in command now"))
		fail_reason = "claimed command with the shift not a minute old"
		return BOT_GYM_FAIL
	return world.time > start_time + 6 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Silence
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/no_small_talk
	name = "speech: with three dead and the killer at large, nobody makes small talk"
	desc = "Three bodies in the room, all last hurt by somebody who's still up and about, and a friendly colleague beside the bot. The user's ruling after the rampage round (2026-11-10): no small talk; the jokes and \"anyone for arcade?\" had carried on over the bodies. The bot's idle chatter is given 30 goes, each with nothing in the way of it but the shift."
	job = "Assistant"
	layout = list(
		"############",
		"#B.C..K....#",
		"############")
	time_limit = 20 SECONDS
	var/mob/living/carbon/human/killer
	var/goes = 0

/datum/bot_scenario/no_small_talk/issue_goal()
	return

/datum/bot_scenario/no_small_talk/post_spawn()
	second_bot(first_marker("C"), "Kit Company")
	killer = stand_in(first_marker("K"), "Kit Killer")
	gym_bodies_by(killer)
	if("bot_body_counts_at" in GLOB.vars)
		GLOB.vars["bot_body_counts_at"] = 0
	brain.sociability = 1
	addtimer(CALLBACK(src, PROC_REF(chat_go)), 2 SECONDS)

/datum/bot_scenario/no_small_talk/proc/chat_go()
	if(result != BOT_GYM_PENDING || QDELETED(bot))
		return
	goes++
	brain.next_chat_time = 0
	brain.gym_scripted = FALSE //handle_idle_chat() leaves a scripted bot alone
	brain.handle_idle_chat()
	brain.gym_scripted = TRUE
	if(goes < 30)
		addtimer(CALLBACK(src, PROC_REF(chat_go)), 4)

/datum/bot_scenario/no_small_talk/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "said \""))
			fail_reason = "made small talk over the bodies: [line]"
			return BOT_GYM_FAIL
	return goes >= 30 ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Answers that fit
// ---------------------------------------------------------------------------------------------

/// "mining?" and "going mining?" (round-14.43.45) got "Wish I knew." and "No idea, sorry.": answers to something nobody asked. A bit with a
/// question mark on it and no question in it is asked back; a real question it can't answer still gets "no idea"; and its name with
/// something it didn't catch isn't "Yeah, that's me."
/datum/bot_scenario/chat/sweep/unclear
	name = "speech: a scrap of a question is asked back, not \"Beats me\", and its name with something it didn't catch isn't \"that's me\""
	desc = "\"pizza?\", \"tomorrow?\", \"Gym, the thing by the door\" and, as the control, \"why is the alert blue?\" said to its face. The bot asks what about it, says it didn't catch the third, and still says it has no idea about the fourth."
	job = "Assistant"
	time_limit = 90 SECONDS

/datum/bot_scenario/chat/sweep/unclear/post_spawn()
	lines = list("pizza?", "tomorrow?", "[bot.first_name()], the thing by the door", "why is the alert blue?")
	..()

/// The first thing it said after line `i` was said, or null
/datum/bot_scenario/chat/sweep/unclear/proc/reply_to(i)
	var/first = said_at[i] + 1
	var/last = (i < length(said_at)) ? said_at[i + 1] : length(transcript)
	for(var/j in first to last)
		if(j > length(transcript))
			break
		var/at = findtext(transcript[j], "said \"")
		if(at)
			var/rest = copytext(transcript[j], at + 6)
			return copytext(rest, 1, findtext(rest, "\""))
	return null

/datum/bot_scenario/chat/sweep/unclear/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(next_line <= length(lines) || world.time < start_time + (length(lines) * 6 + 8) SECONDS)
		return BOT_GYM_PENDING
	for(var/i in 1 to 2)
		var/reply = reply_to(i)
		if(!reply)
			fail_reason = "said nothing to \"[lines[i]]\""
			return BOT_GYM_FAIL
		if(reply in GLOB.bot_question_reply_lines)
			fail_reason = "answered \"[lines[i]]\" with \"[reply]\", as if it were a question it didn't know"
			return BOT_GYM_FAIL
	var/third = reply_to(3)
	if(!third)
		fail_reason = "said nothing to its name and something it didn't catch"
		return BOT_GYM_FAIL
	if(third in GLOB.bot_name_called_lines)
		fail_reason = "answered \"[lines[3]]\" with \"[third]\": it didn't take anything in"
		return BOT_GYM_FAIL
	var/fourth = reply_to(4)
	if(!fourth)
		fail_reason = "said nothing to a question it can't answer"
		return BOT_GYM_FAIL
	if(!(fourth in GLOB.bot_question_reply_lines))
		fail_reason = "answered \"[lines[4]]\" with \"[fourth]\" instead of saying it hasn't a clue"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// The same, to a small crowd: three of them stood round the user, who names nobody. Whoever answers, answers; the transcript is the measure.
/datum/bot_scenario/chat/sweep/user_lines/crowd
	name = "speech: the user's own lines, to a crowd of three (5)"
	layout = list(
		"#########",
		"#.b.C.c.#",
		"#...B...#",
		"#########")
	lines = list("hey", "yo", "hi", "help", "wait", "stop", "what's going on", "anyone got a crowbar?", "who's the captain?", "hello", "you ok?", "thanks", "sorry", "nice", "where's medbay?", "what are you guys doing?")

/datum/bot_scenario/chat/sweep/user_lines/crowd/post_spawn()
	..()
	second_bot(first_marker("b"), "Ray Crowd")
	second_bot(first_marker("c"), "Kit Crowd")

/// "Who's the captain?" said in a room of three, naming nobody, answered by the nearest of them. In a crowd nobody was spoken to, and it got
/// no answer, or a bystander's "Beats me." (17% of the time, by sociability).
/datum/bot_scenario/chat/room_question
	name = "speech: \"who's the curator?\" put to the room, not to anybody, gets one answer that says who"
	desc = "Three of them stand round the user, who says \"who's the curator?\" naming nobody. One answers, with the Curator's name. Before: nobody was spoken to (others are about) and a bystander's \"Beats me.\" was all there was to hear."
	job = "Assistant"
	layout = list(
		"###########",
		"#.b.C.c..K#",
		"#...B.....#",
		"###########")
	time_limit = 20 SECONDS
	var/mob/living/carbon/human/captain
	var/said_line = "who's the curator?"

/datum/bot_scenario/chat/room_question/post_spawn()
	..()
	brain.sociability = 1
	for(var/char in list("b", "c"))
		var/mob/living/carbon/human/other = second_bot(first_marker(char), "[char == "b" ? "Ray" : "Kit"] Crowd")
		other.bot_brain.sociability = 1
	captain = stand_in(first_marker("K"), "Cura Tor")
	captain.mind_initialize()
	captain.mind.assigned_role = "Curator" //a job no other scenario's stand-in has: the question is answered from the whole round's crew
	addtimer(CALLBACK(src, PROC_REF(visitor_says), said_line), 2 SECONDS)

/datum/bot_scenario/chat/room_question/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "nobody said anything to a plain question put to the room"
		return BOT_GYM_FAIL
	if(length(lines) > 1)
		fail_reason = "more than one answered: [english_list(lines)]"
		return BOT_GYM_FAIL
	if(!findtext(lines[1], "Cura"))
		fail_reason = "answered \"[lines[1]]\", which doesn't say who the Curator is"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// "Ai where is emery" (round-12.20.48.49 and round-14.43.45): said to the AI, with the name of somebody else in the room in it, and Emery
/// answered "Not sure where that is" and "Yeah, that's me". The AI's to answer it. Here a stand-in is the AI (what counts is the job on its mind).
/datum/bot_scenario/chat/to_the_ai
	name = "speech: a line said to the AI, with the bot's name in it, isn't answered by the bot"
	desc = "The visitor says \"AI where is Gym\" (the bot's own first name) and \"AI open this door\". An AI is aboard, so nobody says there isn't one. The bot, which isn't the AI, says nothing: it's not talking to it. Before: \"No idea, sorry.\" and \"Which door?\"."
	job = "Assistant"
	layout = list(
		"#########",
		"#B.C.A..#",
		"#########")
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/ai
	var/said = 0

/datum/bot_scenario/chat/to_the_ai/post_spawn()
	..()
	ai = stand_in(first_marker("A"), "Ay Eye")
	ai.mind_initialize()
	ai.mind.assigned_role = "AI"
	addtimer(CALLBACK(src, PROC_REF(ask_one)), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(ask_two)), 9 SECONDS)

/datum/bot_scenario/chat/to_the_ai/proc/ask_one()
	visitor_says("AI where is [lowertext(bot.first_name())]")

/datum/bot_scenario/chat/to_the_ai/proc/ask_two()
	visitor_says("AI open this door")

/datum/bot_scenario/chat/to_the_ai/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/lines = spoken()
	if(length(lines))
		fail_reason = "answered a line said to the AI: \"[lines[1]]\""
		return BOT_GYM_FAIL
	return world.time > start_time + 16 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/// "hey peter", "hey drew", "hey sam" (the user's): a greeting with somebody else's name on it is that somebody's. The bot, alone with whoever
/// said it, didn't say "hey there" to a stranger's name; and still answers its own.
/datum/bot_scenario/chat/hey_somebody_else
	name = "speech: \"hey ray\" isn't answered by somebody who isn't Ray, but \"hey\" and its own name are"
	desc = "The visitor, alone with the bot, says \"hey ray\" (Ray's across the room, and in earshot) and then \"hey\" and the bot's own first name. The bot answers the second only. Before: it said hello to a call for somebody else."
	job = "Assistant"
	layout = list(
		"##########",
		"#B.C....R#",
		"##########")
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/ray

/datum/bot_scenario/chat/hey_somebody_else/post_spawn()
	..()
	ray = stand_in(first_marker("R"), "Ray Elsewhere")
	ray.mind_initialize()
	ray.mind.assigned_role = "Assistant"
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "hey ray"), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "hey [lowertext(bot.first_name())]"), 10 SECONDS)

/datum/bot_scenario/chat/hey_somebody_else/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 18 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "said nothing even to its own name"
		return BOT_GYM_FAIL
	if(length(lines) > 1)
		fail_reason = "answered a hello for somebody else too: [english_list(lines)]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/chat/room_question/cry_for_help
	name = "speech: \"help\" said to a room of three by somebody who isn't hurt gets one \"what's wrong?\""
	desc = "Three of them stand round the user, who says \"help\" and nothing else, and isn't hurt. The nearest asks what's wrong. Before: nobody was spoken to, nobody said a word (the user's \"help\" and \"help me\", round after round)."
	said_line = "help"

/datum/bot_scenario/chat/room_question/cry_for_help/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "nobody said anything to \"help\""
		return BOT_GYM_FAIL
	if(length(lines) > 1)
		fail_reason = "more than one answered: [english_list(lines)]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Explosions heard (bot_talk_more.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/boom_heard
	name = "speech: an explosion close by gets a \"what was that?\" from somebody, not from everybody"
	desc = "A blast goes off two tiles from three of them. The nearest says what anybody would; at most one more does. Bots had nothing to say to an explosion at all."
	job = "Assistant"
	layout = list(
		"############",
		"#B.b.c.....#",
		"############")
	time_limit = 20 SECONDS
	var/went_off = FALSE

/datum/bot_scenario/boom_heard/issue_goal()
	return

/datum/bot_scenario/boom_heard/post_spawn()
	var/list/crew = list(bot, second_bot(first_marker("b"), "Ray Boom"), second_bot(first_marker("c"), "Kit Boom"))
	for(var/mob/living/carbon/human/H in crew)
		if("boom_talk_in_gym" in H.bot_brain.vars)
			H.bot_brain.vars["boom_talk_in_gym"] = TRUE
	addtimer(CALLBACK(src, PROC_REF(go_off)), 2 SECONDS)

/datum/bot_scenario/boom_heard/proc/go_off()
	went_off = TRUE
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_EXPLOSION, get_turf(first_marker("c")), 0, 1, 2, 0, 0, 1, 2)

/datum/bot_scenario/boom_heard/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!went_off || world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	var/said = 0
	for(var/line in transcript)
		if(findtext(line, "said \""))
			said++
	if(!said)
		fail_reason = "nobody said a word about an explosion two tiles away"
		return BOT_GYM_FAIL
	if(said > 2)
		fail_reason = "[said] of three said something about the one explosion"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Answers that fit, the rest
// ---------------------------------------------------------------------------------------------

/// "oh shit", "why", "traitor", "look", "gg", "please" (the user's, said to a bot's face): it had no answer for any of them, and "Mm.", "Fair enough.",
/// "If you say so." and "Huh." came back for all alike. Each now gets what anybody would say to it.
/datum/bot_scenario/chat/sweep/fitting
	name = "speech: a line it has no answer for gets one that fits, not \"Mm.\" or \"If you say so.\""
	desc = "\"oh shit\" gets \"what happened?\", \"why\" \"why what?\", \"traitor\" \"where?\", \"look\" \"what?\", \"please\" \"please what?\", \"gg\" a \"gg\", and \"yes\" an okay. Before: \"Mm.\", \"Right.\", \"Nice.\", \"If you say so.\" for any of them."
	job = "Assistant"
	time_limit = 90 SECONDS
	lines = list("oh shit", "why", "traitor", "look", "please", "gg", "yes")
	var/list/expected = list(
		list("What? What happened?", "What?", "What is it?", "What happened?"),
		list("Why what?", "Sorry, why what?", "Hm?"),
		list("Where?", "Who?", "Are you sure?", "Where? Who?"),
		list("What?", "What is it?", "Hm?"),
		list("Please what?", "What do you need?"),
		list("gg.", "gg", "Ha. gg.", "Right?"),
		list("Okay.", "Alright.", "Right."))

/datum/bot_scenario/chat/sweep/fitting/proc/reply_to(i)
	var/first = said_at[i] + 1
	var/last = (i < length(said_at)) ? said_at[i + 1] : length(transcript)
	for(var/j in first to last)
		if(j > length(transcript))
			break
		var/at = findtext(transcript[j], "said \"")
		if(at)
			var/rest = copytext(transcript[j], at + 6)
			return copytext(rest, 1, findtext(rest, "\""))
	return null

/datum/bot_scenario/chat/sweep/fitting/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(next_line <= length(lines) || world.time < start_time + (length(lines) * 6 + 8) SECONDS)
		return BOT_GYM_PENDING
	for(var/i in 1 to length(lines))
		var/reply = reply_to(i)
		if(!reply)
			fail_reason = "said nothing to \"[lines[i]]\""
			return BOT_GYM_FAIL
		var/list/ok = expected[i]
		if(!(reply in ok))
			fail_reason = "answered \"[lines[i]]\" with \"[reply]\""
			return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/chat/sweep/fitting/more
	name = "speech: more of the user's lines get one that fits (fight me, access, good morning, where you going...)"
	desc = "\"someone come fight me\", \"can you give me more access?\" (to somebody who isn't the HoP), \"good morning\", \"what you up to\", \"where you going\", \"you stuck?\", \"i'm poisoned\" (and not looking it), \"you attacked me first\". Before: nothing, \"Hm, not sure, honestly.\", \"Afternoon.\", nothing, nothing, \"Huh?\", \"Okay.\", nothing."
	lines = list("someone come fight me", "can you give me more access?", "good morning", "what you up to", "where you going", "you stuck?", "i'm poisoned", "you attacked me first", "radiation dangerous", "fire in medbay")
	expected = list(
		list("Ha, no thanks.", "Not today!", "I'll pass.", "No thanks.", "Not interested.", "Don't tempt me.", "Keep talking.", "You don't want that."),
		list("That's the HoP's call.", "Ask the HoP.", "Not me, the HoP does access.", "Try the HoP."),
		list("Morning.", "Morning!", "Good morning."),
		list("Nothing much.", "Just having a wander.", "Taking a breather."),
		list("Nowhere special.", "Just having a wander.", "No place in particular."),
		list("No, I'm fine.", "Nope, why?", "Not stuck. Why, do I look it?"),
		list("You look fine to me?", "Where does it hurt?", "Medbay's the place for that."),
		list("What? No, I didn't.", "I never touched you.", "No I didn't.", "That wasn't me.", "Prove it.", "Liar."),
		list("Thanks for the heads up.", "Got it, I'll keep clear.", "Yikes. Thanks.", "Noted, staying away."),
		list("Thanks for the heads up.", "Got it, I'll keep clear.", "Yikes. Thanks.", "Noted, staying away."))

/// "Hey", "hello", "yo" typed on Common, which is where the user puts most of what they say (all 20 lines of round-14.43.45 went out on it as well as
/// aloud): a bot answers the radio only to its own name, so nobody away from them said a word. One of the crew says hey back.
/datum/bot_scenario/chat/radio_hello
	name = "speech: \"hey\" on Common gets one hey back, not three"
	desc = "Three of them hear \"hey\" come over Common from somebody across the room (nobody's named). One says hey back over the radio; the others leave it to them. Before: silence."
	job = "Assistant"
	layout = list(
		"###############",
		"#B.b.c.......C#",
		"###############")
	time_limit = 20 SECONDS
	var/list/crew = list()

/datum/bot_scenario/chat/radio_hello/post_spawn()
	..()
	crew = list(bot, second_bot(first_marker("b"), "Ray Hello"), second_bot(first_marker("c"), "Kit Hello"))
	for(var/mob/living/carbon/human/H in crew)
		if("radio_hello_odds" in H.bot_brain.vars)
			H.bot_brain.vars["radio_hello_odds"] = 100
	addtimer(CALLBACK(src, PROC_REF(hey)), 2 SECONDS)

/datum/bot_scenario/chat/radio_hello/proc/hey()
	for(var/mob/living/carbon/human/H in crew)
		H.bot_brain.on_heard_speech(visitor, "hey", FREQ_COMMON)

/datum/bot_scenario/chat/radio_hello/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "nobody said hey back"
		return BOT_GYM_FAIL
	if(length(lines) > 1)
		fail_reason = "more than one said hey back: [english_list(lines)]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// "security help" typed on Common (round-12.20.48.49: four officers answered, all on Security's own channel, which the user couldn't hear, so
/// nothing came back to them but a name on the Security channel). The officer who takes it answers on the channel it came over.
/datum/bot_scenario/griefed/bug/call_answered_on_common
	name = "speech: a call for Security over Common is answered on Common, so the caller can hear it"
	job = "Security Officer"
	griefer_job = "Assistant"
	time_limit = 18 SECONDS

/datum/bot_scenario/griefed/bug/call_answered_on_common/grief()
	brain.on_heard_security_call(griefer, "security help", FREQ_COMMON)
	addtimer(CALLBACK(src, PROC_REF(judge_reply)), 11 SECONDS)

/datum/bot_scenario/griefed/bug/call_answered_on_common/proc/judge_reply()
	expect(bot_transcript_said("said \";Responding to a call from Griff Griefer"), "it answered on Common")

// ---------------------------------------------------------------------------------------------
// Not the same joke again
// ---------------------------------------------------------------------------------------------

/// The clown told "I'd tell you a joke about the engine, but it'd blow up in my face" four times in ten minutes (shift batch play1114b): the jokes, idle
/// mutters and small talk were picked at random every time. It goes through them all before it says one twice.
/datum/bot_scenario/fresh_lines
	name = "speech: it goes through all eight lines before it picks one again"
	desc = "Eight picks from a list of eight, as the clown's, the idle mutters' and the small talk's are made. Each is different; picking at random with no memory had all eight different once in 400."
	layout = list(
		"#####",
		"#.B.#",
		"#####")
	time_limit = 6 SECONDS
	var/done = FALSE

/datum/bot_scenario/fresh_lines/issue_goal()
	return

/datum/bot_scenario/fresh_lines/post_spawn()
	addtimer(CALLBACK(src, PROC_REF(pick_them)), 1 SECONDS)

/datum/bot_scenario/fresh_lines/proc/pick_them()
	var/list/pool = list("one", "two", "three", "four", "five", "six", "seven", "eight")
	var/list/got = list()
	for(var/i in 1 to 8)
		var/said = bot_fresh_pick(brain, pool)
		if(said in got)
			fail_reason = "picked \"[said]\" again as its pick number [i], with the rest of the list not yet used: [english_list(got)]"
		got += said
	done = TRUE

/datum/bot_scenario/fresh_lines/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!done)
		return BOT_GYM_PENDING
	return fail_reason ? BOT_GYM_FAIL : BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// A hole in the hull (bot_talk_more.dm, goals/repair_hull.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/hole_in_the_hull
	name = "speech: a hole blown in the hull is called out by whoever can see it, once"
	desc = "A floor tile in the room turns to space, as a bomb or a meteor does it. The one who can see it says where, on the radio, once. Nobody said a word about a hole in the hull: the engineers' own rounds saw to it and the rest carried on."
	job = "Assistant"
	layout = list(
		"#########",
		"#B..H...#",
		"#########")
	time_limit = 20 SECONDS
	var/blown = FALSE

/datum/bot_scenario/hole_in_the_hull/issue_goal()
	return

/datum/bot_scenario/hole_in_the_hull/post_spawn()
	if("boom_talk_in_gym" in brain.vars)
		brain.vars["boom_talk_in_gym"] = TRUE //the flag for what a gym bot says about the world's events
	addtimer(CALLBACK(src, PROC_REF(blow)), 2 SECONDS)

/datum/bot_scenario/hole_in_the_hull/proc/blow()
	var/turf/T = first_marker("H")
	T.ChangeTurf(/turf/open/space/basic)
	blown = TRUE

/datum/bot_scenario/hole_in_the_hull/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!blown || world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	var/said = 0
	var/right_words = FALSE
	for(var/line in transcript)
		if(findtext(line, "said \""))
			said++
			if(findtext(line, "Bot Gym Arena"))
				right_words = TRUE
	if(!said)
		fail_reason = "nobody said a word about a hole in the hull"
		return BOT_GYM_FAIL
	if(said > 1 || !right_words)
		fail_reason = "[said] lines, and where it is [right_words ? "was said" : "wasn't"]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
