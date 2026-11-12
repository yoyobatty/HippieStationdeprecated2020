// Comings and goings. The user's rulings (2026-11-12): dead bots ghost and talk in deadchat (how they died, banter with other ghosts,
// orbiting the action), and some bots log off mid-shift and new ones join during the round. Not picked: the dead coming back as new
// characters.
//
// Ghosts. A bot that dies takes a few seconds, the way a player reads "you have died", then a ghost of it floats up beside the body.
// It's an observer like a player's (only ghosts and admins see it), named for the dead, holding no link to the mind: cloning and the
// rest go on with the body exactly as before. It says how it died in deadchat, now and then says something about the round, answers
// players' ghosts who talk to it or ask what happened, says "rip" when somebody else dies, and orbits whatever's going on (a fight, the
// killer, a friend still alive). Brought back to life, it says so and the ghost is gone.
//
// Log-offs. One bot in five or so has a shift that ends early: some time after the first quarter of an hour, when it's free, it says
// "gtg" (or nothing), finds a bed in the dorms if there's one near and lies down, and its player is gone, the way a Bot Shift's crew
// logs off (gym/bot_shift_population.dm). The brain comes off the body, so the body is what a real player's is when they disconnect:
// "a blank, absent-minded stare" (human/examine.dm), no answers, no reactions. A few come back a few minutes later ("back"), and most
// of the rest are replaced by somebody new off the arrivals shuttle (bot_population.dm's latecomers).

/// Out of a hundred, bots whose shift ends early
#define BOT_LOGOFF_CHANCE 20
/// Out of a hundred, of those, the ones who come back
#define BOT_RECONNECT_CHANCE 25
/// Out of a hundred, the ones who don't who are replaced by a latecomer
#define BOT_REPLACED_CHANCE 60
/// Deadchat from any one bot ghost, at most this often on its own account
#define BOT_GHOST_CHATTER_GAP (3 MINUTES)
/// Deadchat from bot ghosts altogether, at most this often unless spoken to
#define BOT_GHOSTS_CHATTER_GAP (40 SECONDS)

/// Bot brains whose players have logged off, by the body (weakref -> brain), for coming back
GLOBAL_LIST_EMPTY(bot_brains_away)
/// Bot ghosts about
GLOBAL_LIST_EMPTY(bot_ghosts)
GLOBAL_VAR_INIT(bot_ghosts_last_said, 0)

/datum/bot_brain
	/// When its player leaves, if they will: 0 if not
	var/leave_at = 0
	/// Its player will be back in a few minutes
	var/coming_back = FALSE
	/// Off the body for now, coming back (away_for_a_bit())
	var/logged_off = FALSE
	/// Its ghost, while it's dead
	var/mob/dead/observer/bot_ghost/ghost
	/// When it'll ghost, once it's dead
	var/ghost_at = 0

/// Log-offs happen in live rounds, and in a Bot Shift run with bot-logoffs=1.
/proc/bot_logoffs_on()
	if(BOT_GYM_PARAMETER in world.params)
		return FALSE
	if(BOT_SHIFT_PARAMETER in world.params)
		return text2num(world.params["bot-logoffs"]) > 0
	return TRUE

/datum/bot_brain/New(mob/living/carbon/human/new_owner)
	. = ..()
	if(bot_logoffs_on() && prob(BOT_LOGOFF_CHANCE * ((new_owner?.mind?.assigned_role in GLOB.command_positions) ? 0.5 : 1)))
		leave_at = world.time + rand(15 MINUTES, 70 MINUTES)

// ---------------------------------------------------------------------------------------------
// Logging off
// ---------------------------------------------------------------------------------------------

/// Once a wander: its time to go, if it's free to. It goes the way a Bot Shift's crew does (gym/bot_shift_population.dm): a bed in
/// the dorms if there's one near, lie down, and gone.
/datum/bot_brain/proc/mind_leaving()
	if(!leave_at || world.time < leave_at || log_off_pending || state != BOT_STATE_WANDER || current_goal || owner.stat != CONSCIOUS)
		return FALSE
	// Nobody walks out in the middle of being a traitor, or of a fight, or while the shuttle's coming
	if(bot_traitor || is_changeling || op_team || bot_wizard || gone_loud() || attacker || owner.handcuffed || owner.mind?.special_role || !EMERGENCY_IDLE_OR_RECALLED)
		leave_at = world.time + 10 MINUTES
		return FALSE
	leave_at = 0
	coming_back = prob(BOT_RECONNECT_CHANCE)
	if(prob(45 + 40 * sociability))
		bot_say(owner, (prob(35) ? ";" : "") + pick("gtg", "gotta go, cya", "brb", "afk for a bit", "have to go, sorry", "night all", "real life calls, bye"))
	bot_tally("left the shift")
	log_game("BOT CREW: [owner.real_name] ([owner.mind?.assigned_role]) is logging off[coming_back ? ", back soon" : ""]")
	if(!coming_back && GLOB.bot_population.running && prob(BOT_REPLACED_CHANCE))
		GLOB.bot_population.latecomers++ //somebody new joins later
	if(!assign_goal(new /datum/bot_goal/log_off))
		go_now()
	return TRUE

