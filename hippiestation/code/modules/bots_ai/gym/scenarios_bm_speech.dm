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
	pass_thirds = 1.5 //half: in a crowd a hello is answered by whoever feels like it, and wait, stop, nice aren't answered by anybody

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
	GLOB.bot_boom_said_at = -1 MINUTES //the one a blast somewhere else in the gym set is the whole station's, and kept this one's quiet
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
	var/radio_line = "hey"

/datum/bot_scenario/chat/radio_hello/post_spawn()
	..()
	crew = list(bot, second_bot(first_marker("b"), "Ray Hello"), second_bot(first_marker("c"), "Kit Hello"))
	for(var/mob/living/carbon/human/H in crew)
		if("radio_hello_odds" in H.bot_brain.vars)
			H.bot_brain.vars["radio_hello_odds"] = 100
	addtimer(CALLBACK(src, PROC_REF(hey)), 2 SECONDS)

/datum/bot_scenario/chat/radio_hello/proc/hey()
	for(var/mob/living/carbon/human/H in crew)
		H.bot_brain.on_heard_speech(visitor, radio_line, FREQ_COMMON)

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
	time_limit = 24 SECONDS
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
	if(!blown || world.time < start_time + 18 SECONDS) //2 s to the hole, 2-5 s to notice it, and up to 6 s to type the line
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

/// "test", "radio check", "anyone here?" on Common (how somebody finds out whether the radio works, or who's about): one of them answers.
/datum/bot_scenario/chat/radio_hello/radio_check
	name = "speech: \"radio check\" on Common gets one \"loud and clear\""
	desc = "Three of them hear \"radio check\" come over Common. One answers that it can hear them. Before: silence."
	radio_line = "radio check"

/datum/bot_scenario/chat/radio_hello/radio_check/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(length(lines) != 1)
		fail_reason = length(lines) ? "more than one answered: [english_list(lines)]" : "nobody answered a radio check"
		return BOT_GYM_FAIL
	if(!(findtext(lines[1], "Loud and clear") || findtext(lines[1], "Got you") || findtext(lines[1], "Hear you fine") || findtext(lines[1], "Reading you")))
		fail_reason = "answered a radio check with \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// "you need healing" (the user's, said to bots): the words of a call for a doctor, said to a doctor, about the doctor. It answered "Be right there."
/datum/bot_scenario/chat/not_a_call
	name = "speech: \"you need healing\", said to a doctor, isn't a call for a doctor"
	desc = "The visitor tells a doctor who's in perfect health that it needs healing. The doctor says it's fine, instead of \"Be right there.\" and setting off for a patient who isn't there."
	job = "Medical Doctor"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 15 SECONDS

/datum/bot_scenario/chat/not_a_call/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "you need healing"), 2 SECONDS)

/datum/bot_scenario/chat/not_a_call/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "said nothing to being told it needs healing"
		return BOT_GYM_FAIL
	if(!(lines[1] in list("I'm fine, thanks.", "I'm alright, but thanks.", "Nah, I'm good.")))
		fail_reason = "answered \"you need healing\" with \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// Shift batch speech_b: Glenn Asker's ";Cargo, can we get some glass please?" came back from the Cargo Technician as ";Couldn't tell you." (a reply to
/// a "?", over Common, to a request). The order is taken and said so (goals/orders.dm).
/datum/bot_scenario/chat/cargo_asked
	name = "speech: \"cargo, can we get some glass please?\" over Common is taken, not met with \"couldn't tell you\""
	desc = "The Cargo Technician hears a request for glass come over Common. It says it'll order it, on Common. Before (shift batch): \"Couldn't tell you.\""
	job = "Cargo Technician"
	layout = list(
		"###########",
		"#B.......C#",
		"###########")
	time_limit = 20 SECONDS

/datum/bot_scenario/chat/cargo_asked/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/chat/cargo_asked/proc/ask()
	log_line("visitor (over Common): \"Cargo, can we get some glass please?\"")
	brain.on_heard_speech(visitor, "cargo, can we get some glass please?", FREQ_COMMON)

