// Asking the crew for things, and being answered the way a person would answer. bot_requests.dm has calls and how they're
// taken; this is the rest of what a player says to the station that bots used to let go by. Seventy-seven lines from a player in
// one round had about ten answers, nearly all of them "hey" back:
//
//  - a job called by its title is spoken to, like a name: "cap", "hop", "science", "genetics" gets "Yeah?" from whoever it is, and
//    if nobody's on that job somebody says so ("no AI this shift")
//  - whoever answered somebody keeps listening to them for a bit, so the next line is to them too: "cap" then "I was killing a traitor"
//  - "clone this man" brings a doctor for the body; "science, upgrade the machines in Medbay" puts Medbay first on a scientist's
//    list; "HoP, can I get more access?" gets asked what for, and the card back with what fits
//  - "wait", "stop", "hold on" to somebody: it stops and listens
//  - arrested, "why?" gets the charge, and what Security knows can drop it (bot_heard_plea())
//  - "Max is a traitor!" on the radio: a paranoid officer or a hunter believes it, the rest go and look (bot_heard_accusation())
//  - "what you in for?" to a prisoner, "where's Max?" to the station

/// How long a bot that answered somebody takes what they say next as said to it.
#define BOT_TALKING_WITH (25 SECONDS)
/// How long "wait" holds a bot still.
#define BOT_WAIT_FOR (8 SECONDS)
/// Strictness at which a HoP or an officer goes by the book, and below which it's easygoing (bot_departments.dm has the same).
#define BOT_ASK_STRICT 0.6
#define BOT_ASK_EASYGOING 0.3

/datum/bot_brain
	/// Who it's talking with, and until when what they say is to it.
	var/datum/weakref/talking_with
	var/talking_until = 0
	/// Stood still to listen to somebody who said "wait", until then.
	var/talk_pause_until = 0
	var/datum/weakref/talk_pause_for
	/// A body somebody asked this doctor to clone (goals/cloning.dm), and until when.
	var/datum/weakref/clone_wanted
	var/clone_wanted_until = 0
	/// Somewhere somebody asked this scientist to upgrade first (goals/rnd_bench.dm), and until when.
	var/area/upgrade_wanted_in
	var/upgrade_wanted_until = 0
	/// The last charge it was brigged on: what it says it's in for.
	var/last_charge
	/// A HoP that's asked somebody what they want access for: who, and until when the answer's to that.
	var/datum/weakref/access_asker
	var/access_asked_until = 0

/// Kind name -> when somebody last said there's nobody on it, so a radio full of crew doesn't all say it.
GLOBAL_LIST_EMPTY(bot_nobody_said)
/// Person asked about -> when somebody last answered where they are.
GLOBAL_LIST_EMPTY(bot_whereabouts_said)
/// Access somebody's been told they'll get, waiting on their card: list(weakref to them, accesses, what they're called, until).
GLOBAL_LIST_EMPTY(bot_access_pending)

// ---------------------------------------------------------------------------------------------
// Spoken to
// ---------------------------------------------------------------------------------------------

/// Job title words, and the jobs they mean. "cap" is the Captain the way anybody types it.
GLOBAL_LIST_INIT(bot_title_words, list(
	"captain" = list("Captain"), "cap" = list("Captain"), "hop" = list("Head of Personnel"), "hos" = list("Head of Security"),
	"ce" = list("Chief Engineer"), "cmo" = list("Chief Medical Officer"), "rd" = list("Research Director"), "qm" = list("Quartermaster"),
	"warden" = list("Warden"), "detective" = list("Detective"), "det" = list("Detective"),
	"ai" = list("AI"), "borg" = list("Cyborg"), "cyborg" = list("Cyborg"),
	"science" = list("Scientist", "Research Director"), "scientist" = list("Scientist", "Research Director"), "rnd" = list("Scientist", "Research Director"),
	"robotics" = list("Roboticist"), "roboticist" = list("Roboticist"),
	"genetics" = list("Geneticist"), "geneticist" = list("Geneticist"),
	"chemist" = list("Chemist"), "chemistry" = list("Chemist"),
	"botanist" = list("Botanist"), "botany" = list("Botanist"), "hydroponics" = list("Botanist"),
	"bartender" = list("Bartender"), "barkeep" = list("Bartender"), "chef" = list("Cook"), "cook" = list("Cook"),
	"janitor" = list("Janitor"), "cargo" = list("Cargo Technician", "Quartermaster"), "miner" = list("Shaft Miner"), "miners" = list("Shaft Miner"), "mining" = list("Shaft Miner"),
	"atmos" = list("Atmospheric Technician"), "clown" = list("Clown"), "mime" = list("Mime"), "chaplain" = list("Chaplain"),
	"lawyer" = list("Lawyer"), "curator" = list("Curator"), "librarian" = list("Curator"),
))

