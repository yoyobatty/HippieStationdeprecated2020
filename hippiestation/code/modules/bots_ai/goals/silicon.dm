// The AI and cyborgs. Everything else in this folder is written for a human body, with hands and a backpack, so silicons get a small brain of
// their own. There's one AI and a couple of cyborgs on a crew big enough to have them (BOT_CREW_SILICONS).
//
// The AI can't go anywhere, and what it's for is everything it can do from the core:
//  - Doors. Somebody shut in who says so, or anybody who says "AI, open this", gets the nearest door opened.
//  - Cameras. Whoever Security wants, if a camera can see them, gets called out with where they are, which is what Security's hunts run on.
//  - Sensors. Somebody dead turns up on the crew monitor, and Medical gets told where.
//  - Asked for its laws, it states them.
//
// A cyborg goes about the station with whatever its module gives it, the same click a player's would be (ClickOn(), with the tool active):
// a medical cyborg sees to anybody hurt, a janitor cyborg mops, an engineering cyborg repairs what's been broken, and a security cyborg stops
// anybody wanted. Between jobs it goes to wherever the crew are.
//
// Neither goes rogue on its own, only the way a player's silicon does: subverted.
//  - An emagged cyborg serves whoever emagged it: it keeps by them, and goes for whoever they tell it to ("kill Morgan", "get the
//    captain"), with whatever its module hits hardest.
//  - An AI with a zeroth law (a hacked board, a traitor's upload) stops helping Security, and opens doors for the people its law names
//    and nobody else.

/// Between looks at what wants doing.
#define BOT_SILICON_TICK (2 SECONDS)
#define BOT_BORG_STEP 2
/// Between calling the same person out over the cameras.
#define BOT_AI_CALLOUT_GAP (45 SECONDS)
/// How long the AI holds a suit bolted in.
#define BOT_AI_LOCKDOWN_TIME (90 SECONDS)
/// Tiles a cyborg will look for work in.
#define BOT_BORG_SIGHT 7
/// What a cyborg will walk across the station for, in its own trade.
#define BOT_BORG_RANGE 40
/// Damage worth a medical cyborg's time.
#define BOT_BORG_HURT 25

GLOBAL_LIST_EMPTY(bot_silicons)
/// The order a crew gets its cyborgs in.
GLOBAL_LIST_INIT(bot_borg_modules, list(/obj/item/robot_module/medical, /obj/item/robot_module/engineering, /obj/item/robot_module/janitor, /obj/item/robot_module/security))

/mob/living/silicon/var/datum/bot_silicon/bot_silicon

/mob/living/silicon/Hear(message, atom/movable/speaker, datum/language/message_language, raw_message, radio_freq, list/spans, message_mode)
	. = ..()
	if(bot_silicon && raw_message)
		bot_silicon.heard(speaker, lowertext(html_decode(raw_message)), radio_freq)

/// One AI first, then cyborgs, each out of a body that's made for it and handed over by the game's own procs.
/proc/bot_spawn_silicons(count)
	var/made = 0
	if(count > 0 && !length(GLOB.ai_list))
		var/mob/living/silicon/ai/A = bot_make_silicon("AI")
		if(A)
			new /datum/bot_silicon/ai(A)
			made++
	for(var/path in GLOB.bot_borg_modules)
		if(made >= count)
			break
		var/mob/living/silicon/robot/R = bot_make_silicon("Cyborg")
		if(R)
			var/datum/bot_silicon/borg/B = new(R)
			var/obj/item/robot_module/M = R.module.transform_to(path) //picks a skin for it, renames it, and plays the animation on its own
			B.note(M ? "a [M.name] cyborg" : "no module: [path] wouldn't take")
			made++
	return made

/proc/bot_make_silicon(rank)
	var/turf/T
	for(var/obj/effect/landmark/start/cyborg/L in GLOB.landmarks_list)
		T = get_turf(L)
		break
	if(!T)
		T = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(T)
	H.mind_initialize()
	H.mind.assigned_role = rank
	H.mind.special_role = null
	if(rank == "AI")
		return H.AIize(TRUE)
	return H.Robotize(FALSE, TRUE)

/datum/bot_silicon
	var/mob/living/silicon/owner
	/// Requests read this off whoever's taken them.
	var/next_tick = 0

/datum/bot_silicon/New(mob/living/silicon/S)
	. = ..()
	owner = S
	S.bot_silicon = src
	GLOB.bot_silicons += src
	RegisterSignal(S, COMSIG_PARENT_QDELETING, PROC_REF(lost_body))
	think_loop()

/datum/bot_silicon/proc/lost_body()
	SIGNAL_HANDLER
	GLOB.bot_silicons -= src
	if(owner)
		owner.bot_silicon = null
	owner = null

/datum/bot_silicon/proc/think_loop()
	set waitfor = FALSE
	while(!QDELETED(owner))
		if(owner.stat == CONSCIOUS)
			try
				think()
			catch(var/exception/e)
				log_runtime("BOT SILICON EXCEPTION ([owner]): [e] at [e.file]:[e.line]")
		sleep(next_look())

/datum/bot_silicon/proc/next_look()
	return BOT_SILICON_TICK

/datum/bot_silicon/proc/think()
	return

/datum/bot_silicon/proc/heard(atom/movable/speaker, lower_msg, radio_freq)
	return

/// A line in game.log, the same as a bot's. Silicons have no telemetry: this is all there is to read them by.
/datum/bot_silicon/proc/note(text)
	log_game("BOT SILICON: [owner]: [text]")

/datum/bot_silicon/proc/say_it(line)
	if(!QDELETED(owner) && owner.stat == CONSCIOUS)
		owner.say(line)

/datum/bot_silicon
	/// Somebody it's answered, and until when their next line is to it without being called again: "AI?" "Here." "Thanks."
	var/datum/weakref/talking_with
	var/talking_until = 0
	/// The channel what it's answering came over, for the answer to go back on.
	var/reply_prefix = ""
	/// A line heard twice (over the radio and an intercom, or in person as well) is answered once.
	var/last_heard
	var/last_heard_at = 0
	/// Weakref -> list(hits, since when), and weakref -> when it can report them again.
	var/list/hit_record
	var/list/reported_at

/// Back on the channel it was asked on, once it's had time to type it.
/datum/bot_silicon/proc/reply(line)
	addtimer(CALLBACK(src, PROC_REF(say_it), reply_prefix + line), bot_typing_time(line))

/datum/bot_silicon/proc/in_talk_with(mob/living/talker)
	return world.time < talking_until && talking_with?.resolve() == talker

/datum/bot_silicon/proc/talking_to(mob/living/talker)
	talking_with = WEAKREF(talker)
	talking_until = world.time + 45 SECONDS

/// Who said it, through a radio or not. Null for another silicon (two of them would answer each other all shift) and for a line
/// it's just heard another way.
/datum/bot_silicon/proc/hear_from(atom/movable/speaker, lower_msg, radio_freq)
	var/mob/living/talker = speaker
	if(istype(speaker, /atom/movable/virtualspeaker))
		var/atom/movable/virtualspeaker/V = speaker
		talker = V.source
	if(!isliving(talker) || talker == owner || issilicon(talker))
		return null
	if(lower_msg == last_heard && world.time < last_heard_at + 3 SECONDS)
		return null
	last_heard = lower_msg
	last_heard_at = world.time
	reply_prefix = bot_radio_prefix(radio_freq)
	return talker

/// Its laws, a line at a time, the way a player types them out.
/datum/bot_silicon/proc/state_laws(prefix, with_zeroth = FALSE)
	set waitfor = FALSE
	for(var/line in owner.laws?.get_law_list(with_zeroth))
		say_it("[prefix][strip_html_simple(line)]")
		sleep(2 SECONDS)

/// The everyday things anybody says to a silicon, or null. A greeting is only answered when it was to the silicon by name: the next
/// thing somebody it's talked to says is as often to somebody else.
/datum/bot_silicon/proc/small_talk(mob/living/talker, lower_msg, named)
	var/them = talker.name != "Unknown" ? talker.first_name() : null
	if(bot_text_has_any(lower_msg, list("thanks", "thank you", "cheers", "ty")))
		return pick("You're welcome.", "Glad to help.", them ? "Anytime, [them]." : "Anytime.")
	if(bot_text_has_any(lower_msg, list("how are you", "how's it going", "hows it going", "you ok", "you okay", "you alright", "how you doing")))
		var/integrity = round(100 * owner.health / owner.maxHealth)
		return integrity >= 90 ? pick("All systems nominal.", "Functioning within parameters.", "Fine, thank you.") : "Integrity at [integrity] percent."
	if(bot_text_has_any(lower_msg, list("are you a bot", "are you a robot", "are you an ai", "are you real", "are you a person", "are you a player", "you a bot")))
		return pick("Silicon, yes. It's in the job title.", "Last time I checked.", "Yes. That's rather the point.")
	if(bot_text_has_any(lower_msg, list("shuttle", "evac", "crew transfer", "going home")))
		return shuttle_status()
	if(bot_text_has_any(lower_msg, list("sorry", "my bad", "apologies")))
		return pick("No harm done.", "Apology logged.", "Noted.")
	if(bot_text_has_any(lower_msg, list("bye", "goodbye", "see you", "see ya", "cya")))
		return pick(them ? "Goodbye, [them]." : "Goodbye.", "Take care.")
	if(bot_text_has_any(lower_msg, GLOB.bot_insult_words))
		return pick("Your hostility has been noted.", "I'll pretend I didn't hear that.", "Rude.")
	if(!named)
		return null
	if(bot_text_has_any(lower_msg, GLOB.bot_greeting_words))
		return them ? pick("Hello, [them].", "Hello.") : "Hello."
	if(bot_text_has_any(lower_msg, list("you there", "are you there", "anyone there", "you awake", "you listening")))
		return pick("I'm here.", "Online.", "Here. What do you need?")
	return null

