// Favours: what a bot will do when somebody asks. The user's ruling (2026-11-12): requests and orders understood loosely, and done
// or refused by personality. "Take me to Cargo", "bring me a wrench", "wait here", "call Security", "go away", "stop it". Before this
// it could follow, come when called somewhere (the summons, bot_requests.dm), open a door, lend what it had in reach and step aside,
// and the rest got "Yeah, that's me."
//
// Whether it does it (will_do_for()): a friend gets a yes, somebody it can't stand or doesn't trust a no, its boss an order. Everyone
// else: how sociable it is, how much bother it is, and what it's in the middle of. Busy with work, it says "after this" and comes
// when it's done, within a few minutes. The bigger the favour, the more it takes.

/// How much bother a favour is (will_do_for())
#define BOT_FAVOUR_SMALL 1
#define BOT_FAVOUR_WALK 2
#define BOT_FAVOUR_ERRAND 3
/// How long "after this" holds
#define BOT_FAVOUR_LATER (3 MINUTES)
/// How long it waits where it was put
#define BOT_FAVOUR_STAY (2 MINUTES)
/// How far behind somebody being shown the way can fall before it stops for them
#define BOT_GUIDE_SLACK 4

/datum/bot_favour
	var/kind
	var/datum/weakref/asker
	var/asker_name
	var/turf/place
	var/place_name
	var/item_type
	var/item_name
	var/asked_at

/datum/bot_brain
	/// A favour it said it'd do once it's finished what it's doing
	var/datum/bot_favour/favour_later

/// The gym's stand-in for a named place: a scenario points a word at one of its markers.
/datum/bot_scenario/proc/named_spot(lower_msg)
	return null

/// Who's in charge of it: the Captain, and the head of its own department.
/proc/bot_is_boss_of(mob/living/talker, datum/bot_brain/B)
	var/role = talker?.mind?.assigned_role
	if(!role || !B)
		return FALSE
	if(role == "Captain")
		return TRUE
	var/static/list/heads = list("engineering" = "Chief Engineer", "medical" = "Chief Medical Officer", "science" = "Research Director", "security" = "Head of Security", "supply" = "Quartermaster", "service" = "Head of Personnel")
	var/dept = B.department()
	return dept && heads[dept] == role

/// Whether it'll do this for them. `effort` is BOT_FAVOUR_*.
/datum/bot_brain/proc/will_do_for(mob/living/talker, effort)
	if(gone_loud() || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || owner.incapacitated())
		return FALSE
	if(trusts_not(talker))
		return FALSE
	var/r = regard_of(talker)
	if(r >= 4)
		return TRUE //a friend asked
	var/odds = 50 + 40 * sociability + 6 * r - 10 * effort
	if(bot_is_boss_of(talker, src))
		odds += 45
	if(greytider)
		odds -= 15
	if(gym_run) //the gym's runs have to come out the same each time
		return odds >= 50
	return prob(clamp(odds, 5, 95))

/// No, by how it's feeling.
/datum/bot_brain/proc/no_line()
	return mood_pick(list("Sorry, can't right now!", "Ah, sorry, no can do.", "I'd love to, but no."), list("Can't, sorry.", "Not right now.", "Nah, sorry.", "Bit busy."), list("Do it yourself.", "I'm not your servant.", "No.", "Get someone else."))

/// Busy with something that matters: it'll do it after, unless it's for a friend or its boss, who get it now.
/datum/bot_brain/proc/busy_for_favour(mob/living/talker)
	if(state != BOT_STATE_GOAL || !current_goal)
		return FALSE
	if(istype(current_goal, /datum/bot_goal/tag_along) || istype(current_goal, /datum/bot_goal/favour))
		return FALSE //nothing it minds dropping
	if(!current_goal.lawful)
		return TRUE //up to something of its own: it isn't stopping
	return !(is_friend(talker) || bot_is_boss_of(talker, src))

/// Drops whatever it was doing, for a favour it's said yes to.
/datum/bot_brain/proc/drop_for_favour()
	if(state == BOT_STATE_GOAL && current_goal)
		bot_log(src, "dropping [current_goal.type] to do somebody a favour")
		abandon_goals_for_arrest() //goals/security_patrol.dm: stops the walk and clears the goal, whatever it was
	if(owner.buckled)
		owner.buckled.unbuckle_mob(owner, force = TRUE)

