// Talking back: what the canned lines of bot_chat.dm and the answers of bot_chatter.dm leave out.
//
//  - The speakers. When the shuttle's called or recalled or in, the alert goes up or down, or there are meteors, a storm or the Captain
//    on the speakers, somebody or other says what everyone's thinking on the radio. Never the same line twice for the one announcement.
//  - A mood, out of temper and sociability (mood()): the same question gets a cheery answer from one and a short one from another.
//  - Insults count. They go on the same grudge being shoved does (bot_reflexes.dm): the first gets a look, the next a warning, and a
//    short-tempered bot shoves after that. Words alone never start a fight; hands do.
//  - A grumpy bot now and then has a go at somebody it's standing next to. If they're the same sort, it's an argument, and it can end
//    in a shove, which the other one answers the way it would any shove.
//  - People questions: where somebody is (only what it could know: who's in sight, and where that job works), who the Captain or
//    any other job is, and what time it is.

#define BOT_MOOD_CHEERY 1
#define BOT_MOOD_PLAIN 2
#define BOT_MOOD_GRUMPY 3
/// Grudge points a word is worth, against BOT_GRUDGE_SHOVE (bot_reflexes.dm).
#define BOT_INSULT_POINTS 1.2
/// The most bots that answer one announcement.
#define BOT_ANNOUNCE_REACTORS 2
/// Between one argument and the next, for the one who starts them.
#define BOT_ARGUMENT_GAP (6 MINUTES)

/datum/bot_brain
	var/next_argument_time = 0

/datum/bot_brain/proc/mood()
	if(temper >= 0.65)
		return BOT_MOOD_GRUMPY
	if(temper <= 0.35 && sociability >= 0.4)
		return BOT_MOOD_CHEERY
	return BOT_MOOD_PLAIN

/// One of three lists, by mood.
/datum/bot_brain/proc/mood_pick(list/cheery, list/plain, list/grumpy)
	switch(mood())
		if(BOT_MOOD_CHEERY)
			return pick(cheery)
		if(BOT_MOOD_GRUMPY)
			return pick(grumpy)
	return pick(plain)

// ---------------------------------------------------------------------------------------------
// The speakers
// ---------------------------------------------------------------------------------------------

/// Kind of announcement -> what the crew say about it.
GLOBAL_LIST_INIT(bot_announcement_lines, list(
	"shuttle_called" = list("Finally.", "Who called it?", "Already?", "Shuttle's called, people.", "Good, I'm done with this place.", "Why'd we call it?", "About time.", "Wait, why are we leaving?"),
	"shuttle_recalled" = list("Who recalled it?", "Seriously? Recalled?", "Call it back!", "Why would you recall it?", "Recalled?! Come on.", "Somebody recall the recaller."),
	"shuttle_docked" = list("Shuttle's here!", "Everyone to departures.", "Go go go, shuttle's docked.", "Get on the shuttle.", "Shuttle's in, move it."),
	"alert_red" = list("Red alert? What happened?", "Red alert. Great.", "What's going on?", "Who did it this time?", "Red? Seriously?", "Okay, what blew up?"),
	"alert_blue" = list("Blue alert, huh.", "What's going on?", "Blue? Why?", "Something up?"),
	"alert_green" = list("Back to green.", "Green again, nice.", "Finally, green.", "Phew."),
	"alert_delta" = list("DELTA?!", "Get to the shuttle, now!", "Oh no.", "We're all gonna die.", "Run!"),
	"meteors" = list("Meteors! Stay away from the windows.", "Here we go.", "Engineering, get ready to patch some holes.", "Meteors? Great.", "Everyone away from the outer walls."),
	"rad_storm" = list("Into maintenance, everyone.", "Rad storm, get to maint.", "Not again.", "Maint, now."),
	"ion" = list("AI, state your laws.", "Uh, AI? Laws?", "Ion storm. Watch the borgs.", "Anybody check the AI?"),
	"power" = list("Lights are out!", "Power's down.", "Engineering, power?", "Who turned off the lights?"),
	"captain" = list("Thanks, Captain.", "Okay, Captain.", "Who gave the Captain a mic?", "Noted.", "Yes sir."),
	"anomaly" = list("Anyone seen the anomaly?", "Science, there's an anomaly for you.", "Stay clear of the anomaly, folks."),
))