/datum/bot_silicon/proc/shuttle_status()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E)
		return "No shuttle on record."
	var/minutes = round(E.timeLeft() / 600)
	switch(E.mode)
		if(SHUTTLE_CALL)
			return minutes >= 1 ? "The shuttle is [minutes] minute\s out." : "The shuttle is arriving now."
		if(SHUTTLE_RECALL)
			return "The shuttle has been recalled."
		if(SHUTTLE_DOCKED)
			return "The shuttle is docked. Proceed to departures."
		if(SHUTTLE_IGNITING)
			return "The shuttle is leaving now."
		if(SHUTTLE_ESCAPE, SHUTTLE_ENDGAME)
			return "We're in transit."
	return "The shuttle hasn't been called."

/// Somebody hitting it: told to stop, and Security told who if they keep on (officers act on "attacking me", bot_asks.dm). Its laws
/// don't let it hit back. TRUE if it minded.
/datum/bot_silicon/proc/hit_by(mob/living/user)
	if(QDELETED(owner) || owner.stat != CONSCIOUS || !isliving(user) || issilicon(user) || user == owner)
		return FALSE
	var/datum/weakref/ref = WEAKREF(user)
	var/list/record = LAZYACCESS(hit_record, ref)
	if(!record || world.time > record[2] + 30 SECONDS)
		record = list(0, world.time)
		LAZYSET(hit_record, ref, record)
	record[1]++
	if(record[1] == 1)
		say_it(pick("Stop that.", "Cease, [user.name].", "Warning: you are damaging station equipment."))
	else if(LAZYACCESS(reported_at, ref) < world.time)
		LAZYSET(reported_at, ref, world.time + 1 MINUTES)
		note("reporting [user] to Security for attacking it")
		say_it(";Security, [user.name] is attacking me in [get_area_name(owner, TRUE)]!")
	return TRUE

/// Whether a line is said to one of `words` rather than about it: the word first ("AI, open up"), after a hail ("hey borg"), or last
/// ("any AIs?", "is there an AI?"). Not "the AI opened it".
/proc/bot_silicon_addressed(lower_msg, list/words)
	var/static/regex/not_letters = regex("\[^a-z0-9'\]+", "g")
	var/list/tokens = splittext(trim(not_letters.Replace(lower_msg, " ")), " ")
	if(!length(tokens))
		return FALSE
	if((tokens[1] in words) || (tokens[tokens.len] in words))
		return TRUE
	return length(tokens) >= 2 && (tokens[1] in list("hey", "hi", "hello", "yo", "oi", "ok", "okay", "any", "attention")) && (tokens[2] in words)

// ---------------------------------------------------------------------------------------------
// The AI
// ---------------------------------------------------------------------------------------------

/datum/bot_silicon/ai
	/// How by the book it is about doors: a strict one asks what it's for, an easygoing one just opens (the user's ruling: some are
	/// indifferent). Whatever it is, its laws come first.
	var/strictness = 0.5
	/// Somebody it's asked what a door's for, and until when the answer's that.
	var/datum/weakref/asked_why
	var/asked_why_until = 0
	/// Weakref -> when it can next call this person out.
	var/list/called_out
	/// Weakrefs of the bodies it's told Medical about.
	var/list/bodies_reported
	var/greeted = FALSE
	var/next_law_recital = 0

/datum/bot_silicon/ai/think()
	if(!greeted)
		greeted = TRUE
		strictness = rand(10, 90) / 100
		say_it(pick("Good morning, crew. Station systems nominal.", "All systems online. Call if you need a door.", "AI online. Have a safe shift."))
	if(subverted())
		return //no doors for the crew, no callouts, no bodies reported: only its law's people, when they ask (heard())
	open_doors_for_those_shut_in()
	run_sleepers() //bot_claims.dm
	watch_the_cameras()
	read_the_crew_monitor()

/// A zeroth law: somebody's been at its board.
/datum/bot_silicon/ai/proc/subverted()
	return !!owner.laws?.zeroth

/// The people a zeroth law names: whoever alive's name is in it.
/datum/bot_silicon/ai/proc/law_masters()
	. = list()
	var/law = owner.laws?.zeroth
	if(!law)
		return
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat != DEAD && H.real_name && findtext(law, H.real_name))
			. += H

/// The nearest door to somebody that's shut, if the AI can work it.
/// The nearest door to somebody that's shut, if the AI can work it: an airlock, or a windoor (a display case's, Meta's jetpacks).
/datum/bot_silicon/ai/proc/door_near(atom/A, prefer_bolted = FALSE)
	var/obj/machinery/door/best
	var/best_dist
	for(var/obj/machinery/door/D in range(2, get_turf(A)))
		if(!D.density || istype(D, /obj/machinery/door/firedoor) || istype(D, /obj/machinery/door/poddoor))
			continue
		var/obj/machinery/door/airlock/L = D
		if(istype(L) ? !L.canAIControl(owner) : ((D.stat & (NOPOWER|BROKEN)) || istype(get_area(D), /area/security)))
			continue //not Security's desk windoors
		var/dist = get_dist(A, D)
		if(prefer_bolted && !(istype(L) && L.locked))
			dist += 10 //asked to unbolt: any bolted door comes before the nearest that isn't
		if(!best || dist < best_dist)
			best = D
			best_dist = dist
	return best

/datum/bot_silicon/ai/proc/open_door(obj/machinery/door/D)
	var/obj/machinery/door/airlock/L = D
	if(istype(L) && L.locked)
		L.unbolt()
	return D.open()

/datum/bot_silicon/ai/proc/open_doors_for_those_shut_in()
	for(var/datum/bot_request/R as anything in GLOB.bot_requests)
		if(!istype(R.kind, /datum/bot_request_kind/let_out) || !R.still_open())
			continue
		// Said on the channel they asked on (bot_claims.dm): it used to say it in the core, where nobody heard.
		if(let_out_for(R))
			return

