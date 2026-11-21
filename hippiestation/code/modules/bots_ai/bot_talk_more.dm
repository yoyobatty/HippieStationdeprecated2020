// Things said to a bot's face that got nothing back, or a shrug: the user's own lines from three played rounds, said to a bot one at a
// time (a local probe, 2026-11-07). "She's dead!", "truce", "don't kill me" and "you need healing" got nothing; "give me back my pda"
// got "Mm.". Each now has an answer, from what the bot can actually see and has on it (answer_for(), bot_chatter.dm).

GLOBAL_VAR_INIT(bot_death_news_taken, -100)

/// "She's dead!", "there's a body"
/proc/bot_is_death_news(lower_msg)
	return bot_text_has_any(lower_msg, list("dead", "died", "corpse", "body", "killed")) && !bot_text_has_any(lower_msg, list("are you dead", "you dead", "nobody", "anybody", "dead end", "deadline"))

/// Somebody dead, or so they say: a body it can see is called in to Medical, otherwise where?
/datum/bot_brain/proc/death_news(mob/living/talker, over_radio)
	for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, owner))
		if(H.stat != DEAD || H == owner || LAZYACCESS(bodies_reported, WEAKREF(H)))
			continue
		LAZYSET(bodies_reported, WEAKREF(H), TRUE)
		var/where = get_area_name(H, TRUE)
		if(!over_radio)
			call_for(/datum/bot_request_kind/medical, pick("Medical, there's a body in [where]. [H.name].", "Body in [where], Medical. Looks like [H.name]."))
		return pick("Oh no. That's [H.name]... I'll get Medical.", "Oh god. Calling Medical.", "Is that [H.name]? I'll call it in.")
	return mood_pick(list("What?! Where?", "Oh no, who? Where?"), list("What? Where?", "Who's dead?", "Where?"), list("Who now?", "Where?", "Again?"))

/datum/bot_brain
	/// Bodies it's already told Medical about (weakrefs): once each.
	var/list/bodies_reported

/// "Truce", "don't kill me": nothing to it when it isn't fighting them; when it is, it's up to who it is.
/datum/bot_brain/proc/peace_offered(mob/living/talker)
	if(attacker == talker && state == BOT_STATE_COMBAT)
		if(gone_loud() || bot_traitor)
			return pick("Too late for that.", "No chance.", "Should've thought of that.")
		if(temper >= 0.7)
			return pick("You started it!", "Then stop swinging!", "Back off, then!")
		return pick("Then back off!", "Fine, just stop!", "Okay, okay, just stop!")
	return pick("Why would I?", "I'm not going to hurt you.", "Relax, I'm not fighting anybody.", "Whoa, I'm not after you.")

/// "You need healing": hurt, it holds still for them; not, it says so.
/datum/bot_brain/proc/healing_offered(mob/living/talker)
	if(owner.health < owner.maxHealth * 0.9 || bot_bleed_rate(owner) > 0)
		wait_for(talker) //bot_asks.dm: stood still while they get on with it
		return pick("Please. Thanks.", "Yeah, I'm not great. Thanks.", "Thanks, go ahead.")
	return pick("I'm fine, thanks.", "I'm alright, but thanks.", "Nah, I'm good.")

/// "Give me back my PDA": theirs, by the name on it, if it's got it; otherwise it hasn't.
/datum/bot_brain/proc/give_back_theirs(mob/living/talker, lower_msg)
	for(var/obj/item/I in owner.GetAllContents())
		var/obj/item/card/id/card = I
		var/obj/item/pda/pda = I
		var/owner_name = istype(card) ? card.registered_name : (istype(pda) ? pda.owner : null)
		if(!owner_name || owner_name != talker.real_name)
			continue
		if(gone_loud())
			return pick("Come and take it.", "No.")
		if(I.loc != owner) //in its bag: out first
			owner.put_in_hands(I)
		if(bot_is_carried(owner, I))
			set_down(I) //bot_items.dm: at its feet, for them to pick up
		bot_log(src, "gave [talker] back [I]")
		return pick("Oh! Sorry, here.", "Didn't realise that was yours. Here.", "Here you go.")
	var/what = "that"
	for(var/word in list("pda", "id", "card", "bag", "headset", "wallet"))
		if(bot_text_has_any(lower_msg, list(word)))
			what = "your [word == "pda" ? "PDA" : (word == "id" ? "ID" : word)]"
			break
	return pick("I haven't got [what].", "Not me, I haven't got [what].", "I don't have [what], sorry.")

