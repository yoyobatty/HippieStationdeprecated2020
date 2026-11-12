// Conversations between bots: a few lines back and forth, not one line and an answer. The user's ruling (2026-11-12): bot-to-bot
// chats a player can overhear and join. Two bots with a minute to spare talk about what's happened (bot_memory.dm), somebody they
// like or don't (bot_social.dm), work, the shift, a joke, or going for a drink after; the other asks "who told you?" and gets an
// answer. A player standing there can put in "no way" or "who?" and the one who'd know answers them (thread_reply()).
//
// The whole exchange is worked out when it starts, from who the two are, then said a line at a time at typing speed. It stops if
// either walks off, gets into a fight, or goes down.

/// How close two have to stay to keep talking
#define BOT_THREAD_RANGE 4

/// Jokes people tell on the station: list(setup, punchline).
GLOBAL_LIST_INIT(bot_jokes, list(
	list("Why did the clown get kicked out of Security?", "He kept honking at the suspects."),
	list("How many engineers does it take to fix the engine?", "None. They'll wait for it to delaminate and blame atmos."),
	list("What's the Captain's favourite game?", "Hide and seek. He's been winning on the Bridge all shift."),
	list("What do you call an assistant with insulated gloves?", "A suspect."),
	list("Why did the cook quit?", "Too many people asking where the meat came from."),
	list("What does a cyborg say at a party?", "Beep. That's it. That's the joke."),
	list("Why is the janitor always so calm?", "He's used to everything being a mess."),
	list("What's the difference between the HoP and a vending machine?", "The vending machine actually gives you something."),
	list("Why don't scientists trust atoms?", "They make up everything. Toxins especially."),
	list("How do you know the shuttle's been called?", "Cargo's suddenly very interested in the armory."),
	list("Why did the geneticist cross the road?", "To get to the other monkey."),
	list("What's the chaplain's favourite drink?", "Holy water. Ask the cultists how they feel about it."),
))

/// What crew grumble about
GLOBAL_LIST_INIT(bot_complaints, list(
	list("Whoever designed this station hated us.", list("Tell me about it.", "The vents, though.", "At least we've got windows.")),
	list("My feet are killing me.", list("Same.", "Sit down then.", "Should've stayed in bed.")),
	list("They don't pay us enough for this.", list("They don't pay us at all.", "Truth.", "Tell CentCom.")),
	list("Nobody ever cleans up after themselves round here.", list("Not my job.", "Tell the janitor.", "Yeah, it's grim.")),
	list("I swear the clown's out to get me.", list("He's out to get everyone.", "Lock your locker.", "Ha, you too?")),
	list("This shift's taking forever.", list("Tell me about it.", "It's barely started.", "Not long now, surely.")),
))

GLOBAL_LIST_INIT(bot_thread_closers, list("Anyway.", "Anyway, back to it.", "Right.", "Anyway, I'd better get on.", "Yeah.", "Huh."))

/datum/bot_thread
	var/datum/bot_brain/a
	var/datum/bot_brain/b
	var/topic
	/// list(list(1 or 2, line)): who says what, in order
	var/list/script = list()
	var/beat = 0
	var/datum/bot_fact/fact
	var/started_at

/datum/bot_brain
	/// The conversation it's in, if any
	var/datum/bot_thread/thread
	/// The last joke it told, and to whom, for "lol" (bot_banter.dm)
	var/last_joke_at = 0
	/// A gym scenario that tests conversations sets this: the gym's small talk is otherwise one line and an answer
	var/threads_in_gym = FALSE
	/// A gym scenario's pick of what it talks about
	var/thread_topic_wanted

/datum/bot_thread/Destroy()
	if(a?.thread == src)
		a.thread = null
	if(b?.thread == src)
		b.thread = null
	a = null
	b = null
	fact = null
	return ..()

/datum/bot_thread/proc/add(who, line)
	if(line)
		script += list(list(who, line))

