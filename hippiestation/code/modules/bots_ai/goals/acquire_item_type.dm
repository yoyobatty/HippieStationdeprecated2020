// Generic "go get one of these" goal - reusable for any item type, not just the
// curated personal-objective pool below (a real antagonist steal objective could
// reuse this exact goal type with its target item later).
/datum/bot_goal/acquire_item_type
	var/item_type

// Picks the NEAREST reachable-looking candidate on the bot's own z-level, not just the
// first match world// happens to iterate to. A plain "first in world" scan used to
// hand back whatever instance of the type was created first/earliest in memory,
// regardless of where that was - confirmed in-game repeatedly sending a bot after the
// exact same beaker sitting on a completely different z-level (CentCom/away
// storage), which can never path there and fails every single time. Distance is still
// a cheap proxy, not a real reachability check (that's what the actual pathfind in
// do_repath() is for) - but same-z + nearest first means a genuinely reachable local
// item is tried before a farther/off-map one of the same type.
/datum/bot_goal/acquire_item_type/resolve_target(datum/bot_brain/bot)
	if(lawful)
		target = nearest_lawful_source(bot)
		return
	var/obj/item/best
	var/best_dist
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		if(!isturf(I.loc) || I.anchored)
			continue //already held/worn/bagged, or fixed in place - not freely takeable
		var/turf/T = I.loc
		if(T.z != bot.owner.z)
			continue
		var/dist = get_dist(bot.owner, I)
		if(!best || dist < best_dist)
			best = I
			best_dist = dist
	if(best)
		target = best
		return

	// Nothing loose anywhere - try a closet/locker instead. Several item_types this goal
	// is used for round-start (an internals tank stored in suit storage, say) commonly
	// exist ONLY inside a locker, never as a loose floor item at all - without this tier
	// the loose-item scan above would come up empty and the whole goal would just fail,
	// even with several right there behind a door.
	var/obj/structure/closet/best_closet
	var/best_closet_dist
	for(var/obj/structure/closet/C as anything in bot_instances_of(/obj/structure/closet))
		if(QDELETED(C) || !isturf(C.loc) || C.z != bot.owner.z)
			continue
		if(C.secure && C.locked && !C.allowed(bot.owner))
			continue //can't open it anyway - not a real candidate
		if(!(locate(item_type) in C))
			continue
		var/dist = get_dist(bot.owner, C)
		if(!best_closet || dist < best_closet_dist)
			best_closet = C
			best_closet_dist = dist
	target = best_closet

/// For an everyday fetch (`lawful`): the nearest one this bot can simply walk up to - loose, or in a locker it may
/// open. The nearest as the crow flies is as often as not on somebody else's desk, behind a door this bot has no
/// business opening.
/datum/bot_goal/acquire_item_type/proc/nearest_lawful_source(datum/bot_brain/bot)
	var/list/found = list() //source -> how far off
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		if(QDELETED(I) || !isturf(I.loc) || I.anchored || I.z != bot.owner.z)
			continue
		found[I] = get_dist(bot.owner, I)
	for(var/obj/structure/closet/C as anything in bot_instances_of(/obj/structure/closet))
		if(QDELETED(C) || !isturf(C.loc) || C.z != bot.owner.z)
			continue
		if(C.secure && C.locked && !C.allowed(bot.owner))
			continue
		if(!(locate(item_type) in C))
			continue
		found[C] = get_dist(bot.owner, C) + 3 //a loose one is less bother than rummaging
	var/tries = 0
	while(length(found) && tries++ < 6)
		var/atom/nearest
		for(var/atom/A as anything in found)
			if(!nearest || found[A] < found[nearest])
				nearest = A
		found -= nearest
		if(bot.can_walk_lawfully_to(nearest))
			return nearest
	return null

/datum/bot_goal/acquire_item_type/get_strategies(datum/bot_brain/bot)
	if(istype(target, /obj/structure/closet))
		return list(new /datum/bot_strategy/grab_item_from_locker(item_type))
	return list(new /datum/bot_strategy/grab_item())

/datum/bot_strategy/grab_item/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/pickup_item())

/datum/bot_strategy/grab_item/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_strategy/grab_item_from_locker/New(item_type)
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/interact(), new /datum/bot_step/pickup_from_target(item_type))

/datum/bot_strategy/grab_item_from_locker/is_feasible(datum/bot_brain/bot)
	return TRUE

// Personal objectives: occasionally, instead of just wandering, a bot decides it
// wants something specific - mirrors how a real player invents their own little
// goals mid-round rather than only reacting to what's directly in front of them.
GLOBAL_LIST_INIT(bot_personal_objective_lines, list(
	list(/obj/item/clothing/gloves/color/yellow, "I could use some insulated gloves.", "Nice, got some insulated gloves."),
	list(/obj/item/crowbar, "I should grab a crowbar.", "Got a crowbar."),
	list(/obj/item/screwdriver, "I need a screwdriver.", "Found a screwdriver."),
	list(/obj/item/flashlight, "Could use a flashlight.", "Got a flashlight."),
	list(/obj/item/extinguisher, "I should grab a fire extinguisher, just in case.", "Got a fire extinguisher."),
))

/datum/bot_brain/proc/try_personal_objective()
	var/list/line = pick(GLOB.bot_personal_objective_lines)
	var/datum/bot_goal/acquire_item_type/goal = new()
	goal.item_type = line[1]
	goal.flavor_success = line[3]
	// A whim, not a mission: one it can walk to, or it lets the idea go. These used to be fetched through whatever
	// was in the way - a clown after a screwdriver went in through maintenance, ended up shut in the Toxins lab
	// with no way to open its doors from inside, and was still there when the evacuation shuttle left.
	goal.lawful = TRUE
	if(!assign_goal(goal))
		return FALSE
	bot_say(owner, line[2])
	return TRUE
