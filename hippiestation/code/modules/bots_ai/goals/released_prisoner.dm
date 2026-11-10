// Out of a cell: its things back from the cell locker, the way anybody let out goes to the locker first. Processing puts everything
// but a prisoner's clothes in there (bot_law.dm, everything_but_clothes()), their own jumpsuit and shoes too once they're in orange,
// and the timer unlocks it when the sentence is up (brigdoors.dm). Nobody went back for any of it: a chemist let out of Cell 2 at
// the end of their sentence (play5f run6) walked the Brig without an ID, a bag or a radio, couldn't open a door out, and bled to death
// there wandering, with their ID in the locker a few tiles off. What the search turned up as contraband stays where it is.
//
// Also here: Security remembering a prisoner who went for the officer the moment the cuffs came off, so they're left cuffed in the
// cell next time (bot_brain.dm on_attacked(), security_patrol.dm process_prisoner). The same play5f prisoner was cuffed, uncuffed,
// punched the officer, was stunned and cuffed again six times over in one cell before being flashed and left on the floor.

/// How long after the cuffs come off a swing at the officer counts as fighting being processed
#define BOT_UNCUFF_FIGHT_WINDOW (30 SECONDS)
/// How long Security keeps a prisoner who did that in cuffs
#define BOT_KEEP_CUFFED_FOR (20 MINUTES)

/// Prisoner (weakref) -> when they were last uncuffed in a cell, and until when they're kept cuffed for fighting it
GLOBAL_LIST_EMPTY(bot_uncuffed_at)
GLOBAL_LIST_EMPTY(bot_keep_cuffed_until)

/proc/bot_note_uncuffed_in_cell(mob/living/carbon/human/P)
	GLOB.bot_uncuffed_at[WEAKREF(P)] = world.time

/// Somebody just uncuffed in a cell has gone for the officer: they stay cuffed next time
/proc/bot_note_fought_uncuffing(mob/living/user)
	var/datum/weakref/ref = WEAKREF(user)
	var/when = GLOB.bot_uncuffed_at[ref]
	if(!when || world.time > when + BOT_UNCUFF_FIGHT_WINDOW)
		return FALSE
	GLOB.bot_uncuffed_at -= ref
	GLOB.bot_keep_cuffed_until[ref] = world.time + BOT_KEEP_CUFFED_FOR
	return TRUE

/proc/bot_keep_cuffed(mob/living/carbon/human/P)
	return GLOB.bot_keep_cuffed_until[WEAKREF(P)] > world.time

/datum/bot_brain
	/// What Security took off it into a cell locker: item (weakref) -> the slot it was in (0 for a hand), and the locker
	var/list/confiscated
	var/datum/weakref/confiscated_locker

/// The slot something is worn in on them, or 0 for a hand or anywhere else
/proc/bot_slot_holding(mob/living/carbon/human/P, obj/item/I)
	var/static/list/slots = list(ITEM_SLOT_ID, ITEM_SLOT_BACK, ITEM_SLOT_BELT, ITEM_SLOT_EARS, ITEM_SLOT_ICLOTHING, ITEM_SLOT_FEET,
		ITEM_SLOT_OCLOTHING, ITEM_SLOT_SUITSTORE, ITEM_SLOT_GLOVES, ITEM_SLOT_HEAD, ITEM_SLOT_MASK, ITEM_SLOT_EYES, ITEM_SLOT_NECK,
		ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET)
	for(var/slot in slots)
		if(P.get_item_by_slot(slot) == I)
			return slot
	return 0

/// Processing put this in the cell locker (or on its floor): the prisoner will want it back. Not contraband, which stays.
/proc/bot_note_confiscated(mob/living/carbon/human/P, obj/item/I, slot, obj/structure/closet/locker)
	if(!P?.bot_brain || !I || is_type_in_typecache(I, GLOB.bot_contraband) || bot_is_captains_id(I))
		return
	var/datum/bot_brain/B = P.bot_brain
	var/obj/structure/closet/old = B.confiscated_locker?.resolve()
	if(locker && old != locker)
		B.confiscated = list() //a new cell: what was in the last one is old news
		B.confiscated_locker = WEAKREF(locker)
	LAZYSET(B.confiscated, WEAKREF(I), slot)

