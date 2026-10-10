// Calls for help: somebody says "medic to the bar!" on the radio, or "janitor, there's a spill in the hallway",
// or just "doctor, I need help" to one stood next to them - and whoever's job it is answers on the same channel
// and turns up.
//
//  - what was said is read for a trade (a medic, the janitor, an engineer) and for a place. A call with no place
//    in it is answered with "where are you?", unless whoever answers could tell anyway: the caller is stood
//    there saying it, or the call is a medical one and their suit sensors are on (the crew monitor's readout)
//  - the nearest of the right trade who is free takes it, says so, and goes. Something medical is worth
//    dropping everyday work for; a spill waits until the mopping in hand is done
//  - when they get there their ordinary rounds take over (goals/treat_patient.dm, janitor.dm, the engine
//    rounds): the call only decided who to see to first
//  - a bot called by name and asked to come somewhere ("Sam, come to the bar") goes, whatever its job
//  - bots make calls too: one that's hurt and has nothing to patch itself up with asks for a medic, one that
//    walks past a pool of blood mentions it to the janitor
//
// Security has had its own version of this for longer (on_heard_security_call(), goals/security_patrol.dm).

/// How long a call stays worth answering.
#define BOT_REQUEST_LIFETIME (3 MINUTES)
/// The same person asking again within this is the same call.
#define BOT_REQUEST_REPEAT (30 SECONDS)

GLOBAL_LIST_EMPTY(bot_requests)
GLOBAL_LIST_INIT(bot_request_kinds, init_bot_request_kinds())
/// Words that make a sentence with a trade in it a request for one.
GLOBAL_LIST_INIT(bot_request_words, list("need", "needed", "help", "please", "pls", "plz", "asap", "quick", "quickly", "hurry",
	"come", "send", "urgent", "requesting", "required", "wanted", "can you", "could you", "can someone", "can we get", "get over here"))

/proc/init_bot_request_kinds()
	. = list()
	for(var/path in subtypesof(/datum/bot_request_kind))
		. += new path

/datum/bot_request_kind
	var/name
	/// Job titles that answer it.
	var/list/jobs
	/// Enough by themselves to be a call ("medic!", "man down").
	var/list/strong_words
	/// The trade, which needs something more to be a call for it ("janitor, could you...", "engineer to the bar").
	var/list/role_words
	var/list/ack_lines = list("On my way.", "Coming.", "Be right there.", "On it.")
	/// Said on getting there, to whoever called.
	var/list/arrival_lines
	/// Whether everyday work is dropped for it at once.
	var/urgent = FALSE
	/// Whether whoever answers can see where the caller is from their suit sensors.
	var/reads_sensors = FALSE
	/// What a bot answering it says it's doing.
	var/doing = "answering a call"
	/// Whether the answerer walks to the spot as an errand of its own (answer_call), or only bears it in mind.
	var/walks_there = TRUE
	/// Whether it matters where the caller is (an order at the bar doesn't: the drink goes on the bar).
	var/needs_place = TRUE

/// The words that name this kind of call - left out when the same line is read for a place ("I need a doctor"
/// doesn't mean Medbay).
/datum/bot_request_kind/proc/own_words()
	. = list()
	if(role_words)
		. += role_words
	if(strong_words)
		. += strong_words

/// What happens once the answerer is there (or, for a kind that doesn't walk there, once it has taken the call).
/datum/bot_request_kind/proc/attend(datum/bot_brain/bot, datum/bot_request/R)
	return

/datum/bot_request_kind/medical
	name = "medical"
	jobs = list("Medical Doctor", "Chief Medical Officer", "Paramedic")
	strong_words = list("medic", "man down", "need a doctor", "need a doc", "need medical", "im dying", "i'm dying", "bleeding out", "need healing", "paramedic", "need a medic")
	role_words = list("doctor", "doc", "doctors", "medical", "cmo")
	arrival_lines = list("Alright, let's have a look at you.", "Hold still, let me see.", "Where does it hurt?")
	urgent = TRUE
	reads_sensors = TRUE
	doing = "answering a medical call"