/// Logged off, but back in a few minutes (log_off(), gym/bot_shift_population.dm, hands over here instead of deleting it): the brain
/// waits off the body, and what it had taken on is let go of for somebody else.
/datum/bot_brain/proc/away_for_a_bit()
	logged_off = TRUE
	thread = null
	for(var/key in GLOB.bot_work_claims.Copy())
		if(GLOB.bot_work_claims[key] == src)
			GLOB.bot_work_claims -= key
	for(var/datum/bot_request/R as anything in GLOB.bot_requests)
		if(R.taken_by == src)
			R.taken_by = null
	GLOB.bot_brains -= src
	GLOB.bot_security_brains -= src
	GLOB.bot_brains_away[WEAKREF(owner)] = src
	addtimer(CALLBACK(src, PROC_REF(log_back_on)), rand(2 MINUTES, 10 MINUTES))

/// Back from wherever it went, if its body's still there and nobody else has it.
/datum/bot_brain/proc/log_back_on()
	var/datum/weakref/ref = WEAKREF(owner)
	if(!logged_off || QDELETED(owner) || owner.bot_brain || GLOB.bot_brains_away[ref] != src)
		return
	GLOB.bot_brains_away -= ref
	logged_off = FALSE
	log_off_pending = FALSE
	coming_back = FALSE
	owner.bot_logged_off = FALSE
	owner.bot_brain = src
	GLOB.bot_brains |= src
	if(is_security_job())
		GLOB.bot_security_brains |= src
	START_PROCESSING(SSprocessing, src)
	if(owner.buckled)
		owner.buckled.unbuckle_mob(owner, force = TRUE)
	bot_tally("logged back on")
	log_game("BOT CREW: [owner.real_name] logged back on")
	if(owner.stat == CONSCIOUS && prob(50))
		say_after_typing((prob(40) ? ";" : "") + pick("back", "back, what'd I miss?", "sorry, had to go afk", "im back"))

// ---------------------------------------------------------------------------------------------
// Ghosts
// ---------------------------------------------------------------------------------------------

/// A dead bot's ghost: an observer with nobody at the keys. It holds no mind, so nothing that looks for a player's ghost finds it.
/mob/dead/observer/bot_ghost
	var/datum/weakref/body
	var/datum/bot_brain/brain
	var/next_chatter = 0
	var/next_orbit = 0
	/// The handle its player goes by (mind.bot_handle), for nothing but the look of it
	var/how_died

/mob/dead/observer/bot_ghost/Destroy()
	STOP_PROCESSING(SSobj, src)
	GLOB.bot_ghosts -= src
	if(brain?.ghost == src)
		brain.ghost = null
	brain = null
	return ..()

/// Dead: ghost in a few seconds, as a player does.
/datum/bot_brain/proc/mind_ghosting()
	if(owner.stat != DEAD)
		if(ghost)
			ghost.back_to_life()
		ghost_at = 0
		return
	if(ghost || gym_run || logged_off || log_off_pending)
		return
	if(!ghost_at)
		ghost_at = world.time + rand(4 SECONDS, 20 SECONDS)
		return
	if(world.time >= ghost_at)
		make_ghost()

/datum/bot_brain/proc/make_ghost()
	var/turf/T = get_turf(owner)
	if(!T)
		return
	var/mob/dead/observer/bot_ghost/G = new(T) //beside the body, not from it: no mind to hold
	G.name = owner.real_name
	G.real_name = owner.real_name
	G.gender = owner.gender
	G.body = WEAKREF(owner)
	G.brain = src
	G.can_reenter_corpse = FALSE
	G.how_died = how_i_died()
	ghost = G
	GLOB.bot_ghosts += G
	G.next_chatter = world.time + rand(5 SECONDS, 15 SECONDS)
	G.next_orbit = world.time + rand(20 SECONDS, 60 SECONDS)
	bot_tally("ghosted")
	if(prob(60 + 30 * sociability))
		addtimer(CALLBACK(G, TYPE_PROC_REF(/mob/dead/observer/bot_ghost, deadchat), G.death_line()), rand(3 SECONDS, 12 SECONDS))

