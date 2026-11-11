// "Spoken for": a job one person can do, taken by one and said so on the radio, so the rest leave it (the user's rulings, 2026-11-11).
//
//  - Who takes it: the AI first when it can do it from the core (a door, a sleeper on camera), then whoever's nearest and can get in
//    there, then the trade it belongs to. bot_offer_request() asks the AI before the crew.
//  - The bot taking a call that came over the radio says what it's taken and where ("I've got Mikayla, on my way to the Brig"), so
//    anybody else on the channel knows. In person it's the plain "On my way."
//  - A player saying "on it" or "I got it" to a call takes it as well: a bot already going stands down, and nobody else picks it up.
//    Two minutes on, if it still wants doing, it's open again.
//  - Somebody asking for heals from inside a sleeper (round-09.55.24: the user, Captain, in the Brig's sleeper, asked the AI and the
//    HoS four times and nobody came): the AI runs the sleeper if a camera sees it, otherwise the nearest crew member who can get in.
//    A non-medic only works the sleeper; if they're still badly hurt after, a doctor's called.
//  - Repairs and hazards aren't spoken for: they're a team job (engineer calls keep their plain acks).
//  - The AI hears what's said near a camera when it's addressed ("AI, can you heal me"), as a player AI with its eye's speech relay on
//    does (aiEye relay_speech), and answers over the radio.

/// How long somebody's "on it" holds a call before it's open again.
#define BOT_PLAYER_CLAIM_TIME (2 MINUTES)
/// How old a call can be for an "on it" to be about it.
#define BOT_CLAIM_WINDOW (90 SECONDS)
/// Between the AI's doses from a sleeper's panel.
#define BOT_AI_DOSE_GAP (6 SECONDS)

/datum/bot_request
	/// A player who said they'd take it ("on it"), and until when that holds.
	var/datum/weakref/player_claim
	var/claim_until = 0
	/// Whoever took it has said so out loud (say_ack_after_typing()).
	var/ack_said = FALSE

/// The "on my way" for a call, once typed: dropped if somebody else has said they've got it in the meantime, so nobody hears
/// "On my way." from a bot that has already stood down.
/datum/bot_brain/proc/say_ack_after_typing(datum/bot_request/R, line)
	addtimer(CALLBACK(src, PROC_REF(say_ack), R, line), bot_typing_time(line))

/datum/bot_brain/proc/say_ack(datum/bot_request/R, line)
	if(R.taken_by != src && !R.kind.team_call) //a team call has as many takers as went (goals/team_repairs.dm)
		return
	R.ack_said = TRUE
	speak_reply(line)

/datum/bot_request_kind
	/// Whether taking it is said on the radio, and a player's "on it" takes it (FALSE: a team job, or one person's own summons).
	var/spoken_for = TRUE
	/// Said by the bot taking a call that came over the radio: %WHO% is the caller's first name, %WHERE% the place.
	var/list/claim_lines
	/// The AI is asked first (ai_take_request()).
	var/ai_first = FALSE

/datum/bot_request_kind/engineer
	spoken_for = FALSE //repairs and hazards are a team job

/datum/bot_request_kind/summons
	spoken_for = FALSE

/datum/bot_request_kind/medical
	claim_lines = list("Got it, heading to %WHO% in %WHERE%.", "I've got %WHO%. On my way to %WHERE%.", "On my way to %WHERE% for %WHO%.")

/datum/bot_request_kind/janitor
	claim_lines = list("I've got the mess in %WHERE%.", "On my way to %WHERE% with the mop.")

/datum/bot_request_kind/let_out
	claim_lines = list("I've got %WHO%'s door, %WHERE%.", "On my way to let %WHO% out of %WHERE%.")
	ai_first = TRUE

/// Whether it still wants doing, for a call somebody said they'd take and didn't.
/datum/bot_request_kind/proc/still_needed(datum/bot_request/R)
	var/mob/living/who = R.caller_ref?.resolve()
	return who && who.stat != DEAD

/datum/bot_request_kind/medical/still_needed(datum/bot_request/R)
	var/mob/living/carbon/human/who = R.caller_ref?.resolve()
	return istype(who) && who.stat != DEAD && who.health < who.maxHealth * 0.9