/// A line that's a job being called: short, and its title in it. Long lines with a job in them are about the job, not to it.
/proc/bot_title_called(lower_msg)
	if(length(lower_msg) > 40)
		return null
	// The one it's said to comes first ("Mining, science needs silver" is to Mining); the longer word where two start together
	var/best
	var/best_at = 0
	for(var/word in GLOB.bot_title_words)
		var/at = bot_text_word_at(lower_msg, word)
		if(at && (!best || at < best_at || (at == best_at && length(word) > length(best))))
			best = word
			best_at = at
	return best ? GLOB.bot_title_words[best] : null

/// Whether this bot is the one a title called for.
/datum/bot_brain/proc/hears_own_title(lower_msg)
	var/list/jobs = bot_title_called(lower_msg)
	return jobs && (work_role() in jobs)

/// Talking to somebody: the next lines from them are to it, for a while.
/datum/bot_brain/proc/talking_to(mob/living/who)
	talking_with = WEAKREF(who)
	talking_until = world.time + BOT_TALKING_WITH

/datum/bot_brain/proc/in_conversation_with(mob/living/who)
	return world.time < talking_until && talking_with?.resolve() == who

/// Anybody alive on one of these jobs, a cyborg or the AI included. Asked from a Bot Gym arena, only that arena's count: the rest of
/// the gym isn't on its shift (a Shaft Miner in the mining arena had Cargo saying Mining was on for the arena next door).
/proc/bot_anyone_in_jobs(list/jobs, atom/asking)
	var/area/bot_gym/arena = asking ? get_area(asking) : null
	for(var/mob/living/L in GLOB.alive_mob_list)
		if(istype(arena) && get_area(L) != arena)
			continue
		if(L.stat != DEAD && (L.mind?.assigned_role in jobs))
			return TRUE
	return FALSE

/// A job called that nobody's on: one person says so, the way somebody always does. "AI?" with no AI.
/datum/bot_brain/proc/say_nobody_on(list/jobs, radio_freq)
	var/key = jointext(jobs, "/")
	if(world.time < GLOB.bot_nobody_said[key] || bot_anyone_in_jobs(jobs, owner))
		return FALSE
	GLOB.bot_nobody_said[key] = world.time + 2 MINUTES
	var/job = jobs[1]
	var/what = job == "AI" ? "an AI" : (job == "Cyborg" ? "any borgs" : "a [lowertext(job)]")
	say_after_typing(bot_radio_prefix(radio_freq) + pick("There's no [job == "AI" ? "AI" : lowertext(job)] this shift.", "We don't have [what] right now.", "Nobody's on [lowertext(job)], sorry.", "Don't think we've got [what]."))
	bot_log(src, "said nobody's on [job]")
	return TRUE

// ---------------------------------------------------------------------------------------------
// Waiting
// ---------------------------------------------------------------------------------------------