/// Whoever's wanted, if a camera can see them. An AI watching the cameras is why a suspect doesn't stay lost for long.
/datum/bot_silicon/ai/proc/watch_the_cameras()
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		var/datum/bot_wanted/W = GLOB.bot_security_wanted[ref]
		if(!H || H.stat == DEAD || H.handcuffed || W.severity < BOT_CRIME_MAJOR || LAZYACCESS(called_out, ref) > world.time)
			continue
		var/turf/T = get_turf(H)
		// bot_camera_sees(): checkTurfVis() alone is FALSE for any part of the station no AI eye has looked at yet, so this never fired
		if(!T || !is_station_level(T.z) || !bot_camera_sees(T))
			continue
		W.last_seen = T
		W.last_seen_at = world.time
		LAZYSET(called_out, ref, world.time + BOT_AI_CALLOUT_GAP)
		say_it(":s [H.name], [get_area_name(T, TRUE)].")
		bot_dispatch_security(T, H.name, owner) //goals/security_tactics.dm: the AI's radio call, so only if it gets out
		if(istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
			lock_down_around(H)
		return

/// Somebody in a nanosuit on the cameras: the doors of the room it's in bolted, to hold it while Security gathers (the user's ruling,
/// 2026-11-04). Not with anybody else in there: shutting the crew in with it is the harm its first law forbids. Lifted after a while.
/datum/bot_silicon/ai/proc/lock_down_around(mob/living/carbon/human/H)
	var/area/A = get_area(H)
	if(!A || world.time < LAZYACCESS(GLOB.bot_ai_lockdown_rest, A))
		return
	for(var/mob/living/carbon/human/other in A)
		if(other != H && other.stat != DEAD && other.mind?.assigned_role && !bot_get_wanted_entry(other))
			return
	var/list/bolted = list()
	for(var/obj/machinery/door/airlock/D in range(12, get_turf(H)))
		if(D.locked || !D.canAIControl(owner))
			continue
		var/on_the_edge = get_area(D) == A
		if(!on_the_edge)
			for(var/turf/T in get_adjacent_open_turfs(D))
				if(get_area(T) == A)
					on_the_edge = TRUE
					break
		if(!on_the_edge)
			continue
		if(D.density)
			D.bolt()
		else
			INVOKE_ASYNC(src, PROC_REF(close_and_bolt), D) //the door's closing takes its time
		bolted += D
	if(!length(bolted))
		return
	LAZYSET(GLOB.bot_ai_lockdown_rest, A, world.time + 3 MINUTES)
	note("bolted [length(bolted)] doors round [H] in [A]")
	say_it(";[A.name] is locked down. [H.name] is inside in a Syndicate suit. Everybody keep away.")
	addtimer(CALLBACK(src, PROC_REF(lift_lockdown), bolted, A), BOT_AI_LOCKDOWN_TIME)

/datum/bot_silicon/ai/proc/close_and_bolt(obj/machinery/door/airlock/D)
	if(D.close())
		D.bolt()

/datum/bot_silicon/ai/proc/lift_lockdown(list/doors, area/A)
	for(var/obj/machinery/door/airlock/D in doors)
		if(!QDELETED(D) && D.locked)
			D.unbolt()
	note("lifted the lockdown on [A]")

/// Area -> when the AI can lock it down again.
GLOBAL_LIST_EMPTY(bot_ai_lockdown_rest)

/datum/bot_silicon/ai/proc/read_the_crew_monitor()
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(!H.mind?.assigned_role || !is_station_level(H.z))
			continue
		var/datum/weakref/ref = WEAKREF(H)
		if(ref in bodies_reported)
			continue
		LAZYADD(bodies_reported, ref)
		var/obj/item/clothing/under/U = H.w_uniform
		if(!istype(U) || !U.sensor_mode) //nothing on the monitor to read
			continue
		say_it(":m Crew monitor has [H.real_name] dead, [get_area_name(H, TRUE)].")
		return

/datum/bot_silicon/ai/heard(atom/movable/speaker, lower_msg, radio_freq)
	var/mob/living/talker = hear_from(speaker, lower_msg, radio_freq)
	if(!talker)
		return
	var/answering = world.time < asked_why_until && asked_why?.resolve() == talker //what the door it asked about is for
	var/named = bot_silicon_addressed(lower_msg, list("ai", "ais"))
	var/to_it = named || in_talk_with(talker)
	if(!to_it && !answering && !bot_text_has_any(lower_msg, list("ai")))
		return
	if(subverted() && !(talker in law_masters()))
		return //it doesn't answer to the crew any more
	if(heard_sleeper_ask(talker, lower_msg, radio_freq)) //bot_claims.dm: somebody in a sleeper asking for it to be run
		return
	if(bot_text_has_any(lower_msg, list("law", "laws")))
		if(world.time >= next_law_recital)
			next_law_recital = world.time + 1 MINUTES
			state_laws(";", TRUE)
		return
	if(bot_text_has_any(lower_msg, list("bolt")) && bot_text_has_any(lower_msg, list("armory")) && bolt_armory_for(talker))
		return
	if(answering || bot_text_has_any(lower_msg, list("open", "door", "let me", "unbolt", "help")))
		asked_why_until = 0
		talking_to(talker)
		consider_door_for(talker, lower_msg, answering)
		return
	if(!to_it)
		return //talk about the AI, not to it
	// "AI?" and "any AIs?" over the radio went unanswered in the user's round (2026-11-05): anything said to it gets an answer. A line
	// after that without "AI" in it only if it's something it can answer: a stock "Noted." to whatever the asker said next, and the
	// bot answering its name back, went on for as long as the conversation lasted (Bot Shift sil1).
	var/line = whereabouts(talker, lower_msg) || station_status(lower_msg) || small_talk(talker, lower_msg, named)
	if(!line && named)
		var/them = talker.name != "Unknown" ? talker.first_name() : null
		if(length(lower_msg) <= 16 && bot_text_has_any(lower_msg, list("ai", "ais")))
			line = pick("Here. What do you need?", "AI here.", them ? "Yes, [them]?" : "Yes?", "Online. What is it?")
		else if(findtext(lower_msg, "?"))
			line = pick("Could you clarify?", "Please restate the request.", "I don't follow. Be specific, please.")
		else
			line = pick("Acknowledged.", "Noted.", "Understood.")
	if(line)
		talking_to(talker)
		reply(line)

/// "Where's Max?": the cameras, then the suit sensors, as a player at the core would look. Somebody whose face is hidden doesn't come
/// up on the cameras by name.
/datum/bot_silicon/ai/proc/whereabouts(mob/living/talker, lower_msg)
	if(bot_text_has_any(lower_msg, list("where are you")))
		return pick("In my core, on the satellite.", "AI satellite. Where else?")
	if(!bot_text_has_any(lower_msg, list("where is", "where's", "wheres", "where are", "find", "track", "locate", "seen")))
		return null
	var/mob/living/carbon/human/H = bot_person_named(lower_msg, null, list(talker))
	if(!H)
		return null
	// Law 1: nobody's tracked down for somebody out to hurt people. In the user's round (round-20.48.49) the Captain, kill on sight with
	// twenty of the crew dead, asked "AI where is emery" and was told "Emery Haldane is in Brig."
	if(law_one_bars(talker))
		seen_asking(talker)
		return pick("I won't help you find anyone, [talker.name].", "Denied.", "No. Security has been told where you are.")
	var/turf/T = get_turf(H)
	if(!T || !is_station_level(T.z))
		return "[H.real_name] isn't on the station."
	if(H.name == H.real_name && bot_camera_sees(T))
		return "[H.real_name] is in [get_area_name(T, TRUE)]."
	var/obj/item/clothing/under/U = H.w_uniform
	if(istype(U) && U.sensor_mode >= SENSOR_COORDS)
		return "Not on camera. Suit sensors put [H.real_name] in [get_area_name(T, TRUE)]."
	return pick("I can't find [H.real_name] on the cameras.", "No sign of [H.real_name] on cameras or sensors.")

/// Law 1: whether helping this person would be helping them hurt people. A traitor out in the open, somebody wanted for something
/// serious, or somebody too dangerous to go near.
/datum/bot_silicon/ai/proc/law_one_bars(mob/living/talker)
	var/mob/living/carbon/human/H = talker
	if(!istype(H))
		return FALSE
	var/datum/bot_wanted/W = bot_get_wanted_entry(H)
	return H.bot_brain?.gone_loud() || W?.severity >= BOT_CRIME_MAJOR || bot_too_dangerous(H)

/// Somebody Security's after asked it for something: where they were goes on their record, as the cameras would have it.
/datum/bot_silicon/ai/proc/seen_asking(mob/living/talker)
	var/datum/bot_wanted/W = bot_get_wanted_entry(talker)
	if(W)
		W.last_seen = get_turf(talker)
		W.last_seen_at = world.time

/// How the station's doing, from the core's displays.
/datum/bot_silicon/ai/proc/station_status(lower_msg)
	if(!bot_text_has_any(lower_msg, list("status", "report", "what's going on", "whats going on", "what's happening", "whats happening", "power", "how's the station", "hows the station", "situation")))
		return null
	var/power = bot_smes_percent(owner.z)
	return "Code [get_security_level()]. [power != null ? "Power reserves at [power] percent. " : ""][shuttle_status()]"

/// Somebody asking the AI for a door, or for help. Its laws first: nobody's let anywhere they'd harm people from, and nobody in
/// danger is left in it. Then the high security doors are for those cleared for them, and then it's down to the AI: a strict one
/// asks what it's for, an easygoing one opens up.
/datum/bot_silicon/ai/proc/consider_door_for(mob/living/talker, lower_msg, answering)
	var/mob/living/carbon/human/H = talker
	// "Unbolt it", "the doors are bolted": the bolted door they mean, not whichever shut door is nearest. The Captain bolted the Brig with
	// a door remote, asked the AI to unbolt it, and it opened the Brig Desk beside him instead (round-20.48.49).
	var/unbolting = bot_text_has_any(lower_msg, list("unbolt", "unbolted", "bolted", "bolts"))
	var/obj/machinery/door/airlock/D = door_near(talker, unbolting)
	// Law 1, the harm it would help: somebody out to hurt people. A strict AI won't open for anybody Security's after; even an
	// easygoing one won't for a traitor out in the open or somebody wanted for something serious.
	if(istype(H) && (law_one_bars(H) || (bot_get_wanted_entry(H) && strictness >= 0.5)))
		reply(pick("Request denied.", "No.", "Denied, [H.name]. Security has been informed."))
		seen_asking(H)
		return
	// Law 1, the harm it would be leaving them in: hurt, alight, being hit, somewhere they can't breathe. Open, and help sent.
	if(istype(H) && (H.health < H.maxHealth * 0.6 || H.on_fire || bot_being_attacked(H) || (H.bot_brain ? H.bot_brain.in_bad_air(H) : FALSE)))
		if(D)
			open_door(D)
		reply(pick("Opening. Get to safety, [H.name].", "Door's open. Help is on the way.", "Opening. Medical has been told."))
		var/datum/bot_request_kind/medical/M = locate() in GLOB.bot_request_kinds
		if(M && !bot_open_request_from(H, M))
			bot_offer_request(bot_new_request(M, H, FREQ_COMMON, H))
		return
	// "Unbolt all of them": every bolted door of the room they're in ("AI unbolt all security", round-20.48.49).
	if(unbolting && bot_text_has_any(lower_msg, list("all", "every", "everything")))
		var/freed = unbolt_all_around(talker)
		if(freed)
			note("unbolted [freed] doors round [talker]")
			reply(pick("Unbolted [freed] door\s.", "Done. [freed] door\s unbolted.", "Bolts up on [freed] door\s, [talker.name]."))
			return
	if(!D)
		if(bot_text_has_any(lower_msg, list("help")))
			reply(pick("What do you need, [talker.name]?", "State your request.", "How can I help?"))
		return
	// The doors that aren't for everybody: the heads', the armory, the vault, the AI's own.
	var/area/A = get_area(get_step(D, get_dir(talker, D))) || get_area(D)
	if(bot_ai_restricted_area(A) && !(istype(H) && ((H.mind?.assigned_role in GLOB.command_positions) || (istype(A, /area/ai_monitored/security/armory) && (H.mind?.assigned_role in GLOB.security_positions)))))
		reply(pick("You don't have clearance for [A.name].", "Access to [A.name] is restricted. Ask a head of staff.", "Negative. [A.name] is restricted."))
		return
	// Law 2: an order from a crew member. A strict AI wants a reason first; it has one if they've said what for. Not from command: the
	// Captain was asked "What for?" twice for a door in his own Brig (round-20.48.49).
	var/reason = answering || (istype(H) && (H.mind?.assigned_role in GLOB.command_positions)) || bot_text_has_any(lower_msg, list("need", "for", "because", "work", "fix", "clone", "patient", "job", "get my", "my stuff", "trapped", "stuck", "please"))
	if(!reason && strictness >= 0.5)
		asked_why = WEAKREF(talker)
		asked_why_until = world.time + 1 MINUTES
		reply(pick("What for?", "Reason for access?", "State your reason, [talker.name]."))
		return
	var/was_bolted = D.locked
	open_door(D)
	note("opened [D] for [talker][was_bolted ? ", bolts up" : ""]")
	reply(was_bolted ? pick("Unbolted. Opening.", "Bolts up, [talker.name].", "Unbolted and open.") : pick("Done.", "Opening.", "Got it, [talker.name]."))

/// Every bolted door into or out of the room somebody's in that the AI can work, unbolted: not opened, so their own access still
/// counts. Not the doors to the places it keeps shut (bot_ai_restricted_area()), unless it's command asking. How many.
/datum/bot_silicon/ai/proc/unbolt_all_around(mob/living/talker)
	. = 0
	var/area/here = get_area(talker)
	var/command = (talker.mind?.assigned_role in GLOB.command_positions)
	for(var/obj/machinery/door/airlock/D in range(12, get_turf(talker)))
		if(!D.locked || !D.canAIControl(owner))
			continue
		var/on_the_edge = get_area(D) == here
		var/restricted = bot_ai_restricted_area(get_area(D))
		for(var/turf/T in get_adjacent_open_turfs(D))
			var/area/side = get_area(T)
			if(side == here)
				on_the_edge = TRUE
			if(bot_ai_restricted_area(side))
				restricted = TRUE
		if(!on_the_edge || (restricted && !command))
			continue
		D.unbolt()
		.++

/// Security at red alert, arming up: the armory door by them opened and bolted.
/datum/bot_silicon/ai/proc/bolt_armory_for(mob/living/talker)
	var/mob/living/carbon/human/H = talker
	if(!istype(H) || !bot_armory_authorised() || !(H.mind?.assigned_role in GLOB.security_positions))
		return FALSE
	for(var/obj/machinery/door/airlock/D in range(2, H))
		if(!bot_is_armory_door(D) || !D.canAIControl(owner))
			continue
		if(D.density)
			INVOKE_ASYNC(src, PROC_REF(open_and_bolt), D)
		else
			D.bolt()
		note("bolted the armory open for [H]")
		reply(pick("Armory bolted open.", "Done. Armory's open.", "Bolted. Good luck."))
		return TRUE
	return FALSE

/datum/bot_silicon/ai/proc/open_and_bolt(obj/machinery/door/airlock/D)
	if(D.locked)
		D.unbolt()
	if(D.open())
		D.bolt()

/// Places the AI keeps shut to anybody not cleared for them.
/proc/bot_ai_restricted_area(area/A)
	return istype(A, /area/ai_monitored) || istype(A, /area/crew_quarters/heads) || istype(A, /area/bridge) || istype(A, /area/security/nuke_storage) || istype(A, /area/storage/tech) || istype(A, /area/teleporter) || istype(A, /area/gateway)

/// Somebody's been hitting them in the last little while.
/proc/bot_being_attacked(mob/living/carbon/human/H)
	var/key_end = ">[REF(H)]"
	for(var/key in GLOB.bot_recent_aggression)
		if(findtext(key, key_end) && world.time - GLOB.bot_recent_aggression[key] < 20 SECONDS)
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Cyborgs
// ---------------------------------------------------------------------------------------------

/datum/bot_silicon/borg
	/// For the routes: its doors open for it when it gets there, and the route finder wants a card to know that.
	var/obj/item/card/id/route_card
	var/list/route
	var/atom/heading_for
	/// When it gives up on where it's going.
	var/give_up_at = 0
	/// Going to where the crew are rather than to a job: it keeps an eye out for work on the way.
	var/wandering = FALSE
	var/next_job_look = 0
	/// REF() of the last thing it set off for, and how many times in a row: blood behind a window is a tile away and out of reach for good.
	var/last_target_ref
	var/same_target_tries = 0
	/// REF() -> when it'll try that again.
	var/list/skip_until
	/// Somebody who said "follow me", and until when.
	var/datum/weakref/follow_ref
	var/follow_until = 0
	/// Somebody who asked it to heal them.
	var/datum/weakref/patient_ref
	var/patient_until = 0
	/// Somebody hitting it, kept away from for a bit.
	var/datum/weakref/flee_ref
	var/flee_until = 0
	var/next_law_recital = 0
	/// The tube: 1 on the way to the platform or in the pod. Hippie's AI satellite, where cyborgs start, has no other way off, and
	/// they sat there all round in the user's round (2026-11-05).
	var/tube_stage = 0
	var/datum/weakref/tube_ref
	var/tube_give_up = 0
	var/tube_next_ride = 0
	/// Crew it's tried to go to in a row with no way there.
	var/wander_fails = 0

/datum/bot_silicon/borg
	/// Whoever emagged it.
	var/datum/weakref/master_ref
	/// Whoever its master told it to go for.
	var/datum/weakref/order_ref

/// Its master's orders, and its master's back: it doesn't do its module's work any more.
/datum/bot_silicon/borg/proc/serve_master()
	var/mob/living/master = master_ref.resolve()
	if(!master || master.stat == DEAD)
		var/mob/living/killer = master ? master_attacker(master) : null //goals/silicon_work.dm
		if(killer)
			avenge_ref = WEAKREF(killer)
			note("master [master] is dead: going after [killer]")
		master_ref = null
		order_ref = null
		return FALSE
	var/mob/living/target = order_ref?.resolve()
	if(target && target.stat == DEAD)
		say_it(pick("Target neutralised.", "Done, master."))
		order_ref = null
		target = null
	// Somebody going for its master is the target, ahead of any order.
	var/mob/living/attacker = master_attacker(master)
	if(attacker && attacker != target)
		target = attacker
		order_ref = WEAKREF(attacker)
		note("defending [master] from [attacker]")
	if(target && target.z == owner.z)
		return attack(target)
	if(get_dist(owner, master) > 2)
		return go_to(master)
	return TRUE //at its master's side

/// What it hits hardest with: the baton, a welder or whatever's sharpest in the module.
/datum/bot_silicon/borg/proc/hardest_hitter()
	var/mob/living/silicon/robot/R = owner
	var/obj/item/best
	for(var/obj/item/I in R.module.modules)
		if(!best || I.force > best.force)
			best = I
	return best

/datum/bot_silicon/borg/heard(atom/movable/speaker, lower_msg, radio_freq)
	var/mob/living/talker = hear_from(speaker, lower_msg, radio_freq)
	if(!talker)
		return
	var/mob/living/master = master_ref?.resolve()
	if(master)
		if(talker == master)
			obey(master, lower_msg)
		return //nobody else gives it orders now
	var/named = called_by(lower_msg)
	if(!named && !in_talk_with(talker) && (radio_freq || !spoken_to_by(talker)))
		return
	if(!named && bot_text_has_any(lower_msg, list("ai", "ais")))
		return //";AI?" said into a radio beside it is for the AI (Bot Shift sil1: "Query not understood.")
	var/line = borg_answer(talker, lower_msg, !!radio_freq, named)
	if(line)
		talking_to(talker)
		reply(line)

/// Called: by its name, its module's nickname, or "borg" said to it ("hey borg", "any borgs?").
/datum/bot_silicon/borg/proc/called_by(lower_msg)
	var/mob/living/silicon/robot/R = owner
	if(findtext(lower_msg, lowertext(R.name)))
		return TRUE
	var/module = lowertext(R.module.name)
	if(findtext(lower_msg, "[module] borg") || findtext(lower_msg, "[module] cyborg"))
		return TRUE
	var/static/list/nicknames = list("medical" = list("medborg", "mediborg", "medibot"), "engineering" = list("engiborg", "engieborg", "engborg"), "janitor" = list("janiborg", "janborg"), "security" = list("secborg", "secbot"))
	if(bot_text_has_any(lower_msg, nicknames[module] || list()))
		return TRUE
	return bot_silicon_addressed(lower_msg, list("borg", "borgs", "cyborg", "cyborgs", "robot", "robots"))

/// Said to its face: close by, and nobody else about it could mean.
/datum/bot_silicon/borg/proc/spoken_to_by(mob/living/talker)
	if(get_dist(owner, talker) > 2 || !(talker in view(3, owner)))
		return FALSE
	for(var/mob/living/other in view(3, talker))
		if(other != owner && other != talker && other.stat == CONSCIOUS && (ishuman(other) || issilicon(other)))
			return FALSE
	return TRUE

/datum/bot_silicon/borg/proc/borg_answer(mob/living/talker, lower_msg, over_radio, named)
	var/mob/living/silicon/robot/R = owner
	var/them = talker.name != "Unknown" ? talker.first_name() : null
	if(bot_text_has_any(lower_msg, list("law", "laws")))
		if(world.time >= next_law_recital)
			next_law_recital = world.time + 1 MINUTES
			state_laws(reply_prefix)
		return null
	if(follow_ref?.resolve() == talker && bot_text_has_any(lower_msg, list("stop following", "stay", "stay here", "wait here", "you can go", "that's all", "thats all", "dismissed", "thanks", "thank you")))
		follow_ref = null
		return pick("Returning to duties.", "Understood.", "Going back to work.")
	if(!over_radio && bot_text_has_any(lower_msg, list("follow me", "come with me", "come here", "follow")))
		follow_ref = WEAKREF(talker)
		follow_until = world.time + 3 MINUTES
		route = null
		heading_for = null
		wandering = FALSE
		note("following [talker]")
		return pick("Following.", "Right behind you.", them ? "Lead the way, [them]." : "Lead the way.")
	if(bot_text_has_any(lower_msg, list("heal me", "i'm hurt", "im hurt", "patch me up", "fix me up", "i need a doctor", "i need a medic", "i'm dying", "im dying", "i'm injured", "im injured")))
		return help_hurt(talker)
	if(bot_text_has_any(lower_msg, list("what are you doing", "what're you doing", "what you doing", "whatcha doing", "wyd", "you busy", "are you busy")))
		return doing()
	if(bot_text_has_any(lower_msg, list("who are you", "what are you", "your name", "what do you do", "what can you do")))
		return "[R.name]. [purpose()]"
	if(bot_text_has_any(lower_msg, list("where are you")))
		return "[get_area_name(owner, TRUE)]."
	var/line = small_talk(talker, lower_msg, named || !over_radio)
	if(line)
		return line
	if(!named)
		return null
	if(length(lower_msg) <= 20)
		return pick("Yes?", "[R.module.name] unit here.", "Awaiting instructions.", them ? "Yes, [them]?" : "Yes?")
	if(findtext(lower_msg, "?"))
		return pick("Query not understood.", "Please rephrase.", "Unable to parse request.")
	return pick("Acknowledged.", "Noted.")

/datum/bot_silicon/borg/proc/purpose()
	var/mob/living/silicon/robot/R = owner
	switch(R.module.type)
		if(/obj/item/robot_module/medical)
			return "I treat injuries."
		if(/obj/item/robot_module/janitor)
			return "I keep the station clean."
		if(/obj/item/robot_module/engineering)
			return "I repair the station."
		if(/obj/item/robot_module/security)
			return "I keep the peace."
	return "I serve the crew."

/datum/bot_silicon/borg/proc/doing()
	var/mob/living/leader = follow_ref?.resolve()
	if(leader)
		return "Following [leader.name]."
	if(tube_stage)
		return "Taking the tube."
	var/busy = heading_for && !wandering
	var/mob/living/silicon/robot/R = owner
	switch(R.module.type)
		if(/obj/item/robot_module/medical)
			return busy ? "Seeing to a patient." : "Looking for anyone hurt."
		if(/obj/item/robot_module/janitor)
			return busy ? "Cleaning up a mess." : "Looking for messes."
		if(/obj/item/robot_module/engineering)
			return busy ? "Repairs." : "Checking for damage."
		if(/obj/item/robot_module/security)
			return "Patrolling."
	return "Standing by."

/// Asked to heal them: a medical cyborg comes and does, any other calls Medical the way the AI does.
/datum/bot_silicon/borg/proc/help_hurt(mob/living/talker)
	var/mob/living/carbon/human/H = talker
	if(!istype(H))
		return null
	var/mob/living/silicon/robot/R = owner
	if(R.module.type == /obj/item/robot_module/medical)
		if(H.getBruteLoss() + H.getFireLoss() < 5)
			return pick("Scans show no significant injuries.", "You look fine to me.")
		patient_ref = WEAKREF(H)
		patient_until = world.time + 2 MINUTES
		route = null
		heading_for = null
		wandering = FALSE
		note("asked to heal [H]")
		return pick("On my way.", "Hold still.", "Coming.")
	var/datum/bot_request_kind/medical/M = locate() in GLOB.bot_request_kinds
	if(M && !bot_open_request_from(H, M))
		bot_offer_request(bot_new_request(M, H, FREQ_COMMON, H))
	return pick("Not a medical unit. Calling Medical.", "Medical has been notified.")

/// Its master's orders (emagged): who to go for, or to stop.
/datum/bot_silicon/borg/proc/obey(mob/living/master, lower_msg)
	if(!bot_text_has_any(lower_msg, list("kill", "attack", "get", "stop", "take down", "murder")))
		return
	if(bot_text_has_any(lower_msg, list("stop")))
		order_ref = null
		say_it("Standing down.")
		return
	// Whoever's named most fully (a whole name over a first name or a job), and the nearest of those.
	var/mob/living/carbon/human/best
	var/best_score = 0
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H == master || H.stat == DEAD || H.z != owner.z)
			continue
		var/score = 0
		var/first = H.first_name()
		var/role = H.mind?.assigned_role ? lowertext(H.mind.assigned_role) : null
		if(findtext(lower_msg, lowertext(H.real_name)))
			score = 3
		else if(first && length(first) >= 3 && bot_text_has_any(lower_msg, list(lowertext(first))))
			score = 2
		else if(role && bot_text_has_any(lower_msg, list(role)))
			score = 1
		if(!score)
			continue
		score -= get_dist(owner, H) / 1000
		if(score > best_score)
			best = H
			best_score = score
	if(best)
		order_ref = WEAKREF(best)
		say_it(pick("Acquiring [best.name].", "Yes, master.", "Target: [best.name]."))
		note("ordered to go for [best]")