/// The line taking it: on the radio, what and where; in person, the plain one.
/datum/bot_request_kind/ack_for(datum/bot_brain/bot, datum/bot_request/R)
	if(!R.radio_freq || !spoken_for || !length(claim_lines))
		return ..()
	return bot_fill_claim_line(pick(claim_lines), R)

/// Whether a line is one of this kind's acknowledgements, plain or spoken-for (the gym's check).
/datum/bot_request_kind/proc/is_ack_line(line)
	if(line in ack_lines)
		return TRUE
	for(var/template in claim_lines)
		var/fixed = copytext(template, 1, findtext(template, "%"))
		if(length(fixed) && findtext(line, fixed) == 1)
			return TRUE
	return FALSE

/proc/bot_fill_claim_line(template, datum/bot_request/R)
	var/mob/living/who = R.caller_ref?.resolve()
	var/atom/where_atom = isarea(R.place) ? R.place : (R.place || who)
	var/where = "there"
	if(isarea(where_atom))
		var/area/A = where_atom
		where = A.name
	else if(where_atom)
		where = get_area_name(where_atom, TRUE)
	var/name = who ? (who.name == "Unknown" ? "them" : who.first_name()) : "them"
	. = replacetext(template, "%WHO%", name)
	. = replacetext(., "%WHERE%", where)

// ---------------------------------------------------------------------------------------------
// Somebody saying they'll take it
// ---------------------------------------------------------------------------------------------

GLOBAL_LIST_INIT(bot_claim_words, list("on it", "i'm on it", "im on it", "i got it", "i've got it", "ive got it", "i got this", "i've got this",
	"ive got this", "got it", "i'll get it", "ill get it", "i'll do it", "ill do it", "i'll handle it", "ill handle it", "leave it to me",
	"on my way", "omw", "coming", "i'm coming", "im coming", "i'll go", "ill go", "i'll take it", "ill take it", "i'll take that", "ill take that"))

/// A player's "on it" after a call: the call is theirs. TRUE if it was one.
/proc/bot_heard_claim(mob/living/talker, lower_msg, radio_freq)
	if(!talker || talker.stat != CONSCIOUS || findtext(lower_msg, "?") || length(lower_msg) > 60)
		return FALSE
	if(!bot_text_has_any(lower_msg, GLOB.bot_claim_words))
		return FALSE
	var/datum/bot_request/best
	for(var/datum/bot_request/R as anything in GLOB.bot_requests)
		if(!R.kind.spoken_for || world.time > R.made + BOT_CLAIM_WINDOW || R.only_for)
			continue
		if(R.taken_by && !istype(R.taken_by, /datum/bot_brain))
			continue //the AI has it in hand
		var/mob/living/who = R.caller_ref?.resolve()
		if(!who || who == talker)
			continue
		if(radio_freq ? R.radio_freq != radio_freq : (R.radio_freq || get_dist(who, talker) > 7))
			continue
		if(!best || R.made > best.made)
			best = R
	if(!best)
		return FALSE
	if(best.player_claim?.resolve() == talker)
		return TRUE
	best.player_claim = WEAKREF(talker)
	best.claim_until = world.time + BOT_PLAYER_CLAIM_TIME
	var/mob/living/asker = best.caller_ref?.resolve()
	log_game("BOT AI: [key_name(talker)] took the [best.kind.name] call from [asker] ([lower_msg])")
	// Whoever had it stands down.
	var/datum/bot_brain/B = best.taken_by
	if(istype(B) && !QDELETED(B) && !QDELETED(B.owner))
		var/datum/bot_goal/answer_call/G = B.current_goal
		if(istype(G) && G.request == best)
			B.drop_goals("[talker] has that call")
			if(best.ack_said) //nothing to take back if it never said it was coming
				B.say_after_typing(bot_radio_prefix(best.radio_freq) + pick("Alright, it's yours.", "Okay, you've got it.", "Cool, leaving it to you."))
		bot_log(B, "stood down from the [best.kind.name] call: [talker] has it")
	best.taken_by = null
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_claim_lapsed), best, best.player_claim), BOT_PLAYER_CLAIM_TIME)
	return TRUE