/// How it died, as it'd put it: list(what, who)
/datum/bot_brain/proc/how_i_died()
	var/killer = (owner.last_assailant && world.time - owner.last_assailant_at < 3 MINUTES && owner.last_assailant != owner.real_name) ? owner.last_assailant : null
	var/what
	if(isspaceturf(get_turf(owner)) || owner.getOxyLoss() > 100)
		what = "air"
	else if(owner.getFireLoss() > owner.getBruteLoss() && owner.getFireLoss() > 50)
		what = "fire"
	else if(owner.getToxLoss() > 60)
		what = "toxin"
	else if(owner.radiation > 1500)
		what = "radiation"
	else
		what = "brute"
	return list(what, killer)

/mob/dead/observer/bot_ghost/proc/death_line()
	var/killer = LAZYACCESS(how_died, 2)
	if(killer)
		var/list/parts = splittext(killer, " ")
		var/first = parts[1]
		return pick("rip me. [first] got me", "killed by [killer] lol", "[first] is the traitor btw, got me in [get_area_name(src, TRUE)]", "well [first] killed me", "f. [first] did it", "[first] murdered me for no reason")
	switch(LAZYACCESS(how_died, 1))
		if("air")
			return pick("suffocated lmao", "air ran out. great", "rip, no air", "should have worn internals")
		if("fire")
			return pick("burned to death. cool", "fire. classic", "rip, cooked")
		if("toxin")
			return pick("poisoned??", "what even killed me", "toxins. nice")
		if("radiation")
			return pick("rads got me", "radiation, wonderful")
	return pick("rip", "well that sucked", "dead lol", "f", "ow", "that was quick")

/// A line in deadchat, the way a player's ghost says it (say_dead(), mob/say.dm). Nobody in deadchat, nothing said.
/mob/dead/observer/bot_ghost/proc/deadchat(line)
	if(QDELETED(src) || !line)
		return
	if(brain)
		line = brain.in_own_words(line)
	GLOB.bot_ghosts_last_said = world.time
	next_chatter = world.time + BOT_GHOST_CHATTER_GAP
	var/source = "<span class='game'><span class='prefix'>DEAD:</span> <span class='name'>[name]</span>"
	var/rendered = " <span class='message'>[say_quote(line)]</span></span>"
	log_talk(line, LOG_SAY, tag = "DEAD (bot)")
	deadchat_broadcast(rendered, source, follow_target = src)

/// Back from the dead: a word in deadchat on the way, and the ghost's gone.
/mob/dead/observer/bot_ghost/proc/back_to_life()
	if(prob(50))
		deadchat(pick("im getting cloned, bye", "back to the land of the living", "revived lol", "brb, alive again"))
	qdel(src)

/// Now and then: who to watch, and something about the round.
/mob/dead/observer/bot_ghost/proc/haunt()
	var/mob/living/carbon/human/H = body?.resolve()
	if(!H || QDELETED(H) || H.stat != DEAD)
		if(H?.stat != DEAD && brain)
			back_to_life()
		else if(!H)
			qdel(src)
		return
	if(world.time >= next_orbit)
		next_orbit = world.time + rand(1 MINUTES, 3 MINUTES)
		var/atom/movable/watch = something_to_watch()
		if(watch && watch != orbiting?.parent)
			ManualFollow(watch)
	if(world.time >= next_chatter && world.time >= GLOB.bot_ghosts_last_said + BOT_GHOSTS_CHATTER_GAP && prob(25))
		deadchat(round_comment())

/// The most interesting thing going on: a fight, the killer, a friend still alive, or the body.
/mob/dead/observer/bot_ghost/proc/something_to_watch()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.state == BOT_STATE_COMBAT && B.attacker && !QDELETED(B.owner))
			return B.owner
	var/killer = LAZYACCESS(how_died, 2)
	if(killer)
		var/mob/living/K = bot_mob_named(killer)
		if(K && K.stat != DEAD)
			return K
	if(brain)
		for(var/name in brain.regard)
			if(brain.regard[name] >= 4)
				var/mob/living/F = bot_mob_named(name)
				if(F && F.stat != DEAD)
					return F
	return body?.resolve()