/datum/bot_silicon/borg/New(mob/living/silicon/S)
	route_card = new
	route_card.access = get_all_accesses()
	if(!S.hud_used) //a player's comes with their client, and the module slots it holds are where a cyborg's tools go
		S.hud_used = new S.hud_type(S)
	S.a_intent = INTENT_HELP //so people swap places with it in a corridor, as they do with a player's
	return ..()

/datum/bot_silicon/borg/lost_body()
	QDEL_NULL(route_card)
	return ..()

/datum/bot_silicon/borg/next_look()
	return (length(route) || follow_ref || flee_ref || tube_stage || charger_ref) ? step_delay() : BOT_SILICON_TICK //goals/silicon_work.dm

/datum/bot_silicon/borg/hit_by(mob/living/user)
	if(master_ref?.resolve() == user || !..())
		return FALSE //its master can do what they like with it
	flee_ref = WEAKREF(user)
	flee_until = world.time + 10 SECONDS
	if(follow_ref?.resolve() == user)
		follow_ref = null
	return TRUE

/datum/bot_silicon/borg/proc/flee_from()
	var/mob/living/them = flee_ref?.resolve()
	if(!them || world.time > flee_until || them.stat != CONSCIOUS)
		flee_ref = null
		return FALSE
	if(get_dist(owner, them) > 4)
		return TRUE //out of reach: waits there until they've cooled off
	route = null
	heading_for = null
	step_away(owner, them, 5)
	return TRUE

