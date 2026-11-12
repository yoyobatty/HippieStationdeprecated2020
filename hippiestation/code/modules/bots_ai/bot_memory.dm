// What a bot knows about the round, and how it knows it. Until now there was one list of news for the whole crew (bot_news(),
// bot_chatter.dm): a killing in a locked room was round the station the moment it happened, and nobody could say who did it or
// how they knew. Now each bot keeps its own facts:
//
//  - what it saw: a fight, a killing, a body, somebody cuffed, somebody walking about with Syndicate kit
//  - what it was told: by whoever saw it, or by somebody who heard it from somebody (hops), or by a player saying so
//  - what Security's records say, for Security
//
// It answers from them ("who killed Sam?" "Morgan. I saw it, in the Bar." / "Jamie says it was Morgan." / "No idea, didn't see it."),
// and passes them on in small talk to whoever hasn't heard (gossip, make_small_talk()), so word goes round at the speed people talk.
// Whether it tells is up to who it is (the user's ruling of 2026-11-10 for traitor kit: some tell people, some keep quiet), and a
// greytider asked by Security saw nothing.

// The kinds of fact. Left defined for the files after this one that feed facts in (bot_witness.dm, bot_playstyles.dm, bot_social.dm).
#define BOT_FACT_ATTACKED "attacked"
#define BOT_FACT_KILLED "killed"
#define BOT_FACT_DIED "died"
#define BOT_FACT_ARRESTED "arrested"
#define BOT_FACT_WANTED "wanted"
#define BOT_FACT_CONTRABAND "contraband"
/// Somebody said so: "Morgan's a traitor". A claim, not a thing seen.
#define BOT_FACT_CLAIM "claim"

/// How many facts a bot keeps: the oldest go first.
#define BOT_FACTS_KEPT 40
/// After this a fact is old news: still answered when asked, no longer brought up.
#define BOT_FACT_FRESH (20 MINUTES)
/// How long after the last blow somebody's death is put down to whoever struck it, for somebody watching.
#define BOT_FACT_KILL_WINDOW (15 SECONDS)

/datum/bot_fact
	var/kind
	/// Who did it, and the name they went by to whoever saw. A masked killer is "somebody in a mask", with no ref.
	var/datum/weakref/actor
	var/actor_name
	var/datum/weakref/victim
	var/victim_name
	/// The area's name, as the station's signs have it.
	var/place
	/// A crime, or the thing they were seen with.
	var/detail
	/// When it happened, or when it was found.
	var/when
	/// 0 saw it; 1 told by somebody who did; 2 and up, word going round.
	var/hops = 0
	/// Who told it, by name; "the radio"; or null if it saw for itself.
	var/source
	/// Whoever it's told about this already (bot brains and players, weakrefs).
	var/list/told

/datum/bot_fact/proc/fact_key()
	return "[kind]|[actor_name]|[victim_name]|[detail]"

/datum/bot_fact/proc/copy_for(datum/bot_brain/teller)
	var/datum/bot_fact/F = new
	F.kind = kind
	F.actor = actor
	F.actor_name = actor_name
	F.victim = victim
	F.victim_name = victim_name
	F.place = place
	F.detail = detail
	F.when = when
	F.hops = hops + 1
	F.source = teller?.owner?.real_name
	return F

/datum/bot_brain
	/// What it knows (BOT_FACT_*), by key(): the newest last.
	var/list/facts

/// The name somebody goes by to whoever's looking at them.
/proc/bot_seen_name(mob/living/M)
	if(!M)
		return null
	return M.name == "Unknown" ? "somebody in a mask" : M.name

/// Learns a fact. A first-hand one replaces a rumour of the same thing; a rumour of something it saw changes nothing.
/datum/bot_brain/proc/learn_fact(kind, mob/living/actor, mob/living/victim, place, detail, hops = 0, source)
	var/datum/bot_fact/F = new
	F.kind = kind
	F.actor_name = bot_seen_name(actor)
	if(actor && actor.name != "Unknown")
		F.actor = WEAKREF(actor)
	F.victim_name = victim ? (victim.stat == DEAD ? victim.real_name : bot_seen_name(victim)) : null
	if(victim)
		F.victim = WEAKREF(victim)
	F.place = place
	F.detail = detail
	F.when = world.time
	F.hops = hops
	F.source = source
	return take_fact(F)