/datum/bot_request_kind/medical/attend(datum/bot_brain/bot, datum/bot_request/R)
	bot.called_patient = R.caller_ref
	bot.called_patient_until = world.time + 2 MINUTES
	bot.continue_medical_round() //goals/treat_patient.dm

/datum/bot_request_kind/janitor
	name = "janitor"
	jobs = list("Janitor")
	strong_words = list("need a janitor", "janitor needed")
	role_words = list("janitor", "janny", "jannie", "custodian")
	ack_lines = list("On my way.", "I'll get the mop.", "Be there in a minute.", "On it.")
	doing = "going to clean something up"
	walks_there = FALSE //the mop and bucket first: the rounds do that, and go to the mess nearest the spot (pick_mess())

/datum/bot_request_kind/janitor/attend(datum/bot_brain/bot, datum/bot_request/R)
	bot.janitor_called_to = get_turf(R.place)
	bot.janitor_called_until = world.time + BOT_REQUEST_LIFETIME
	if(bot.state == BOT_STATE_WANDER)
		bot.continue_janitor_round() //goals/janitor.dm

/datum/bot_request_kind/engineer
	name = "engineer"
	jobs = list("Station Engineer", "Chief Engineer", "Atmospheric Technician")
	strong_words = list("hull breach", "breach in", "power is out", "powers out", "power's out", "no power in", "need an engineer", "engineer needed")
	role_words = list("engineer", "engineers", "engie", "engi", "ce", "atmos tech")
	arrival_lines = list("Right, what's the problem?", "What needs fixing?", "Engineering. What's up?")
	doing = "answering a call for an engineer"

/datum/bot_request_kind/engineer/attend(datum/bot_brain/bot, datum/bot_request/R)
	bot.continue_engineering_round() //goals/setup_tesla_engine.dm

/// Called by name and asked to come somewhere. Nobody's trade: whoever was named.
/datum/bot_request_kind/summons
	name = "summons"
	strong_words = list("come to", "come over to", "get to", "get over to", "meet me", "need you in", "need you at", "can you come", "could you come")
	ack_lines = list("On my way.", "Sure, coming.", "Be right there.", "Alright, give me a minute.")
	arrival_lines = list("You wanted me?", "Here I am. What's up?", "What did you need?")
	doing = "going to see somebody who asked for me"

/// One call: who wants whom, and where.
/datum/bot_request
	var/datum/bot_request_kind/kind
	var/datum/weakref/caller_ref
	/// Where to go, once that's known: the caller, or the place they named (an /area).
	var/atom/place
	var/made = 0
	/// The frequency it came over, for answering on - null for something said in person.
	var/radio_freq
	var/datum/bot_brain/taken_by
	/// Somebody has already asked the caller where they are.
	var/asked_where = FALSE
	/// Brains that set off for it and couldn't get there.
	var/list/failed_by
	/// For a summons: the one bot it's meant for.
	var/datum/bot_brain/only_for
	/// What was asked for, for the kinds that are orders (a /datum/bot_drink, a supply pack's type).
	var/detail
	/// Times whoever took it has tried and not managed.
	var/failures = 0

/datum/bot_request/proc/still_open()
	if(world.time > made + BOT_REQUEST_LIFETIME)
		return FALSE
	if(taken_by && (QDELETED(taken_by) || QDELETED(taken_by.owner) || taken_by.owner.stat != CONSCIOUS))
		taken_by = null //whoever had it is in no state to see it through
	return !taken_by

/// The prefix that puts a line on the channel something was heard on. In person: none.
/proc/bot_radio_prefix(radio_freq)
	if(!radio_freq)
		return ""
	if(radio_freq == FREQ_COMMON)
		return ";"
	var/channel = GLOB.reverseradiochannels["[radio_freq]"]
	var/token = channel ? GLOB.channel_tokens[channel] : null
	return token ? "[token] " : ";"