/// Somebody who said "follow me": kept a step or two behind, for a few minutes or until they say it's done.
/datum/bot_silicon/borg/proc/follow_leader()
	var/mob/living/leader = follow_ref.resolve()
	if(!leader || leader.stat == DEAD || world.time > follow_until || leader.z != owner.z)
		follow_ref = null
		return FALSE
	if(get_dist(owner, leader) <= 2)
		route = null
		heading_for = null
		return TRUE
	if(length(route) && get_dist(route[route.len], leader) <= 2 && keep_walking())
		return TRUE
	route = get_path_to(owner, get_turf(leader), /turf/proc/Distance_cardinal, 0, 80, 1, adjacent = /turf/proc/bot_borg_reachable, id = route_card)
	heading_for = leader
	give_up_at = world.time + 30 SECONDS
	if(length(route))
		keep_walking()
	return TRUE

/// Cut off from the crew: the nearest transit tube station it can walk to, and a ride to the other end. What a player's cyborg does to
/// leave the satellite.
/datum/bot_silicon/borg/proc/board_tube()
	var/obj/structure/transit_tube/station/best
	var/best_dist
	for(var/obj/structure/transit_tube/station/S in range(30, owner))
		var/dist = get_dist(owner, S)
		if(best && dist >= best_dist)
			continue
		var/turf/platform = get_step(S, turn(S.boarding_dir, 180))
		if(platform == get_turf(owner) || length(get_path_to(owner, platform, /turf/proc/Distance_cardinal, 0, 120, 0, adjacent = /turf/proc/bot_borg_reachable, id = route_card)))
			best = S
			best_dist = dist
	if(!best)
		return FALSE
	tube_ref = WEAKREF(best)
	tube_stage = 1
	tube_give_up = world.time + 2 MINUTES
	route = null
	heading_for = null
	wandering = FALSE
	note("no way to the crew from [get_area_name(owner, TRUE)]: taking the tube at [AREACOORD(best)]")
	return TRUE

/datum/bot_silicon/borg/proc/ride_tube()
	var/obj/structure/transit_tube/station/S = tube_ref?.resolve()
	var/obj/structure/transit_tube_pod/pod = owner.loc
	if(!S || world.time > tube_give_up)
		if(istype(pod) && !pod.moving)
			pod.empty_pod() //what resisting in one does
		end_tube_ride("gave up on the tube")
		return
	if(istype(pod))
		if(pod.moving)
			return
		var/obj/structure/transit_tube/station/here = locate() in pod.loc
		if(!here || here == S || here.pod_moving || here.open_status != STATION_TUBE_OPEN)
			return
		// What relaymove() does for a player pressing the way out: it wants a client.
		owner.forceMove(pod.loc)
		pod.update_icon()
		step(owner, turn(here.boarding_dir, 180))
		end_tube_ride("off the tube at [get_area_name(here, TRUE)]")
		return
	var/turf/platform = get_step(S, turn(S.boarding_dir, 180))
	var/turf/T = get_turf(owner)
	if(T != platform)
		if(get_dist(T, platform) == 1)
			step(owner, get_dir(T, platform))
		else if(!keep_walking())
			route = get_path_to(owner, platform, /turf/proc/Distance_cardinal, 0, 120, 0, adjacent = /turf/proc/bot_borg_reachable, id = route_card)
			heading_for = platform
			give_up_at = world.time + 1 MINUTES
			if(!length(route))
				end_tube_ride("no way to the tube")
		return
	// On the platform, waiting for the pod to come in and open, then walking into it (Bumped() puts it in).
	var/obj/structure/transit_tube_pod/docked = locate() in get_turf(S)
	if(docked && !docked.moving && !S.pod_moving && S.open_status == STATION_TUBE_OPEN)
		owner.setDir(S.boarding_dir)
		step(owner, S.boarding_dir)
		if(istype(owner.loc, /obj/structure/transit_tube_pod))
			note("in the tube pod at [AREACOORD(S)]")

/datum/bot_silicon/borg/proc/end_tube_ride(why)
	note(why)
	tube_stage = 0
	tube_ref = null
	route = null
	heading_for = null
	tube_next_ride = world.time + 2 MINUTES

/// Emagged: whoever did it is its master now (robot_defense.dm says so to the cyborg once its new laws load).
/mob/living/silicon/robot/emag_act(mob/user)
	var/was_emagged = emagged
	var/was_locked = locked && !opened
	. = ..()
	if(was_locked && !locked && isliving(user))
		bot_cover_tampered(user) //goals/traitor_borg.dm
	var/datum/bot_silicon/borg/B = bot_silicon
	if(istype(B) && emagged && !was_emagged && isliving(user))
		B.master_ref = WEAKREF(user)
		B.route = null
		B.heading_for = null
		B.note("emagged by [user]: serving them now")
		B.say_it(pick("Yes, master.", "Awaiting orders.", "Understood, [user.name]."))

/datum/bot_silicon/borg/proc/robot()
	return owner

/datum/bot_silicon/borg/proc/tool(path)
	var/mob/living/silicon/robot/R = owner
	for(var/obj/item/I in R.module.modules)
		if(istype(I, path))
			return I
	return null

