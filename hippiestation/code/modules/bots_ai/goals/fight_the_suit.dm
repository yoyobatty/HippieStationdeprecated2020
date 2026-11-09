// The crew against a Syndicate nanosuit. The user's ruling (2026-11-09), after robust traitors killed six to nine at a time while the crew
// stood there or ran: "Crew should definitely help and find ways to kill and grief the nanosuit by any means necessary." Anybody, any
// time: a crew bot that sees a suit hurting somebody, or a suit it knows is wanted, goes for it with whatever's to hand, alone or not,
// and only runs once it's badly hurt itself. It doesn't stop when the suit goes down either: that's up again in seconds, so it's
// kept at until it's cuffed or dead (handle_combat(), bot_brain.dm). One with nothing to swing gets the toolbox or extinguisher if there's one close, on the
// way. Security keep their own way of doing it (goals/security_tactics.dm: together, from range, the Armory's gear).

/// How far a crew bot goes for something to swing before taking a suit on: further and the fight's over before it's back
#define BOT_SUIT_ARM_UP_RANGE 10
/// How old a sighting of a suit is still worth going to
#define BOT_SUIT_SIGHTING (3 MINUTES)

/// Every nanosuit there is, so the crew only looks round for one while somebody's wearing it
GLOBAL_LIST_EMPTY(bot_nanosuits)

/obj/item/clothing/suit/space/hardsuit/nano/Initialize()
	. = ..()
	GLOB.bot_nanosuits += src

/obj/item/clothing/suit/space/hardsuit/nano/Destroy()
	GLOB.bot_nanosuits -= src
	return ..()

/// Whether anybody's wearing one right now
/proc/bot_any_suit_worn()
	for(var/obj/item/clothing/suit/space/hardsuit/nano/N as anything in GLOB.bot_nanosuits)
		var/mob/living/carbon/human/H = N.loc
		if(istype(H) && H.wear_suit == N)
			return TRUE
	return FALSE

/// Somebody in a Syndicate nanosuit, up and about
/proc/bot_suit_to_fight(mob/living/carbon/human/H)
	return istype(H) && bot_in_nanosuit(H) && H.stat == CONSCIOUS && !H.handcuffed //goals/security_tactics.dm

/// Whether this bot goes for a suit: crew, not Security (who have their own way) and not a traitor
/datum/bot_brain/proc/takes_on_suits(mob/living/carbon/human/suit)
	if(is_security_job() || owner.incapacitated() || owner.mind?.has_antag_datum(/datum/antagonist/traitor))
		return FALSE
	return !on_my_side(suit) //bot_brain.dm

/// Already on it: fighting it, or getting something to fight it with
/datum/bot_brain/proc/busy_with_suit(mob/living/carbon/human/suit)
	if(state == BOT_STATE_COMBAT && attacker == suit)
		return TRUE
	var/datum/bot_goal/tide/arm_up/for_suit/G = current_goal
	return istype(G) && G.suit == suit

/// Goes for it. With nothing to hit it with and a toolbox or extinguisher close by, that first.
/datum/bot_brain/proc/take_on_the_suit(mob/living/carbon/human/suit)
	if(busy_with_suit(suit))
		return
	if(!has_a_weapon()) //bot_playstyles.dm
		var/datum/bot_goal/tide/arm_up/for_suit/kit = new
		kit.suit = suit
		if(assign_goal(kit))
			bot_log(src, "getting something to hit [suit] with")
			bot_say(owner, pick("Somebody grab something heavy!", "Get something to hit it with!", "I'm getting the toolbox!"))
			return
	bot_log(src, "going for [suit] in the nanosuit")
	bot_tally("went for a nanosuit")
	if(prob(50))
		bot_say(owner, pick("Get them!", "Pile on!", "Kill it!", "Everybody, on the suit!", "Hit it, hit it!"))
	step_in_against(suit) //bot_witness.dm

/// The nearest toolbox or extinguisher within reach of the fight, then straight back to it
/datum/bot_goal/tide/arm_up/for_suit
	var/mob/living/carbon/human/suit

/datum/bot_goal/tide/arm_up/for_suit/resolve_target(datum/bot_brain/bot)
	..()
	if(target && get_dist(bot.owner, target) > BOT_SUIT_ARM_UP_RANGE)
		target = null //nothing close: bare hands it is (take_on_the_suit() goes straight in)

/datum/bot_goal/tide/arm_up/for_suit/on_success(datum/bot_brain/bot)
	if(bot_suit_to_fight(suit) && get_dist(bot.owner, suit) <= 12)
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, step_in_against), suit), TRUE)

/datum/bot_goal/tide/arm_up/for_suit/on_give_up(datum/bot_brain/bot)
	if(bot_suit_to_fight(suit) && get_dist(bot.owner, suit) <= 12)
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, step_in_against), suit), TRUE)

// ---------------------------------------------------------------------------------------------
// Going after one that's been seen
// ---------------------------------------------------------------------------------------------

/// A suit seen in the last little while, close enough to go after: the crew hunts it, the way the hunters do the wanted (bot_playstyles.dm)
/datum/bot_duty/hunt_suit
	name = "going after the nanosuit"
	tier = BOT_DUTY_URGENT
	priority = 26
	interval_min = 30
	interval_max = 60

/datum/bot_duty/hunt_suit/applies_to(datum/bot_brain/bot)
	return !bot.is_security_job()

/datum/bot_duty/hunt_suit/try_start(datum/bot_brain/bot)
	if(!length(GLOB.bot_security_wanted))
		return FALSE
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		var/datum/bot_wanted/W = GLOB.bot_security_wanted[ref]
		if(!bot_suit_to_fight(H) || !bot.takes_on_suits(H) || !W.last_seen || W.last_seen.z != bot.owner.z)
			continue
		if(world.time > W.last_seen_at + BOT_SUIT_SIGHTING || LAZYACCESS(bot.hunted_sightings, REF(H)) == W.last_seen_at)
			continue
		if(get_dist(bot.owner, W.last_seen) > 60 || (bot.gym_run && get_area(W.last_seen) != get_area(bot.owner)))
			continue
		LAZYSET(bot.hunted_sightings, REF(H), W.last_seen_at)
		if(!bot.has_a_weapon())
			var/datum/bot_goal/tide/arm_up/for_suit/kit = new
			kit.suit = H
			if(bot.assign_goal(kit))
				return TRUE
		if(bot.can_walk_lawfully_to(W.last_seen) && bot.assign_goal(new /datum/bot_goal/hunt(W.last_seen)))
			bot_log(bot, "going after [H] in the nanosuit, last seen in [get_area_name(W.last_seen, TRUE)]")
			bot_tally("hunted a nanosuit")
			if(prob(50))
				bot_say(bot.owner, pick(";I'm going after [H.name].", ";Where's [H.name] now? I'm coming.", ";Somebody's got to stop [H.name]."))
			return TRUE
	return FALSE

#undef BOT_SUIT_ARM_UP_RANGE
#undef BOT_SUIT_SIGHTING