/// Keeps a fact (new or passed on); returns it, or null if it knew it as well or better already.
/datum/bot_brain/proc/take_fact(datum/bot_fact/F)
	LAZYINITLIST(facts)
	var/key = F.fact_key()
	var/datum/bot_fact/had = facts[key]
	if(had && had.hops <= F.hops)
		return null
	if(had)
		facts -= key
	facts[key] = F
	if(length(facts) > BOT_FACTS_KEPT)
		facts.Cut(1, 2)
	fact_learned(F) //bot_social.dm: how it feels about the people in it
	return F

/// Its facts of a kind (or any kind), about somebody by name as the doer or the done-to, newest first.
/datum/bot_brain/proc/facts_about(name, list/kinds, as_actor = TRUE, as_victim = TRUE)
	. = list()
	if(!length(facts))
		return
	for(var/i in length(facts) to 1 step -1)
		var/datum/bot_fact/F = facts[facts[i]]
		if(kinds && !(F.kind in kinds))
			continue
		if(name && !((as_actor && F.actor_name == name) || (as_victim && F.victim_name == name)))
			continue
		. += F

// ---------------------------------------------------------------------------------------------
// Seeing things
// ---------------------------------------------------------------------------------------------

/// Every bot that can see `where` learns it first-hand.
/proc/bot_crew_saw(kind, mob/living/actor, mob/living/victim, atom/where, detail)
	if(!length(GLOB.bot_brains) || !where)
		return
	var/place = get_area_name(where, TRUE)
	for(var/datum/bot_brain/B as anything in bot_witnesses_of(where, list(actor, victim)))
		B.learn_fact(kind, actor, victim, place, detail)

/// Somebody's died. Whoever can see the body saw it; whoever can also see the last person to hurt them in the last few seconds saw
/// a killing. From the death listener (goals/security_patrol.dm), a tick after.
/proc/bot_crew_saw_death(mob/living/carbon/human/victim)
	if(QDELETED(victim) || victim.stat != DEAD || !length(GLOB.bot_brains))
		return
	var/mob/living/carbon/human/killer
	if(victim.last_assailant && victim.last_assailant != victim.real_name && world.time - victim.last_assailant_at <= BOT_FACT_KILL_WINDOW)
		for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, victim))
			if(H.real_name == victim.last_assailant)
				killer = H
				break
	var/place = get_area_name(victim, TRUE)
	for(var/datum/bot_brain/B as anything in bot_witnesses_of(victim, list(victim, killer)))
		if(killer && (killer in view(BOT_SIGHT_RANGE, B.owner)))
			B.learn_fact(BOT_FACT_KILLED, killer, victim, place)
		else
			B.learn_fact(BOT_FACT_DIED, null, victim, place)

/// Somebody cuffed in front of people: an arrest if it's Security doing it, otherwise just what it looks like.
/proc/bot_crew_saw_cuffing(mob/living/carbon/human/cuffer, mob/living/carbon/human/cuffed)
	if(!length(GLOB.bot_brains) || QDELETED(cuffed))
		return
	var/datum/bot_wanted/W = bot_is_wanted(cuffed) ? GLOB.bot_security_wanted[WEAKREF(cuffed)] : null
	bot_crew_saw(BOT_FACT_ARRESTED, cuffer, cuffed, cuffed, W?.crime)

// ---------------------------------------------------------------------------------------------
// Being told
// ---------------------------------------------------------------------------------------------

