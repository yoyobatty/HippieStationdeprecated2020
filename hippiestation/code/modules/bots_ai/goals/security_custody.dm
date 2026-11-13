// A prisoner left lying (the user's playtest, 2026-11-13). Two officers cuffed the user in crit, each said "bringing them to the brig",
// and both walked off: one had used its last pair of cuffs, and the errand to fetch more was being weighed up when the escort was, so
// the escort was turned down (assign_goal() takes one at a time) and never asked again. The user crawled off cuffed and bled out in
// maintenance.
//
// An officer remembers who it's cuffed until they're in a cell, in somebody's hands, being seen to, or let go, and goes back for one
// left lying: dropping an errand of its own for it (a drink, a fresh pair of cuffs), not anything that matters more, and for anybody
// cuffed it sees lying about that nobody's seeing to. A go at it that comes to nothing waits a minute and a half before the next, and
// after three it radios for somebody else to see to them: the first batch with this had officers dropping errands, air included, to go
// back for the same prisoner 24 times.

/// Between goes at the same prisoner, and how many goes before it asks somebody else
#define BOT_PICKUP_REST (90 SECONDS)
#define BOT_PICKUP_TRIES 3

/datum/bot_brain
	/// Who this officer's cuffed and not yet seen into a cell or to a doctor (weakrefs)
	var/list/my_prisoners
	/// REF(prisoner) -> list(when it last went back for them, how many times)
	var/list/pickup_tries

/// Somebody cuffed and on Security's books, left where they are: not in a cell, not being walked or carried off, not somebody else's job
/datum/bot_brain/proc/left_lying(mob/living/carbon/human/P)
	if(QDELETED(P) || P.stat == DEAD || !P.handcuffed || !isturf(P.loc) || P.pulledby || P.buckled)
		return FALSE
	if(is_in_active_cell(P) || brigged_by_another(P) || taken_by_another(P))
		return FALSE
	if(!bot_get_wanted_entry(P))
		return FALSE //not Security's
	if(bot_in_medbay(P) && bot_prisoner_needs_medbay(P))
		return FALSE //with the doctors
	if(gym_run && get_area(P) != get_area(owner))
		return FALSE
	return TRUE

/// Whether it's due another go at them
/datum/bot_brain/proc/pickup_due(mob/living/carbon/human/P)
	var/list/tried = LAZYACCESS(pickup_tries, REF(P))
	if(tried && world.time < tried[1] + BOT_PICKUP_REST)
		return FALSE
	return world.time >= LAZYACCESS(failed_brig_targets, P)

/// Its own prisoners left lying and due a go, and the list kept to those still to see to
/datum/bot_brain/proc/my_prisoners_left()
	. = list()
	for(var/datum/weakref/W as anything in my_prisoners)
		var/mob/living/carbon/human/P = W?.resolve()
		if(QDELETED(P) || P.stat == DEAD || !P.handcuffed || is_in_active_cell(P))
			LAZYREMOVE(my_prisoners, W) //in a cell, let go, or gone
			continue
		if(P.z == owner.z && left_lying(P) && pickup_due(P))
			. += P

/// A go at them: TRUE if it's on its way. The third that comes to nothing, it asks for somebody else and lets them go from its list.
/datum/bot_brain/proc/go_back_for(mob/living/carbon/human/P)
	var/list/tried = LAZYACCESS(pickup_tries, REF(P))
	var/count = (tried ? tried[2] : 0) + 1
	LAZYSET(pickup_tries, REF(P), list(world.time, count))
	if(count > BOT_PICKUP_TRIES)
		LAZYREMOVE(my_prisoners, WEAKREF(P))
		if(!gym_scripted)
			bot_say(owner, ":s [P.name]'s in cuffs in [get_area_name(P, TRUE)] and I can't get them in. Somebody see to them.")
		bot_log(src, "can't get [P] in after [BOT_PICKUP_TRIES] goes - asked for somebody else")
		return FALSE
	if(start_brig_escort(P)) //goals/security_patrol.dm: a cell, or Medbay if they're down
		bot_log(src, "back for [P], left in cuffs in [get_area_name(P, TRUE)]")
		bot_tally("prisoners gone back for")
		return TRUE
	return FALSE

/datum/bot_duty/loose_prisoner
	name = "going back for a prisoner left lying"
	jobs = list("Security Officer", "Warden", "Head of Security")
	tier = BOT_DUTY_URGENT
	priority = 62 //before a collapsed one in a cell (prisoner_down, 60): that one's at least somewhere
	interval_min = 20
	interval_max = 40
	interrupts = TRUE

/// Only an errand of its own: a break, or a fresh pair of cuffs (what took the officer off in the user's round). Never air, healing, a run
/// for it, a call for backup, or anybody else's prisoner or patient.
/datum/bot_duty/loose_prisoner/should_interrupt(datum/bot_brain/bot)
	if(!LAZYLEN(bot.my_prisoners) || bot.state != BOT_STATE_GOAL || !bot.current_goal || bot.current_goal.exclusive)
		return FALSE
	var/datum/bot_goal/G = bot.current_goal
	if(!G.off_duty && !istype(G, /datum/bot_goal/acquire_item_type))
		return FALSE
	return length(bot.my_prisoners_left()) > 0

/datum/bot_duty/loose_prisoner/try_start(datum/bot_brain/bot)
	if(bot.state != BOT_STATE_WANDER || bot.owner.incapacitated() || bot.owner.handcuffed)
		return FALSE
	var/list/found = bot.my_prisoners_left()
	if(!length(found))
		for(var/mob/living/carbon/human/P in view(BOT_SIGHT_RANGE, bot.owner))
			if(P != bot.owner && P.handcuffed && bot.left_lying(P) && bot.pickup_due(P))
				found += P
	for(var/mob/living/carbon/human/P as anything in found)
		if(bot.go_back_for(P))
			return TRUE
	return FALSE

#undef BOT_PICKUP_REST
#undef BOT_PICKUP_TRIES