/datum/bot_scenario/chat/cargo_asked/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "nobody took the order for glass"
		return BOT_GYM_FAIL
	for(var/ack in list("put the order in", "ordering now", "give it a few minutes", "get that ordered"))
		if(findtext(lines[1], ack))
			return BOT_GYM_PASS
	var/datum/bot_request_kind/read_as = bot_request_kind_of("cargo, can we get some glass please?", TRUE, get_turf(visitor))
	fail_reason = "answered a request for glass with \"[lines[1]]\" (read as: [read_as ? read_as.name : "no request"], heard_by [read_as ? read_as.heard_by(brain, TRUE) : "-"], work role [brain.work_role()])"
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// What's said to a job over Common
// ---------------------------------------------------------------------------------------------

/// The user types nearly everything on Common, and over the radio a bot answers only to its name or its job's title. A line to a job over the radio, one
/// every 6 s, to somebody of that job: what comes back, and whether it fits (read the transcript: data/bot_gym/transcripts/). Passes at half answered.
/datum/bot_scenario/chat/sweep/radio_lines
	name = "speech: lines to the Engineer over Common"
	job = "Station Engineer"
	pass_thirds = 0.75 //a quarter: most of these aren't asking for anything, and who's here is said once for twenty seconds
	lines = list("engineering, how's the engine?", "ce, status?", "is the engine ok?", "engineer to the bridge please", "anyone in engineering?", "who's on the engine?", "can engineering fix the lights?", "we need power in medbay", "engineering, the singularity is loose!", "engineers, hello?", "engi, you there?", "any engineer about?")

/datum/bot_scenario/chat/sweep/radio_lines/visitor_says(line)
	if(result != BOT_GYM_PENDING || QDELETED(visitor))
		return
	log_line("visitor (over Common): \"[line]\"")
	// What /mob/living/carbon/human/Hear() hands a bot (bot_brain.dm)
	brain.on_heard_security_call(visitor, lowertext(line), FREQ_COMMON)
	brain.on_heard_ruling(visitor, lowertext(line))
	brain.on_heard_speech(visitor, lowertext(line), FREQ_COMMON)

/datum/bot_scenario/chat/sweep/radio_lines/doctor
	name = "speech: lines to the Doctor over Common"
	job = "Medical Doctor"
	lines = list("medbay, status?", "doctor to the bridge", "cmo, got a sec?", "anyone in medbay?", "need a doctor in cargo", "can medbay clone me?", "is medbay open?", "medic!", "doctor, i'm hurt", "who's the cmo?", "medbay, hello?", "any doctor about?")

/datum/bot_scenario/chat/sweep/radio_lines/cargo
	name = "speech: lines to Cargo over Common"
	job = "Cargo Technician"
	lines = list("cargo, any crates for me?", "qm, can we get metal?", "cargo, status?", "cargo, where's my order?", "anyone in cargo?", "qm, got a sec?", "cargo, can you order some tools?", "what's the supply shuttle doing?", "is cargo open?", "who's the qm?", "cargo, hello?", "any cargo tech about?")

/datum/bot_scenario/chat/sweep/radio_lines/security
	name = "speech: lines to Security over Common"
	job = "Security Officer"
	lines = list("sec, any updates?", "security, is the brig empty?", "anyone in security?", "sec, what's the alert?", "who's the hos?", "security, i've got a trespasser in cargo", "sec, are you there?", "officer, over here!", "sec, status?", "any officer about?", "security, hello?", "sec to the bridge please")

/datum/bot_scenario/chat/sweep/radio_lines/janitor
	name = "speech: lines to the Janitor over Common"
	job = "Janitor"
	lines = list("janitor, can you clean medbay?", "mess in cargo, janitor", "anyone seen the janitor?", "janitor, got a sec?", "who's the janitor?", "janitor, got a mop?", "janitor, hello?", "any janitor about?", "janitor, there's blood in the bar", "can the janitor come to science?", "janny, you there?", "janitor, status?")

/datum/bot_scenario/chat/sweep/radio_lines/hop
	name = "speech: lines to the HoP over Common"
	job = "Head of Personnel"
	lines = list("hop, i need access", "hop, can i have a new job?", "hop, got a sec?", "hop, are you there?", "where's the hop?", "hop, my id's broken", "can i get a promotion?", "hop, i need engineering access", "who's the hop?", "which jobs are open?", "hop, hello?", "any hop about?")