/// From priority_announce() and minor_announce(): what everyone heard over the speakers.
/proc/bot_crew_heard_announcement(text, title, type)
	if(!length(GLOB.bot_brains))
		return
	var/kind = bot_announcement_kind(lowertext("[title] [text]"), type)
	var/list/lines = kind ? GLOB.bot_announcement_lines[kind] : null
	if(!length(lines))
		return
	lines = lines.Copy()
	var/reactors = rand(1, BOT_ANNOUNCE_REACTORS)
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(!reactors || !length(lines))
			break
		if(QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.gym_scripted || B.gone_loud() || B.state == BOT_STATE_COMBAT || !prob(20 + 60 * B.sociability))
			continue
		reactors--
		addtimer(CALLBACK(B, TYPE_PROC_REF(/datum/bot_brain, say_after_typing), ";" + pick_n_take(lines)), rand(2 SECONDS, 12 SECONDS))

/proc/bot_announcement_kind(lower, type)
	if(type == "Captain")
		return "captain"
	if(findtext(lower, "emergency shuttle has been called"))
		return "shuttle_called"
	if(findtext(lower, "has been recalled"))
		return "shuttle_recalled"
	if(findtext(lower, "has docked with the station"))
		return "shuttle_docked"
	if(findtext(lower, "security level elevated to red") || findtext(lower, "security level lowered to red"))
		return "alert_red"
	if(findtext(lower, "to blue"))
		return "alert_blue"
	if(findtext(lower, "lowered to green"))
		return "alert_green"
	if(findtext(lower, "delta"))
		return "alert_delta"
	if(findtext(lower, "meteor"))
		return "meteors"
	if(findtext(lower, "radiation"))
		return "rad_storm"
	if(findtext(lower, "ion storm") || findtext(lower, "ionospheric"))
		return "ion"
	if(findtext(lower, "powernet") || findtext(lower, "power failure") || findtext(lower, "overload"))
		return "power"
	if(findtext(lower, "anomal"))
		return "anomaly"
	return null

// ---------------------------------------------------------------------------------------------
// Insults and arguments
// ---------------------------------------------------------------------------------------------

GLOBAL_LIST_INIT(bot_insult_words, list("idiot", "stupid", "moron", "fuck you", "shut up", "asshole", "dumbass", "loser", "noob", "useless", "you suck",
	"piece of shit", "prick", "bitch", "screw you", "get lost", "go away", "shithead", "dipshit", "jackass", "clueless", "incompetent"))

/// Said to it: an answer by how far it's been pushed, or a shove once a short-tempered one has had enough.
/datum/bot_brain/proc/insulted_by(mob/living/who)
	var/grudge = add_grudge(who, BOT_INSULT_POINTS) //bot_reflexes.dm
	bot_tally("insulted")
	if(grudge >= shove_limit() && temper >= 0.55 && shove_back(who))
		bot_tally("shoved over words")
		return pick("That's it.", "Say that again.", "Keep it up.")
	if(grudge >= BOT_INSULT_POINTS * 1.5)
		if(temper >= 0.5)
			return pick("Say that again. I dare you.", "Keep talking.", "You want to go?", "Watch your mouth.", "Careful.")
		return pick("Whatever.", "I'm not doing this.", "Leave me alone.", "Okay, I'm done talking to you.")
	return mood_pick(list("Wow, okay.", "That's not very nice.", "Rude!", "Somebody's grumpy."), list("Rude.", "What's your problem?", "Yeah, okay.", "Charming."), list("Same to you.", "Get bent.", "Talk to me like that again.", "Who asked you?"))