/// "Wait!" said to it: it stops what it's doing and listens. Not in a fight, an arrest or anything urgent.
/datum/bot_brain/proc/wait_for(mob/living/talker)
	if(state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || owner.on_fire)
		return null
	if(current_goal && !current_goal.lawful)
		return null
	var/datum/bot_goal/run_from/running = current_goal
	if(istype(running))
		if(running.foe_ref?.resolve() == talker && (bot_is_wanted(talker) || attacker == talker))
			return null //who it's running from, saying wait
		drop_goals("told to stop running")
	talk_pause_until = world.time + BOT_WAIT_FOR
	talk_pause_for = WEAKREF(talker)
	stop_pursuit()
	owner.face_atom(talker)
	return pick("Yeah?", "What's up?", "What?", "Hm?", "Okay, what?")

/// Stood listening: nothing else this tick. Its reflexes ran before this (fire, the pool, its air).
/datum/bot_brain/proc/hold_still_for_talk()
	if(world.time >= talk_pause_until || (state != BOT_STATE_GOAL && state != BOT_STATE_WANDER))
		return FALSE
	var/mob/living/who = talk_pause_for?.resolve()
	if(!who || get_dist(owner, who) > 7)
		talk_pause_until = 0
		return FALSE
	if(pursuing_kind)
		stop_pursuit()
	return TRUE

// ---------------------------------------------------------------------------------------------
// In the cells
// ---------------------------------------------------------------------------------------------

/// "What you in for?" to somebody locked up.
/datum/bot_brain/proc/what_im_in_for()
	if(!last_charge || (!is_in_active_cell(owner) && !owner.handcuffed && !owner.bot_life_sentence))
		return pick("I'm not in for anything.", "Nothing. Why?")
	var/charge = lowertext(last_charge)
	if(bot_traitor)
		return pick("[capitalize(charge)]. They'll never prove the rest.", "[capitalize(charge)]. Long story.")
	return mood_pick(list("[capitalize(charge)], apparently. It was a misunderstanding.", "[capitalize(charge)]. I'll be out soon."), list("[capitalize(charge)]. Don't ask.", "[capitalize(charge)], they say.", "[capitalize(charge)]."), list("[capitalize(charge)]. Wasn't even me.", "[capitalize(charge)]. Shitcurity.", "Mind your own business."))

// ---------------------------------------------------------------------------------------------
// Where somebody is
// ---------------------------------------------------------------------------------------------

/// Who somebody means by a name in what they said: a whole name first, then a first name, the nearest to them of those it fits.
/proc/bot_person_named(lower_msg, mob/living/near, list/not_these)
	var/mob/living/carbon/human/best
	var/best_score
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD || (H in not_these) || (near && H.z != near.z))
			continue
		var/score
		if(H.real_name && bot_text_has_any(lower_msg, list(lowertext(H.real_name))))
			score = 0
		else
			var/first = H.first_name()
			if(!first || length(first) < 3 || !bot_text_has_any(lower_msg, list(lowertext(first))))
				continue
			score = 1000
		score += near ? get_dist(near, H) : 0
		if(!best || score < best_score)
			best = H
			best_score = score
	return best

/// "Where's Max?" to everybody: one person who can see them says where. Over the radio nobody answers what they don't know.
/datum/bot_brain/proc/answer_whereabouts(mob/living/talker, lower_msg, radio_freq)
	if(!bot_text_has_any(lower_msg, list("where is", "where's", "wheres", "where are", "anyone seen", "has anyone seen", "seen")))
		return FALSE
	var/mob/living/carbon/human/asked
	for(var/mob/living/carbon/human/H in view(7, owner))
		var/first = H.first_name()
		if(H != owner && H != talker && H.stat != DEAD && first && length(first) >= 3 && bot_text_has_any(lower_msg, list(lowertext(first))))
			asked = H
			break
	if(!asked)
		return FALSE
	var/datum/weakref/ref = WEAKREF(asked)
	if(world.time < GLOB.bot_whereabouts_said[ref])
		return TRUE
	GLOB.bot_whereabouts_said[ref] = world.time + 30 SECONDS
	var/where = get_area_name(asked, TRUE)
	say_after_typing(bot_radio_prefix(radio_freq) + pick("[asked.first_name()]'s in [where].", "Saw [asked.first_name()] in [where] just now.", "[where], with me."))
	return TRUE

