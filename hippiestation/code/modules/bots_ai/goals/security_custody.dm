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
/// How long somebody held for something that isn't violence is kept waiting for a cell before an officer lets them off with a warning:
/// most officers (strictness runs 0.75 to 1 on Security), the strictest, and a paranoid one.
#define BOT_CELL_WAIT_LENIENT (3 MINUTES)
#define BOT_CELL_WAIT_STRICT (6 MINUTES)
#define BOT_CELL_WAIT_PARANOID (8 MINUTES)
/// A place in the line for a cell that nobody's asked about for this long is dead: whoever had them gave up
#define BOT_CELL_QUEUE_STALE (3 MINUTES)

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
		bot_log(src, "can't get [P] in after [BOT_PICKUP_TRIES] goes - asking for somebody else")
		if(!gym_scripted)
			hand_over_prisoner(P, "three goes at it came to nothing") //below: it says so on the radio, and another officer's duty takes them
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

// ---------------------------------------------------------------------------------------------
// A full brig
// ---------------------------------------------------------------------------------------------
// Four cells and a crowd of vandals. In the shift batches of 2026-11-14 and 11-16 a fifth of the arrests had no cell for more than three
// minutes and the longest waited twenty, cuffed on a hallway floor, while whoever came along next took each cell as it came free.
// Anybody turned away for want of a cell is put in line: the worst charge goes in first, then whoever's waited longest. And somebody
// held for something that isn't violence who's waited a good while is let off with a warning for lack of room, as an officer with a full
// brig does it.

/// REF(prisoner) -> list(weakref, when they were first turned away, when they were last asked about)
GLOBAL_LIST_EMPTY(bot_cell_waiting)

/// Nobody's cell was free: P is in line. How long they've been waiting.
/proc/bot_cell_wait_start(mob/living/carbon/human/P)
	var/list/entry = GLOB.bot_cell_waiting[REF(P)]
	if(!entry)
		entry = list(WEAKREF(P), world.time, world.time)
		GLOB.bot_cell_waiting[REF(P)] = entry
	entry[3] = world.time
	return world.time - entry[2]

/proc/bot_cell_wait_end(mob/living/carbon/human/P)
	GLOB.bot_cell_waiting -= REF(P)

/// Who has first claim on a cell that's come free: the worst charge, then whoever's been waiting longest. Null if nobody's in line. A Bot
/// Gym arena's line is its own (the arenas share globals with the station and with each other).
/proc/bot_next_for_a_cell(obj/machinery/door_timer/T)
	var/mob/living/carbon/human/best
	var/best_score
	var/area/here = get_area(T)
	for(var/key in GLOB.bot_cell_waiting.Copy())
		var/list/entry = GLOB.bot_cell_waiting[key]
		var/datum/weakref/ref = entry[1]
		var/mob/living/carbon/human/P = ref.resolve()
		if(QDELETED(P) || P.stat == DEAD || !P.handcuffed || !bot_is_wanted(P) || world.time > entry[3] + BOT_CELL_QUEUE_STALE || bot_serving_sentence(P))
			GLOB.bot_cell_waiting -= key
			continue
		var/area/there = get_area(P)
		if(P.z != T.z || (istype(here, /area/bot_gym) ? there != here : istype(there, /area/bot_gym)))
			continue
		var/datum/bot_wanted/W = bot_get_wanted_entry(P)
		var/score = (W ? W.severity : BOT_CRIME_MINOR) * 100000000 - entry[2]
		if(!best || score > best_score)
			best = P
			best_score = score
	return best

/// Charges an officer with a full brig lets go with a warning: nothing violent, nothing capital, no more than ten minutes' worth.
GLOBAL_LIST_INIT(bot_let_off_for_room, list("Vandalism", "Major Vandalism", "Trespassing", "Breaking and Entering", "Trespassing in a Dangerous Area", "Breaking into a Dangerous Area", "Theft", "Vigilantism"))