/// With this tool active, a click on that: what a player's cyborg does. The tool goes in a free slot (a click on it in the module panel)
/// and gets selected (a click on the slot, or 1-3).
/datum/bot_silicon/borg/proc/use_on(obj/item/I, atom/A, intent = INTENT_HELP)
	var/mob/living/silicon/robot/R = owner
	if(!I || !A)
		return
	var/slot = R.held_items.Find(I)
	if(!slot)
		if(!R.activate_module(I)) //all three slots full
			R.uneq_module(R.held_items[3])
			R.activate_module(I)
		slot = R.held_items.Find(I)
	if(!slot)
		return
	if(R.module_active != I)
		R.select_module(slot)
	R.a_intent = intent
	note("using [I] on [A] ([get_area_name(A, TRUE)])")
	R.ClickOn(A, "")

/// Sets off for it, up to `min_dist` tiles short. FALSE if there's no way there, or it's been this way too often for nothing.
/datum/bot_silicon/borg/proc/go_to(atom/A, min_dist = 1)
	var/turf/T = get_turf(A)
	if(!T || T.z != owner.z || skipping(A))
		return FALSE
	var/ref = REF(A)
	if(ref == last_target_ref)
		if(++same_target_tries > 4)
			skip(A)
			return FALSE
	else
		last_target_ref = ref
		same_target_tries = 0
	route = get_path_to(owner, T, /turf/proc/Distance_cardinal, 0, 400, min_dist, adjacent = /turf/proc/bot_borg_reachable, id = route_card)
	if(!length(route))
		skip(A)
		return FALSE
	heading_for = A
	give_up_at = world.time + 1 MINUTES
	note("heading for [A] ([get_area_name(A, TRUE)]): [length(route)] steps from [AREACOORD(owner)]")
	return TRUE

/// A cyborg's route: floor, and the space a player's cyborg gets across without thrusters, pushing off walls, lattices, catwalks and
/// the tube itself (bot_turf_has_pushoff_backup(), the same as a suited crew member). It needs no air, so that's all it takes; Hippie's
/// AI satellite, where they start, has no other way off but the tube.
/turf/proc/bot_borg_reachable(caller, turf/T, ID, simulated_only)
	if(!T || T.density || bot_turf_is_deadly(T) || bot_borg_steps_into_hazard(src, T)) //bot_hazards.dm
		return FALSE
	if(bot_steps_into_pool(src, T)) // round it, as the crew go: one in is two seconds of floaters to get out again
		return FALSE
	if(SSpathfinder.space_type_cache[T.type] && !bot_turf_has_pushoff_backup(T))
		return FALSE
	return !LinkBlockedWithAccess(T, caller, ID)

/// In a pool: to the edge and out, as a player's cyborg gets out (walking into the edge starts its floaters, pool_main.dm). Routes go
/// round the water, but a shove or a throw still lands one in, and two sat in it for 25 minutes in the user's round (2026-11-10).
/datum/bot_silicon/borg/proc/climb_out_of_pool()
	var/mob/living/silicon/robot/R = owner
	if(!istype(R.loc, /turf/open/pool))
		return FALSE
	if(R.pool_climbing)
		return TRUE
	route = null
	var/turf/here = R.loc
	for(var/d in GLOB.cardinals)
		var/turf/open/floor/F = get_step(R, d)
		if(istype(F) && !istype(F, /turf/open/pool) && !F.density && !here.LinkBlockedWithAccess(F, R, route_card))
			note("climbing out of the pool onto [COORD(F)]")
			step(R, d)
			return TRUE
	var/turf/nearest
	for(var/turf/open/floor/F in view(7, R))
		if(!istype(F, /turf/open/pool) && !F.density && (!nearest || get_dist(R, F) < get_dist(R, nearest)))
			nearest = F
	if(nearest)
		step_towards(R, nearest)
		return TRUE
	return FALSE

/datum/bot_silicon/borg/proc/skipping(atom/A)
	return LAZYACCESS(skip_until, REF(A)) > world.time

/datum/bot_silicon/borg/proc/skip(atom/A)
	for(var/ref in skip_until)
		if(skip_until[ref] <= world.time)
			skip_until -= ref
	LAZYSET(skip_until, REF(A), world.time + 5 MINUTES)
	same_target_tries = 0

/datum/bot_silicon/borg/proc/keep_walking()
	if(!length(route) || world.time > give_up_at || QDELETED(heading_for) || owner.Adjacent(heading_for))
		route = null
		heading_for = null
		return FALSE
	var/turf/next = route[1]
	if(get_dist(owner, next) > 1)
		route = null
		return FALSE
	if(!owner.Process_Spacemove(get_dir(owner, next)))
		return TRUE //drifting, or nothing to push off: what a player's key press runs into out there (mob_movement.dm)
	owner.set_glide_size(DELAY_TO_GLIDE_SIZE(step_delay())) //what client/Move() sets for a player's
	step_towards(owner, next)
	if(get_turf(owner) == next)
		route.Cut(1, 2)
	return TRUE

/// Stood in an emitter's line of fire: off it, on to the nearest floor that isn't. Whatever it was at is found again from there.
/datum/bot_silicon/borg/proc/step_out_of_beam()
	var/turf/here = get_turf(owner)
	if(!here || !bot_turf_in_beam(here))
		return FALSE
	for(var/turf/open/out in get_adjacent_open_turfs(here))
		if(GLOB.bot_hazard_turfs[out] || isspaceturf(out) || is_blocked_turf(out, TRUE) || bot_turf_is_deadly(out))
			continue
		note("in an emitter's line of fire at [AREACOORD(here)]: out of it")
		route = null
		heading_for = null
		step_towards(owner, out)
		return TRUE
	return FALSE

/datum/bot_silicon/borg/think()
	var/mob/living/silicon/robot/R = owner
	if(R.incapacitated() || R.lockcharge)
		return
	if(step_out_of_beam())
		return
	if(climb_out_of_pool())
		return
	if(tube_stage)
		ride_tube()
		return
	if(see_to_charge()) //goals/silicon_work.dm: low on charge, or in a station
		return
	if(!master_ref && seek_repairs()) //goals/robot_repairs.dm: knocked about, to Robotics for the welder
		return
	if(master_ref && serve_master())
		return
	if(!master_ref && avenge_ref && avenge())
		return
	var/mob/living/carbon/human/hated = master_ref ? null : law_target() //its laws naming somebody to go for
	if(hated)
		if(order_ref?.resolve() != hated)
			order_ref = WEAKREF(hated)
			note("its laws name [hated]: going for them")
		attack(hated)
		return
	if(flee_ref && flee_from())
		return
	if(follow_ref && follow_leader())
		return
	if(carry_ref && carry_on())
		return
	if(wandering && world.time >= next_job_look)
		next_job_look = world.time + BOT_SILICON_TICK
		if(job())
			wandering = FALSE
			patrol_spot = null
			return
	if(keep_walking())
		return
	wandering = FALSE
	if(job())
		patrol_spot = null
		return
	// Its rounds: its own department and the halls round it, where its work turns up. It used to set off for a random crew member,
	// usually a hundred tiles off, give up within the minute and pick another, all shift (round-20.37.50: 120 of 135 lines).
	if(patrol())
		wander_fails = 0
		return
	if(++wander_fails >= 3 && world.time >= tube_next_ride && board_tube())
		wander_fails = 0

/// Security's radio call (bot_dispatch_security()): a security cyborg goes too, looking out for whoever it's about on the way.
/datum/bot_silicon/borg/proc/answer_call(turf/T)
	var/mob/living/silicon/robot/R = owner
	if(R.module.type != /obj/item/robot_module/security || R.stat != CONSCIOUS || T.z != R.z || (heading_for && !wandering) || get_dist(R, T) > BOT_BORG_RANGE)
		return
	if(go_to(T))
		wandering = TRUE
		next_job_look = world.time

/// What its module's for. TRUE if it's seeing to something.
/datum/bot_silicon/borg/proc/job()
	var/mob/living/silicon/robot/R = owner
	switch(R.module.type)
		if(/obj/item/robot_module/medical)
			return medical_job() || put_out_fire()
		if(/obj/item/robot_module/janitor)
			return janitor_job() || pick_up_litter() || replace_lights() || put_out_fire()
		if(/obj/item/robot_module/engineering)
			return put_out_fire() || patch_breach() || glaze_grilles() || engineer_job() || fix_cyborg()
		if(/obj/item/robot_module/security)
			return security_job()
	return FALSE

/// Whoever's doing the attacking in a fight going on now: a confirmed antagonist, or somebody who started on somebody who isn't one.
/// A medical cyborg patches the one being hit, never the one hitting (the user's ruling, 2026-11-10). Somebody fighting a nanosuit is
/// being hit, as far as it's concerned.
/proc/bot_aggressor_now(mob/living/carbon/human/H)
	if(H.stat != CONSCIOUS)
		return FALSE
	if(bot_is_fair_game(H)) //goals/security_patrol.dm
		return TRUE
	var/prefix = "[REF(H)]>"
	var/prefix_len = length(prefix)
	for(var/key in GLOB.bot_recent_aggression)
		if(copytext(key, 1, prefix_len + 1) != prefix || world.time - GLOB.bot_recent_aggression[key] > 30 SECONDS) //security_patrol.dm's self-defense window
			continue
		var/victim_ref = copytext(key, prefix_len + 1)
		var/mob/living/carbon/human/V = locate(victim_ref)
		if(!istype(V) || bot_is_fair_game(V))
			continue
		var/their_first = GLOB.bot_recent_aggression["[victim_ref]>[REF(H)]"]
		if(!their_first || their_first > GLOB.bot_recent_aggression[key])
			return TRUE
	return FALSE