/// Two minutes on from somebody's "on it": if it still wants doing, it's open again.
/proc/bot_claim_lapsed(datum/bot_request/R, datum/weakref/claim)
	if(R.player_claim != claim)
		return
	R.player_claim = null
	if(!(R in GLOB.bot_requests))
		return
	if(!R.kind.still_needed(R))
		GLOB.bot_requests -= R
		return
	R.made = world.time
	bot_offer_request(R)

// ---------------------------------------------------------------------------------------------
// The AI first
// ---------------------------------------------------------------------------------------------

/// Whether the AI took it (bot_offer_request()).
/proc/bot_ai_take_request(datum/bot_request/R)
	if(!R.kind.ai_first)
		return FALSE
	for(var/datum/bot_silicon/ai/A in GLOB.bot_silicons)
		if(A.take_request(R))
			return TRUE
	return FALSE

/datum/bot_silicon/ai/proc/can_work_from_core()
	var/mob/living/silicon/ai/AI = owner
	return !QDELETED(AI) && AI.stat == CONSCIOUS && !AI.control_disabled && !subverted()

/datum/bot_silicon/ai/proc/take_request(datum/bot_request/R)
	if(!can_work_from_core())
		return FALSE
	if(istype(R.kind, /datum/bot_request_kind/let_out))
		return let_out_for(R)
	if(istype(R.kind, /datum/bot_request_kind/run_sleeper))
		return take_sleeper(R)
	return FALSE

/// Inside a Brig cell whose timer is running.
/proc/bot_in_timed_cell(atom/M)
	var/turf/here = get_turf(M)
	if(!here)
		return FALSE
	for(var/obj/machinery/door_timer/T as anything in bot_instances_of(/obj/machinery/door_timer))
		if(!T.timing || T.z != here.z)
			continue
		var/list/interior = bot_get_cell_interior(T)
		if(interior && (here in interior))
			return TRUE
	return FALSE

/// Opens the door by somebody shut in that it can see on the cameras, and says so on the channel they asked on.
/datum/bot_silicon/ai/proc/let_out_for(datum/bot_request/R)
	var/mob/living/asker = R.caller_ref?.resolve()
	if(!asker || asker.stat == DEAD || !bot_camera_sees(get_turf(asker)))
		return FALSE
	// Its laws and its doors, as when it's asked outright (consider_door_for()): it used to open whatever was by them, a cell with
	// its timer running included. Those are left to whoever's ID opens them.
	var/mob/living/carbon/human/H = asker
	if(istype(H) && (bot_is_wanted(H) || H.bot_brain?.gone_loud()))
		return FALSE
	if(bot_in_timed_cell(asker))
		return FALSE
	var/obj/machinery/door/airlock/D = door_near(asker)
	if(!D)
		return FALSE
	var/area/beyond = get_area(get_step(D, get_dir(asker, D))) || get_area(D)
	if(bot_ai_restricted_area(beyond) && !(istype(H) && (H.mind?.assigned_role in GLOB.command_positions)))
		return FALSE
	R.taken_by = src
	GLOB.bot_requests -= R //done there and then
	open_door(D)
	note("opened [D] for [asker], who was shut in")
	say_it(bot_radio_prefix(R.radio_freq || FREQ_COMMON) + pick("Door's open, [asker.first_name()].", "Got [asker.first_name()]'s door. It's open.", "Opened it for you, [asker.first_name()]."))
	return TRUE

// ---------------------------------------------------------------------------------------------
// Heals asked for from inside a sleeper
// ---------------------------------------------------------------------------------------------

/datum/bot_request_kind/run_sleeper
	name = "sleeper"
	jobs = list()
	ack_lines = list("Hang on, I'll run it.", "Sure, let me get it going.", "One sec, I'll work the panel.")
	claim_lines = list("I've got the %WHERE% sleeper for %WHO%.", "On it, running the %WHERE% sleeper for %WHO%.")
	arrival_lines = list("Let's see what it's got.", "Alright, getting you dosed.", "Hold still.")
	doing = "running a sleeper for somebody"
	needs_place = FALSE
	urgent = TRUE
	ai_first = TRUE
	precedence = 20 //before a call for a medic: they're in the sleeper already