/// Picks at somebody next to it. They answer by their own temper, and two short tempers can end in a shove.
/datum/bot_brain/proc/start_argument(mob/living/carbon/human/other)
	var/datum/bot_brain/them = other.bot_brain
	if(!them || world.time < next_argument_time || them.state == BOT_STATE_COMBAT || them.state == BOT_STATE_ARREST || them.gone_loud())
		return FALSE
	next_argument_time = world.time + BOT_ARGUMENT_GAP
	if(!pursuing_kind)
		owner.face_atom(other)
	bot_say(owner, pick(GLOB.bot_jab_lines))
	bot_tally("arguments started")
	them.add_grudge(owner, BOT_INSULT_POINTS)
	addtimer(CALLBACK(them, PROC_REF(argue_back), WEAKREF(owner), 1), rand(2 SECONDS, 4 SECONDS))
	return TRUE

/// One turn of an argument. `round` 1 is the answer to the first jab.
/datum/bot_brain/proc/argue_back(datum/weakref/ref, round)
	var/mob/living/carbon/human/other = ref?.resolve()
	if(!other || QDELETED(owner) || owner.stat != CONSCIOUS || other.stat != CONSCIOUS || get_dist(owner, other) > 3 || state == BOT_STATE_COMBAT)
		return
	if(!pursuing_kind)
		owner.face_atom(other)
	var/datum/bot_brain/them = other.bot_brain
	if(round >= 3)
		if(temper >= 0.6 && shove_back(other))
			bot_tally("arguments ended in a shove")
			return
		bot_say(owner, pick("Whatever.", "Not worth it.", "Get out of my face."))
		return
	if(temper < 0.5)
		bot_say(owner, mood_pick(list("Okay...", "Wow, rude.", "Somebody woke up on the wrong side of the bed."), list("Excuse me?", "What's that supposed to mean?", "Okay then."), list("Excuse me?")))
		return //it lets it go
	bot_say(owner, pick(round == 1 ? GLOB.bot_argue_back_lines : GLOB.bot_argue_harder_lines))
	if(them)
		them.add_grudge(owner, BOT_INSULT_POINTS)
		addtimer(CALLBACK(them, PROC_REF(argue_back), WEAKREF(owner), round + 1), rand(2 SECONDS, 4 SECONDS))

GLOBAL_LIST_INIT(bot_jab_lines, list(
	"Do you ever actually work?",
	"Nice outfit. Lose a bet?",
	"You're in my way.",
	"Who let you in here?",
	"You again.",
	"Can you not stand right there?",
	"Were you raised in a barn?",
	"Do you even know what you're doing?",
	"Great, it's you.",
))

GLOBAL_LIST_INIT(bot_argue_back_lines, list(
	"Excuse me?",
	"Mind your own business.",
	"Like you're any better.",
	"What's your problem?",
	"Says you.",
	"Wow. Okay. And you are?",
))

GLOBAL_LIST_INIT(bot_argue_harder_lines, list(
	"You heard me.",
	"Don't start with me.",
	"Say that again.",
	"Back off.",
	"You want to take this outside?",
	"Keep talking and see what happens.",
))

// ---------------------------------------------------------------------------------------------
// People questions
// ---------------------------------------------------------------------------------------------

/// What people call a job when they ask after it -> list(the job, where that job is).
GLOBAL_LIST_INIT(bot_job_words, list(
	"captain" = list("Captain", "on the Bridge"), "cap" = list("Captain", "on the Bridge"),
	"hop" = list("Head of Personnel", "in their office off the Bridge"), "head of personnel" = list("Head of Personnel", "in their office off the Bridge"),
	"hos" = list("Head of Security", "in Security"), "head of security" = list("Head of Security", "in Security"),
	"warden" = list("Warden", "in the Brig"),
	"cmo" = list("Chief Medical Officer", "in Medbay"), "chief medical officer" = list("Chief Medical Officer", "in Medbay"),
	"ce" = list("Chief Engineer", "in Engineering"), "chief engineer" = list("Chief Engineer", "in Engineering"),
	"rd" = list("Research Director", "in Science"), "research director" = list("Research Director", "in Science"),
	"qm" = list("Quartermaster", "in Cargo"), "quartermaster" = list("Quartermaster", "in Cargo"),
	"doctor" = list("Medical Doctor", "in Medbay"), "doc" = list("Medical Doctor", "in Medbay"), "medic" = list("Medical Doctor", "in Medbay"),
	"chemist" = list("Chemist", "in Chemistry"),
	"engineer" = list("Station Engineer", "in Engineering"),
	"atmos" = list("Atmospheric Technician", "in Atmospherics"),
	"janitor" = list("Janitor", "wherever the wet floor signs are"), "jani" = list("Janitor", "wherever the wet floor signs are"),
	"clown" = list("Clown", "wherever the honking is"),
	"bartender" = list("Bartender", "in the Bar"),
	"chef" = list("Cook", "in the Kitchen"), "cook" = list("Cook", "in the Kitchen"),
	"botanist" = list("Botanist", "in Hydroponics"),
	"scientist" = list("Scientist", "in Science"),
	"roboticist" = list("Roboticist", "in Robotics"),
	"detective" = list("Detective", "in their office"),
	"lawyer" = list("Lawyer", "near the Brig"),
	"chaplain" = list("Chaplain", "in the Chapel"),
	"curator" = list("Curator", "in the Library"),
	"security" = list("Security Officer", "in Security"), "sec" = list("Security Officer", "in Security"), "officer" = list("Security Officer", "in Security"),
))