// ---------------------------------------------------------------------------------------------
// Cloning
// ---------------------------------------------------------------------------------------------

/// The body somebody means: the one they're dragging, or the dead nearest them.
/proc/bot_body_near(mob/living/who)
	if(!who)
		return null
	var/mob/living/carbon/human/dragged = who.pulling
	if(istype(dragged) && dragged.stat == DEAD)
		return dragged
	var/mob/living/carbon/human/best
	for(var/mob/living/carbon/human/H in range(3, who))
		if(H.stat == DEAD && (!best || get_dist(who, H) < get_dist(who, best)))
			best = H
	return best

/datum/bot_request_kind/cloning
	name = "cloning"
	jobs = list("Medical Doctor", "Chief Medical Officer", "Geneticist", "Paramedic")
	strong_words = list("clone", "cloning", "clone him", "clone her", "clone them", "clone this", "needs cloning", "need cloning", "revive him", "revive her", "revive them", "bring him back", "bring her back", "bring them back")
	ack_lines = list("On my way. Is it a body?", "Coming - bring them to the scanner if you can.", "I'll take them.", "On it.")
	arrival_lines = list("Right, let's get them in the scanner.", "I've got them from here.", "Let go of them, I'll take it from here.")
	urgent = TRUE
	reads_sensors = TRUE
	doing = "coming for a body to clone"

/datum/bot_request_kind/cloning/read_details(datum/bot_request/R, lower_msg)
	var/mob/living/carbon/human/body = bot_body_near(R.caller_ref?.resolve())
	R.detail = body ? WEAKREF(body) : null

/datum/bot_request_kind/cloning/attend(datum/bot_brain/bot, datum/bot_request/R)
	var/datum/weakref/ref = R.detail
	var/mob/living/carbon/human/body = ref?.resolve() || bot_body_near(R.caller_ref?.resolve())
	if(!istype(body) || body.stat != DEAD)
		bot_say(bot.owner, pick("Where's the body?", "Who needs cloning?"))
		return
	bot.clone_wanted = WEAKREF(body)
	bot.clone_wanted_until = world.time + 3 MINUTES
	bot_log(bot, "asked to clone [body]")
	if(body.pulledby && body.pulledby != bot.owner)
		bot_say(bot.owner, pick("Let go of [body.p_them()], I'll take [body.p_them()] from here.", "I've got [body.p_them()], you can let go."))
	bot.continue_medical_round() //goals/treat_patient.dm: the body asked about goes first (find_body_to_clone())

// ---------------------------------------------------------------------------------------------
// Upgrades
// ---------------------------------------------------------------------------------------------

/datum/bot_request_kind/upgrades
	name = "upgrades"
	jobs = list("Scientist", "Research Director")
	strong_words = list("upgrade the", "upgrade machines", "upgrade our", "upgrade medbay", "upgrade the machines", "upgraded parts", "better parts", "rped", "upgrades", "upgrade some", "upgrade them")
	role_words = list("science", "scientist", "scientists", "rnd", "research", "rd")
	ack_lines = list("Sure, once I've printed the parts.", "Will do, give me a bit.", "Yeah, I'll get to it.", "On the list.")
	walks_there = FALSE
	doing = "upgrading somebody's machines"

/datum/bot_request_kind/upgrades/attend(datum/bot_brain/bot, datum/bot_request/R)
	bot.upgrade_wanted_in = isarea(R.place) ? R.place : get_area(R.place)
	bot.upgrade_wanted_until = world.time + 15 MINUTES
	bot_log(bot, "asked to upgrade [bot.upgrade_wanted_in]")

// ---------------------------------------------------------------------------------------------
// Access, from the HoP
// ---------------------------------------------------------------------------------------------