/datum/bot_request_kind/run_sleeper/matches(lower_msg, named, turf/near)
	var/obj/machinery/sleeper/S = locate() in near
	if(!S?.occupant)
		return FALSE
	return bot_text_has_any(lower_msg, list("heal", "heals", "healing", "help", "sleeper", "activate", "turn on", "turn it on", "switch it on",
		"start it", "run it", "use it", "operate", "inject", "medic", "doctor", "doc", "meds", "medicine", "epi", "hurt", "dying", "patch me"))

/datum/bot_request_kind/run_sleeper/heard_by(datum/bot_brain/bot, named)
	return TRUE

/datum/bot_request_kind/run_sleeper/proc/sleeper_of(datum/bot_request/R)
	var/mob/living/who = R.caller_ref?.resolve()
	return istype(who?.loc, /obj/machinery/sleeper) ? who.loc : null

/datum/bot_request_kind/run_sleeper/still_needed(datum/bot_request/R)
	var/obj/machinery/sleeper/S = sleeper_of(R)
	var/mob/living/carbon/human/H = S?.occupant
	return istype(H) && H.stat != DEAD && (bot_sleeper_dose(S, H) || bot_needs_doctor(H))

/// Anybody can press the buttons: whoever can get in there and isn't too far.
/datum/bot_request_kind/run_sleeper/answered_by(datum/bot_brain/bot, datum/bot_request/R)
	var/obj/machinery/sleeper/S = sleeper_of(R)
	if(!S || S.z != bot.owner.z || get_dist(S, bot.owner) > 50 || bot.gone_loud() || bot.owner == R.caller_ref?.resolve())
		return FALSE
	return bot.can_walk_lawfully_to(S)

/datum/bot_request_kind/run_sleeper/where_to_go(datum/bot_brain/bot, datum/bot_request/R)
	return sleeper_of(R)

/datum/bot_request_kind/run_sleeper/attend(datum/bot_brain/bot, datum/bot_request/R)
	var/obj/machinery/sleeper/S = sleeper_of(R)
	var/mob/living/carbon/human/H = S?.occupant
	if(istype(H))
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, run_sleeper_for), S, H))

/// Hurt past what a sleeper's panel is for: a doctor wanted as well.
/proc/bot_needs_doctor(mob/living/carbon/human/H)
	if(!istype(H) || H.stat == DEAD)
		return FALSE
	return H.health < H.maxHealth * 0.5 || H.stat >= UNCONSCIOUS || H.bleed_rate >= 3 || bot_needs_blood(H)

/// A medic sent for somebody: a call in their name, offered to the doctors.
/proc/bot_send_doctor_for(mob/living/carbon/human/H)
	var/datum/bot_request_kind/medical/M = locate() in GLOB.bot_request_kinds
	if(!M || bot_open_request_from(H, M))
		return FALSE
	var/datum/bot_request/R = bot_new_request(M, H, FREQ_MEDICAL, H)
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_offer_request), R), rand(15, 30))
	return TRUE

/datum/bot_brain/proc/run_sleeper_for(obj/machinery/sleeper/S, mob/living/carbon/human/H)
	return assign_goal(new /datum/bot_goal/run_sleeper(S, H))

/datum/bot_goal/run_sleeper
	lawful = TRUE
	exclusive = TRUE
	doing = "running a sleeper for somebody"
	var/datum/weakref/patient_ref

/datum/bot_goal/run_sleeper/New(obj/machinery/sleeper/S, mob/living/carbon/human/H)
	. = ..()
	target = S
	patient_ref = WEAKREF(H)

/datum/bot_goal/run_sleeper/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/run_sleeper/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/run_sleeper())
	return list(S)

/// At the panel: a dose of what they need whenever it'll give one, until there's nothing more or they've got out.
/datum/bot_step/paced/run_sleeper
	max_clicks = 25
	var/until = 0
	var/idle_since = 0
	var/looked = FALSE
	var/doses = 0

/datum/bot_step/paced/run_sleeper/start(datum/bot_brain/bot)
	until = world.time + 90 SECONDS
	return TRUE

