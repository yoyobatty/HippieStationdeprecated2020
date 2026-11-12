// Who a bot likes. Grudges (bot_reflexes.dm) are the heat of the moment and fade in minutes; this is what stays for the shift: the
// doctor who patched it up, the friend from Engineering, the clown who punched it, the Captain everybody says shot the Warden. The
// user's rulings (2026-11-12): friends and cliques (stick with friends, back them in fights, avoid people it dislikes), and player
// bonds (remember how the player treated them this shift: help, follow and back them, or avoid and badmouth them).
//
// Kept by name, the way people remember each other: a clone is the same person, and a body with somebody else's ID isn't.
//
//  - regard: -10 to 10. A friend is 4 and up, somebody it dislikes -3 and down.
//  - Some of the crew know each other from shifts before (same department, same habits): the odd friend or old feud to start with.
//  - Talking, help, healing, a hand in a fight raise it. Insults, shoves, punches, and what it sees or hears of them (bot_memory.dm)
//    lower it. It remembers why, and says so when asked.

#define BOT_REGARD_MAX 10
/// Friends from here up.
#define BOT_REGARD_FRIEND 4
/// It dislikes them from here down.
#define BOT_REGARD_DISLIKE -3
/// Regard lost for each grudge point (a shove is 2-3, a punch more): what's left once the anger's gone.
#define BOT_REGARD_PER_GRUDGE 0.6
/// Talk alone makes acquaintances, not friends.
#define BOT_REGARD_TALK_CAP 3
/// Regard a chat is worth, up to the cap.
#define BOT_REGARD_PER_CHAT 0.4

/datum/bot_goal/tag_along
	/// Going along with a friend for a bit (mind_the_company()), not asked to come: a shorter walk.
	var/short = FALSE

/datum/bot_brain
	/// real_name -> regard, for everybody it's had to do with or has an opinion of
	var/list/regard
	/// real_name -> why it feels that way, the latest reason big enough to remember ("patched me up", "punched me")
	var/list/regard_why
	/// When it last went off with a friend, or moved away from somebody it can't stand
	var/next_company_move = 0

/// What it thinks of them, starting from what they are to it before they've done anything.
/datum/bot_brain/proc/regard_of(mob/living/M)
	if(!M || M == owner)
		return 0
	var/name = M.real_name
	if(!name)
		return 0
	if(isnull(LAZYACCESS(regard, name)))
		LAZYSET(regard, name, first_impression(M))
	return regard[name]

/// Before they've done anything: shifts it's worked with them before, a department in common, the sort of person they are.
/datum/bot_brain/proc/first_impression(mob/living/carbon/human/M)
	. = 0
	if(!istype(M) || gym_run) //the gym's people are strangers, unless a scenario says otherwise
		return
	var/datum/bot_brain/them = M.bot_brain
	var/same_dept = department() && them && them.department() == department()
	if(same_dept)
		. += 1
	if(them)
		for(var/habit in habits)
			if(habit in them.habits)
				. += 0.5
		if(is_security_job() && them.greytider)
			. -= 1
		if(greytider && them.is_security_job())
			. -= 1.5
	// Regulars: some of the crew have known each other a while.
	if(prob((same_dept ? 20 : 6) + 15 * sociability))
		. += rand(2, 4)
		LAZYSET(regard_why, M.real_name, "known them for ages")
	else if(prob(4))
		. -= rand(2, 4)
		LAZYSET(regard_why, M.real_name, "never got on with them")

/// Changes what it thinks of them, and remembers why when it's a big enough change.
/datum/bot_brain/proc/feel(mob/living/M, amount, why)
	if(!M || M == owner || !M.real_name || !amount)
		return
	var/now = clamp(regard_of(M) + amount, -BOT_REGARD_MAX, BOT_REGARD_MAX)
	regard[M.real_name] = now
	if(why && abs(amount) >= 1)
		LAZYSET(regard_why, M.real_name, why)

/datum/bot_brain/proc/is_friend(mob/living/M)
	return M && regard_of(M) >= BOT_REGARD_FRIEND

/datum/bot_brain/proc/dislikes(mob/living/M)
	return M && regard_of(M) <= BOT_REGARD_DISLIKE

// ---------------------------------------------------------------------------------------------
// What changes it
// ---------------------------------------------------------------------------------------------