/// The station area somebody means by what they said, the nearest such to `near` - or null. `not_words` are left
/// out of it: "I need a doctor" doesn't mean Medbay.
/proc/bot_area_named(lower_msg, turf/near, list/not_words)
	var/asked
	for(var/word in GLOB.bot_place_words)
		if((word in not_words) || !bot_text_has_any(lower_msg, list(word)))
			continue
		if(!asked || length(word) > length(asked))
			asked = word
	if(!asked || !near)
		return null
	var/keyword = GLOB.bot_place_words[asked]
	var/area/best
	var/best_dist
	for(var/area_name in GLOB.teleportlocs)
		if(!findtext(area_name, keyword))
			continue
		var/area/AR = GLOB.teleportlocs[area_name]
		var/turf/spot = locate(/turf/open) in AR
		if(!spot || spot.z != near.z)
			continue
		var/dist = get_dist(near, spot)
		if(!best || dist < best_dist)
			best = AR
			best_dist = dist
	return best

/// Which kind of call a line is, if any. Summonses are only looked for in something said to a bot by name.
/proc/bot_request_kind_of(lower_msg, named, turf/near)
	for(var/datum/bot_request_kind/K as anything in GLOB.bot_request_kinds)
		if(K.matches(lower_msg, named, near))
			return K
	return null

/// Whether a line is a call of this kind. A summons (no jobs) only counts when said to a bot by name.
/datum/bot_request_kind/proc/matches(lower_msg, named, turf/near)
	if(!jobs)
		return named && bot_text_has_any(lower_msg, strong_words)
	if(bot_text_has_any(lower_msg, strong_words))
		return TRUE
	if(!bot_text_has_any(lower_msg, role_words))
		return FALSE
	return bot_text_has_any(lower_msg, GLOB.bot_request_words) || bot_area_named(lower_msg, near, own_words())

/// Whether a bot is one of those whose call this is.
/datum/bot_request_kind/proc/answered_by(datum/bot_brain/bot, datum/bot_request/R)
	return bot.owner.mind?.assigned_role in jobs

/// Where whoever answers walks to: the caller, or somewhere in the place they named.
/datum/bot_request_kind/proc/where_to_go(datum/bot_brain/bot, datum/bot_request/R)
	if(isarea(R.place))
		return bot.nearest_spot_in(R.place)
	return QDELETED(R.place) ? null : R.place

/// Anything more a call of this kind says that whoever answers will want (what was ordered): onto R.detail.
/datum/bot_request_kind/proc/read_details(datum/bot_request/R, lower_msg)
	return

/// A call somebody already has open that a new line from them belongs to.
/proc/bot_open_request_from(mob/living/talker, datum/bot_request_kind/kind)
	for(var/datum/bot_request/R as anything in GLOB.bot_requests)
		if(R.caller_ref?.resolve() != talker || world.time > R.made + BOT_REQUEST_LIFETIME)
			continue
		if(kind ? (R.kind == kind && world.time <= R.made + BOT_REQUEST_REPEAT) : !R.place)
			return R
	return null

/proc/bot_new_request(datum/bot_request_kind/kind, mob/living/talker, radio_freq, atom/place)
	for(var/datum/bot_request/old as anything in GLOB.bot_requests)
		if(world.time > old.made + BOT_REQUEST_LIFETIME)
			GLOB.bot_requests -= old
	var/datum/bot_request/R = new
	R.kind = kind
	R.caller_ref = WEAKREF(talker)
	R.radio_freq = radio_freq
	R.place = place
	R.made = world.time
	GLOB.bot_requests += R
	return R

/// Whether the caller's whereabouts are known without their saying: stood there talking, or on the suit sensors.
/proc/bot_caller_locatable(mob/living/talker, datum/bot_request_kind/kind, radio_freq)
	if(!radio_freq)
		return TRUE
	if(!kind.reads_sensors || !ishuman(talker))
		return FALSE
	var/mob/living/carbon/human/H = talker
	var/obj/item/clothing/under/uniform = H.w_uniform
	return istype(uniform) && uniform.has_sensor > NO_SENSORS && uniform.sensor_mode >= SENSOR_COORDS