/datum/bot_step/paced/run_sleeper/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/run_sleeper/G = bot.current_goal
	var/obj/machinery/sleeper/S = G?.target
	var/mob/living/carbon/human/H = G?.patient_ref?.resolve()
	if(!istype(S) || QDELETED(S) || !H || H.loc != S || H.stat == DEAD || world.time > until || !bot.owner.Adjacent(S))
		return FALSE
	if(!looked) //reading the panel first
		looked = TRUE
		bot.owner.face_atom(S)
		wait_for = 15
		return TRUE
	var/chem = bot_sleeper_dose(S, H)
	if(chem && S.is_operational() && S.inject_chem(chem, bot.owner))
		var/datum/reagent/R = chem
		doses++
		idle_since = 0
		bot.telemetry_ui_action(S, "inject")
		bot_log(bot, "gave [H] [initial(R.name)] in [S]")
		wait_for = 50
		return TRUE
	if(!idle_since)
		idle_since = world.time
	if(world.time - idle_since > 10 SECONDS)
		return FALSE
	wait_for = 20
	return TRUE

/datum/bot_step/paced/run_sleeper/finish(datum/bot_brain/bot)
	var/datum/bot_goal/run_sleeper/G = bot.current_goal
	var/obj/machinery/sleeper/S = G?.target
	var/mob/living/carbon/human/H = G?.patient_ref?.resolve()
	if(!istype(H) || H.stat == DEAD || H.loc != S)
		return GOAL_STEP_SUCCESS
	if(bot_needs_doctor(H))
		if(bot.is_medical_job())
			bot.called_patient = WEAKREF(H)
			bot.called_patient_until = world.time + 2 MINUTES
			bot.continue_medical_round()
		else if(bot_send_doctor_for(H))
			bot.say_after_typing(";Medical, [H.first_name()]'s in the [get_area_name(S, TRUE)] sleeper and needs a doctor.")
			bot_say(bot.owner, pick("That's what it'll give you. A doctor's coming.", "Doctor's on the way. Sit tight."))
		return GOAL_STEP_SUCCESS
	bot_say(bot.owner, doses ? pick("That should do you.", "There. Give it a minute.", "You're dosed up.") : pick("It's got nothing more for you right now.", "Nothing more it can give you yet."))
	return GOAL_STEP_SUCCESS

/datum/bot_silicon/ai
	/// Sleeper calls it's running: request -> when it can give the next dose.
	var/list/running_sleepers
	/// Request -> since when the panel has had nothing to give them, and when it took the call.
	var/list/sleeper_idle_since
	var/list/sleeper_taken_at

/// Takes a sleeper call if a camera sees the sleeper and the panel answers it.
/datum/bot_silicon/ai/proc/take_sleeper(datum/bot_request/R)
	var/datum/bot_request_kind/run_sleeper/K = R.kind
	var/obj/machinery/sleeper/S = K.sleeper_of(R)
	var/mob/living/carbon/human/H = S?.occupant
	if(!istype(H) || !S.can_interact(owner) || !S.is_operational() || !bot_camera_sees(get_turf(S)))
		return FALSE
	R.taken_by = src
	LAZYSET(running_sleepers, R, world.time + 2 SECONDS)
	LAZYSET(sleeper_taken_at, R, world.time)
	note("running [S] for [H]")
	say_it(bot_radio_prefix(R.radio_freq || FREQ_COMMON) + bot_fill_claim_line(pick("I've got the %WHERE% sleeper for %WHO%.", "Running the %WHERE% sleeper for %WHO% from here."), R))
	return TRUE