/// "what did i miss?" got "We've lost 3 so far." from a bot that had seen nobody die (shift_news() counted every body on the station).
/datum/bot_scenario/chat/shift_news_unseen
	name = "speech: asked what it missed, it doesn't give a count of dead it hasn't seen"
	desc = "Somebody's dead in a room behind a wall, and the bot knows nothing about it. Asked \"what did i miss?\", it says it's quiet, not how many have died."
	job = "Assistant"
	layout = list(
		"#########",
		"#B.C#.K.#",
		"#########")
	time_limit = 15 SECONDS

/datum/bot_scenario/chat/shift_news_unseen/post_spawn()
	..()
	var/mob/living/carbon/human/body = stand_in(first_marker("K"), "Dead Crew")
	body.mind_initialize()
	body.mind.assigned_role = "Botanist"
	body.death()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "what did i miss?"), 2 SECONDS)

/datum/bot_scenario/chat/shift_news_unseen/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "said nothing to \"what did i miss?\""
		return BOT_GYM_FAIL
	if(findtext(lines[1], "lost") || findtext(lines[1], "dead") || findtext(lines[1], "Security's after"))
		fail_reason = "knew of what it hadn't seen: \"[lines[1]]\"" //the dead, or the news another scenario's arena has put in the one pool
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// "Any janitor about?" over Common: one of the two janitors that hear it says it's here. Over the radio a bot answers only to its name, and asked
/// to its face it said "Don't ask me." or "Haven't a clue." (the janitor, to "any janitor about?").
/datum/bot_scenario/chat/roll_call
	name = "speech: \"any janitor about?\" over Common gets one \"here\", from a janitor"
	desc = "Two janitors hear \"any janitor about?\" come over Common. One says it's here, on Common; the other leaves it to them."
	job = "Janitor"
	layout = list(
		"###########",
		"#B.b.....C#",
		"###########")
	time_limit = 20 SECONDS
	var/mob/living/carbon/human/other

/datum/bot_scenario/chat/roll_call/post_spawn()
	..()
	other = second_bot(first_marker("b"), "Jan Itor")
	other.mind.assigned_role = "Janitor"
	brain.sociability = 1
	other.bot_brain.sociability = 1
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/chat/roll_call/proc/ask()
	log_line("visitor (over Common): \"any janitor about?\"")
	for(var/datum/bot_brain/B in list(brain, other.bot_brain))
		B.on_heard_speech(visitor, "any janitor about?", FREQ_COMMON)

/datum/bot_scenario/chat/roll_call/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(length(lines) != 1)
		fail_reason = length(lines) ? "more than one answered: [english_list(lines)]" : "nobody said it was here"
		return BOT_GYM_FAIL
	if(!(findtext(lines[1], "here") || findtext(lines[1], "Go ahead") || findtext(lines[1], "what do you need")))
		fail_reason = "answered \"any janitor about?\" with \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// "Anyone in engineering?" (a trade the bot-title words don't have: bot_roll_call_trades) over Common, to an Engineer.
/datum/bot_scenario/chat/roll_call/engineering
	name = "speech: \"anyone in engineering?\" over Common gets a \"here\" from an engineer"
	desc = "An engineer hears \"anyone in engineering?\" over Common. It says it's here."
	job = "Station Engineer"

/datum/bot_scenario/chat/roll_call/engineering/post_spawn()
	..()
	other.mind.assigned_role = "Station Engineer"

/datum/bot_scenario/chat/roll_call/engineering/ask()
	log_line("visitor (over Common): \"anyone in engineering?\"")
	for(var/datum/bot_brain/B in list(brain, other.bot_brain))
		B.on_heard_speech(visitor, "anyone in engineering?", FREQ_COMMON)

/datum/bot_scenario/chat/roll_call/engineering/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(length(lines) != 1)
		fail_reason = length(lines) ? "more than one answered: [english_list(lines)]" : "nobody said it was here"
		return BOT_GYM_FAIL
	if(!(findtext(lines[1], "here") || findtext(lines[1], "Go ahead") || findtext(lines[1], "what do you need")))
		fail_reason = "answered \"anyone in engineering?\" with \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// "Who's the lawyer?", asked of the lawyer, was answered with the lawyer's own name, as if about somebody else.
/datum/bot_scenario/chat/that_is_me
	name = "speech: \"who's the lawyer?\", asked of the lawyer, gets \"that's me\""
	desc = "The visitor asks the only lawyer who the lawyer is. It says it's the lawyer, not a name as if it were somebody else."
	job = "Lawyer"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 15 SECONDS