/// What the fact sounds like in the middle of a sentence ("Morgan killed Sam in the Bar").
/datum/bot_fact/proc/as_said()
	var/where = place ? " in [place]" : ""
	switch(kind)
		if(BOT_FACT_KILLED)
			return "[actor_name] killed [victim_name][where]"
		if(BOT_FACT_DIED)
			return "[victim_name]'s dead, found[where]"
		if(BOT_FACT_ATTACKED)
			return "[actor_name] went for [victim_name][where]"
		if(BOT_FACT_ARRESTED)
			return "Security cuffed [victim_name][where][detail ? ", for [lowertext(detail)]" : ""]"
		if(BOT_FACT_WANTED)
			return "Security's after [actor_name][detail ? " for [lowertext(detail)]" : ""]"
		if(BOT_FACT_CONTRABAND)
			return "[actor_name]'s walking about with \a [detail][where]"
		if(BOT_FACT_CLAIM)
			return "[source || "somebody"] reckons [actor_name] [detail]"
	return null

/// "I saw it" / "Jamie told me" / "word is": how it says where it got this from.
/datum/bot_fact/proc/how_known()
	if(!hops)
		return pick("I saw it.", "Saw it myself.", "I was right there.")
	if(source == "the records")
		return pick("It's on the records.", "Records say so.")
	if(hops == 1 && source)
		return pick("[source] saw it.", "[source] told me, they were there.", "That's from [source].")
	return pick("That's what I heard, anyway.", "Word is, anyway.", "Don't quote me.")

/// A line of gossip: the fact, put the way it was come by.
/datum/bot_brain/proc/gossip_line(datum/bot_fact/F)
	var/said = F.as_said()
	if(!said)
		return null
	if(!F.hops)
		return pick("I just saw [said].", "Did you hear? [capitalize(said)]. I saw it.", "You won't believe it. [capitalize(said)]. Saw it with my own eyes.")
	if(F.hops == 1 && F.source)
		return pick("[F.source] says [said].", "Did you hear? [capitalize(said)]. [F.source] saw it.", "Apparently [said]. [F.source] told me.")
	return pick("Word is [said].", "Heard [said].", "Did you hear? Apparently [said].", "Somebody said [said].")

/// Whether it tells people what it knows. The quiet keep it to themselves, mostly; the chatty, the paranoid and the hunters don't.
/datum/bot_brain/proc/tells_things()
	if(playstyle == BOT_STYLE_HUNTER || is_paranoid())
		return TRUE
	return sociability >= 0.35

/// The freshest thing it knows and hasn't told `company`, worth telling them. Null if nothing.
/datum/bot_brain/proc/gossip_for(mob/living/carbon/human/company)
	if(!length(facts) || !tells_things())
		return null
	var/static/list/worth = list(BOT_FACT_KILLED = 6, BOT_FACT_DIED = 5, BOT_FACT_CONTRABAND = 4, BOT_FACT_ARRESTED = 3, BOT_FACT_WANTED = 3, BOT_FACT_CLAIM = 2, BOT_FACT_ATTACKED = 2)
	var/datum/bot_fact/best
	var/best_score = 0
	var/datum/weakref/them = WEAKREF(company)
	for(var/key in facts)
		var/datum/bot_fact/F = facts[key]
		if(world.time > F.when + BOT_FACT_FRESH || (them in F.told))
			continue
		if(F.actor?.resolve() == company || F.victim?.resolve() == company)
			continue //nobody tells you what you did, or what was done to you
		if(company.bot_brain)
			var/datum/bot_fact/theirs = LAZYACCESS(company.bot_brain.facts, key)
			if(theirs && theirs.hops <= F.hops + 1)
				continue //they know
		var/score = worth[F.kind] * 10 - F.hops * 4 - (world.time - F.when) / (1 MINUTES)
		if(score > best_score)
			best = F
			best_score = score
	return best

/// Told `company` the fact: they've heard it now, and a bot keeps it, one hop further on.
/datum/bot_brain/proc/told_fact(datum/bot_fact/F, mob/living/carbon/human/company)
	LAZYOR(F.told, WEAKREF(company))
	bot_tally("gossip passed on")
	if(company.bot_brain)
		var/datum/bot_fact/theirs = company.bot_brain.take_fact(F.copy_for(src))
		if(theirs)
			LAZYOR(theirs.told, WEAKREF(owner)) //and they won't tell it back
			bot_log(company.bot_brain, "heard from [owner] that [F.as_said()]")