/// Each look: a dose from the panel of every sleeper it's running, then the doctor called if that's not enough.
/datum/bot_silicon/ai/proc/run_sleepers()
	for(var/datum/bot_request/R as anything in running_sleepers)
		var/datum/bot_request_kind/run_sleeper/K = R.kind
		var/obj/machinery/sleeper/S = K.sleeper_of(R)
		var/mob/living/carbon/human/H = S?.occupant
		if(!istype(H) || H.stat == DEAD || R.taken_by != src || !can_work_from_core() || !S.is_operational())
			finish_sleeper(R, H, S)
			continue
		if(world.time < running_sleepers[R])
			continue
		var/chem = bot_sleeper_dose(S, H)
		if(chem && S.inject_chem(chem, owner))
			var/datum/reagent/C = chem
			note("gave [H] [initial(C.name)] in [S]")
			running_sleepers[R] = world.time + BOT_AI_DOSE_GAP
			LAZYREMOVE(sleeper_idle_since, R)
			continue
		// Nothing to give just now: what's in them is working. Watched a while for the next dose, as the crew's runner does
		// (/datum/bot_step/paced/run_sleeper), and given up on after a minute and a half whatever.
		if(!LAZYACCESS(sleeper_idle_since, R))
			LAZYSET(sleeper_idle_since, R, world.time)
		if(world.time - sleeper_idle_since[R] < 10 SECONDS && world.time - LAZYACCESS(sleeper_taken_at, R) < 90 SECONDS)
			continue
		finish_sleeper(R, H, S)

/datum/bot_silicon/ai/proc/finish_sleeper(datum/bot_request/R, mob/living/carbon/human/H, obj/machinery/sleeper/S)
	LAZYREMOVE(running_sleepers, R)
	LAZYREMOVE(sleeper_idle_since, R)
	LAZYREMOVE(sleeper_taken_at, R)
	GLOB.bot_requests -= R
	if(R.taken_by == src)
		R.taken_by = null
	if(!istype(H) || H.stat == DEAD || H.loc != S)
		return
	if(bot_needs_doctor(H) && bot_send_doctor_for(H))
		say_it(":m Medbay, [H.real_name] needs a doctor at the [get_area_name(S, TRUE)] sleeper.")
		say_it(bot_radio_prefix(R.radio_freq || FREQ_COMMON) + "That's all the sleeper can do, [H.first_name()]. A doctor's been called.")
		return
	say_it(bot_radio_prefix(R.radio_freq || FREQ_COMMON) + pick("Sleeper's done, [H.first_name()].", "That's you dosed, [H.first_name()].", "Nothing more it can give you for now, [H.first_name()]."))

/// The AI's ear on a sleeper ask: the call made (or found), and offered, AI first.
/datum/bot_silicon/ai/proc/heard_sleeper_ask(mob/living/talker, lower_msg, radio_freq)
	if(!istype(talker?.loc, /obj/machinery/sleeper))
		return FALSE
	var/datum/bot_request_kind/run_sleeper/K = locate() in GLOB.bot_request_kinds
	if(!K || !K.matches(lower_msg, TRUE, get_turf(talker)))
		return FALSE
	var/datum/bot_request/R = bot_open_request_from(talker, K)
	if(!R)
		R = bot_new_request(K, talker, radio_freq || FREQ_COMMON, talker)
	if(R.still_open())
		bot_offer_request(R)
	return TRUE

// ---------------------------------------------------------------------------------------------
// The AI hearing what's said to it in front of a camera
// ---------------------------------------------------------------------------------------------

/mob/living/say(message, bubble_type, list/spans = list(), sanitize = TRUE, datum/language/language = null, ignore_spam = FALSE, forced = null)
	. = ..()
	if(. && length(GLOB.bot_silicons) && !issilicon(src) && message)
		bot_ai_overhear(src, message)

/// Something said out loud (not over the radio, which it hears anyway) that names the AI, by somebody a camera can see.
/proc/bot_ai_overhear(mob/living/talker, message)
	var/first = copytext(message, 1, 2)
	if(first == ";" || first == ":" || first == "." || first == "*" || first == "#")
		return
	var/lower_msg = lowertext(message)
	if(!bot_text_has_any(lower_msg, list("ai")))
		return
	var/turf/T = get_turf(talker)
	if(!T || !bot_camera_sees(T))
		return
	for(var/datum/bot_silicon/ai/A in GLOB.bot_silicons)
		if(QDELETED(A.owner) || (A.owner.z == T.z && get_dist(A.owner, T) <= 7))
			continue //it heard that itself
		INVOKE_ASYNC(A, TYPE_PROC_REF(/datum/bot_silicon, heard), talker, lower_msg, FREQ_COMMON) //answered over the radio; a door it opens takes its time

#undef BOT_PLAYER_CLAIM_TIME
#undef BOT_CLAIM_WINDOW
#undef BOT_AI_DOSE_GAP