/datum/bot_brain
	/// When this bot may next put a call of its own out.
	var/next_call_time = 0
	/// A patient who called for a medic and this bot answered - seen to first (treat_patient/resolve_target()).
	var/datum/weakref/called_patient
	var/called_patient_until = 0
	/// Where the janitor was last asked to come, and until when that's worth bearing in mind (pick_mess()).
	var/turf/janitor_called_to
	var/janitor_called_until = 0

/// Whether this bot could take a call of this kind right now.
/datum/bot_brain/proc/can_take_call(datum/bot_request/R)
	if(QDELETED(owner) || owner.stat != CONSCIOUS || owner.incapacitated())
		return FALSE
	if(R.only_for ? (R.only_for != src) : !R.kind.answered_by(src, R))
		return FALSE
	if(gym_run)
		var/mob/living/who = R.caller_ref?.resolve()
		if(!who || get_area(who) != get_area(owner))
			return FALSE //a Bot Gym bot only hears its own arena
	if(src in R.failed_by)
		return FALSE
	var/turf/there = get_turf(R.place)
	if(!R.place || (there && there.z != owner.z && !isarea(R.place)))
		return FALSE
	if(bot_staying_aboard(owner) || !EMERGENCY_IDLE_OR_RECALLED)
		return FALSE //the shuttle comes first
	if(state == BOT_STATE_WANDER)
		return TRUE
	if(state != BOT_STATE_GOAL || !current_goal || !R.kind.walks_there)
		return state == BOT_STATE_GOAL && !R.kind.walks_there
	if(!R.kind.urgent && !R.only_for)
		return FALSE
	// Dropped for it: everyday work, a stroll, a drink. Not somebody else's emergency.
	var/datum/bot_goal/G = suspended_goal || current_goal
	if(istype(G, /datum/bot_goal/answer_call) || istype(G, /datum/bot_goal/revive_patient) || istype(G, /datum/bot_goal/escort_to_sleeper) || istype(G, /datum/bot_goal/treat_patient) || istype(G, /datum/bot_goal/evacuate))
		return FALSE
	return G.lawful

/// Takes the call: says so on the channel it came over, and sets off (or bears it in mind).
/datum/bot_brain/proc/take_call(datum/bot_request/R)
	if(R.kind.walks_there)
		if(state == BOT_STATE_GOAL)
			drop_goals("somebody's calling for [R.only_for ? "me" : "a [R.kind.name]"]")
		if(!assign_goal(new /datum/bot_goal/answer_call(R)))
			LAZYOR(R.failed_by, src)
			return FALSE
	R.taken_by = src
	var/mob/living/who = R.caller_ref?.resolve()
	bot_log(src, "taking a [R.kind.name] call from [who || "somebody"] ([isarea(R.place) ? "[R.place]" : get_area_name(R.place, TRUE)])")
	if(who != owner)
		say_after_typing(bot_radio_prefix(R.radio_freq) + pick(R.kind.ack_lines))
	if(!R.kind.walks_there)
		R.kind.attend(src, R)
	return TRUE

/// Hands a call to whoever of the right trade is nearest and free. Nobody: it stays open for the first to come free.
/proc/bot_offer_request(datum/bot_request/R)
	if(!R.still_open() || !R.place)
		return
	var/turf/there = isarea(R.place) ? null : get_turf(R.place)
	var/datum/bot_brain/best
	var/best_dist
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(QDELETED(B) || QDELETED(B.owner) || !B.can_take_call(R))
			continue
		var/dist = there ? get_dist(B.owner, there) : 0
		if(!best || dist < best_dist)
			best = B
			best_dist = dist
	best?.take_call(R)