/proc/bot_is_carried(mob/living/carbon/human/H, obj/item/I)
	return I && (I.loc == H || I.loc?.loc == H)

// ---------------------------------------------------------------------------------------------
// Explosions heard
// ---------------------------------------------------------------------------------------------
// A bomb goes off, and nobody says a word: bots had nothing to say to an explosion at all. Whoever's nearest says what anybody would ("WHAT WAS THAT?!"),
// and now and then somebody else does. Not to a bomb in the test range, which is what that's for.

/// How far, in tiles, an explosion's heard: this much, and more for a big one (a station-wide thud is for the radio and the news, not a line).
#define BOT_BOOM_HEARD 30
/// How near one has to be for it to be "that was close"
#define BOT_BOOM_CLOSE 12

GLOBAL_DATUM(bot_boom_listener, /datum/bot_boom_listener)
/// When somebody last said something about one, so a string of them isn't a string of lines
GLOBAL_VAR_INIT(bot_boom_said_at, -1000)

GLOBAL_LIST_INIT(bot_boom_close_lines, list("WHAT WAS THAT?!", "Whoa! That was close!", "What the hell was that?!", "Everyone okay?!", "Okay, that was too close."))
GLOBAL_LIST_INIT(bot_boom_far_lines, list("What was that?", "Anyone else feel that?", "Was that an explosion?", "That sounded big.", "Somebody blew something up again."))

/datum/bot_brain
	/// A gym scenario that tests explosions heard sets this: a gym bot is otherwise scripted and has nothing to say to one (bot_boom_listener).
	var/boom_talk_in_gym = FALSE

/// Hears explosions, from the first bot on (SSdcs isn't up when globals are made)
/proc/bot_listen_for_booms()
	if(GLOB.bot_boom_listener)
		return
	GLOB.bot_boom_listener = new
	GLOB.bot_boom_listener.RegisterSignal(SSdcs, COMSIG_GLOB_EXPLOSION, TYPE_PROC_REF(/datum/bot_boom_listener, on_explosion))

/datum/bot_boom_listener/proc/on_explosion(datum/source, turf/epicenter, devastation_range, heavy_impact_range, light_impact_range)
	SIGNAL_HANDLER
	if(!epicenter || (devastation_range + heavy_impact_range + light_impact_range) < 1)
		return
	// A moment, for it to have gone off and for whoever heard it to take it in
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_crew_heard_explosion), epicenter, devastation_range + heavy_impact_range + light_impact_range), rand(8, 25))

/// Whoever's nearest says what it was, if it can hear it; a second, now and then, from further off.
/proc/bot_crew_heard_explosion(turf/epicenter, size)
	if(QDELETED(epicenter) || world.time < GLOB.bot_boom_said_at + 15 SECONDS)
		return
	var/area/where = get_area(epicenter)
	if(istype(where, /area/science/test_area) || istype(where, /area/science/mixing)) //the test range: that's what it's for
		return
	var/list/heard = list()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(QDELETED(B) || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.logged_off || (B.gym_scripted && !B.boom_talk_in_gym) || B.gone_loud() || B.state == BOT_STATE_ARREST)
			continue
		var/turf/T = get_turf(B.owner)
		if(!T || T.z != epicenter.z || isspaceturf(T) || !B.owner.can_hear())
			continue
		var/dist = get_dist(T, epicenter)
		if(dist > BOT_BOOM_HEARD + size * 3)
			continue
		heard[B] = dist
	if(!length(heard))
		return
	var/datum/bot_brain/first
	for(var/datum/bot_brain/B as anything in heard)
		if(!first || heard[B] < heard[first])
			first = B
	GLOB.bot_boom_said_at = world.time
	first.say_about_boom(heard[first])
	if(length(heard) > 1 && prob(30))
		var/datum/bot_brain/second
		for(var/datum/bot_brain/B as anything in heard)
			if(B != first && (!second || heard[B] < heard[second]))
				second = B
		if(second)
			addtimer(CALLBACK(second, TYPE_PROC_REF(/datum/bot_brain, say_about_boom), heard[second]), rand(15, 40))