/// What people ask the HoP to get into -> the access for it.
GLOBAL_LIST_INIT(bot_access_words, list(
	"maint" = list(ACCESS_MAINT_TUNNELS), "maintenance" = list(ACCESS_MAINT_TUNNELS),
	"science" = list(ACCESS_RESEARCH), "research" = list(ACCESS_RESEARCH), "rnd" = list(ACCESS_RESEARCH), "toxins" = list(ACCESS_RESEARCH, ACCESS_TOX),
	"robotics" = list(ACCESS_ROBOTICS), "xenobiology" = list(ACCESS_RESEARCH, ACCESS_XENOBIOLOGY), "xeno" = list(ACCESS_RESEARCH, ACCESS_XENOBIOLOGY),
	"medbay" = list(ACCESS_MEDICAL), "medical" = list(ACCESS_MEDICAL), "morgue" = list(ACCESS_MORGUE), "surgery" = list(ACCESS_MEDICAL, ACCESS_SURGERY),
	"genetics" = list(ACCESS_MEDICAL, ACCESS_GENETICS), "cloning" = list(ACCESS_MEDICAL, ACCESS_GENETICS, ACCESS_CLONING), "clone" = list(ACCESS_MEDICAL, ACCESS_GENETICS, ACCESS_CLONING),
	"chemistry" = list(ACCESS_MEDICAL, ACCESS_CHEMISTRY), "virology" = list(ACCESS_MEDICAL, ACCESS_VIROLOGY),
	"engineering" = list(ACCESS_ENGINE), "engine" = list(ACCESS_ENGINE, ACCESS_ENGINE_EQUIP), "atmos" = list(ACCESS_ATMOSPHERICS), "atmospherics" = list(ACCESS_ATMOSPHERICS),
	"tech storage" = list(ACCESS_TECH_STORAGE), "construction" = list(ACCESS_CONSTRUCTION),
	"cargo" = list(ACCESS_CARGO, ACCESS_MAILSORTING), "mining" = list(ACCESS_MINING), "bar" = list(ACCESS_BAR), "kitchen" = list(ACCESS_KITCHEN),
	"botany" = list(ACCESS_HYDROPONICS), "hydroponics" = list(ACCESS_HYDROPONICS), "janitor" = list(ACCESS_JANITOR), "theatre" = list(ACCESS_THEATRE),
	"library" = list(ACCESS_LIBRARY), "eva" = list(ACCESS_EVA), "gateway" = list(ACCESS_GATEWAY), "teleporter" = list(ACCESS_TELEPORTER),
))
/// What a HoP doesn't give to anybody who asks.
GLOBAL_LIST_INIT(bot_access_refused, list("armory", "armoury", "captain", "captains", "bridge", "vault", "upload", "ai core", "hos", "all access", "aa", "heads", "command", "security", "brig"))

/datum/bot_request_kind/access
	name = "access"
	jobs = list("Head of Personnel")
	strong_words = list("more access", "extra access", "access to", "all access", "upgrade my id", "id upgrade", "change my id", "add access", "give me access", "get access", "need access", "my access")
	walks_there = FALSE
	needs_place = FALSE
	doing = "seeing to somebody's access"

/datum/bot_request_kind/access/read_details(datum/bot_request/R, lower_msg)
	R.detail = lower_msg

/datum/bot_request_kind/access/attend(datum/bot_brain/bot, datum/bot_request/R)
	bot.consider_access_request(R.caller_ref?.resolve(), R.detail, R.radio_freq)