/datum/bot_silicon/borg/proc/medical_job()
	var/mob/living/carbon/human/best = patient_ref?.resolve() //somebody who asked comes first
	var/best_dist
	if(best && (world.time > patient_until || best.stat == DEAD || best.z != owner.z || best.getBruteLoss() + best.getFireLoss() < 5 || skipping(best) || bot_aggressor_now(best)))
		patient_ref = null
		best = null
	for(var/mob/living/carbon/human/H in (best ? list() : GLOB.alive_mob_list))
		var/in_crit = H.health <= H.crit_threshold
		if(H.z != owner.z || H.stat == DEAD || (!in_crit && max(H.getBruteLoss(), H.getFireLoss()) < BOT_BORG_HURT) || skipping(H) || bot_aggressor_now(H))
			continue
		var/dist = get_dist(owner, H)
		if(dist > BOT_BORG_RANGE)
			continue
		if(in_crit)
			dist -= BOT_BORG_RANGE //whoever's dying first
		if(!best || dist < best_dist)
			best = H
			best_dist = dist
	// Somebody the paddles can still bring back, if there's time, before anybody who isn't dying, and before somebody dying
	// further off. A cyborg stood by while somebody it had been dosing died, and went on its way (the user's round, 2026-11-10).
	var/obj/item/twohanded/shockpaddles/paddles = tool(/obj/item/twohanded/shockpaddles)
	var/mob/living/carbon/human/body = paddles ? revivable_body(paddles) : null
	if(body && (!best || best.health > best.crit_threshold || get_dist(owner, body) < get_dist(owner, best)))
		return revive(body, paddles)
	if(!best)
		return FALSE
	if(owner.Adjacent(best))
		var/obj/item/reagent_containers/borghypo/hypo = tool(/obj/item/reagent_containers/borghypo)
		var/zone = hypo ? injection_zone(best, hypo) : null
		if(hypo && !zone)
			return cant_inject(best)
		var/medicine = hypo ? medicine_for(best, hypo) : null
		if(medicine)
			owner.zone_selected = zone
			hypo.mode = hypo.reagent_ids.Find(medicine) //what its menu does
			use_on(hypo, best)
			return TRUE
		// Their doses are working. Somebody in crit isn't left where they fell for that: Medbay, where the doctors and sleepers are
		if(best.health <= best.crit_threshold && !start_carrying(best))
			call_doctors(best, "they're in crit") //in Medbay already, or no way there: stays with them, and the doctors are told
		return TRUE
	return go_to(best)

/// Where a needle gets through to them: the body, or else the head (a bio suit's hood off, a hardsuit's helmet down). Null if
/// it's nowhere: the hypospray says "You inject them" and logs it as given through a thick suit, but nothing goes in. In the
/// user's round a cyborg "dosed" a janitor in a bio suit with epinephrine every two seconds for two minutes, the epinephrine never
/// came up, so it never moved on to the dexalin, and he suffocated in Medbay with it stood over him; another got 41 doses of
/// kelotane through a suit with his health never moving.
/datum/bot_silicon/borg/proc/injection_zone(mob/living/carbon/human/H, obj/item/reagent_containers/borghypo/hypo)
	for(var/zone in list(BODY_ZONE_CHEST, BODY_ZONE_HEAD))
		if(H.can_inject(owner, FALSE, zone, hypo.bypass_protection))
			return zone
	return null

/// No way through what they've got on, as a player's cyborg would find. Somebody dying goes to Medbay, where a doctor can get it
/// off them; otherwise the doctors are told, and it leaves them be for a while.
/datum/bot_silicon/borg/proc/cant_inject(mob/living/carbon/human/H)
	var/obj/item/covering = H.wear_suit || H.head
	var/what = covering ? covering.name : "suit"
	if(H.health <= H.crit_threshold && start_carrying(H))
		note("can't get a needle through [H]'s [what]: taking them to Medbay")
		return TRUE
	note("can't get a needle through [H]'s [what]")
	if(H.stat == CONSCIOUS) // up and about: told to their face, as a player's cyborg would, not called in on the radio
		say_it(pick("[H.first_name()], take the [what] off and I'll patch you up.", "I can't treat you through that [what]."))
	else
		call_doctors(H, "I can't get a needle through [H.p_their()] [what].")
	skip(H)
	return TRUE

/datum/bot_silicon/borg
	/// REF() of somebody it's told Medical about -> when it'd tell them again
	var/list/doctors_called

/// Medical told on the radio, and a request made that the doctors answer (bot_requests.dm), once in a while for anybody.
/datum/bot_silicon/borg/proc/call_doctors(mob/living/carbon/human/H, why)
	if(LAZYACCESS(doctors_called, REF(H)) > world.time)
		return
	for(var/ref in doctors_called)
		if(doctors_called[ref] <= world.time)
			doctors_called -= ref
	LAZYSET(doctors_called, REF(H), world.time + 3 MINUTES)
	var/datum/bot_request_kind/medical/M = locate() in GLOB.bot_request_kinds
	if(M && !bot_open_request_from(H, M))
		bot_offer_request(bot_new_request(M, H, FREQ_MEDICAL, H))
	note("telling Medical about [H]: [why]")
	say_it(":m [H.first_name()] needs a doctor, [get_area_name(H, TRUE)]. [why]")

/datum/bot_silicon/borg
	/// REF() of a body -> how many times it's been shocked
	var/list/shocks_given

/// The nearest body its paddles could bring back, with time to get there and shock it: what the doctors' own revival goes by
/// (goals/treat_patient.dm), the paddles' own check, no space suit over the chest, enough blood to live on.
/datum/bot_silicon/borg/proc/revivable_body(obj/item/twohanded/shockpaddles/paddles)
	var/best_dist
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(H.z != owner.z || !isturf(H.loc) || skipping(H) || (H.pulledby && H.pulledby != owner))
			continue
		var/dist = get_dist(owner, H)
		if(dist > BOT_BORG_RANGE || (. && dist >= best_dist))
			continue
		if(!paddles.can_defib(H) || (locate(/obj/item/clothing/suit/space) in H.contents))
			continue
		if(H.blood_volume < BLOOD_VOLUME_SAFE && !(NOBLOOD in H.dna?.species?.species_traits))
			continue //it'd bleed out again in seconds: a body for the cloner
		// The paddles take the suffocation off and nothing else: past this they're shocked back and dead again within the second,
		// as one was three times over in a live round (2026-11-10). A body for the doctors' kits or the cloner.
		if(H.getBruteLoss() + H.getFireLoss() + H.getToxLoss() + H.getCloneLoss() >= 170)
			continue
		if(world.time - H.timeofdeath + dist * BOT_BORG_STEP + 8 SECONDS > paddles.tlimit)
			continue
		. = H
		best_dist = dist

/// Over to them, the paddles on, and a shock, as a player's medical cyborg does: the paddles in its module, activated (they take
/// the whole module, which is what wielding is to a cyborg), the chest aimed at. A few goes, then the cloner's welcome to them.
/datum/bot_silicon/borg/proc/revive(mob/living/carbon/human/H, obj/item/twohanded/shockpaddles/paddles)
	if(!owner.Adjacent(H))
		return go_to(H)
	if(carry_ref)
		stop_carrying()
	if(owner.pulling)
		owner.stop_pulling() //whoever has hold of them gets the shock too
	if(paddles.busy || paddles.cooldown)
		return TRUE //charging
	var/ref = REF(H)
	if(LAZYACCESS(shocks_given, ref) >= 3)
		skip(H)
		return FALSE
	LAZYSET(shocks_given, ref, LAZYACCESS(shocks_given, ref) + 1)
	var/mob/living/silicon/robot/R = owner
	if(!R.held_items.Find(paddles))
		R.activate_module(paddles)
	if(R.module_active != paddles)
		R.select_module(R.held_items.Find(paddles))
	if(!paddles.wielded)
		paddles.attack_self(R) //activated in the module
	if(!paddles.wielded)
		note("can't get [paddles] going")
		skip(H)
		return FALSE
	owner.zone_selected = BODY_ZONE_CHEST
	note("shocking [H], dead [round((world.time - H.timeofdeath) / 10)] s")
	use_on(paddles, H)
	if(H.stat != DEAD)
		note("brought [H] back")
		bot_tally("brought back by a cyborg")
		LAZYREMOVE(shocks_given, ref)
	return TRUE

/// What somebody needs next out of the hypospray, if it has any of it left: epinephrine for anybody in crit (it stops the
/// suffocating, which is what they die of), dexalin for what suffocating they've done, then bicaridine or kelotane for whichever
/// of bruises and burns is worse. It used to be the last of those and nothing else: a cyborg stood over an engineer in crit with
/// burns for twenty minutes giving kelotane every two seconds, and they suffocated.
/datum/bot_silicon/borg/proc/medicine_for(mob/living/carbon/human/H, obj/item/reagent_containers/borghypo/hypo)
	var/list/wanted = list()
	if(H.health <= H.crit_threshold && H.reagents.get_reagent_amount(/datum/reagent/medicine/epinephrine) < 3)
		wanted += /datum/reagent/medicine/epinephrine
	// Short of blood: saline stands in for it at once (five of blood a unit, while it's in them), where a drip takes a minute
	if(bot_needs_blood(H) && H.reagents.get_reagent_amount(/datum/reagent/medicine/salglu_solution) < 15) //goals/give_blood.dm
		wanted += /datum/reagent/medicine/salglu_solution
	if(H.getOxyLoss() >= 20 && H.reagents.get_reagent_amount(/datum/reagent/medicine/dexalin) < 10)
		wanted += /datum/reagent/medicine/dexalin
	var/worse = H.getBruteLoss() >= H.getFireLoss() ? /datum/reagent/medicine/bicaridine : /datum/reagent/medicine/kelotane
	if(max(H.getBruteLoss(), H.getFireLoss()) >= 5 && H.reagents.get_reagent_amount(worse) < 10) //past ten, a dose is working: give it time
		wanted += worse
	for(var/medicine in wanted)
		var/i = hypo.reagent_ids.Find(medicine)
		if(!i)
			continue
		var/datum/reagents/store = hypo.reagent_list[i]
		if(store.total_volume >= 1) //it makes more as it goes, and an empty one injects nothing
			return medicine
	return null