/// Its things still in the cell locker or on the floor in front of it, the ID first. Forgets the rest (taken, gone, carried).
/datum/bot_brain/proc/confiscated_left()
	. = list()
	var/obj/structure/closet/L = confiscated_locker?.resolve()
	if(!L || QDELETED(L))
		confiscated = null
		confiscated_locker = null
		return
	var/turf/T = get_turf(L)
	// In the order anybody dresses (the clone's, goals/cloning.dm): the jumpsuit before the ID and belt, which a jumpsuit coming off
	// drops - the ID went back on first and fell to the floor when the orange came off for its own jumpsuit.
	var/list/order = GLOB.bot_clone_dress_order
	var/list/found = .
	var/list/ranks = list()
	for(var/datum/weakref/ref as anything in confiscated.Copy())
		var/obj/item/I = ref.resolve()
		if(!I || QDELETED(I) || is_carried(I) || (I.loc != L && I.loc != T))
			confiscated -= ref
			continue
		var/rank = order.Find(confiscated[ref]) || (length(order) + 1) //held things last
		var/at = 1
		while(at <= length(found) && ranks[at] <= rank)
			at++
		found.Insert(at, I)
		ranks.Insert(at, rank)
	if(!length(confiscated))
		confiscated = null

/datum/bot_duty/collect_confiscated
	name = "getting my things back from the cell locker"
	tier = BOT_DUTY_URGENT
	priority = 45
	interval_min = 10
	interval_max = 30

/datum/bot_duty/collect_confiscated/try_start(datum/bot_brain/bot)
	if(!length(bot.confiscated) || bot.owner.handcuffed || bot.owner.bot_life_sentence || bot.is_in_active_cell(bot.owner))
		return FALSE
	// Just uncuffed in the cell, with the officer on its way to the timer: the locker's not locked yet, but that's no release. A janitor
	// had everything back out of it 0.03 s before his sentence started (2026-11-10).
	var/uncuffed = GLOB.bot_uncuffed_at[WEAKREF(bot.owner)]
	if(uncuffed && world.time < uncuffed + 1 MINUTES)
		return FALSE
	var/obj/structure/closet/L = bot.confiscated_locker?.resolve()
	if(!L || QDELETED(L) || L.z != bot.owner.z || get_dist(bot.owner, L) > 40)
		return FALSE
	if(L.locked && !L.opened) //a sentence still running in there, theirs or the next one's
		return FALSE
	if(!length(bot.confiscated_left()))
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/collect_confiscated(L))

/datum/bot_goal/collect_confiscated
	doing = "getting my things back"

/datum/bot_goal/collect_confiscated/New(obj/structure/closet/L)
	. = ..()
	target = L

/datum/bot_goal/collect_confiscated/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/collect_confiscated/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/collect_confiscated/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/take_confiscated_back())
	return list(S)

/datum/bot_goal/collect_confiscated/on_success(datum/bot_brain/bot)
	bot_log(bot, "got my things back from [target]")
	bot.confiscated = null
	bot.confiscated_locker = null

/datum/bot_goal/collect_confiscated/on_give_up(datum/bot_brain/bot)
	bot.confiscated = null //no going round for ever: whatever's left, it does without
	bot.confiscated_locker = null

/datum/bot_strategy/collect_confiscated/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// The locker open, then a thing at a time out of it and back where it was worn: the ID first.
/datum/bot_step/paced/take_confiscated_back
	max_clicks = 20

/datum/bot_step/paced/take_confiscated_back/start(datum/bot_brain/bot)
	var/obj/structure/closet/L = bot.current_goal?.target
	return istype(L) && bot.owner.Adjacent(L)

/datum/bot_step/paced/take_confiscated_back/do_click(datum/bot_brain/bot)
	var/obj/structure/closet/L = bot.current_goal?.target
	if(!istype(L) || QDELETED(L) || !bot.owner.Adjacent(L))
		return FALSE
	var/list/left = bot.confiscated_left()
	if(!length(left))
		return FALSE
	if(!L.opened)
		if(L.locked)
			return FALSE
		bot.human_pause(L)
		if(!L.open(bot.owner))
			return FALSE
		bot_log(bot, "opened [L] for my things")
		return TRUE
	var/obj/item/I = left[1]
	var/slot = bot.confiscated[WEAKREF(I)]
	bot.confiscated -= WEAKREF(I)
	if(QDELETED(I) || !bot.owner.Adjacent(I))
		return TRUE
	if(slot == ITEM_SLOT_ID && istype(I, /obj/item/card/id))
		if(bot.try_pickup_target(I))
			bot.wear_card(I)
	else if(slot)
		if(!bot.try_pickup_target(I) || !bot.wear(I, slot))
			if(bot.is_carried(I) && I.loc == bot.owner)
				bot.put_away(I)
	else if(bot.try_pickup_target(I))
		bot.put_away(I)
	bot_log(bot, "took back [I]")
	return TRUE

#undef BOT_UNCUFF_FIGHT_WINDOW
#undef BOT_KEEP_CUFFED_FOR
