// Assistants. Most are out for trouble when they get the chance (goals/greytide.dm), and one short-handed job or another gets picked up
// by somebody (bot_hopping.dm). Between times, and for the rest, an assistant does what a player with no job does: goes through
// maintenance a locker at a time and keeps whatever's worth having, insulated gloves above everything.

/// Between one crawl and the next, for one bot.
#define BOT_CRAWL_GAP (5 MINUTES)
/// How far off a maintenance locker can be.
#define BOT_CRAWL_REACH 50
/// The nearest few lockers it picks between, so two assistants don't make for the same one.
#define BOT_CRAWL_CHOICES 4

/// What's worth keeping out of a maintenance locker, and how much. Anything else small enough to pocket is worth a 1.
GLOBAL_LIST_INIT(bot_maint_loot, list(
	/obj/item/clothing/gloves/color/yellow = 10,
	/obj/item/clothing/gloves/color/fyellow = 6,
	/obj/item/storage/belt/utility = 6,
	/obj/item/storage/toolbox = 5,
	/obj/item/weldingtool = 4,
	/obj/item/clothing/mask/gas = 4,
	/obj/item/multitool = 3,
	/obj/item/crowbar = 3,
	/obj/item/wirecutters = 3,
	/obj/item/screwdriver = 2,
	/obj/item/wrench = 2,
	/obj/item/flashlight = 2,
	/obj/item/stack/cable_coil = 2,
	/obj/item/tank/internals/emergency_oxygen = 2,
))

/// Never worth the pocket space.
GLOBAL_LIST_INIT(bot_maint_junk, typecacheof(list(/obj/item/trash, /obj/item/cigbutt, /obj/item/paper, /obj/item/shard, /obj/item/stack/sheet, /obj/item/stack/rods, /obj/item/stack/tile)))

/datum/bot_brain
	var/next_maint_crawl = 0
	/// Weakrefs of the lockers it's been through.
	var/list/lockers_searched

/datum/bot_duty/maint_crawl
	name = "going through maintenance"
	tier = BOT_DUTY_WORK
	jobs = list("Assistant")
	interval_min = 600
	interval_max = 1800

/datum/bot_duty/maint_crawl/try_start(datum/bot_brain/bot)
	if(world.time < bot.next_maint_crawl)
		return FALSE
	bot.next_maint_crawl = world.time + BOT_CRAWL_GAP
	var/obj/structure/closet/C = bot.find_maint_locker()
	return C ? bot.assign_goal(new /datum/bot_goal/rummage(C)) : FALSE

/// One of the nearest maintenance lockers it hasn't been through, that it can open and walk to.
/datum/bot_brain/proc/find_maint_locker()
	var/list/near = list() //locker -> how far
	for(var/obj/structure/closet/C as anything in bot_instances_of(/obj/structure/closet))
		if(QDELETED(C) || !isturf(C.loc) || C.z != owner.z || C.welded || (C.secure && C.locked) || istype(C, /obj/structure/closet/body_bag) || istype(C, /obj/structure/closet/crate/coffin))
			continue
		var/dist = get_dist(owner, C)
		if(dist > BOT_CRAWL_REACH || !istype(get_area(C), /area/maintenance) || (WEAKREF(C) in lockers_searched))
			continue
		near[C] = dist
	var/list/choices = list()
	while(length(near) && length(choices) < BOT_CRAWL_CHOICES)
		var/obj/structure/closet/nearest
		for(var/obj/structure/closet/C as anything in near)
			if(!nearest || near[C] < near[nearest])
				nearest = C
		near -= nearest
		choices += nearest
	for(var/i in 1 to 3)
		if(!length(choices))
			break
		var/obj/structure/closet/C = pick_n_take(choices)
		if(can_walk_lawfully_to(C))
			return C
	return null

/// How much it wants this. 0 is leave it.
/datum/bot_brain/proc/loot_worth(obj/item/I)
	if(I.anchored || I.w_class > WEIGHT_CLASS_NORMAL || is_type_in_typecache(I, GLOB.bot_maint_junk) || find_carried_tool(I.type))
		return 0
	if(istype(I, /obj/item/clothing/gloves) && istype(owner.gloves, /obj/item/clothing/gloves))
		var/obj/item/clothing/gloves/worn = owner.gloves
		if(worn.siemens_coefficient <= 0)
			return 0 //already insulated
	for(var/path in GLOB.bot_maint_loot)
		if(istype(I, path))
			return GLOB.bot_maint_loot[path]
	return 1

/// Puts it where it goes: gloves on, the rest in the bag.
/datum/bot_brain/proc/keep_loot(obj/item/I)
	if(istype(I, /obj/item/clothing/gloves/color/yellow) || istype(I, /obj/item/clothing/gloves/color/fyellow))
		var/obj/item/clothing/gloves/worn = owner.gloves
		if(!istype(worn) || worn.siemens_coefficient > 0)
			human_pause(I)
			if(equip_displacing(I, ITEM_SLOT_GLOVES))
				return
	stow_or_drop(I)

/datum/bot_goal/rummage
	lawful = TRUE
	doing = "going through the lockers in maintenance"
	var/obj/structure/closet/locker

/datum/bot_goal/rummage/New(obj/structure/closet/C)
	. = ..()
	locker = C

/datum/bot_goal/rummage/resolve_target(datum/bot_brain/bot)
	target = QDELETED(locker) ? null : locker

/datum/bot_goal/rummage/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/rummage/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/interact(), new /datum/bot_step/rummage())
	return list(S)

/datum/bot_goal/rummage/on_give_up(datum/bot_brain/bot)
	if(locker)
		LAZYADD(bot.lockers_searched, WEAKREF(locker))

/datum/bot_strategy/rummage/is_feasible(datum/bot_brain/bot)
	return TRUE

/// Looks over what came out of the locker and keeps the best of it, and a second thing if that's good too.
/datum/bot_step/rummage/execute(datum/bot_brain/bot)
	var/obj/structure/closet/C = bot.current_goal?.target
	if(!istype(C) || !C.opened)
		return GOAL_STEP_FAIL
	LAZYADD(bot.lockers_searched, WEAKREF(C))
	bot.human_pause(C) //a look at what's there
	var/turf/T = get_turf(C)
	var/list/kept = list()
	for(var/i in 1 to 2)
		var/obj/item/best
		var/best_worth = 0
		for(var/obj/item/I in T)
			var/worth = bot.loot_worth(I)
			if(worth > best_worth)
				best = I
				best_worth = worth
		if(!best || (length(kept) && best_worth < 4) || !bot.try_pickup_target(best))
			break
		kept += best
		if(best_worth >= 10 && prob(70))
			bot_say(bot.owner, pick("Insuls!", "Yes, insuls.", "Score. Insulated gloves.", "Free insuls, nice."))
		bot.keep_loot(best)
	bot.telemetry_event("rummage", list("locker" = "[C]", "area" = get_area_name(C, TRUE), "kept" = english_list(kept, nothing_text = "nothing")))
	return GOAL_STEP_SUCCESS

#undef BOT_CRAWL_GAP
#undef BOT_CRAWL_REACH
#undef BOT_CRAWL_CHOICES
