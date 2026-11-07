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