/// Asked for access: what it's for decides it, and the HoP's own nature.
/datum/bot_brain/proc/consider_access_request(mob/living/carbon/human/who, lower_msg, radio_freq)
	if(!istype(who))
		return
	var/prefix = bot_radio_prefix(radio_freq)
	talking_to(who)
	if(bot_is_wanted(who))
		say_after_typing(prefix + pick("You're wanted by Security. Sort that out first.", "Not while Security's after you."))
		return
	for(var/word in GLOB.bot_access_refused)
		if(bot_text_has_any(lower_msg, list(word)) && !(who.mind?.assigned_role in GLOB.command_positions))
			say_after_typing(prefix + pick("Can't give you that, sorry.", "No can do. That's heads only.", "Not a chance."))
			return
	var/list/accesses = list()
	var/list/names = list()
	for(var/word in GLOB.bot_access_words)
		if(bot_text_has_any(lower_msg, list(word)))
			accesses |= GLOB.bot_access_words[word]
			names |= word
	if(!length(accesses))
		access_asker = WEAKREF(who)
		access_asked_until = world.time + 1 MINUTES
		say_after_typing(prefix + pick("What do you need it for?", "Access to what?", "What for?", "Where do you need to get into?"))
		return
	// A strict HoP gives one place at a time, and only with a reason; an easygoing one gives what's asked.
	if(strictness >= BOT_ASK_STRICT && length(names) > 1)
		accesses = GLOB.bot_access_words[names[1]]
		names = list(names[1])
	GLOB.bot_access_pending += list(list(WEAKREF(who), accesses, english_list(names), world.time + 5 MINUTES))
	say_after_typing(prefix + pick("Alright, [english_list(names)]. Put your ID down on my desk and I'll sort it.", "Sure. Drop your card at my window and I'll add [english_list(names)].", "Fine, [english_list(names)]. Leave your ID on the desk."))
	bot_log(src, "promised [who] access to [english_list(names)]")

/// A card on the desk for the access it was promised: the transfer machinery does the rest (bot_hopping.dm).
/datum/bot_brain/proc/find_promised_card()
	for(var/list/pending as anything in GLOB.bot_access_pending.Copy())
		var/datum/weakref/ref = pending[1]
		var/mob/living/carbon/human/who = ref.resolve()
		if(!who || world.time > pending[4])
			GLOB.bot_access_pending -= list(pending)
			continue
		for(var/obj/item/card/id/card in range(3, owner))
			if(!isturf(card.loc) || card.registered_name != who.real_name)
				continue
			GLOB.bot_access_pending -= list(pending)
			var/datum/bot_transfer/T = new(card, null, who)
			T.add_access = pending[2]
			T.access_names = pending[3]
			return T
	return null

// ---------------------------------------------------------------------------------------------
// Pleading, when arrested
// ---------------------------------------------------------------------------------------------

/// Arrested and talking back: "why?" gets the charge; a reason that fits what Security knows gets it dropped. TRUE if it answered.
/datum/bot_brain/proc/bot_heard_plea(mob/living/carbon/human/talker, lower_msg)
	var/datum/bot_goal/brig_prisoner/escort = current_goal
	var/escorting = istype(escort) && escort.prisoner == talker
	if(!escorting && (state != BOT_STATE_ARREST || arrest_suspect != talker))
		return FALSE
	if(get_dist(owner, talker) > 7)
		return FALSE
	var/datum/bot_wanted/W = bot_get_wanted_entry(talker)
	var/crime = W?.crime || arrest_crime
	if(!bot_text_has_any(lower_msg, list("traitor", "valid", "syndie", "syndicate", "antag", "self defense", "self-defense", "self defence", "attacked me", "started it", "hit me first", "he started", "she started", "they started", "wasn't me", "wasnt me", "not me", "innocent", "didn't do", "didnt do", "i was helping", "was helping")))
		if(bot_text_has_any(lower_msg, list("why", "what did i do", "what for", "what's the charge", "whats the charge", "what charge", "for what")))
			say_after_typing(pick("[capitalize(crime)]. [W?.details ? W.details : ""]", "You're under arrest for [lowertext(crime)].", "[capitalize(crime)], that's what."))
			return TRUE
		return FALSE
	var/mob/living/carbon/human/victim = W?.victim?.resolve()
	var/reason
	if(victim && bot_is_wanted(victim))
		reason = "[victim.real_name]'s wanted"
	else if(victim && GLOB.bot_recent_aggression["[REF(victim)]>[REF(talker)]"] && (GLOB.bot_recent_aggression["[REF(victim)]>[REF(talker)]"] < (GLOB.bot_recent_aggression["[REF(talker)]>[REF(victim)]"] || INFINITY)))
		reason = "[victim.real_name] started it"
	else if(victim && victim.bot_brain?.gone_loud())
		reason = "[victim.real_name]'s a traitor"
	if(!reason)
		if(W?.severity < BOT_CRIME_MAJOR && strictness < BOT_ASK_EASYGOING && prob(50))
			reason = "a warning"
		else
			say_after_typing(pick("Tell it to the Warden.", "Save it.", "You can explain in the cell.", "Not my call. Hands where I can see them."))
			return TRUE
	bot_log(src, "dropped the charge on [talker]: [reason]")
	bot_tally("dropped a charge")
	bot_clear_wanted(talker)
	bot_set_criminal_status(talker, "None")
	if(escorting)
		owner.stop_pulling()
		drop_goals("they explained")
	else
		end_arrest("they explained")
	if(talker.handcuffed && get_dist(owner, talker) <= 1)
		talker.uncuff()
	say_after_typing(reason == "a warning" ? pick("Fine. Consider this a warning.", "Alright, just this once. Behave.") : pick("Alright, my mistake. You're free to go.", "Fair enough - sorry about that.", "Okay. Go on, then."))
	return TRUE

