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
/datum/bot_silicon/ai/proc/door_near(atom/A)
	var/obj/machinery/door/best
	var/best_dist
	for(var/obj/machinery/door/D in range(2, get_turf(A)))
		if(!D.density || istype(D, /obj/machinery/door/firedoor) || istype(D, /obj/machinery/door/poddoor))
			continue
		var/obj/machinery/door/airlock/L = D
		if(istype(L) ? !L.canAIControl(owner) : ((D.stat & (NOPOWER|BROKEN)) || istype(get_area(D), /area/security)))
			continue //not Security's desk windoors
		var/dist = get_dist(A, D)
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
		var/mob/living/asker = R.caller_ref?.resolve()
		if(!asker || asker.stat == DEAD || !GLOB.cameranet.checkTurfVis(get_turf(asker)))
			continue
		var/obj/machinery/door/airlock/D = door_near(asker)
		if(!D)
			continue
		R.taken_by = src
		open_door(D)
		say_it(pick("Door's open, [asker.name].", "Got it.", "There you go."))
		return

/// Whoever's wanted, if a camera can see them. An AI watching the cameras is why a suspect doesn't stay lost for long.
/datum/bot_silicon/ai/proc/watch_the_cameras()
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		var/datum/bot_wanted/W = GLOB.bot_security_wanted[ref]
		if(!H || H.stat == DEAD || H.handcuffed || W.severity < BOT_CRIME_MAJOR || LAZYACCESS(called_out, ref) > world.time)
			continue
		var/turf/T = get_turf(H)
		if(!T || !is_station_level(T.z) || !GLOB.cameranet.checkTurfVis(T))
			continue
		W.last_seen = T
		W.last_seen_at = world.time
		LAZYSET(called_out, ref, world.time + BOT_AI_CALLOUT_GAP)
		say_it(":s [H.name], [get_area_name(T, TRUE)].")
		bot_dispatch_security(T, H.name) //goals/security_tactics.dm
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
	var/turf/T = get_turf(H)
	if(!T || !is_station_level(T.z))
		return "[H.real_name] isn't on the station."
	if(H.name == H.real_name && bot_camera_sees(T))
		return "[H.real_name] is in [get_area_name(T, TRUE)]."
	var/obj/item/clothing/under/U = H.w_uniform
	if(istype(U) && U.sensor_mode >= SENSOR_COORDS)
		return "Not on camera. Suit sensors put [H.real_name] in [get_area_name(T, TRUE)]."
	return pick("I can't find [H.real_name] on the cameras.", "No sign of [H.real_name] on cameras or sensors.")

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
	var/obj/machinery/door/airlock/D = door_near(talker)
	// Law 1, the harm it would help: somebody out to hurt people. A strict AI won't open for anybody Security's after; even an
	// easygoing one won't for a traitor out in the open or somebody wanted for something serious.
	if(istype(H))
		var/datum/bot_wanted/W = bot_get_wanted_entry(H)
		if(H.bot_brain?.gone_loud() || W?.severity >= BOT_CRIME_MAJOR || (W && strictness >= 0.5) || bot_too_dangerous(H))
			reply(pick("Request denied.", "No.", "Denied, [H.name]. Security has been informed."))
			if(W)
				W.last_seen = get_turf(H)
				W.last_seen_at = world.time
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
	if(!D)
		if(bot_text_has_any(lower_msg, list("help")))
			reply(pick("What do you need, [talker.name]?", "State your request.", "How can I help?"))
		return
	// The doors that aren't for everybody: the heads', the armory, the vault, the AI's own.
	var/area/A = get_area(get_step(D, get_dir(talker, D))) || get_area(D)
	if(bot_ai_restricted_area(A) && !(istype(H) && ((H.mind?.assigned_role in GLOB.command_positions) || (istype(A, /area/ai_monitored/security/armory) && (H.mind?.assigned_role in GLOB.security_positions)))))
		reply(pick("You don't have clearance for [A.name].", "Access to [A.name] is restricted. Ask a head of staff.", "Negative. [A.name] is restricted."))
		return
	// Law 2: an order from a crew member. A strict AI wants a reason first; it has one if they've said what for.
	var/reason = answering || bot_text_has_any(lower_msg, list("need", "for", "because", "work", "fix", "clone", "patient", "job", "get my", "my stuff", "trapped", "stuck", "please"))
	if(!reason && strictness >= 0.5)
		asked_why = WEAKREF(talker)
		asked_why_until = world.time + 1 MINUTES
		reply(pick("What for?", "Reason for access?", "State your reason, [talker.name]."))
		return
	open_door(D)
	note("opened [D] for [talker]")
	reply(pick("Done.", "Opening.", "Got it, [talker.name]."))

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
		master_ref = null
		return FALSE
	var/mob/living/target = order_ref?.resolve()
	if(target && target.stat == DEAD)
		say_it(pick("Target neutralised.", "Done, master."))
		order_ref = null
		target = null
	if(target && target.z == owner.z)
		if(owner.Adjacent(target))
			use_on(hardest_hitter(), target, INTENT_HARM)
			return TRUE
		var/obj/item/gun/G = tool(/obj/item/gun)
		if(G && (target in view(BOT_BORG_SIGHT, owner)))
			use_on(G, target, INTENT_HARM)
			return TRUE
		return go_to(target)
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
	return (length(route) || follow_ref || flee_ref || tube_stage) ? BOT_BORG_STEP : BOT_SILICON_TICK

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
	. = ..()
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
	if(SSpathfinder.space_type_cache[T.type] && !bot_turf_has_pushoff_backup(T))
		return FALSE
	return !LinkBlockedWithAccess(T, caller, ID)

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
	if(tube_stage)
		ride_tube()
		return
	if(master_ref && serve_master())
		return
	if(flee_ref && flee_from())
		return
	if(follow_ref && follow_leader())
		return
	if(wandering && world.time >= next_job_look)
		next_job_look = world.time + BOT_SILICON_TICK
		if(job())
			wandering = FALSE
			return
	if(keep_walking())
		return
	wandering = FALSE
	if(job())
		return
	var/list/crew = GLOB.bot_crew_members
	if(length(crew))
		var/mob/living/carbon/human/H = pick(crew)
		if(!QDELETED(H) && H.stat != DEAD && H.z == owner.z)
			if(go_to(H))
				wander_fails = 0
				wandering = TRUE
				next_job_look = world.time + BOT_SILICON_TICK
			else if(++wander_fails >= 3 && world.time >= tube_next_ride && board_tube())
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
			return medical_job()
		if(/obj/item/robot_module/janitor)
			return janitor_job()
		if(/obj/item/robot_module/engineering)
			return engineer_job()
		if(/obj/item/robot_module/security)
			return security_job()
	return FALSE