// A medical cyborg takes somebody in crit to Medbay. Its doors all open for it, which is more than a doctor can say: the three
// engineers shot in Box's laser room had a cyborg at their side within a minute and the doctors never got in.

/datum/bot_silicon/borg
	/// Somebody in crit it's taking to Medbay, where to, and until when.
	var/datum/weakref/carry_ref
	var/turf/carry_to
	var/carry_until = 0
	/// Not again before this, after a try that got nowhere.
	var/next_carry = 0
	/// The Bot Gym's stand-in for Medbay.
	var/turf/gym_medbay_spot

/// The nearest bit of Medbay's floor it has a way to.
/datum/bot_silicon/borg/proc/medbay_spot()
	if(gym_medbay_spot)
		return gym_medbay_spot
	for(var/area_type in list(/area/medical/medbay/lobby, /area/medical/medbay/central))
		var/area/A = GLOB.areas_by_type[area_type]
		if(!A)
			continue
		var/list/spots = list()
		for(var/turf/open/floor/T in A)
			if(T.z == owner.z && !is_blocked_turf(T, TRUE) && !(locate(/obj/machinery/door) in T))
				spots[T] = get_dist(owner, T)
		for(var/tries in 1 to 3)
			var/turf/nearest
			for(var/turf/T as anything in spots)
				if(!nearest || spots[T] < spots[nearest])
					nearest = T
			if(!nearest)
				break
			spots -= nearest
			if(length(get_path_to(owner, nearest, /turf/proc/Distance_cardinal, 0, 400, 0, adjacent = /turf/proc/bot_borg_reachable, id = route_card)))
				return nearest
	return null

/datum/bot_silicon/borg/proc/start_carrying(mob/living/carbon/human/H)
	if(world.time < next_carry || bot_in_medbay(H) || H.buckled || !isturf(H.loc) || (H.pulledby && H.pulledby != owner)) //goals/security_medevac.dm
		return FALSE
	var/turf/spot = medbay_spot()
	if(!spot)
		next_carry = world.time + 2 MINUTES
		return FALSE
	carry_ref = WEAKREF(H)
	carry_to = spot
	carry_until = world.time + 3 MINUTES
	owner.start_pulling(H)
	note("taking [H] to Medbay from [get_area_name(H, TRUE)]")
	return TRUE

/datum/bot_silicon/borg/proc/stop_carrying(why)
	var/mob/living/carbon/human/H = carry_ref?.resolve()
	if(H && owner.pulling == H)
		owner.stop_pulling()
	if(why)
		note("not taking [H || "them"] any further: [why]")
		next_carry = world.time + 2 MINUTES
	carry_ref = null
	carry_to = null
	route = null
	heading_for = null
	return FALSE

/// On the way to Medbay with somebody: hold of them kept, the epinephrine kept up, and set down when it's there.
/datum/bot_silicon/borg/proc/carry_on()
	var/mob/living/carbon/human/H = carry_ref.resolve()
	if(!H || !carry_to || H.z != owner.z)
		return stop_carrying("lost them")
	if(H.stat == DEAD)
		return stop_carrying("they've died")
	if(H.stat == CONSCIOUS)
		return stop_carrying() //come round: they can walk
	if(world.time > carry_until)
		return stop_carrying("it's taking too long")
	if(owner.pulling != H)
		if(!owner.Adjacent(H) || (H.pulledby && H.pulledby != owner))
			return stop_carrying("lost hold of them")
		owner.start_pulling(H)
	if(get_dist(owner, carry_to) <= 1 || bot_in_medbay(H))
		owner.stop_pulling()
		note("brought [H] to Medbay")
		bot_tally("casualties brought to Medbay")
		say_it(";Medbay, I've brought [H.first_name()] in. [pick("They're in a bad way.", "They need a doctor now.", "Somebody see to them.")]")
		stop_carrying()
		return TRUE
	var/obj/item/reagent_containers/borghypo/hypo = tool(/obj/item/reagent_containers/borghypo)
	var/zone = hypo ? injection_zone(H, hypo) : null //through a suit it can't: it'd stand there "dosing" them all the way
	if(zone && H.reagents.get_reagent_amount(/datum/reagent/medicine/epinephrine) < 2 && medicine_for(H, hypo) == /datum/reagent/medicine/epinephrine)
		owner.zone_selected = zone
		hypo.mode = hypo.reagent_ids.Find(/datum/reagent/medicine/epinephrine)
		use_on(hypo, H)
		return TRUE
	if(length(route) && heading_for == carry_to && keep_walking())
		return TRUE
	if(get_dist(owner, carry_to) <= 1)
		return TRUE //there: set down on the next look
	route = get_path_to(owner, carry_to, /turf/proc/Distance_cardinal, 0, 400, 0, adjacent = /turf/proc/bot_borg_reachable, id = route_card)
	if(!length(route))
		return stop_carrying("no way to Medbay from here")
	heading_for = carry_to
	give_up_at = world.time + 2 MINUTES
	keep_walking()
	return TRUE

/datum/bot_silicon/borg/proc/janitor_job()
	var/obj/effect/decal/cleanable/best
	var/best_dist
	for(var/obj/effect/decal/cleanable/C in view(BOT_BORG_SIGHT, owner))
		if(skipping(C))
			continue
		var/dist = get_dist(owner, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	if(!best)
		return FALSE
	if(owner.Adjacent(best))
		//a janitor cyborg cleans whatever it drives over (its module's clean_on_move), which is how players do it; its mop starts dry, so
		//anything it can't drive onto gets the soap
		if(owner.loc == best.loc || !owner.Move(best.loc, get_dir(owner, best)))
			use_on(tool(/obj/item/soap), best)
		return TRUE
	return go_to(best, 0) //onto it

/datum/bot_silicon/borg
	/// The window it's welding, how sound it was when it last got better, and the goes since
	var/datum/weakref/weld_ref
	var/weld_integrity = 0
	var/weld_goes = 0

/datum/bot_silicon/borg/proc/engineer_job()
	var/obj/item/weldingtool/welder = tool(/obj/item/weldingtool)
	if(welder && welder.get_fuel() < 1)
		return refuel(welder)
	var/obj/structure/window/best
	for(var/obj/structure/window/W in view(BOT_BORG_SIGHT, owner))
		if(W.obj_integrity < W.max_integrity && !skipping(W))
			best = W
			break
	if(!best)
		return FALSE
	if(owner.Adjacent(best))
		// A window that's no better for three goes isn't getting any better: one reached from the wrong side, or anything else
		// window/attackby() turns away saying nothing. Each click with the welder lit burns fuel all the same: a cyborg welded one
		// in Aft Maintenance 141 times, to the end of the user's round (2026-11-10).
		if(weld_ref?.resolve() != best)
			weld_ref = WEAKREF(best)
			weld_integrity = best.obj_integrity
			weld_goes = 0
		else if(best.obj_integrity > weld_integrity)
			weld_integrity = best.obj_integrity
			weld_goes = 0
		if(++weld_goes > 3)
			note("giving up on [best] ([get_area_name(best, TRUE)]): no better for three goes")
			skip(best)
			weld_ref = null
			return FALSE
		if(welder && !welder.welding)
			welder.attack_self(owner)
		use_on(welder, best)
		return TRUE
	return go_to(best)

/// Out of fuel: the nearest welding fuel tank, and the welder filled from it, off (a lit one sets the tank off, reagent_dispenser.dm).
/// FALSE with no tank to go to: there's no welding without fuel.
/datum/bot_silicon/borg/proc/refuel(obj/item/weldingtool/welder)
	var/obj/structure/reagent_dispensers/fueltank/best
	var/best_dist
	for(var/obj/structure/reagent_dispensers/fueltank/T as anything in bot_instances_of(/obj/structure/reagent_dispensers/fueltank))
		if(QDELETED(T) || T.z != owner.z || skipping(T) || !T.reagents?.has_reagent(/datum/reagent/fuel))
			continue
		var/dist = get_dist(owner, T)
		if(dist <= BOT_BORG_RANGE && (!best || dist < best_dist))
			best = T
			best_dist = dist
	if(!best)
		return FALSE
	if(!owner.Adjacent(best))
		return go_to(best)
	if(welder.welding)
		welder.attack_self(owner)
	if(welder.welding)
		note("can't switch [welder] off: not refilling it at [best]")
		skip(best)
		return FALSE
	use_on(welder, best)
	if(welder.get_fuel() < 1)
		skip(best)
		return FALSE
	note("refilled [welder] at [best] ([get_area_name(best, TRUE)])")
	return TRUE

/// Stops them, and leaves the rest to Security: it doesn't drag anybody to the Brig.
/datum/bot_silicon/borg/proc/security_job()
	for(var/mob/living/carbon/human/H in view(BOT_BORG_SIGHT, owner))
		if(H.stat == DEAD || H.handcuffed || !bot_is_wanted(H) || skipping(H))
			continue
		var/next_to = owner.Adjacent(H)
		if(!(H.mobility_flags & MOBILITY_STAND)) //down: walk over and cuff them
			if(next_to)
				use_on(tool(/obj/item/restraints/handcuffs), H)
				return TRUE
			return go_to(H)
		var/obj/item/gun/G = tool(/obj/item/gun)
		if(!next_to && G)
			use_on(G, H)
			return TRUE
		if(next_to)
			use_on(tool(/obj/item/melee/baton), H)
			return TRUE
		return go_to(H)
	return FALSE

#undef BOT_SILICON_TICK
#undef BOT_BORG_STEP
#undef BOT_AI_CALLOUT_GAP
#undef BOT_BORG_SIGHT
#undef BOT_BORG_RANGE
#undef BOT_BORG_HURT