/// Starts a conversation with another bot standing by, if they're both free for it. TRUE if one started.
/datum/bot_brain/proc/start_thread(mob/living/carbon/human/company)
	var/datum/bot_brain/other = company.bot_brain
	if(!other || thread || other.thread || other.state == BOT_STATE_COMBAT || other.state == BOT_STATE_ARREST || other.gone_loud() || !company.can_hear())
		return FALSE
	var/datum/bot_thread/T = new
	T.a = src
	T.b = other
	T.started_at = world.time
	if(!T.write_script())
		qdel(T)
		return FALSE
	thread = T
	other.thread = T
	bot_tally("conversations")
	bot_log(src, "talking with [company] about [T.topic] ([length(T.script)] lines)")
	if(!pursuing_kind)
		owner.face_atom(company)
	if(!other.pursuing_kind)
		company.face_atom(owner)
	other.next_reaction_time = world.time + 30 SECONDS //it's in this, not answering stock replies to it
	T.next_line()
	return TRUE

/// What the two talk about, and how it goes. FALSE if there's nothing to say.
/datum/bot_thread/proc/write_script()
	var/list/topics = list()
	var/datum/bot_fact/F = a.gossip_for(b.owner)
	if(F)
		topics["gossip"] = 6
	topics["joke"] = 1 + round(2 * a.sociability)
	topics["complain"] = a.temper >= 0.5 ? 3 : 1
	topics["about"] = 1
	if(a.department() && a.department() == b.department())
		topics["work"] = 3
	if(a.thread_subject_for(b))
		topics["opinion"] = 2
	if(a.pursuit == BOT_PURSUIT_SOCIAL || a.has_habit(BOT_HABIT_BARFLY) || a.is_friend(b.owner))
		topics["plan"] = 2
	topic = (a.thread_topic_wanted in topics) ? a.thread_topic_wanted : pickweight(topics)
	switch(topic)
		if("gossip")
			return gossip_script(F)
		if("joke")
			var/list/J = pick(GLOB.bot_jokes)
			add(1, pick("Heard a good one. ", "Okay, okay. ", "") + J[1])
			add(2, b.mood_pick(list("Go on.", "What?", "Ha, what?"), list("Go on.", "Dunno, what?", "What?"), list("I'm going to regret asking. What?", "...What.", "Get on with it.")))
			add(1, J[2])
			add(2, b.mood_pick(list("Hahaha.", "Ha! Good one.", "lol"), list("Ha.", "That's terrible.", "lol"), list("...I'm leaving.", "Awful.", "Wow.")))
			a.last_joke_at = world.time
			return TRUE
		if("complain")
			var/list/C = pick(GLOB.bot_complaints)
			add(1, C[1])
			add(2, pick(C[2]))
			if(prob(50))
				add(1, pick("Right?", "Exactly.", "Yeah.", "Anyway."))
			return TRUE
		if("about")
			add(1, pick("How long have you been on the station?", "You new here?", "Where'd you transfer from?"))
			add(2, pick("Couple of years. Feels longer.", "First week, honestly.", "Long enough to know better.", "Came over from a mining outpost.", "Few months. Still getting lost."))
			add(1, pick("Nice.", "Ha. Fair.", "Rather you than me.", "Welcome aboard, then."))
			return TRUE
		if("work")
			var/list/fact_line = a.shop_talk_now()
			if(!fact_line)
				var/list/shop = GLOB.bot_shop_talk[a.department()]
				if(!length(shop))
					return FALSE
				add(1, pick(shop))
				add(2, pick(GLOB.bot_shop_talk_replies))
				return TRUE
			add(1, fact_line[1])
			add(2, pick(fact_line[2] == "good" ? GLOB.bot_shop_talk_good_replies : (fact_line[2] == "bad" ? GLOB.bot_shop_talk_bad_replies : GLOB.bot_shop_talk_plain_replies)))
			if(fact_line[2] == "bad")
				add(1, pick("I'll keep at it.", "Not much I can do about it right now.", "If it gets worse I'm calling it in."))
			return TRUE
		if("opinion")
			var/mob/living/subject = a.thread_subject_for(b)
			var/them = subject.first_name()
			var/mine = a.regard_of(subject)
			var/theirs = b.regard_of(subject)
			var/why = LAZYACCESS(a.regard_why, subject.real_name)
			if(mine > 0)
				add(1, pick("[them]'s alright, you know.", "Have you met [them]? Good sort.") + (why ? " [capitalize(bot_why_line(why))]." : ""))
			else
				add(1, pick("Have you had to deal with [them]?", "[them]'s a nightmare.", "Watch out for [them].") + (why ? " [capitalize(bot_why_line(why))]." : ""))
			if((mine > 0) == (theirs > 0) && abs(theirs) >= 1)
				add(2, mine > 0 ? pick("Yeah, [them]'s alright.", "Agreed.") : pick("Ugh, tell me about it.", "Yeah, [them]'s a pain.", "Don't get me started."))
			else if(abs(theirs) >= 1)
				add(2, theirs > 0 ? pick("Really? [them]'s always been fine with me.", "Huh. Not my experience.") : pick("Really? Can't stand them myself.", "Huh. You can have them."))
				add(1, pick("Each to their own.", "Your call.", "Just saying."))
			else
				add(2, pick("Don't really know them.", "Huh. I'll keep that in mind.", "Noted."))
			b.feel(subject, mine > 0 ? 0.5 : -0.75, "[a.owner.first_name()] says [why ? bot_why_line(why) : "so"]")
			return TRUE
		if("plan")
			add(1, pick("Bar after this?", "Fancy a drink later?", "Want to grab something to eat?", "Break soon? I'm starving."))
			if(b.will_hang_out_with(a.owner))
				add(2, pick("Sure, why not.", "Go on then.", "Yeah, I could do with a break.", "You're buying."))
				add(1, pick("Meet you there.", "Great.", "Nice."))
				addtimer(CALLBACK(a, TYPE_PROC_REF(/datum/bot_brain, plan_a_break), WEAKREF(b.owner)), 12 SECONDS) //bot_hangouts.dm
			else
				add(2, pick("Can't, too much on.", "Maybe later.", "Not today.", "I'm good, thanks."))
				add(1, pick("Fair enough.", "Suit yourself.", "Another time."))
			return TRUE
	return FALSE