/// The place a request names, as somewhere to stand, and its name. list(turf, name) or null.
/datum/bot_brain/proc/favour_place(lower_msg, mob/living/talker)
	if(gym_run)
		var/turf/T = gym_run.named_spot(lower_msg)
		if(T)
			return list(T, "over there")
	var/area/A = bot_area_named(lower_msg, get_turf(talker) || get_turf(owner)) //bot_requests.dm
	if(!A)
		return null
	var/turf/spot = nearest_spot_in(A)
	return spot ? list(spot, get_area_name(A, TRUE)) : null

// ---------------------------------------------------------------------------------------------
// Hearing one
// ---------------------------------------------------------------------------------------------

GLOBAL_LIST_INIT(bot_favour_guide_words, list("take me to", "show me the way to", "show me where", "lead me to", "walk me to", "can you take me", "could you take me", "show me to", "guide me to"))
GLOBAL_LIST_INIT(bot_favour_bring_words, list("bring me", "get me", "fetch me", "grab me", "bring us", "get us", "can you get", "could you get", "can you bring", "could you bring", "bring a", "bring some", "bring the"))
GLOBAL_LIST_INIT(bot_favour_stay_words, list("wait here", "stay here", "stay put", "don't move", "dont move", "stay there", "wait there", "hold on here", "wait for me", "hold position"))
GLOBAL_LIST_INIT(bot_favour_release_words, list("you can go", "you can leave", "ok go", "okay go", "at ease", "dismissed", "carry on", "that's all", "thats all", "you're free", "youre free", "go on then"))
GLOBAL_LIST_INIT(bot_favour_call_words, list("call security", "get security", "call sec", "get sec", "call the cops", "call an engineer", "get an engineer", "call engineering", "get engineering", "call a janitor", "get a janitor", "call the janitor", "get the janitor"))

/// Something asked of it that's a favour: done, or refused, with the line to say. Null if it isn't one of these.
/datum/bot_brain/proc/favour_asked(mob/living/talker, lower_msg, over_radio)
	// Let go from waiting about
	var/datum/bot_goal/favour/stay/staying = current_goal
	if(istype(staying) && staying.asker?.resolve() == talker && bot_text_has_any(lower_msg, GLOB.bot_favour_release_words))
		staying.dismissed = TRUE
		return pick("Alright.", "Okay, see you.", "Cool.")
	if(bot_text_has_any(lower_msg, GLOB.bot_favour_call_words))
		return call_for_them(talker, lower_msg, over_radio)
	if(bot_text_has_any(lower_msg, GLOB.bot_favour_guide_words))
		var/list/where = favour_place(lower_msg, talker)
		if(where && !over_radio)
			return ask_favour(talker, "guide", BOT_FAVOUR_WALK, where)
	if(bot_text_has_any(lower_msg, GLOB.bot_favour_bring_words))
		var/item_type = bot_item_asked_after(lower_msg) //bot_knowledge.dm
		if(item_type)
			if(over_radio)
				return find_carried_tool(item_type) ? pick("Got one. Come grab it, I'm in [get_area_name(owner, TRUE)].", "I've got one on me, [get_area_name(owner, TRUE)].") : pick("Haven't got one, sorry.", "Not on me.")
			return ask_favour(talker, "fetch", find_carried_tool(item_type) ? BOT_FAVOUR_SMALL : BOT_FAVOUR_ERRAND, null, item_type)
	if(!over_radio && bot_text_has_any(lower_msg, GLOB.bot_favour_stay_words))
		return ask_favour(talker, "stay", BOT_FAVOUR_SMALL)
	if(!over_radio && bot_text_has_any(lower_msg, list("go away", "leave me alone", "get lost", "piss off", "buzz off", "shoo", "get out of here")))
		return go_away_from(talker)
	if(!over_radio && bot_text_has_any(lower_msg, list("stop it", "stop that", "quit it", "knock it off", "cut it out", "stop hitting me", "stop attacking me", "leave off")))
		return stop_it(talker)
	return null