/datum/bot_brain/proc/say_about_boom(dist)
	if(QDELETED(owner) || owner.stat != CONSCIOUS || logged_off)
		return
	say_after_typing(pick(dist <= BOT_BOOM_CLOSE ? GLOB.bot_boom_close_lines : GLOB.bot_boom_far_lines))

/// "Good morning" and its like, answered in kind: "Afternoon." came back for "good morning" and for "sup" alike.
/datum/bot_brain/proc/time_greeting(lower_msg)
	if(length(splittext(lower_msg, " ")) > 3)
		return null //"hey, what happened this morning?" isn't one
	if(bot_text_has_any(lower_msg, list("good morning", "morning")))
		return pick("Morning.", "Morning!", "Good morning.")
	if(bot_text_has_any(lower_msg, list("good afternoon", "afternoon")))
		return pick("Afternoon.", "Afternoon!", "Good afternoon.")
	if(bot_text_has_any(lower_msg, list("good evening", "evening")))
		return pick("Evening.", "Evening!", "Good evening.")
	return null

/// bot.fresh_pick() (bot_chatter.dm) where there is one: one of these that it hasn't picked lately. A call site outside bot_chatter.dm goes
/// through this, so a build without it (a gym A/B's "before") still compiles.
/proc/bot_fresh_pick(B, list/options)
	// The proc's name in a variable, and the brain untyped: dm.exe checks a constant name against a typed object, and in a build without
	// fresh_pick() that was two errors.
	var/proc_name = "fresh_pick"
	if(hascall(B, proc_name))
		return call(B, proc_name)(options)
	return pick(options)

// ---------------------------------------------------------------------------------------------
// A hole in the hull
// ---------------------------------------------------------------------------------------------
// Nobody said a word about one: the engineers' own rounds saw to it (goals/repair_hull.dm) and the rest of the crew carried on. Whoever's nearest, and can
// see it, says where, once for the area. Not in the words that call the engineers ("hull breach", "breach in": bot_requests.dm), which would have them
// answer a call they have the hole for already.

/// Area -> until when somebody's said there's a hole in it
GLOBAL_LIST_EMPTY(bot_breach_called)

/proc/bot_crew_noticed_breach(turf/T)
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_say_about_breach), T), rand(20, 50))

/proc/bot_say_about_breach(turf/T)
	if(QDELETED(T) || !istype(T, /turf/open/space))
		return //patched since
	var/area/A = get_area(T)
	if(!A || world.time < GLOB.bot_breach_called[A])
		return
	var/datum/bot_brain/nearest
	var/nearest_dist = 11
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(QDELETED(B) || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.logged_off || (B.gym_scripted && !B.boom_talk_in_gym) || B.gone_loud() || B.owner.z != T.z)
			continue
		var/dist = get_dist(B.owner, T)
		if(dist < nearest_dist && (T in view(10, B.owner)))
			nearest = B
			nearest_dist = dist
	if(!nearest || !prob(75))
		return
	GLOB.bot_breach_called[A] = world.time + 90 SECONDS
	nearest.say_after_typing(";" + bot_fresh_pick(nearest, list("There's a hole in the hull at [A.name]!", "[A.name]'s open to space!", "Hull's been breached at [A.name], Engineering!", "Something's blown a hole in [A.name]!")))