/// Gossip, with a question about it and the answer.
/datum/bot_thread/proc/gossip_script(datum/bot_fact/F)
	var/line = a.gossip_line(F)
	if(!line)
		return FALSE
	fact = F
	add(1, line)
	switch(rand(1, 4))
		if(1)
			add(2, pick("Who told you that?", "How do you know?"))
			add(1, F.how_known())
		if(2)
			add(2, pick("Where?", "Where was this?"))
			add(1, F.place ? "[F.place]." : pick("Not sure where.", "Didn't say."))
		if(3)
			add(2, pick("When?", "When was this?"))
			var/minutes = round((world.time - F.when) / (1 MINUTES))
			add(1, minutes >= 1 ? "Like [minutes] minute\s ago." : "Just now.")
		if(4)
			add(2, b.gossip_reply(F))
			add(1, pick("Yeah.", "Keep your eyes open.", "Just thought you should know.", "I know."))
			return TRUE
	add(2, gossip_closer(F))
	return TRUE

/datum/bot_thread/proc/gossip_closer(datum/bot_fact/F)
	switch(F.kind)
		if(BOT_FACT_KILLED)
			return pick("Keeping away from [F.actor_name], then.", "Has anyone told Security?", "Jesus.", "Poor [F.victim_name].")
		if(BOT_FACT_DIED)
			return pick("Poor [F.victim_name].", "Hope someone clones them.", "This shift, honestly.")
		if(BOT_FACT_CONTRABAND)
			return pick("I'll keep an eye out.", "Shifty.", "Someone should search them.")
		if(BOT_FACT_ARRESTED, BOT_FACT_WANTED)
			return pick("Good.", "Huh. Didn't see that coming.", "Figures.")
	return pick(GLOB.bot_thread_closers)

/// Somebody to talk about with this other bot: one it has strong views on, who isn't either of them.
/datum/bot_brain/proc/thread_subject_for(datum/bot_brain/other)
	for(var/name in regard)
		if(name == other.owner.real_name || name == owner.real_name || !LAZYACCESS(regard_why, name))
			continue
		if(abs(regard[name]) >= 3)
			var/mob/living/M = bot_mob_named(name)
			if(M)
				return M
	return null