/datum/bot_silicon/borg/proc/medical_job()
	var/mob/living/carbon/human/best = patient_ref?.resolve() //somebody who asked comes first
	var/best_dist
	if(best && (world.time > patient_until || best.stat == DEAD || best.z != owner.z || best.getBruteLoss() + best.getFireLoss() < 5))
		patient_ref = null
		best = null
	for(var/mob/living/carbon/human/H in (best ? list() : GLOB.alive_mob_list))
		if(H.z != owner.z || H.stat == DEAD || max(H.getBruteLoss(), H.getFireLoss()) < BOT_BORG_HURT || skipping(H))
			continue
		var/dist = get_dist(owner, H)
		if(dist <= BOT_BORG_RANGE && (!best || dist < best_dist))
			best = H
			best_dist = dist
	if(!best)
		return FALSE
	if(owner.Adjacent(best))
		var/obj/item/reagent_containers/borghypo/hypo = tool(/obj/item/reagent_containers/borghypo)
		var/datum/reagent/medicine = best.getBruteLoss() >= best.getFireLoss() ? /datum/reagent/medicine/bicaridine : /datum/reagent/medicine/kelotane
		if(!hypo || best.reagents.get_reagent_amount(medicine) >= 10) //a dose is working: give it time
			return TRUE
		var/i = hypo.reagent_ids.Find(medicine)
		if(i)
			hypo.mode = i //what its menu does
		use_on(hypo, best)
		return TRUE
	return go_to(best)

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

/datum/bot_silicon/borg/proc/engineer_job()
	var/obj/structure/window/best
	for(var/obj/structure/window/W in view(BOT_BORG_SIGHT, owner))
		if(W.obj_integrity < W.max_integrity && !skipping(W))
			best = W
			break
	if(!best)
		return FALSE
	if(owner.Adjacent(best))
		var/obj/item/weldingtool/welder = tool(/obj/item/weldingtool)
		if(welder && !welder.welding)
			welder.attack_self(owner)
		use_on(welder, best)
		return TRUE
	return go_to(best)

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