/// What it says back to gossip it's just been told.
/datum/bot_brain/proc/gossip_reply(datum/bot_fact/F)
	var/mob/living/actor = F.actor?.resolve()
	if(actor && actor == owner)
		return pick("That's not what happened.", "Who told you that?", "Lies.")
	switch(F.kind)
		if(BOT_FACT_KILLED)
			return mood_pick(list("No way. Poor [F.victim_name].", "That's awful.", "Oh no."), list("Seriously? [F.actor_name]?", "Figures.", "Where's Security?", "Keep away from [F.actor_name] then."), list("Somebody should do something about [F.actor_name].", "Great.", "Not surprised."))
		if(BOT_FACT_DIED)
			return mood_pick(list("Oh no, [F.victim_name]...", "That's horrible.", "Poor [F.victim_name]."), list("Who did it?", "Seriously?", "Rest in peace."), list("Who's next?", "This shift.", "Figures."))
		if(BOT_FACT_CONTRABAND)
			return mood_pick(list("Yikes. Steering clear.", "That's not good."), list("Has anyone told Security?", "Huh. Thanks for the heads up.", "Shifty."), list("Knew it.", "Somebody should search them.", "Great."))
		if(BOT_FACT_ARRESTED, BOT_FACT_WANTED)
			return mood_pick(list("Huh, what did they do?", "Oh dear."), list("What for?", "Huh.", "Good."), list("About time.", "Lock them up.", "Not surprised."))
	return pick(GLOB.bot_news_replies)

// ---------------------------------------------------------------------------------------------
// Asked about it
// ---------------------------------------------------------------------------------------------