/// The job asked about, as list(job, where), or null.
/proc/bot_job_asked_about(lower_msg)
	var/best
	for(var/word in GLOB.bot_job_words)
		if((!best || length(word) > length(best)) && bot_text_has_any(lower_msg, list(word)))
			best = word
	return best ? GLOB.bot_job_words[best] : null

/// "Where's the Captain?", "have you seen Morgan?", "who's the HoS?", "what time is it?" - or null if it's none of those.
/datum/bot_brain/proc/people_answer(lower_msg)
	if(bot_text_has_any(lower_msg, list("what time", "the time", "how long have we")))
		return pick("It's [station_time_timestamp("hh:mm")].", "[station_time_timestamp("hh:mm")], station time.", "We're about [round((world.time - SSticker.round_start_time) / (1 MINUTES))] minutes in.")
	var/list/job = bot_job_asked_about(lower_msg)
	if(bot_text_has_any(lower_msg, list("who's the", "whos the", "who is the", "who's our", "whos our", "who is our")) && job)
		var/mob/living/carbon/human/H = bot_alive_in_job(job[1])
		return H ? pick("[H.real_name].", "That's [H.real_name].", "[H.first_name()], I think.") : pick("Don't think we have one.", "Nobody, as far as I know.")
	if(!bot_text_has_any(lower_msg, list("where is", "where's", "wheres", "where are", "seen", "find")))
		return null
	var/mob/living/carbon/human/asked
	if(job)
		asked = bot_alive_in_job(job[1])
		if(!asked)
			return pick("Don't think we have one.", "Haven't seen one all shift.")
	else
		for(var/mob/living/carbon/human/H in GLOB.carbon_list)
			var/first = H.first_name()
			if(H != owner && H.mind?.assigned_role && first && length(first) >= 3 && bot_text_has_any(lower_msg, list(lowertext(first))))
				asked = H
				break
		if(!asked)
			return null
	if(asked in view(7, owner))
		return pick("Right there.", "They're just over there.", "[asked.first_name()]? Right behind you.")
	var/list/their_job = job
	if(!their_job)
		for(var/word in GLOB.bot_job_words)
			var/list/candidate = GLOB.bot_job_words[word]
			if(candidate[1] == asked.mind?.assigned_role)
				their_job = candidate
				break
	if(their_job)
		return pick("Should be [their_job[2]].", "Probably [their_job[2]].", "Haven't seen them. Maybe [their_job[2]]?")
	return pick("Haven't seen them.", "No idea, sorry.", "Not since this morning.")

/// Somebody alive with that job, the way the manifest would tell anyone.
/proc/bot_alive_in_job(job)
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat != DEAD && H.mind?.assigned_role == job)
			return H
	return null

#undef BOT_MOOD_CHEERY
#undef BOT_MOOD_PLAIN
#undef BOT_MOOD_GRUMPY
#undef BOT_INSULT_POINTS
#undef BOT_ANNOUNCE_REACTORS
#undef BOT_ARGUMENT_GAP