/datum/bot_scenario/chat/that_is_me/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "who's the lawyer?"), 2 SECONDS)

/datum/bot_scenario/chat/that_is_me/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "said nothing to \"who's the lawyer?\""
		return BOT_GYM_FAIL
	if(!(lines[1] in list("That's me.", "Me.", "I am. What's up?")))
		fail_reason = "answered \"who's the lawyer?\" with \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// A trade nobody's on, called by its letters: "nobody's on research director" was how it came out.
/datum/bot_scenario/chat/nobody_on_short
	name = "speech: told there's no RD, it says RD, not research director"
	desc = "Somebody calls for the RD over Common and there isn't one. The answer calls it the RD."
	job = "Assistant"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 15 SECONDS

/datum/bot_scenario/chat/nobody_on_short/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "rd, you there?"), 2 SECONDS)

/datum/bot_scenario/chat/nobody_on_short/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "said nothing to a call for the RD with no RD about"
		return BOT_GYM_FAIL
	if(findtext(lines[1], "research director") || !findtext(lines[1], "RD") && !findtext(lines[1], "one"))
		fail_reason = "said \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Typed one line after another
// ---------------------------------------------------------------------------------------------

/// Three lines from one officer in 10 s (the Security call, the arrest, "in custody") came out the tick they were decided, in 18 bots' 20-minute shift. A person types
/// the first, then the next, and sends each when it's typed (bot_say(), bot_chat.dm). The gym says lines at once but for a scenario that tests typing.
/datum/bot_scenario/pace_lines
	name = "speech: three things to say in one tick come out one after another, as they're typed"
	desc = "A bot with typing on is handed three lines in the same tick. The first goes out a moment later, not that tick, and the others each after the one before has been typed. Before: all three that tick."
	job = "Assistant"
	layout = list(
		"#####",
		"#.B.#",
		"#####")
	time_limit = 30 SECONDS
	var/talked_at = 0
	var/list/said_at = list()

/datum/bot_scenario/pace_lines/issue_goal()
	return

/datum/bot_scenario/pace_lines/post_spawn()
	brain.typing_in_gym = TRUE
	RegisterSignal(bot, COMSIG_MOB_SAY, PROC_REF(note_say))
	addtimer(CALLBACK(src, PROC_REF(talk)), 2 SECONDS)

/datum/bot_scenario/pace_lines/proc/talk()
	talked_at = world.time
	for(var/line in list("Hold on a sec", "Right behind you", "Mind the door"))
		bot_say(bot, line)

/datum/bot_scenario/pace_lines/proc/note_say(datum/source, list/arguments)
	SIGNAL_HANDLER
	said_at += world.time

/datum/bot_scenario/pace_lines/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!talked_at || world.time < talked_at + 20 SECONDS)
		return BOT_GYM_PENDING
	if(length(said_at) < 3)
		fail_reason = "said only [length(said_at)] of its three lines"
		return BOT_GYM_FAIL
	if(said_at[1] <= talked_at)
		fail_reason = "said the first the tick it was decided"
		return BOT_GYM_FAIL
	for(var/i in 2 to length(said_at))
		if(said_at[i] - said_at[i - 1] < 12) //a line takes 2 s or more to type: the timers that send them are a few tenths late or early
			fail_reason = "line [i] went out [(said_at[i] - said_at[i - 1]) / 10]s after the one before: nobody types that fast"
			return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// News goes round by being seen and told
// ---------------------------------------------------------------------------------------------

/// "Did you hear? Security's after Max Adeyemi for suspected syndicate activity." from a bot nowhere near it (bot_news() was one pool for the crew).
/datum/bot_scenario/chat/news_unseen
	name = "speech: asked what it missed, it doesn't tell of an arrest it wasn't there for"
	desc = "Security's after somebody in a room behind a wall, and the bot has no way to know. Asked \"what did i miss?\", it doesn't tell of it. Before: the news was one pool for everybody."
	job = "Assistant"
	layout = list(
		"#########",
		"#B.C#.K.#",
		"#########")
	time_limit = 15 SECONDS
	var/felon_name = "Max Felon"

/datum/bot_scenario/chat/news_unseen/post_spawn()
	..()
	var/mob/living/carbon/human/felon = stand_in(first_marker("K"), felon_name)
	bot_news("Security's after [felon_name] for vandalism", felon)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "what did i miss?"), 2 SECONDS)