/// Whether P, who's waited this long for a cell, is let off with a warning: a few minutes for most officers, longer for the strictest and a
/// paranoid one, and only for what's no danger to anybody.
/datum/bot_brain/proc/lets_off_for_room(mob/living/carbon/human/P, waited)
	var/datum/bot_wanted/W = bot_get_wanted_entry(P)
	if(!W || bot_case_of(P) || W.kill_on_sight || bot_is_fair_game(P) || !(W.crime in GLOB.bot_let_off_for_room))
		return FALSE
	if(bot_keep_cuffed(P) || bot_serving_sentence(P)) //went for an officer the last time the cuffs came off (goals/released_prisoner.dm)
		return FALSE
	return waited >= (is_paranoid() ? BOT_CELL_WAIT_PARANOID : (strictness >= 0.9 ? BOT_CELL_WAIT_STRICT : BOT_CELL_WAIT_LENIENT))

/// The goal's other way out of having no cell for somebody: walk up to them, say so, and take the cuffs off.
/datum/bot_strategy/let_off
	var/datum/bot_goal/brig_prisoner/goal

/datum/bot_strategy/let_off/New(datum/bot_goal/brig_prisoner/G)
	. = ..()
	goal = G
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/let_off(G))

/datum/bot_strategy/let_off/is_feasible(datum/bot_brain/bot)
	return !QDELETED(goal.prisoner) && goal.prisoner.handcuffed

/datum/bot_step/paced/let_off
	max_clicks = 4
	var/datum/bot_goal/brig_prisoner/goal
	var/said = FALSE
	var/freed = FALSE

/datum/bot_step/paced/let_off/New(datum/bot_goal/brig_prisoner/G)
	. = ..()
	goal = G

/datum/bot_step/paced/let_off/start(datum/bot_brain/bot)
	said = FALSE
	freed = FALSE
	return !QDELETED(goal.prisoner) && bot.owner.Adjacent(goal.prisoner)

/datum/bot_step/paced/let_off/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.prisoner
	if(QDELETED(P) || !P.handcuffed || !bot.owner.Adjacent(P))
		return FALSE
	var/datum/bot_wanted/W = bot_get_wanted_entry(P)
	if(!said)
		said = TRUE
		bot_say(bot.owner, pick("No room in the brig, [P.name], and it's only [lowertext(W?.crime || "that")]. This is your warning.", "The cells are full, [P.name]. I'm letting you off with a warning for [lowertext(W?.crime || "that")], so don't make me regret it.", "I've nowhere to put you, [P.name]. Consider that a warning, and keep out of trouble."))
		wait_for = 20
		return TRUE
	var/obj/item/restraints/handcuffs/cuffs = P.handcuffed
	P.uncuff()
	P.visible_message("<span class='notice'>[bot.owner] removes [P]'s restraints.</span>")
	if(!QDELETED(cuffs) && isturf(cuffs.loc) && !istype(cuffs, /obj/item/restraints/handcuffs/cable/zipties/used))
		bot.try_pickup_target(cuffs)
	freed = TRUE
	return FALSE