/// Something a bot heard that might be a call. TRUE if it was one (answered or not): nothing else to say to it.
/datum/bot_brain/proc/heard_call(mob/living/talker, lower_msg, radio_freq, named)
	var/turf/here = get_turf(talker)
	if(!here)
		return FALSE
	// The answer to "where are you?".
	var/datum/bot_request/waiting = bot_open_request_from(talker, null)
	if(waiting)
		var/area/told = bot_area_named(lower_msg, here, waiting.kind.own_words())
		if(!told)
			return FALSE
		waiting.place = told
		waiting.made = world.time
		bot_offer_request(waiting)
		return TRUE
	var/datum/bot_request_kind/kind = bot_request_kind_of(lower_msg, named, here)
	if(!kind)
		return FALSE
	// Only those whose call it is have anything to do with it (and for a summons, only whoever was named).
	if(kind.jobs ? !(owner.mind?.assigned_role in kind.jobs) : !named)
		return FALSE
	var/datum/bot_request/R = bot_open_request_from(talker, kind)
	if(R)
		return TRUE //heard it already (another bot's ears, or the same shout twice)
	var/atom/place = kind.needs_place ? bot_area_named(lower_msg, here, kind.own_words()) : talker
	if(!place && bot_caller_locatable(talker, kind, radio_freq))
		place = talker
	R = bot_new_request(kind, talker, radio_freq, place)
	kind.read_details(R, lower_msg)
	if(!kind.jobs)
		R.only_for = src
	if(!place)
		R.asked_where = TRUE
		say_after_typing(bot_radio_prefix(radio_freq) + pick("Where are you?", "Where?", "Whereabouts?"))
		return TRUE
	// A beat for everyone to have heard it, then the nearest free one answers.
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_offer_request), R), rand(8, 20))
	return TRUE

/// Puts a call out over the radio for somebody of another trade: says the line, and has it answered like anyone's.
/datum/bot_brain/proc/call_for(kind_type, line, detail)
	if(world.time < next_call_time || gym_scripted || QDELETED(owner) || owner.stat != CONSCIOUS)
		return FALSE
	var/datum/bot_request_kind/kind = locate(kind_type) in GLOB.bot_request_kinds
	if(!kind || bot_open_request_from(owner, kind))
		return FALSE
	// Nobody to hear it: no point saying it.
	var/anyone = !length(kind.jobs)
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(anyone)
			break
		if(H != owner && H.stat == CONSCIOUS && (H.mind?.assigned_role in kind.jobs))
			anyone = TRUE
	if(!anyone)
		return FALSE
	next_call_time = world.time + 5 MINUTES
	var/datum/bot_request/R = bot_new_request(kind, owner, FREQ_COMMON, kind.walks_there ? owner : get_turf(owner))
	R.detail = detail
	bot_say(owner, ";[line]")
	bot_log(src, "called for a [kind.name]: \"[line]\"")
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_offer_request), R), rand(25, 50))
	return TRUE

// ---------------------------------------------------------------------------------------------
// Picking calls up later
// ---------------------------------------------------------------------------------------------

/// A call nobody was free for when it came in, picked up by the first of the right trade to come free.
/datum/bot_duty/answer_call
	name = "calls for help"
	tier = BOT_DUTY_URGENT
	priority = 60
	interval_min = 30
	interval_max = 60
	interrupts = TRUE

/datum/bot_duty/answer_call/proc/call_for_bot(datum/bot_brain/bot)
	var/datum/bot_request/best
	var/best_dist
	for(var/datum/bot_request/R as anything in GLOB.bot_requests)
		if(!R.still_open() || !R.place || !bot.can_take_call(R))
			continue
		var/dist = isarea(R.place) ? 0 : get_dist(bot.owner, R.place)
		if(!best || dist < best_dist)
			best = R
			best_dist = dist
	return best

/datum/bot_duty/answer_call/try_start(datum/bot_brain/bot)
	if(!length(GLOB.bot_requests))
		return FALSE
	var/datum/bot_request/R = call_for_bot(bot)
	return R ? bot.take_call(R) : FALSE

/datum/bot_duty/answer_call/should_interrupt(datum/bot_brain/bot)
	if(!length(GLOB.bot_requests))
		return FALSE
	var/datum/bot_request/R = call_for_bot(bot)
	return R && R.kind.walks_there