/datum/bot_scenario/chat/news_unseen/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "said nothing to \"what did i miss?\""
		return BOT_GYM_FAIL
	if(findtext(lines[1], "Security's after"))
		fail_reason = "told of what happened out of its sight: \"[lines[1]]\"" //its own, or another scenario's arena's: all one pool before
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// What it did see, it tells.
/datum/bot_scenario/chat/news_unseen/seen
	name = "speech: asked what it missed, it tells of an arrest it saw"
	desc = "Security's after somebody in the same room, in plain view of the bot. Asked \"what did i miss?\", it tells of it."
	layout = list(
		"##########",
		"#B.C....K#",
		"##########") //in view of the bot and not within three of the visitor, which would make the visitor's question nobody's
	felon_name = "Sam Seen"

/datum/bot_scenario/chat/news_unseen/seen/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "said nothing to \"what did i miss?\""
		return BOT_GYM_FAIL
	if(!findtext(lines[1], felon_name))
		if(seclevel2num(get_security_level()) >= SEC_LEVEL_RED)
			return BOT_GYM_PASS //another scenario's red alert is on, and that's the first thing it'd say about how the shift's going
		fail_reason = "didn't tell of what it saw: \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// Favours, asked of somebody stood in front of the asker, one every 6 s (bot_favours.dm): read the transcript for whether each answer fits.
/datum/bot_scenario/chat/sweep/favours
	name = "speech: favours asked face to face"
	desc = "Bring me a crowbar, come with me, show me where medbay is, call the doctor, tell security: whether what comes back fits."
	lines = list("can you bring me a crowbar?", "can you show me where medbay is?", "can you call the doctor?", "can you tell security?", "go get the captain", "can you hold this for me?", "can you watch my stuff?", "can you give me a hand with this?", "go get the janitor", "bring me a toolbox", "can you grab me a welder?", "take me to engineering", "lead the way", "where can i get a pen?", "do you have a pen?", "can i borrow your crowbar?", "can you lend me some money?", "can you cover for me?", "i need a ride", "can you take me to medbay?")
	pass_thirds = 1.5

/// "Can you lend me some money?" is something asked of it, not a question it doesn't know the answer to ("Wish I knew.").
/datum/bot_scenario/chat/polite_request
	name = "speech: \"can you lend me some money?\" is turned down, not met with \"wish I knew\""
	desc = "The visitor asks the bot for a favour it can't do. It says it can't, in some way or other, instead of a stock \"I don't know\"."
	job = "Assistant"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 15 SECONDS

/datum/bot_scenario/chat/polite_request/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "can you lend me some money?"), 2 SECONDS)

/datum/bot_scenario/chat/polite_request/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "said nothing to \"can you lend me some money?\""
		return BOT_GYM_FAIL
	if(lines[1] in GLOB.bot_question_reply_lines)
		fail_reason = "answered a request as a question it didn't know: \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// "Can you call the doctor?" and "can you tell security?" were answered "No clue." and "Beats me." (bot_favours.dm had call words for Security, Engineering and the janitor, not the doctor).
/datum/bot_scenario/chat/call_the_doctor
	name = "speech: \"can you call the doctor?\" is something it does, not a question it doesn't know"
	desc = "Asked to call the doctor, the bot calls over the radio or says there's nobody to call. Before: \"No clue.\""
	job = "Assistant"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 15 SECONDS

/datum/bot_scenario/chat/call_the_doctor/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "can you call the doctor?"), 2 SECONDS)

/datum/bot_scenario/chat/call_the_doctor/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "said nothing to \"can you call the doctor?\""
		return BOT_GYM_FAIL
	if(!(lines[1] in list("Calling them.", "Sure.", "Don't think there's anybody on.", "Can't raise anyone, sorry.")))
		fail_reason = "answered \"can you call the doctor?\" with \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// What people say that isn't a question or an order, said to somebody stood in front of them, one every 6 s: read the transcript for whether each answer fits.