/// Asked for a favour: yes now, yes after this, or no.
/datum/bot_brain/proc/ask_favour(mob/living/talker, kind, effort, list/where, item_type)
	if(!will_do_for(talker, effort))
		bot_tally("favour refused")
		bot_log(src, "won't [kind] for [talker] ([regard_of(talker)] regard)")
		return no_line()
	var/datum/bot_favour/F = new
	F.kind = kind
	F.asker = WEAKREF(talker)
	F.asker_name = talker.first_name()
	F.asked_at = world.time
	if(where)
		F.place = where[1]
		F.place_name = where[2]
	F.item_type = item_type
	if(item_type)
		var/obj/item/sample = item_type
		F.item_name = initial(sample.name)
	if(busy_for_favour(talker))
		favour_later = F
		bot_tally("favour put off")
		var/doing = describe_activity()
		return doing ? pick("After this, I'm [doing].", "Give me a minute, I'm [doing].", "Sure, once I'm done [doing].") : pick("In a minute.", "Sure, after this.")
	return start_favour(F, TRUE)

/// Starts on a favour. The line it says, or null if it couldn't.
/datum/bot_brain/proc/start_favour(datum/bot_favour/F, now = FALSE)
	var/mob/living/asker = F.asker?.resolve()
	if(!asker || asker.stat == DEAD)
		return null
	drop_for_favour()
	var/datum/bot_goal/favour/G
	switch(F.kind)
		if("guide")
			G = new /datum/bot_goal/favour/guide(F)
		if("stay")
			G = new /datum/bot_goal/favour/stay(F)
		if("fetch")
			if(find_carried_tool(F.item_type))
				G = new /datum/bot_goal/favour/deliver(F)
			else
				var/datum/bot_goal/acquire_item_type/for_someone/fetch = new
				fetch.item_type = F.item_type
				fetch.lawful = TRUE
				fetch.favour = F
				fetch.doing = "getting [F.asker_name] \a [F.item_name]"
				if(!assign_goal(fetch))
					return now ? pick("Don't know where there's one, sorry.", "No idea where to get one.") : null
				bot_tally("favour done")
				return now ? pick("Sure, I'll get you one.", "On it.", "I'll go find one.") : "Right, getting that [F.item_name] for [F.asker_name]."
	if(!G || !assign_goal(G))
		return now ? pick("Can't, sorry.", "Can't get there, sorry.") : null
	bot_tally("favour done")
	bot_log(src, "doing [F.asker_name] a favour: [F.kind][F.place_name ? " to [F.place_name]" : ""][F.item_name ? ", \a [F.item_name]" : ""]")
	if(!now)
		return pick("Right, [F.asker_name], coming.", "Done. On my way, [F.asker_name].")
	switch(F.kind)
		if("guide")
			return pick("Sure, follow me.", "This way.", "Come on, I'll show you.")
		if("stay")
			return pick("Okay, I'll wait.", "Sure.", "I'll be here.")
		if("fetch")
			return pick("Here, hang on.", "Sure, one sec.", "Yeah, got one.")
	return "Sure."

/// Once a wander: the favour it put off, if it's free now and it's still worth doing.
/datum/bot_brain/proc/do_favour_later()
	if(!favour_later)
		return FALSE
	var/datum/bot_favour/F = favour_later
	if(world.time > F.asked_at + BOT_FAVOUR_LATER)
		favour_later = null
		return FALSE
	if(state != BOT_STATE_WANDER || current_goal)
		return FALSE
	favour_later = null
	var/line = start_favour(F)
	if(line)
		var/mob/living/asker = F.asker?.resolve()
		say_after_typing((asker && get_dist(owner, asker) > 5 ? ";" : "") + line)
		return TRUE
	return FALSE