// ---------------------------------------------------------------------------------------------
// Going
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/answer_call
	lawful = TRUE
	var/datum/bot_request/request

/datum/bot_goal/answer_call/New(datum/bot_request/R)
	. = ..()
	request = R
	doing = R.kind.doing

/datum/bot_goal/answer_call/resolve_target(datum/bot_brain/bot)
	target = request.kind.where_to_go(bot, request)

/datum/bot_goal/answer_call/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/answer_call/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/attend_call())
	return list(S)

/datum/bot_goal/answer_call/on_success(datum/bot_brain/bot)
	GLOB.bot_requests -= request
	request.kind.attend(bot, request)

/// Couldn't get there: says so, and leaves it for somebody who can.
/datum/bot_goal/answer_call/on_give_up(datum/bot_brain/bot)
	LAZYOR(request.failed_by, bot)
	if(request.taken_by == bot)
		request.taken_by = null
	var/mob/living/who = request.caller_ref?.resolve()
	if(who && who != bot.owner)
		bot.say_after_typing(bot_radio_prefix(request.radio_freq) + pick("I can't get to you.", "Can't get in there, sorry.", "No way through to you from here."))

/datum/bot_strategy/answer_call/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// There: a word to whoever called, if they're about.
/datum/bot_step/attend_call/execute(datum/bot_brain/bot)
	var/datum/bot_goal/answer_call/G = bot.current_goal
	if(!istype(G))
		return GOAL_STEP_FAIL
	var/mob/living/who = G.request.caller_ref?.resolve()
	if(who && who != bot.owner && who.stat == CONSCIOUS && length(G.request.kind.arrival_lines) && (who in view(6, bot.owner)))
		bot.owner.face_atom(who)
		bot_say(bot.owner, pick(G.request.kind.arrival_lines))
	return GOAL_STEP_SUCCESS

/// Somewhere to stand in an area: the open floor nearest the bot that isn't a doorway.
/datum/bot_brain/proc/nearest_spot_in(area/A)
	var/turf/best
	var/best_dist
	for(var/turf/open/T in A)
		if(T.z != owner.z || T.density || is_blocked_turf(T, TRUE) || (locate(/obj/machinery/door) in T))
			continue
		var/dist = get_dist(owner, T)
		if(!best || dist < best_dist)
			best = T
			best_dist = dist
	return best

// ---------------------------------------------------------------------------------------------
// Shut in somewhere
// ---------------------------------------------------------------------------------------------

/// A bot shut in a room its ID doesn't open (it answered a call in there, or followed somebody, and the door has
/// shut): it asks over the radio to be let out, and anybody whose ID opens one of the room's doors comes and opens
/// it. Bots only make this call - what a player means by "can someone open the kitchen" isn't read yet.
/datum/bot_request_kind/let_out
	name = "locked in"
	jobs = list()
	ack_lines = list("On my way to let you out.", "Hang on, I'll get the door.", "Coming - give me a minute.", "I'll come and open it.")
	arrival_lines = list("There you go.", "Out you come.", "Door's open.")
	doing = "going to let somebody out"

/datum/bot_request_kind/let_out/matches(lower_msg, named, turf/near)
	return FALSE

/// The door of the caller's room this bot would open: one its ID opens, that it can walk up to.
/datum/bot_request_kind/let_out/proc/door_for(datum/bot_brain/bot, datum/bot_request/R)
	for(var/obj/machinery/door/airlock/D as anything in R.detail)
		if(QDELETED(D) || D.locked || D.welded || !D.hasPower() || !D.allowed(bot.owner))
			continue
		if(!D.density || bot.can_walk_lawfully_to(D))
			return D
	return null

/datum/bot_request_kind/let_out/answered_by(datum/bot_brain/bot, datum/bot_request/R)
	var/mob/living/who = R.caller_ref?.resolve()
	if(!who || who == bot.owner || who.z != bot.owner.z || get_dist(who, bot.owner) > 60)
		return FALSE
	return !!door_for(bot, R)