/datum/bot_scenario/chat/sweep/statements
	name = "speech: statements face to face"
	desc = "I'm bored, the engine's on fire, there's a body in medbay, brb: whether what comes back fits."
	lines = list("i'm bored", "this station sucks", "the engine is on fire", "there's a body in medbay", "i found a gun", "someone stole my pda", "the captain is dead", "i'm going to cargo", "brb", "afk", "lol", "that's funny", "i'm tired", "i'm hungry", "i just got here", "it's quiet today", "somebody's been in my locker", "i'm lost", "my head hurts", "i don't feel well", "the lights are out", "the door's stuck", "i can't breathe", "there's a fire in cargo", "i saw a ghost", "the clown stole my shoes", "i love this job", "i hate this job", "good game", "see you later")
	pass_thirds = 1.5

/// "I'm going to cargo" and "the clown stole my shoes" got "Don't think we've got a cargo technician." and "Nobody's on clown, sorry.": a line with a job's
/// name in it isn't a call to it for that. And "i can't breathe" got "Okay.".
/datum/bot_scenario/chat/about_a_job
	name = "speech: \"the clown stole my shoes\" isn't a call for a clown, and \"i can't breathe\" isn't met with \"okay\""
	desc = "Two statements said to a bot: one with a job in it that's about the job, one that needs somebody to say something. Neither gets \"nobody's on clown\" or \"Okay.\""
	job = "Assistant"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 25 SECONDS

/datum/bot_scenario/chat/about_a_job/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "the clown stole my shoes"), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "i can't breathe"), 14 SECONDS)

/datum/bot_scenario/chat/about_a_job/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 20 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	for(var/line in lines)
		if(findtext(line, "clown") || findtext(line, "Nobody's on"))
			fail_reason = "answered a statement as a call for the clown: \"[line]\""
			return BOT_GYM_FAIL
	if(!length(lines))
		fail_reason = "said nothing to \"i can't breathe\""
		return BOT_GYM_FAIL
	var/last = lines[length(lines)]
	if(last in list("Okay.", "Alright.", "Right.", "Gotcha.", "Yeah."))
		fail_reason = "answered \"i can't breathe\" with \"[last]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// What's said over Common to nobody in particular: a bystander's reactions, if any. Read the transcript: silence is fine, nonsense isn't.
/datum/bot_scenario/chat/sweep/radio_lines/to_nobody
	name = "speech: lines over Common to nobody in particular"
	job = "Assistant"
	pass_thirds = 0
	lines = list("traitor in cargo", "someone fix the lights in medbay", "fire in medbay", "plasma flood in engineering", "hull breach in cargo", "the singularity is loose", "the supermatter is delaminating", "the AI is rogue", "the shuttle's here", "the captain is dead", "sec is traitor", "xenos in maint", "i'm at the bridge", "who has insuls?", "anyone seen the captain?", "i need a medic, i'm in cargo", "sec to medbay", "where is everyone?", "gg", "that was loud")

/// "security, is the brig empty?" was answered ";Responding to a call from Casey Visitor in ..." (the word "security" was a call whatever else was said).
/datum/bot_scenario/chat/question_to_security
	name = "speech: \"security, is the brig empty?\" isn't a call for Security"
	desc = "The visitor asks an officer a question about Security over Common. The officer doesn't set off as if it were a call. Before: \"Responding to a call\"."
	job = "Security Officer"
	layout = list(
		"#########",
		"#B.....C#",
		"#########")
	time_limit = 18 SECONDS

/datum/bot_scenario/chat/question_to_security/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/chat/question_to_security/proc/ask()
	log_line("visitor (over Common): \"security, is the brig empty?\"")
	brain.on_heard_security_call(visitor, "security, is the brig empty?", FREQ_COMMON)

/datum/bot_scenario/chat/question_to_security/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	for(var/line in spoken())
		if(findtext(line, "Responding to a call"))
			fail_reason = "answered a question about Security as a call: \"[line]\""
			return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// "Why you following me?" (the user's own, face to face): "Couldn't tell you." was the answer.
/datum/bot_scenario/chat/following_me
	name = "speech: \"why you following me?\" gets a denial, not \"couldn't tell you\""
	desc = "The visitor asks why the bot is following them. It says it isn't."
	job = "Assistant"
	layout = list(
		"#######",
		"#B.C..#",
		"#######")
	time_limit = 15 SECONDS

/datum/bot_scenario/chat/following_me/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "why you following me?"), 2 SECONDS)