/// What a ghost says about the round it's watching
/mob/dead/observer/bot_ghost/proc/round_comment()
	var/list/options = list("this round is chaos", "anyone else just watching sec", "cloning when", "ghost life", "how long till shuttle", "boring", "who's still alive")
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(E && E.mode == SHUTTLE_CALL)
		options += list("shuttle's coming at least", "finally the shuttle")
	if(seclevel2num(get_security_level()) >= SEC_LEVEL_RED)
		options += list("red alert lol", "this is going great")
	var/dead = 0
	for(var/mob/dead/observer/bot_ghost/G in GLOB.bot_ghosts)
		dead++
	if(dead >= 4)
		options += list("[dead] of us dead already", "body count's climbing", "deadchat getting crowded")
	return pick(options)

/// Somebody died: a ghost or two notice.
/proc/bot_ghosts_saw_death(mob/living/carbon/human/H)
	if(!length(GLOB.bot_ghosts) || QDELETED(H) || H.stat != DEAD || prob(50))
		return
	var/mob/dead/observer/bot_ghost/G = pick(GLOB.bot_ghosts)
	if(G.real_name == H.real_name)
		return
	var/list/parts = splittext(H.real_name, " ")
	addtimer(CALLBACK(G, TYPE_PROC_REF(/mob/dead/observer/bot_ghost, deadchat), pick("rip [parts[1]]", "f", "welcome to the club", "another one", "o7 [parts[1]]")), rand(5 SECONDS, 20 SECONDS))

/// A player's ghost said something in deadchat: one bot ghost may answer, if it's to them or about dying.
/proc/bot_ghosts_heard(mob/speaker, message)
	if(!length(GLOB.bot_ghosts) || !message || istype(speaker, /mob/dead/observer/bot_ghost))
		return
	var/lower = lowertext(message)
	var/mob/dead/observer/bot_ghost/to_whom
	for(var/mob/dead/observer/bot_ghost/G as anything in GLOB.bot_ghosts)
		var/list/parts = splittext(lowertext(G.real_name), " ")
		if(length(parts[1]) >= 3 && bot_text_has_any(lower, list(parts[1])))
			to_whom = G
			break
	var/answer
	var/mob/dead/observer/bot_ghost/G = to_whom || pick(GLOB.bot_ghosts)
	if(bot_text_has_any(lower, list("who killed you", "how did you die", "how'd you die", "what happened to you", "what killed you")))
		answer = G.death_line()
	else if(bot_text_has_any(lower, list("who's the traitor", "whos the traitor", "who is the traitor", "who's the antag", "whos the antag", "antags?")))
		var/killer = LAZYACCESS(G.how_died, 2)
		answer = killer ? "[killer] killed me, so them probably" : pick("no idea", "haven't seen", "check the orbit menu")
	else if(bot_text_has_any(lower, list("rip", "f", "o7")) && length(lower) <= 10)
		answer = to_whom ? pick("thanks", "it is what it is", "rip me indeed") : (prob(40) ? pick("rip", "f") : null)
	else if(bot_text_has_any(lower, list("lol", "lmao", "haha")) && length(lower) <= 12)
		answer = prob(30) ? pick("lol", "lmao") : null
	else if(bot_text_has_any(lower, list("hi", "hello", "hey", "sup", "yo")))
		answer = to_whom || prob(40) ? pick("hey", "hi", "sup", "o/") : null
	else if(to_whom)
		answer = findtext(lower, "?") ? pick("dunno", "no idea", "maybe?", "beats me") : pick("yeah", "true", "lol", "mhm")
	if(answer)
		addtimer(CALLBACK(G, TYPE_PROC_REF(/mob/dead/observer/bot_ghost, deadchat), answer), rand(2 SECONDS, 6 SECONDS))

/mob/dead/observer/bot_ghost/Initialize()
	. = ..()
	START_PROCESSING(SSobj, src)

/mob/dead/observer/bot_ghost/process()
	haunt()

/// A player's ghost talking in deadchat: the bot ghosts hear it.
/mob/say_dead(message)
	. = ..()
	bot_ghosts_heard(src, message)

/// The round's over: the report's up.
/datum/controller/subsystem/ticker/display_report(popcount)
	..()
	bot_ghosts_round_end()

/// What a ghost says at the end of a round.
/proc/bot_ghosts_round_end()
	for(var/mob/dead/observer/bot_ghost/G as anything in GLOB.bot_ghosts)
		if(prob(40))
			addtimer(CALLBACK(G, TYPE_PROC_REF(/mob/dead/observer/bot_ghost, deadchat), pick("gg", "gg all", "ggs", "gg wp")), rand(1 SECONDS, 15 SECONDS))

#undef BOT_LOGOFF_CHANCE
#undef BOT_RECONNECT_CHANCE
#undef BOT_REPLACED_CHANCE
#undef BOT_GHOST_CHATTER_GAP
#undef BOT_GHOSTS_CHATTER_GAP