/datum/bot_request_kind/let_out/where_to_go(datum/bot_brain/bot, datum/bot_request/R)
	return door_for(bot, R)

/// At the door: open it, and whoever is inside gets the word.
/datum/bot_request_kind/let_out/attend(datum/bot_brain/bot, datum/bot_request/R)
	var/obj/machinery/door/airlock/D = door_for(bot, R)
	var/mob/living/carbon/human/who = R.caller_ref?.resolve()
	if(!D || !bot.owner.Adjacent(D))
		return
	if(D.density && !D.operating)
		bot.use_atom(D)
	bot_log(bot, "opened [D] to let [who || "somebody"] out")
	// They head for it while it's open.
	var/datum/bot_brain/theirs = istype(who) ? who.bot_brain : null
	if(theirs && theirs.state == BOT_STATE_WANDER && !QDELETED(D))
		theirs.shut_in_checked_at = -1000
		var/turf/outside = get_step(D, get_dir(who, D))
		if(isopenturf(outside) && !outside.density)
			theirs.assign_goal(new /datum/bot_goal/walk_up_to(outside))

/// The airlocks around the pocket this bot is shut in, which it can't open itself.
/datum/bot_brain/proc/doors_shutting_me_in()
	. = list()
	if(!is_shut_in() || !shut_in_region)
		return
	for(var/turf/T as anything in shut_in_region)
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(T, d)
			if(!next || shut_in_region[next])
				continue
			for(var/obj/machinery/door/airlock/D in next)
				if(D.density && !D.welded && !D.locked)
					. |= D

/// Shut in, with a door somebody else could open: asks to be let out. Now and then - not for the first minute, in
/// case whoever it followed in comes back out.
/datum/bot_brain/proc/maybe_ask_to_be_let_out()
	if(gym_scripted && !gym_asks_out)
		return FALSE
	if(world.time < next_call_time || owner.stat != CONSCIOUS || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST)
		return FALSE
	var/list/doors = doors_shutting_me_in()
	if(!length(doors))
		return FALSE
	var/where = get_area_name(owner, TRUE)
	return call_for(/datum/bot_request_kind/let_out, pick("Can somebody let me out of [where]? Door won't open for me.", "I'm shut in [where] - could someone get the door?", "Anyone near [where]? I can't get the door open from in here."), doors)

/datum/bot_brain
	/// A Bot Gym bot keeps quiet about being shut in unless its scenario is about that.
	var/gym_asks_out = FALSE
	var/next_shut_in_look = 0

// ---------------------------------------------------------------------------------------------
// Calls bots make
// ---------------------------------------------------------------------------------------------

/// Hurt, and nothing to hand to do anything about it: asks for a medic, the way anyone would before limping off to
/// Medbay. Not for a scratch.
/datum/bot_brain/proc/maybe_call_medic()
	if(is_medical_job() || owner.health > owner.maxHealth * 0.6 || !prob(40 + 40 * sociability))
		return FALSE
	var/where = get_area_name(owner, TRUE)
	return call_for(/datum/bot_request_kind/medical, pick("Could use a medic in [where].", "Need a doctor in [where], I'm hurt.", "Medic to [where], please."))

/// Walking past something that wants mopping up: mentions it to the janitor, now and then.
/datum/bot_brain/proc/maybe_report_mess()
	if(owner.mind?.assigned_role == "Janitor" || world.time < next_call_time || !prob(30 * sociability))
		return FALSE
	for(var/obj/effect/decal/cleanable/C in view(4, owner))
		if(!bot_is_mess(C) || bot_mess_priority(C) < 2)
			continue
		var/area/A = get_area(C)
		if(findtext(A.name, "Maintenance"))
			continue
		return call_for(/datum/bot_request_kind/janitor, pick("Janitor, there's a mess in [A.name].", "Could we get the janitor to [A.name]? It's a state.", "Janitor needed in [A.name]."))
	return FALSE

#undef BOT_REQUEST_LIFETIME
#undef BOT_REQUEST_REPEAT