/// A fact it's just learnt (bot_memory.dm): what it says about the people in it.
/datum/bot_brain/proc/fact_learned(datum/bot_fact/F)
	var/mob/living/actor = F.actor?.resolve()
	var/mob/living/victim = F.victim?.resolve()
	if(!actor || actor == owner)
		return
	// Told, not seen: it counts for as much as it trusts who said it. Somebody it can't stand isn't believed at all.
	var/weight = F.hops ? 0.5 : 1
	if(F.source && F.hops)
		var/mob/living/teller = bot_mob_named(F.source)
		if(teller && dislikes(teller))
			return
		if(teller && is_friend(teller))
			weight = 0.8
	var/for_a_friend = victim && victim != owner && is_friend(victim)
	switch(F.kind)
		if(BOT_FACT_KILLED)
			if(victim && (bot_is_fair_game(victim) || dislikes(victim)))
				return //nobody misses them
			feel(actor, -6 * weight - (for_a_friend ? 3 : 0), "killed [F.victim_name]")
		if(BOT_FACT_ATTACKED)
			if(victim && (bot_is_fair_game(victim) || dislikes(victim)))
				return
			feel(actor, -1.5 * weight - (for_a_friend ? 2 : 0), "went for [F.victim_name]")
		if(BOT_FACT_CONTRABAND)
			feel(actor, -1 * weight, "was walking about with \a [F.detail]")
		if(BOT_FACT_WANTED)
			feel(actor, -1 * weight, "Security's after them")
		if(BOT_FACT_CLAIM)
			feel(actor, -0.5 * weight, "[F.source] reckons they [F.detail]")

/// Somebody did something kind to it: patched it up, brought it round, took its side.
/datum/bot_brain/proc/helped_by(mob/living/M, amount, why)
	if(!M || M == owner || QDELETED(owner))
		return
	feel(M, amount, why)
	bot_tally("helped by somebody")
	var/mob/living/carbon/human/H = M
	if(owner.stat == CONSCIOUS && !(istype(H) && H.bot_brain) && world.time >= next_reaction_time && prob(60))
		next_reaction_time = world.time + 50
		say_after_typing(pick("Thanks, [M.first_name()].", "Cheers.", "Thanks, I owe you one.", "Appreciate it."))

/// From log_combat() (goals/security_patrol.dm) for what isn't a blow: healing is a kindness.
/proc/bot_note_kindness(mob/living/user, mob/living/carbon/human/target, what_done)
	if(!target.bot_brain || user == target)
		return
	if(findtext(what_done, "healed"))
		target.bot_brain.helped_by(user, 1.5, "patched me up")
	else if(findtext(what_done, "CPRed"))
		target.bot_brain.helped_by(user, 2, "gave me CPR")

/// A blow landed on somebody a bot is fighting: whoever threw it took its side.
/proc/bot_note_backup(mob/living/user, mob/living/target)
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.attacker == target && B.owner != user && B.state == BOT_STATE_COMBAT && !QDELETED(B.owner) && get_dist(B.owner, target) <= 7)
			B.feel(user, 1, "had my back in a fight")

// ---------------------------------------------------------------------------------------------
// What it changes
// ---------------------------------------------------------------------------------------------

/// "What do you think of Morgan?", "is Morgan alright?": what it makes of them, and why, when it hasn't seen or heard anything.
/datum/bot_brain/proc/opinion_of_line(mob/living/M)
	if(!M)
		return pick("Who?", "Don't know them.")
	var/them = M.first_name() || M.real_name
	var/r = regard_of(M)
	var/why = LAZYACCESS(regard_why, M.real_name)
	if(r >= BOT_REGARD_FRIEND)
		return pick("[them]? Good sort.", "[them]'s alright. Friend of mine.", "I'd trust [them].") + (why ? " [capitalize(bot_why_line(why))]." : "")
	if(r <= BOT_REGARD_DISLIKE)
		return pick("[them]? Can't stand them.", "Wouldn't trust [them] as far as I could throw them.", "Keep away from [them].") + (why ? " [capitalize(bot_why_line(why))]." : "")
	if(r >= 1.5)
		return pick("[them] seems alright.", "Seems decent enough.", "No complaints.")
	if(r <= -1)
		return pick("Not a fan, honestly.", "[them]'s a bit off.", "Hm. Not sure about [them].")
	return pick("Don't really know [them].", "Never really talked to them.", "Seems normal enough?")

/// The reason, the way it'd say it: "patched me up" -> "they patched me up earlier".
/proc/bot_why_line(why)
	if(findtext(why, "known them") || findtext(why, "never got on") || findtext(why, "reckons") || findtext(why, "Security's after"))
		return why
	return "they [why] earlier"

/// Somebody alive by name, nearest to nobody in particular.
/proc/bot_mob_named(name)
	if(!name)
		return null
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.real_name == name)
			return H
	return null