/datum/bot_scenario/chat/following_me/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!length(lines))
		fail_reason = "said nothing to \"why you following me?\""
		return BOT_GYM_FAIL
	if(lines[1] in GLOB.bot_question_reply_lines)
		fail_reason = "answered an accusation as a question it didn't know: \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// "Nobody in Medbay right now." from a chemist at the Bar: shop_talk_now() read the state of the whole department from anywhere.
/datum/bot_scenario/shop_talk_away
	name = "speech: a chemist away from Medbay doesn't tell how many are in it"
	desc = "Its department's state (patients in Medbay, the cells, the SMES) is what it can see where it works. Stood somewhere else it has nothing of the sort to say. Before: it said how many were in Medbay."
	job = "Chemist"
	layout = list(
		"#####",
		"#.B.#",
		"#####")
	time_limit = 6 SECONDS

/datum/bot_scenario/shop_talk_away/issue_goal()
	return

/datum/bot_scenario/shop_talk_away/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 2 SECONDS)
		return BOT_GYM_PENDING
	var/list/fact = brain.shop_talk_now()
	if(fact)
		fail_reason = "talked of the state of its department from the wrong side of the station: \"[fact[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Second pass: Security named as a place, animals, the HoP
// ---------------------------------------------------------------------------------------------

/// "On my way to Sec office with the mop." (a janitor's line) sent an officer to it: "sec" in about 10 of 1262 calls answered in the shift batches.
/datum/bot_scenario/chat/place_not_call
	name = "speech: \"on my way to sec office with the mop\" isn't a call for Security"
	desc = "Security named as a place, not called. The officer doesn't respond. Before: \"Responding to a call\"."
	job = "Security Officer"
	layout = list(
		"#########",
		"#B.....C#",
		"#########")
	time_limit = 18 SECONDS
	var/said_line = "on my way to sec office with the mop"
	var/expect_call = FALSE

/datum/bot_scenario/chat/place_not_call/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/chat/place_not_call/proc/ask()
	log_line("visitor (over Common): \"[said_line]\"")
	brain.on_heard_security_call(visitor, said_line, FREQ_COMMON)

/datum/bot_scenario/chat/place_not_call/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	var/answered = FALSE
	for(var/line in spoken())
		if(findtext(line, "Responding to a call"))
			answered = TRUE
	if(answered && !expect_call)
		fail_reason = "answered a line naming Security as a place as a call"
		return BOT_GYM_FAIL
	if(!answered && expect_call)
		fail_reason = "didn't answer a call for Security"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/chat/place_not_call/control
	name = "speech: \"sec to the bar\" is still a call for Security"
	desc = "The same officer, a line that does call it."
	said_line = "sec to the bar please"
	expect_call = TRUE

/// Poly picks up what the crew say and repeats it: ";Security help!" from a parrot sent officers to the parrot.
/datum/bot_scenario/chat/parrot_calls
	name = "speech: a parrot saying \"security help\" isn't a call, and nobody says hello back to it"
	desc = "A parrot repeats what it's heard. The officer neither responds to it nor answers it."
	job = "Security Officer"
	layout = list(
		"#########",
		"#B.....C#",
		"#########")
	time_limit = 18 SECONDS
	var/mob/living/simple_animal/parrot/parrot

/datum/bot_scenario/chat/parrot_calls/post_spawn()
	..()
	parrot = new(visitor.loc)
	parrot.name = "Pollie"
	addtimer(CALLBACK(src, PROC_REF(squawk)), 2 SECONDS)

/datum/bot_scenario/chat/parrot_calls/proc/squawk()
	if(QDELETED(parrot))
		return
	log_line("parrot: \"security help\" and \"hey\"")
	brain.on_heard_security_call(parrot, "security help", FREQ_COMMON)
	brain.on_heard_speech(parrot, "security help", FREQ_COMMON)
	brain.on_heard_speech(parrot, "hey", null)

/datum/bot_scenario/chat/parrot_calls/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(length(lines))
		fail_reason = "answered a parrot: \"[lines[1]]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// The HoP just asked "What do you need it for?" and the next thing said isn't the answer.
/datum/bot_scenario/chat/hop_context
	name = "speech: after \"what do you need it for?\" the HoP answers \"hop, are you there?\" as that, and tells which jobs are open"
	desc = "The HoP is asked for access and asks what for. The asker then says \"hop, are you there?\", and \"which jobs are open?\". Before: \"Access to what?\", and \"Beats me.\"."
	job = "Head of Personnel"
	layout = list(
		"#########",
		"#B.C....#",
		"#########")
	time_limit = 40 SECONDS