/datum/bot_step/paced/let_off/finish(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.prisoner
	if(!freed || QDELETED(P))
		return GOAL_STEP_FAIL
	bot_cell_wait_end(P)
	bot_clear_wanted(P)
	bot_set_criminal_status(P, "Discharged")
	LAZYREMOVE(bot.my_prisoners, WEAKREF(P))
	bot_log(bot, "no room for [P] and it's only [lowertext(goal.let_off_for)] - let them off with a warning")
	bot_tally("let off for lack of cells")
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// An officer with no ID
// ---------------------------------------------------------------------------------------------
// The user's ruling (2026-11-12): an officer with no ID, who can't set a cell timer, hands the prisoner to another officer or the Warden
// at once, and gets a replacement ID from the HoP after. In gen1116f four officers got to the timer with the prisoner already searched and
// uncuffed in the cell, found "no access", and gave up: the prisoner was loose again, and the next officer to see them began the arrest
// over. Now the officer asks before it starts: any other officer with access takes the prisoner in, and the officer without a card asks
// the HoP for a new one (bot_hopping.dm). The same ask goes out when an officer's three goes at getting somebody in came to nothing.

/// How long an officer who has asked for somebody else to take a prisoner in leaves it before it asks again
#define BOT_HANDOVER_WAIT (3 MINUTES)

/// REF(prisoner) -> list(weakref to them, weakref to the officer who asked, when)
GLOBAL_LIST_EMPTY(bot_handovers)

/// Whether this officer's card opens the Brig's timers and cells: no card, or one without Security's access, is no.
/datum/bot_brain/proc/has_brig_access()
	var/obj/item/card/id/card = route_card()
	return card && (ACCESS_SECURITY in card.GetAccess())

/// Asks another officer to take this cuffed prisoner in, and lets go of them. Always FALSE: it hasn't got them in.
/datum/bot_brain/proc/hand_over_prisoner(mob/living/carbon/human/H, why)
	LAZYREMOVE(my_prisoners, WEAKREF(H))
	LAZYSET(failed_brig_targets, H, world.time + BOT_HANDOVER_WAIT)
	arrest_refusal_note = "[why]: asked for another officer to take them in"
	if(GLOB.bot_handovers[REF(H)])
		return FALSE
	owner.stop_pulling()
	bot_log(src, "can't take [H] in ([why]) - asked for another officer to")
	bot_tally("prisoners handed over")
	var/where = get_area_name(H, TRUE)
	var/need = has_brig_access() ? "can't get them in" : "haven't got an ID to book them with"
	var/said_at = world.time
	var/said = bot_say(owner, ":s [H.name] is in cuffs in [where] and I [need]. Somebody take them in.")
	// Only on the list if the radio carried it (bot_radio.dm). If it didn't, it's kept for the next officer it meets close by and told them
	// to their face, as a call in is. A line kept back as a repeat counts on the call that went out before it.
	var/datum/callback/register = CALLBACK(src, PROC_REF(register_handover), WEAKREF(H))
	bot_radio_then(owner, said_at - 10 SECONDS, register, said ? CALLBACK(src, PROC_REF(keep_to_tell), register, "[H.name] is in cuffs in [where] and I [need]. Take them in.", null) : null)
	return FALSE

/// The ask got out, or an officer's been told it in person: the prisoner's on the list for whoever's free to take in.
/datum/bot_brain/proc/register_handover(datum/weakref/prisoner_ref)
	var/mob/living/carbon/human/H = prisoner_ref?.resolve()
	if(QDELETED(H) || !H.handcuffed || GLOB.bot_handovers[REF(H)])
		return
	GLOB.bot_handovers[REF(H)] = list(prisoner_ref, WEAKREF(src), world.time)

/datum/bot_duty/take_over_prisoner
	name = "taking over a prisoner another officer can't take in"
	jobs = list("Security Officer", "Warden", "Head of Security")
	tier = BOT_DUTY_URGENT
	priority = 36
	interval_min = 20
	interval_max = 40

/datum/bot_duty/take_over_prisoner/try_start(datum/bot_brain/bot)
	if(!length(GLOB.bot_handovers) || bot.state != BOT_STATE_WANDER || bot.owner.incapacitated() || bot.owner.handcuffed || !bot.has_brig_access())
		return FALSE
	var/mob/living/carbon/human/best
	var/datum/bot_brain/asker
	var/best_dist
	for(var/key in GLOB.bot_handovers.Copy())
		var/list/entry = GLOB.bot_handovers[key]
		var/datum/weakref/prisoner_ref = entry[1]
		var/datum/weakref/asker_ref = entry[2]
		var/mob/living/carbon/human/H = prisoner_ref?.resolve()
		if(QDELETED(H) || H.stat == DEAD || !H.handcuffed || world.time > entry[3] + BOT_HANDOVER_WAIT || bot.is_in_active_cell(H))
			GLOB.bot_handovers -= key
			continue
		if(asker_ref?.resolve() == bot || H.z != bot.owner.z || (bot.gym_run && get_area(H) != get_area(bot.owner)))
			continue
		var/cooldown = LAZYACCESS(bot.failed_brig_targets, H)
		if(cooldown && world.time < cooldown)
			continue
		var/d = get_dist(bot.owner, H)
		if(!best || d < best_dist)
			best = H
			best_dist = d
			asker = asker_ref?.resolve()
	if(!best || bot.nearer_officer_free_for(best, best_dist))
		return FALSE
	if(!bot.start_brig_escort(best))
		LAZYSET(bot.failed_brig_targets, best, world.time + 30 SECONDS) //not asked again every few seconds
		return FALSE
	GLOB.bot_handovers -= REF(best)
	bot_log(bot, "took over [best] from [asker ? asker.owner : "an officer"]")
	bot_say(bot.owner, ":s I've got [best.name]. I'll take them in.")
	return TRUE

/// Another officer who'd take this prisoner, nearer to them than this one is: it gets first go.
/datum/bot_brain/proc/nearer_officer_free_for(mob/living/carbon/human/H, my_dist)
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(B == src || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner.z != H.z || B.state != BOT_STATE_WANDER || B.owner.handcuffed)
			continue
		if(B.gym_run && get_area(B.owner) != get_area(H))
			continue
		if(get_dist(B.owner, H) < my_dist && B.has_brig_access() && world.time >= LAZYACCESS(B.failed_brig_targets, H))
			return TRUE
	return FALSE

/// Another officer, awake and free, whose card opens the Brig
/datum/bot_brain/proc/another_officer_with_access()
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(B == src || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner.handcuffed || B.owner.z != owner.z || !B.has_brig_access())
			continue
		if(gym_run && get_area(B.owner) != get_area(owner))
			continue
		return TRUE
	return FALSE

/// An officer with no ID of its own on it, between jobs: it asks the HoP for a new one, once its prisoner has gone to somebody else.
/datum/bot_duty/new_id_from_hop
	name = "asking the HoP for a new ID"
	jobs = list("Security Officer", "Warden", "Head of Security", "Detective")
	tier = BOT_DUTY_URGENT
	priority = 18
	interval_min = 50
	interval_max = 100

/datum/bot_duty/new_id_from_hop/try_start(datum/bot_brain/bot)
	if(bot.state != BOT_STATE_WANDER || bot.owner.incapacitated() || bot.owner.handcuffed || bot.owner.bot_life_sentence || bot.is_in_active_cell(bot.owner) || bot.gone_loud())
		return FALSE
	if(bot.owner.get_idcard(TRUE) || bot.owner.get_idcard(FALSE) || bot.my_card_to_fetch()) //one on it, or its own lying where it can get it
		return FALSE
	if(bot.applying_for || world.time < bot.card_wait_until) //its card's at the HoP's desk for a job change, or somebody's bringing it back
		return FALSE
	for(var/datum/bot_transfer/T as anything in GLOB.bot_transfers)
		if(T.who == bot.owner && !T.done)
			return FALSE
	for(var/list/promise as anything in GLOB.bot_new_ids_promised)
		var/datum/weakref/who_ref = promise[1]
		if(who_ref?.resolve() == bot.owner)
			return FALSE //it's been promised one already
	for(var/key in GLOB.bot_handovers)
		var/list/entry = GLOB.bot_handovers[key]
		var/datum/weakref/asker_ref = entry[2]
		if(asker_ref?.resolve() == bot && bot.another_officer_with_access())
			return FALSE //the prisoner first, while there's somebody to take them
	bot.call_for(/datum/bot_request_kind/new_id, pick("HoP, I've lost my ID and I need a new one printed. I'm [bot.owner.real_name], Security.", "HoP, I need a new ID, mine's gone. [bot.owner.real_name], Security Officer."))
	return FALSE

#undef BOT_HANDOVER_WAIT

#undef BOT_PICKUP_REST
#undef BOT_PICKUP_TRIES
#undef BOT_CELL_WAIT_LENIENT
#undef BOT_CELL_WAIT_STRICT
#undef BOT_CELL_WAIT_PARANOID
#undef BOT_CELL_QUEUE_STALE