/// "Call Security": on the radio for them, which Security answers like any call (on_heard_security_call(), goals/security_patrol.dm).
/datum/bot_brain/proc/call_for_them(mob/living/talker, lower_msg, over_radio)
	var/where = get_area_name(talker, TRUE)
	var/who = talker.first_name() || "somebody"
	if(bot_text_has_any(lower_msg, list("security", "sec", "cops")))
		if(gone_loud())
			return pick("Ha. No.", "Not a chance.")
		addtimer(CALLBACK(src, PROC_REF(say_after_typing), pick(";Security to [where], [who] needs you.", ";Security, [where] please. [who]'s asking.", ";Need Security in [where].")), 5)
		bot_tally("called for somebody")
		return pick("Calling them.", "On it.", "Okay, okay.")
	if(bot_text_has_any(lower_msg, list("engineer", "engineering")))
		call_for(/datum/bot_request_kind/engineer, pick("Engineering, [where] please. [who] needs you.", "Need an engineer in [where]."))
		bot_tally("called for somebody")
		return pick("Calling them.", "Sure.")
	if(bot_text_has_any(lower_msg, list("janitor")))
		call_for(/datum/bot_request_kind/janitor, pick("Janitor to [where], please.", "Need a janitor in [where]."))
		bot_tally("called for somebody")
		return pick("Calling them.", "Sure.")
	return null

/// "Go away": it does, some of them with a word about it.
/datum/bot_brain/proc/go_away_from(mob/living/talker)
	feel(talker, -0.5)
	if(state == BOT_STATE_WANDER && !current_goal && !gym_scripted)
		begin_wander_pick()
	return mood_pick(list("Sorry! Going.", "Okay, okay."), list("Fine.", "Alright, alright.", "Jeez, okay."), list("What's your problem?", "Gladly.", "Rude."))

/// "Stop it": a quarrel it's in with them ends, if it's the sort to let it; anything else, it wasn't doing anything.
/datum/bot_brain/proc/stop_it(mob/living/talker)
	if(state == BOT_STATE_COMBAT && attacker == talker)
		if(bot_is_wanted(talker) || bot_traitor || gone_loud() || temper >= 0.75)
			return pick("You started it!", "Then back off!", "Make me.")
		end_combat_with(talker) //bot_witness.dm
		return pick("Fine. Just leave me alone.", "Okay, okay. We're done.", "Fine.")
	var/datum/bot_goal/tag_along/following = current_goal
	if(istype(following) && following.target == talker)
		following.dismissed = TRUE
		return pick("Sorry.", "Okay, okay.")
	return pick("Stop what?", "I'm not doing anything.", "What?")

// ---------------------------------------------------------------------------------------------
// The favours
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/favour
	lawful = TRUE
	var/datum/bot_favour/favour
	var/datum/weakref/asker

/datum/bot_goal/favour/New(datum/bot_favour/F)
	. = ..()
	favour = F
	asker = F?.asker

/datum/bot_goal/favour/resolve_target(datum/bot_brain/bot)
	target = favour?.place || asker?.resolve()

/datum/bot_strategy/favour/is_feasible(datum/bot_brain/bot)
	return TRUE

/// "Take me to Cargo": it walks there with them, stopping when they fall behind.
/datum/bot_goal/favour/guide/New(datum/bot_favour/F)
	. = ..()
	doing = "showing [F.asker_name] the way to [F.place_name]"

/datum/bot_goal/favour/guide/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new
	S.steps = list(new /datum/bot_step/paced/guide())
	return list(S)

/datum/bot_step/paced/guide
	var/waited = 0
	var/next_hurry = 0
	var/arrived = FALSE

/datum/bot_step/paced/guide/start(datum/bot_brain/bot)
	next_hurry = world.time + 6 SECONDS //a moment to get going before it calls them on
	return TRUE

/datum/bot_step/paced/guide/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/favour/G = bot.current_goal
	var/mob/living/asker = G?.asker?.resolve()
	var/turf/dest = G?.favour?.place
	if(!asker || asker.stat == DEAD || !dest)
		return FALSE
	wait_for = 5 //a look back every half second: they walk, it shouldn't leave them behind
	if(get_dist(bot.owner, dest) <= 1)
		arrived = TRUE
		return FALSE
	var/behind = get_dist(bot.owner, asker)
	if(asker.z != bot.owner.z || behind > 20 || waited > 120)
		return FALSE //lost them
	if(behind > BOT_GUIDE_SLACK)
		if(bot.pursuing_kind)
			bot.stop_pursuit()
		bot.owner.face_atom(asker)
		waited++
		if(world.time >= next_hurry)
			next_hurry = world.time + 15 SECONDS
			bot.say_after_typing(pick("This way.", "Come on, keep up.", "Over here!", "You coming?"))
		return TRUE
	waited = 0
	if(bot.pursuing_kind != "follow")
		bot.pursue(dest, "follow", force = TRUE)
	return TRUE