/datum/bot_scenario/chat/hop_context/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "hop, i need access"), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "hop, are you there?"), 14 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "which jobs are open?"), 26 SECONDS)

/datum/bot_scenario/chat/hop_context/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 34 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(length(lines) < 3)
		fail_reason = "only said [english_list(lines)]"
		return BOT_GYM_FAIL
	var/asked = 0
	for(var/line in lines)
		if(line in list("Access to what?", "What do you need it for?", "What for?", "Where do you need to get into?"))
			asked++
	if(asked > 1)
		fail_reason = "asked what the access was for more than once: [english_list(lines)]"
		return BOT_GYM_FAIL
	var/last = lines[length(lines)]
	if(!(findtext(last, "pen") || findtext(last, "full") || findtext(last, "filled") || findtext(last, "Slots")))
		fail_reason = "answered \"which jobs are open?\" with \"[last]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// News of something that happened somewhere (bot_news() with a place): known to whoever's within earshot, not to a bot the length of the station away.
/datum/bot_scenario/news_place
	name = "speech: news of a blast is known to the bot beside it and not to the one across the station"
	desc = "A blast goes off beside one bot and 30 tiles from another. Asked how the shift's going, the first tells of it and the other has no idea. Before: the news was everybody's."
	job = "Assistant"
	layout = list(
		"###################################",
		"#B.K.............................b#",
		"###################################")
	time_limit = 8 SECONDS
	var/mob/living/carbon/human/far

/datum/bot_scenario/news_place/issue_goal()
	return

/datum/bot_scenario/news_place/post_spawn()
	far = second_bot(first_marker("b"), "Far Away")
	call("/proc/bot_news")("a bomb went off in the gym's far corner", null, first_marker("K"), 15) //the old bot_news() takes two: there the news goes to everybody

/datum/bot_scenario/news_place/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 2 SECONDS)
		return BOT_GYM_PENDING
	var/near_says = brain.shift_news()
	var/far_says = far.bot_brain.shift_news()
	if(!findtext(near_says, "bomb went off"))
		fail_reason = "the bot beside it didn't know: \"[near_says]\""
		return BOT_GYM_FAIL
	if(findtext(far_says, "bomb went off"))
		fail_reason = "the one 30 tiles away knew of it: \"[far_says]\""
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// "How's the engine?" over Common got nothing from an engineer, and what it'd have had to look to know otherwise. Away from its department it says it hasn't looked.
/datum/bot_scenario/chat/status_question
	name = "speech: \"how's the engine?\" over Common gets \"haven't looked\" from an engineer who isn't in Engineering"
	desc = "An engineer stood in the Gym is asked how the engine is. It has no way to know, and says so. Before: nothing."
	job = "Station Engineer"
	layout = list(
		"#########",
		"#B.....C#",
		"#########")
	time_limit = 18 SECONDS
	var/said_line = "how's the engine?"
	var/expect_answer = TRUE

/datum/bot_scenario/chat/status_question/post_spawn()
	..()
	brain.sociability = 1
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/chat/status_question/proc/ask()
	log_line("visitor (over Common): \"[said_line]\"")
	brain.on_heard_speech(visitor, said_line, FREQ_COMMON)

/datum/bot_scenario/chat/status_question/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	var/list/lines = spoken()
	if(!expect_answer)
		if(length(lines))
			fail_reason = "answered a question about a department it isn't in: \"[lines[1]]\""
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	if(!length(lines))
		fail_reason = "said nothing to \"[said_line]\""
		return BOT_GYM_FAIL
	if(!(findtext(lines[1], "looked") || findtext(lines[1], "No idea") || findtext(lines[1], "Couldn't say")))
		fail_reason = "answered \"[said_line]\" with \"[lines[1]]\", which it can't know from here"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/chat/status_question/medbay
	name = "speech: \"is medbay open?\" over Common gets \"haven't looked\" from a doctor who isn't in Medbay"
	job = "Medical Doctor"
	said_line = "is medbay open?"

/datum/bot_scenario/chat/status_question/not_theirs
	name = "speech: \"how's the engine?\" over Common isn't answered by an assistant"
	desc = "Somebody with nothing to do with the engine hears the question and says nothing."
	job = "Assistant"
	expect_answer = FALSE