/// "Who killed Sam?", "what happened to him?", "why's Morgan in the brig?", "is Morgan a traitor?", "who's wanted?": answered from what
/// it knows, and how. Null if it's none of those.
/datum/bot_brain/proc/memory_answer(mob/living/talker, lower_msg)
	var/asks_killer = bot_text_has_any(lower_msg, list("who killed", "who did it", "who did this", "who did that", "who's the killer", "whos the killer", "who murdered", "who shot", "who stabbed", "know who killed"))
	var/asks_fate = bot_text_has_any(lower_msg, list("what happened to", "how did", "is he dead", "is she dead", "are they dead", "what killed"))
	var/asks_attack = bot_text_has_any(lower_msg, list("who attacked", "who hit", "who beat up", "who went for", "who hurt"))
	var/asks_why = bot_text_has_any(lower_msg, list("why is", "why's", "whys", "what did", "what's he wanted", "whats he wanted", "wanted for", "arrested for", "in for"))
	var/asks_trust = bot_text_has_any(lower_msg, list("a traitor", "an antag", "valid", "syndie", "trust", "dangerous", "safe to", "shifty", "suspicious"))
	var/asks_wanted = bot_text_has_any(lower_msg, list("who's wanted", "whos wanted", "anyone wanted", "who is wanted", "who's sec after", "whos sec after", "who's security after", "who is security after"))
	if(!asks_killer && !asks_fate && !asks_attack && !asks_why && !asks_trust && !asks_wanted)
		return null
	if(asks_wanted)
		var/list/wanted = facts_about(null, list(BOT_FACT_WANTED))
		if(!length(wanted))
			return pick("Nobody I know of.", "Not that I've heard.")
		var/list/names = list()
		for(var/datum/bot_fact/F as anything in wanted)
			names |= F.actor_name
		return "[english_list(names)], last I heard."
	lower_msg = without_my_name(lower_msg)
	var/mob/living/carbon/human/about = bot_person_named(lower_msg, talker, list(owner))
	if(!about)
		about = bot_named_body(lower_msg) //the dead aren't in bot_person_named()'s list
	if(!about && bot_text_has_any(lower_msg, list("me", "i")) && (asks_attack || asks_killer))
		about = talker //"who attacked me?"
	var/about_name = about?.real_name
	if(about && bot_text_has_any(lower_msg, list("dead", "died")))
		asks_fate = TRUE
	// "Who did it?", "what happened to him?": the latest death it knows of
	if(!about_name && (asks_killer || (asks_fate && bot_text_has_any(lower_msg, list("him", "her", "them")))))
		var/list/latest = facts_about(null, list(BOT_FACT_KILLED, BOT_FACT_DIED))
		if(length(latest))
			var/datum/bot_fact/F = latest[1]
			about_name = F.victim_name
	if(!about_name)
		return asks_killer ? pick("Who killed who?", "No idea, didn't see anything.", "Wait, somebody's dead?") : null
	if(snitch_shy(talker))
		return pick("Didn't see nothing.", "Dunno. Wasn't there.", "Wasn't looking.")
	if(asks_killer || asks_fate)
		var/list/known = facts_about(about_name, list(BOT_FACT_KILLED, BOT_FACT_DIED), FALSE, TRUE)
		var/datum/bot_fact/killing
		var/datum/bot_fact/death
		for(var/datum/bot_fact/F as anything in known)
			if(F.kind == BOT_FACT_KILLED && (!killing || F.hops < killing.hops))
				killing = F
			else if(F.kind == BOT_FACT_DIED && !death)
				death = F
		if(killing)
			return said_the_killing(killing, talker)
		if(death)
			return pick("Found dead in [death.place]. No idea who did it.", "Dead, in [death.place]. Didn't see who.", "[death.place], they found them. Nobody knows who yet.") + (death.hops ? "" : " I saw the body.")
		if(about && about.stat != DEAD)
			return (about in view(BOT_SIGHT_RANGE, owner)) ? pick("They're fine? They're right there.", "Nothing, they're right over there.") : pick("Nothing, as far as I know.", "Haven't heard anything.")
		return pick("No idea. Didn't see it.", "Couldn't tell you. I wasn't there.", "Wish I knew.")
	if(asks_attack)
		var/list/known = facts_about(about_name, list(BOT_FACT_ATTACKED, BOT_FACT_KILLED), FALSE, TRUE)
		if(!length(known))
			return pick("Didn't see it.", "No idea, sorry.")
		var/datum/bot_fact/F = known[1]
		return "[F.actor_name]. [F.how_known()]"
	if(!about_name)
		return null
	var/list/theirs = facts_about(about_name, null, TRUE, FALSE)
	if(asks_why)
		for(var/datum/bot_fact/F as anything in facts_about(about_name, list(BOT_FACT_ARRESTED, BOT_FACT_WANTED)))
			if(F.detail)
				return pick("[lowertext(F.detail)], [F.hops ? "apparently" : "by the records"].", "Something about [lowertext(F.detail)].")
		if(length(theirs))
			var/datum/bot_fact/F = theirs[1]
			return "[capitalize(F.as_said())]. [F.how_known()]"
		return pick("No idea what they did.", "Haven't heard.")
	// "is Morgan a traitor?", "can I trust her?"
	if(length(theirs))
		var/datum/bot_fact/F = theirs[1]
		return pick("All I know is [F.as_said()]. [F.how_known()]", "Well, [F.as_said()]. Make of that what you will.", "[capitalize(F.as_said())]. [F.how_known()]")
	return opinion_of_line(about) //bot_social.dm: what it makes of them, from how they've been with it