// ---------------------------------------------------------------------------------------------
// "X is a traitor!"
// ---------------------------------------------------------------------------------------------

/// Words that make a line about somebody an accusation.
GLOBAL_LIST_INIT(bot_accusation_words, list("is a traitor", "is traitor", "traitor", "is valid", "valid", "is syndie", "syndie", "syndicate", "is an antag", "antag", "attacked me", "attacking me", "killed", "murdered", "is a changeling", "changeling", "cultist", "arrest"))

/// An officer hearing one: a paranoid one or a hunter believes it and goes for them; the rest go and look.
/datum/bot_brain/proc/bot_heard_accusation(mob/living/talker, lower_msg, radio_freq)
	if(!is_security_job() || !bot_text_has_any(lower_msg, GLOB.bot_accusation_words) || state == BOT_STATE_ARREST || state == BOT_STATE_COMBAT)
		return FALSE
	if(bot_is_wanted(talker) && !in_conversation_with(talker))
		return FALSE //somebody Security's after pointing at somebody else
	var/mob/living/carbon/human/accused = bot_person_named(lower_msg, talker, list(talker, owner))
	if(!accused || bot_is_wanted(accused))
		bot_log(src, "heard an accusation from [talker], but [accused ? "[accused]'s wanted already" : "not of anybody it knows"]")
		return FALSE
	var/believes = is_paranoid() || playstyle == BOT_STYLE_HUNTER || bot_too_dangerous(accused)
	if(believes)
		file_crime(accused, "Suspected Syndicate Activity", "Reported by [talker.name].", BOT_CRIME_MINOR)
		say_after_typing(bot_radio_prefix(radio_freq) + pick("Copy, going for [accused.first_name()].", "On it. [accused.first_name()]'s getting searched.", "Heard. [accused.name], you're coming with me."))
		bot_log(src, "believes [talker] about [accused]")
		begin_arrest(accused)
		return TRUE
	say_after_typing(bot_radio_prefix(radio_freq) + pick("I'll have a look at [accused.first_name()].", "Noted. I'll check on [accused.first_name()].", "Got it, I'll keep an eye on them."))
	bot_log(src, "going to look at [accused] for [talker]")
	if(state == BOT_STATE_WANDER || (state == BOT_STATE_GOAL && current_goal?.lawful))
		var/datum/bot_goal/respond_to_call/G = new()
		G.caller_turf = get_turf(accused)
		G.caller_name = accused.name
		if(state == BOT_STATE_GOAL)
			abandon_goals_for_arrest()
		assign_goal(G)
	return TRUE

#undef BOT_TALKING_WITH
#undef BOT_WAIT_FOR
#undef BOT_ASK_STRICT
#undef BOT_ASK_EASYGOING