/datum/bot_step/paced/guide/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	var/datum/bot_goal/favour/G = bot.current_goal
	if(arrived)
		bot.say_after_typing(pick("Here we are.", "This is it, [G?.favour?.place_name].", "Here you go."))
	return GOAL_STEP_SUCCESS

/// "Wait here": it stays put a couple of minutes, or until it's told it can go.
/datum/bot_goal/favour/stay
	var/dismissed = FALSE

/datum/bot_goal/favour/stay/New(datum/bot_favour/F)
	. = ..()
	doing = "waiting here for [F.asker_name]"

/datum/bot_goal/favour/stay/resolve_target(datum/bot_brain/bot)
	target = get_turf(bot.owner)

/datum/bot_goal/favour/stay/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new
	S.steps = list(new /datum/bot_step/paced/stay_put())
	return list(S)

/datum/bot_step/paced/stay_put
	var/until = 0

/datum/bot_step/paced/stay_put/start(datum/bot_brain/bot)
	until = world.time + BOT_FAVOUR_STAY
	return TRUE

/datum/bot_step/paced/stay_put/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/favour/stay/G = bot.current_goal
	if(!istype(G) || G.dismissed || world.time >= until)
		return FALSE
	wait_for = 20
	return TRUE

/// "Bring me a wrench": one it has, or one it's gone and got, set down at their feet.
/datum/bot_goal/favour/deliver/New(datum/bot_favour/F)
	. = ..()
	doing = "taking [F.asker_name] \a [F.item_name]"

/datum/bot_goal/favour/deliver/resolve_target(datum/bot_brain/bot)
	target = asker?.resolve()

/datum/bot_goal/favour/deliver/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new
	S.steps = list(new /datum/bot_step/paced/hand_over())
	return list(S)

/datum/bot_step/paced/hand_over
	var/given = FALSE
	var/tries = 0

/datum/bot_step/paced/hand_over/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/favour/deliver/G = bot.current_goal
	var/mob/living/asker = G?.asker?.resolve()
	var/obj/item/I = bot.find_carried_tool(G?.favour?.item_type)
	if(!asker || asker.stat == DEAD || !I || asker.z != bot.owner.z || ++tries > 90)
		return FALSE
	wait_for = 10
	if(!bot.owner.Adjacent(asker))
		if(bot.pursuing_kind != "follow")
			bot.pursue(asker, "follow", force = TRUE)
		return TRUE
	bot.stop_pursuit()
	bot.owner.face_atom(asker)
	if(!bot.ready_in_hand(I))
		return FALSE
	bot.owner.dropItemToGround(I)
	given = TRUE
	return FALSE

/datum/bot_step/paced/hand_over/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	var/datum/bot_goal/favour/deliver/G = bot.current_goal
	if(given)
		bot.say_after_typing(pick("Here you go.", "There, [G?.favour?.item_name].", "All yours."))
		bot_log(bot, "gave [G?.favour?.asker_name] \a [G?.favour?.item_name]")
	return GOAL_STEP_SUCCESS

/// Fetching something for somebody: once it's got it, it takes it to them.
/datum/bot_goal/acquire_item_type/for_someone
	var/datum/bot_favour/favour

/datum/bot_goal/acquire_item_type/for_someone/on_success(datum/bot_brain/bot)
	. = ..()
	var/datum/bot_favour/F = favour
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, deliver_favour), F))

/datum/bot_brain/proc/deliver_favour(datum/bot_favour/F)
	if(!F?.asker?.resolve() || !find_carried_tool(F.item_type))
		return
	assign_goal(new /datum/bot_goal/favour/deliver(F))

#undef BOT_FAVOUR_SMALL
#undef BOT_FAVOUR_WALK
#undef BOT_FAVOUR_ERRAND
#undef BOT_FAVOUR_LATER
#undef BOT_FAVOUR_STAY
#undef BOT_GUIDE_SLACK