/// The killing, as it knows it. Its own doing it keeps to itself; the killer asking is told.
/datum/bot_brain/proc/said_the_killing(datum/bot_fact/F, mob/living/talker)
	var/mob/living/actor = F.actor?.resolve()
	if(actor == owner)
		return pick("No idea. Didn't see it.", "Couldn't tell you.", "Wasn't there.")
	if(actor && actor == talker)
		return F.hops ? pick("You did, from what I hear.", "Word is it was you.") : pick("You did! I saw you!", "You did, [talker.first_name()]. I was right there.", "YOU did it. I saw.")
	if(!F.hops)
		return pick("[F.actor_name]. I saw it, in [F.place].", "It was [F.actor_name]. I was right there.", "[F.actor_name] did it. Saw it myself, in [F.place].")
	if(F.source == "the records")
		return pick("Records say [F.actor_name].", "Security has [F.actor_name] down for it.")
	if(F.hops == 1 && F.source)
		return pick("[F.source] says it was [F.actor_name].", "[F.actor_name], according to [F.source]. They saw it.")
	return pick("Word is it was [F.actor_name].", "Heard it was [F.actor_name], but don't quote me.", "People are saying [F.actor_name].")

/// "Who killed X?", "who did this?": the line for it when it knows (saw it, or was told), null when it doesn't. For
/// answer_massacre_question() (goals/massacre.dm), which hears the question whoever it's put to.
/datum/bot_brain/proc/killing_known_line(mob/living/talker, lower_msg)
	if(!length(facts) || snitch_shy(talker))
		return null
	lower_msg = without_my_name(lower_msg)
	var/mob/living/carbon/human/about = bot_named_body(lower_msg) || bot_person_named(lower_msg, talker, list(owner))
	var/datum/bot_fact/best
	for(var/datum/bot_fact/F as anything in facts_about(about?.real_name, list(BOT_FACT_KILLED), FALSE, TRUE))
		if(!best || F.hops < best.hops)
			best = F
	return best ? said_the_killing(best, talker) : null

/// What was said with its own name taken out: "hey Sam, who killed Yuri?" is about Yuri, not anybody else called Sam.
/datum/bot_brain/proc/without_my_name(lower_msg)
	var/first = lowertext(owner.first_name())
	if(!first || length(first) < 3)
		return lower_msg
	return replacetext(replacetext(lower_msg, lowertext(owner.real_name), ""), first, "")

/// A greytider asked by Security, or somebody asked about a friend by somebody it doesn't like, saw nothing.
/datum/bot_brain/proc/snitch_shy(mob/living/talker)
	if(greytider && bot_is_officer(talker))
		return TRUE
	return FALSE

/// A dead body somebody named.
/proc/bot_named_body(lower_msg)
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat != DEAD || !H.mind?.assigned_role)
			continue
		var/first = H.first_name()
		if((H.real_name && bot_text_has_any(lower_msg, list(lowertext(H.real_name)))) || (first && length(first) >= 3 && bot_text_has_any(lower_msg, list(lowertext(first)))))
			return H
	return null

/// A player saying something about somebody ("Morgan's a traitor", "Morgan killed Sam"): taken as a claim, from them, for what it's
/// worth (fact_learned() weighs it by what it thinks of them). Bots' own speech never comes here.
/datum/bot_brain/proc/heard_claim_about(mob/living/talker, lower_msg)
	if(!bot_text_has_any(lower_msg, GLOB.bot_accusation_words))
		return
	var/mob/living/carbon/human/accused = bot_person_named(lower_msg, talker, list(talker, owner))
	if(!accused)
		return
	var/what = "is up to something"
	if(bot_text_has_any(lower_msg, list("killed", "murdered")))
		what = "killed somebody"
	else if(bot_text_has_any(lower_msg, list("attacked me", "attacking me")))
		what = "went for them"
	else if(bot_text_has_any(lower_msg, list("traitor", "syndie", "syndicate", "antag", "valid")))
		what = "is a traitor"
	else if(bot_text_has_any(lower_msg, list("changeling")))
		what = "is a changeling"
	else if(bot_text_has_any(lower_msg, list("cultist")))
		what = "is a cultist"
	learn_fact(BOT_FACT_CLAIM, accused, null, null, what, 1, talker.real_name)

#undef BOT_FACTS_KEPT
#undef BOT_FACT_FRESH
#undef BOT_FACT_KILL_WINDOW