/// The person it'd most like to talk to here: a friend first, never somebody it can't stand.
/datum/bot_brain/proc/best_company(list/candidates)
	var/mob/living/best
	var/best_score
	for(var/mob/living/carbon/human/H as anything in candidates)
		var/r = regard_of(H)
		if(r <= BOT_REGARD_DISLIKE)
			continue
		var/score = r * 2 - get_dist(owner, H)
		if(!best || score > best_score)
			best = H
			best_score = score
	return best

/// What a person it has strong views on is like, told to somebody else: "stay away from Morgan, he punched me". Null if nothing to say.
/datum/bot_brain/proc/opinion_gossip_for(mob/living/carbon/human/company)
	if(!length(regard) || !tells_things())
		return null
	var/best_name
	var/best_strength = 0
	for(var/name in regard)
		if(name == company.real_name || !LAZYACCESS(regard_why, name))
			continue
		var/r = regard[name]
		var/strength = abs(r)
		if((r >= BOT_REGARD_FRIEND + 1 || r <= BOT_REGARD_DISLIKE - 1) && strength > best_strength)
			best_name = name
			best_strength = strength
	if(!best_name || !prob(40))
		return null
	var/list/parts = splittext(best_name, " ")
	var/first = parts[1]
	var/why = bot_why_line(regard_why[best_name])
	var/line
	if(regard[best_name] > 0)
		line = pick("[first]'s good people, by the way. [capitalize(why)].", "If you need anything, [first]'s alright. [capitalize(why)].")
	else
		line = pick("Watch out for [first]. [capitalize(why)].", "Stay away from [first], seriously. [capitalize(why)].", "[first]'s a piece of work. [capitalize(why)].")
	// A bot listening takes it on, as far as it trusts whoever's saying it.
	var/datum/bot_brain/listener = company.bot_brain
	var/mob/living/subject = bot_mob_named(best_name)
	if(listener && subject && subject != company && !listener.dislikes(owner))
		listener.feel(subject, regard[best_name] > 0 ? 0.5 : -0.75, "[owner.first_name()] says [why]")
	return line

/// Friends and the people it can't stand, now and then while it's got nothing to do: off with a friend going somewhere, or away from
/// somebody it doesn't want to be near.
/datum/bot_brain/proc/mind_the_company()
	if(world.time < next_company_move || state != BOT_STATE_WANDER || current_goal || gone_loud() || gym_scripted || owner.buckled)
		return FALSE
	next_company_move = world.time + rand(40 SECONDS, 90 SECONDS)
	for(var/mob/living/carbon/human/H in view(5, owner))
		if(H == owner || H.stat != CONSCIOUS)
			continue
		var/r = regard_of(H)
		if(r <= BOT_REGARD_DISLIKE - 1 && get_dist(owner, H) <= 2 && !bot_is_officer(H))
			bot_tally("moved away from somebody it can't stand")
			bot_log(src, "moving away from [H], can't stand them ([LAZYACCESS(regard_why, H.real_name) || "no reason"])")
			if(temper >= 0.6 && prob(40))
				bot_say(owner, pick("Ugh. You.", "Oh great, it's you.", "Don't.", "Not you again."))
			begin_wander_pick()
			return TRUE
		if(r >= BOT_REGARD_FRIEND && H.bot_brain && H.bot_brain.state == BOT_STATE_WANDER && H.bot_brain.pursuing_kind == "wander" && prob(35 + 30 * sociability))
			if(assign_goal(new /datum/bot_goal/tag_along(H)))
				bot_tally("went along with a friend")
				bot_log(src, "going along with [H], a friend")
				var/datum/bot_goal/tag_along/G = current_goal
				G.short = TRUE
				if(prob(50 + 40 * sociability))
					bot_say(owner, pick("Where you off to, [H.first_name()]?", "Wait up, [H.first_name()].", "I'll come with.", "Hey, [H.first_name()], wait for me."))
				return TRUE
	return FALSE

/// Grudge points just added (bot_reflexes.dm add_grudge()): the anger fades, a bit of it stays.
/datum/bot_brain/proc/grudge_felt(mob/living/who, points)
	if(points > 0)
		feel(who, -points * BOT_REGARD_PER_GRUDGE, points >= 2 ? "went for me" : "had a go at me")

/// A chat with them (small talk, either way round): acquaintances, up to a point.
/datum/bot_brain/proc/chatted_with(mob/living/M)
	if(regard_of(M) < BOT_REGARD_TALK_CAP)
		feel(M, BOT_REGARD_PER_CHAT)

#undef BOT_REGARD_PER_CHAT
#undef BOT_REGARD_MAX
#undef BOT_REGARD_FRIEND
#undef BOT_REGARD_DISLIKE
#undef BOT_REGARD_PER_GRUDGE
#undef BOT_REGARD_TALK_CAP