/// The next line, once whoever's saying it has had time to type it.
/datum/bot_thread/proc/next_line()
	if(QDELETED(src))
		return
	beat++
	if(beat > length(script) || !still_talking())
		qdel(src)
		return
	var/list/L = script[beat]
	var/datum/bot_brain/speaker = L[1] == 1 ? a : b
	var/line = L[2]
	var/wait = bot_typing_time(line) + (beat == 1 ? 0 : rand(5, 15))
	addtimer(CALLBACK(src, PROC_REF(say_line), speaker, line), wait)

/datum/bot_thread/proc/say_line(datum/bot_brain/speaker, line)
	if(QDELETED(src) || !still_talking())
		qdel(src)
		return
	var/datum/bot_brain/listener = speaker == a ? b : a
	if(!speaker.pursuing_kind)
		speaker.owner.face_atom(listener.owner)
	bot_say(speaker.owner, line)
	bot_log(speaker, "said \"[line]\" to [listener.owner]")
	if(beat == 1 && fact)
		a.told_fact(fact, b.owner)
	speaker.chatted_with(listener.owner)
	next_line()

/datum/bot_thread/proc/still_talking()
	for(var/datum/bot_brain/B in list(a, b))
		if(QDELETED(B) || B.logged_off || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.state == BOT_STATE_COMBAT || B.state == BOT_STATE_ARREST || B.gone_loud())
			return FALSE
	return get_dist(a.owner, b.owner) <= BOT_THREAD_RANGE && world.time < started_at + 2 MINUTES

/// Which of the two answers somebody putting a word in: whoever told the news, else whoever's nearer them.
/datum/bot_thread/proc/answerer_for(mob/living/talker)
	if(fact)
		return a
	return get_dist(a.owner, talker) <= get_dist(b.owner, talker) ? a : b

/// A player putting a word in while it's talking with another bot: what it says back, in the conversation's terms. Null to let the
/// ordinary answers have it.
/datum/bot_brain/proc/thread_reply(mob/living/talker, lower_msg)
	var/datum/bot_thread/T = thread
	if(!T || T.answerer_for(talker) != src)
		return null
	var/datum/bot_fact/F = T.fact
	if(F)
		if(bot_text_has_any(lower_msg, list("who told you", "how do you know", "says who", "source")))
			return F.how_known()
		if(bot_text_has_any(lower_msg, list("where", "where was")))
			return F.place ? "[F.place]." : "Didn't say where."
		if(bot_text_has_any(lower_msg, list("when")))
			var/minutes = round((world.time - F.when) / (1 MINUTES))
			return minutes >= 1 ? "About [minutes] minute\s ago." : "Just now."
		if(bot_text_has_any(lower_msg, list("no way", "really", "seriously", "for real", "fr", "you sure", "are you sure")))
			return F.hops ? pick("That's what I heard.", "So they say.") : pick("Saw it myself.", "Swear. I was there.")
		if(bot_text_has_any(lower_msg, list("who", "who did")))
			return F.actor_name ? "[F.actor_name]." : "Nobody knows yet."
	if(T.topic == "joke" && bot_text_has_any(lower_msg, list("lol", "lmao", "haha", "hahaha", "rofl", "lmfao", "kek")))
		return pick("Right?", "I've got loads of them.", "Ha, thanks.")
	if(T.topic == "joke" && bot_text_has_any(lower_msg, list("boo", "terrible", "awful", "bad joke", "not funny", "cringe")))
		return pick("Everyone's a critic.", "Tough crowd.", "You can do better then.")
	if(T.topic == "complain" && bot_text_has_any(lower_msg, list("same", "agreed", "true", "facts", "yeah", "real")))
		return pick("See? It's not just me.", "Right?", "Exactly.")
	if(T.topic == "plan" && bot_text_has_any(lower_msg, list("can i come", "me too", "count me in", "i'll come", "ill come", "mind if i join")))
		return pick("Sure, the more the merrier.", "Course. Bar, in a bit.", "Yeah, come along.")
	return null

#undef BOT_THREAD_RANGE
