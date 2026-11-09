// Clearing out a full bag. At the end of a shift 134 of 143 bots' bags were full (bot_shift.dm's "bag:" line, 2026-11-09), and with a
// full bag every new thing a bot picks up pushes another out of its hands onto the floor (set_down(), bot_items.dm): about sixteen
// thousand set-downs in twelve shifts. What filled them, past the survival box, the tools and the first-aid kit, was what a player
// clears out of theirs now and then: drinks bought and never drunk, cigarette butts, dead mice, the salt and pepper off a table,
// spare shoes, a second and third of the same tool.
//
// So now and then, with its bag nearly full and nothing much on, a bot takes the rubbish to the nearest bin and leaves the rest on the
// nearest table: the salt and pepper, a spare pair of shoes, an empty glass, a drink past the second, a second of a tool it has one
// of already. What it would miss stays: its ID and PDA, insulated gloves, one of each tool, a first-aid kit, a mask, its weapons.

/// What it does with something in its bag, if it's clearing it out: put it in the bin, or leave it on a table. Null keeps it.
#define BOT_BAG_BIN "bin"
#define BOT_BAG_TABLE "table"

/// Rubbish, whoever's bag it's in.
GLOBAL_LIST_INIT(bot_bag_rubbish, typecacheof(list(/obj/item/trash, /obj/item/cigbutt, /obj/item/paper/crumpled, /obj/item/grown/bananapeel,
	/obj/item/reagent_containers/food/snacks/deadmouse, /obj/item/reagent_containers/food/drinks/soda_cans)))

/// The bag it's wearing, if it's got one with storage.
/datum/bot_brain/proc/worn_bag()
	RETURN_TYPE(/obj/item/storage)
	var/obj/item/storage/pack = owner.get_item_by_slot(ITEM_SLOT_BACK)
	return istype(pack) && pack.GetComponent(/datum/component/storage) ? pack : null

/// Nearly full: no room left for something the size of a toolbox's worth of bits, or the last slot or two taken.
/datum/bot_brain/proc/bag_nearly_full()
	var/obj/item/storage/pack = worn_bag()
	if(!pack)
		return FALSE
	var/datum/component/storage/S = pack.GetComponent(/datum/component/storage)
	var/used = 0
	for(var/obj/item/I in pack.contents)
		used += I.w_class
	return used >= S.max_combined_w_class - WEIGHT_CLASS_NORMAL || length(pack.contents) >= S.max_items - 1

/// What's to come out of its bag: item -> BOT_BAG_BIN or BOT_BAG_TABLE.
/datum/bot_brain/proc/bag_clear_out()
	. = list()
	var/obj/item/storage/pack = worn_bag()
	if(!pack)
		return
	var/list/tools_seen = list()
	var/drinks = 0
	var/kits = 0
	var/botanist = work_role() == "Botanist"
	for(var/obj/item/I in pack.contents)
		if(is_type_in_typecache(I, GLOB.bot_bag_rubbish))
			if(!istype(I, /obj/item/reagent_containers/food/drinks/soda_cans) || !I.reagents?.total_volume)
				.[I] = BOT_BAG_BIN
				continue
		if(istype(I, /obj/item/reagent_containers/food/condiment/saltshaker) || istype(I, /obj/item/reagent_containers/food/condiment/peppermill))
			.[I] = BOT_BAG_TABLE //they belong on a table
			continue
		if(istype(I, /obj/item/clothing/shoes))
			.[I] = BOT_BAG_TABLE //it's wearing a pair
			continue
		var/obj/item/clothing/gloves/G = I
		if(istype(G) && G.siemens_coefficient >= 1)
			.[I] = BOT_BAG_TABLE //insulated ones are worth keeping
			continue
		var/obj/item/reagent_containers/food/drinks/D = I
		if(istype(D))
			if(!D.reagents?.total_volume)
				.[I] = BOT_BAG_TABLE //an empty glass or cup: the bar's
			else if(++drinks > 2)
				.[I] = BOT_BAG_TABLE
			continue
		if(istype(I, /obj/item/storage/firstaid))
			if(++kits > 1)
				.[I] = BOT_BAG_TABLE
			continue
		if(I.tool_behaviour)
			if(I.tool_behaviour in tools_seen)
				.[I] = BOT_BAG_TABLE //a second of the same
			else
				tools_seen += I.tool_behaviour
			continue
		if(!botanist && istype(I, /obj/item/reagent_containers/glass/bottle/nutrient))
			.[I] = BOT_BAG_TABLE //Botany's, picked up somewhere

/// The nearest table it can walk to, near `near`.
/datum/bot_brain/proc/nearest_table(atom/near)
	var/list/by_dist = list()
	for(var/obj/structure/table/T as anything in bot_instances_of(/obj/structure/table))
		if(QDELETED(T) || T.z != owner.z || (gym_run && get_area(T) != get_area(owner)))
			continue
		var/dist = get_dist(near, T)
		if(dist <= 10)
			by_dist[T] = dist
	sortTim(by_dist, GLOBAL_PROC_REF(cmp_numeric_asc), TRUE)
	var/tries = 0
	for(var/obj/structure/table/T as anything in by_dist)
		if(gym_run || can_walk_lawfully_to(T))
			return T
		if(++tries >= 3)
			break
	return null

/datum/bot_brain
	/// When it last cleared out its bag: not more than every so often.
	var/bag_cleared_at = 0

/// Now and then, with its bag nearly full, it's cleared out.
/datum/bot_duty/clear_bag
	name = "clearing out a full bag"
	tier = BOT_DUTY_LEISURE
	priority = 3
	interval_min = 2 MINUTES
	interval_max = 4 MINUTES

/datum/bot_duty/clear_bag/try_start(datum/bot_brain/bot)
	if((bot.bag_cleared_at && world.time < bot.bag_cleared_at + 10 MINUTES) || !bot.bag_nearly_full())
		return FALSE
	var/list/out = bot.bag_clear_out()
	if(!length(out))
		return FALSE
	bot.bag_cleared_at = world.time
	var/datum/bot_goal/clear_bag/G = new
	for(var/obj/item/I as anything in out)
		if(out[I] == BOT_BAG_BIN)
			LAZYADD(G.to_bin, I)
		else
			LAZYADD(G.to_table, I)
	return bot.assign_goal(G)

/datum/bot_goal/clear_bag
	lawful = TRUE
	doing = "clearing out my bag"
	var/list/to_bin
	var/list/to_table
	var/obj/machinery/disposal/bin/bin
	var/obj/structure/table/table

/datum/bot_goal/clear_bag/resolve_target(datum/bot_brain/bot)
	bin = length(to_bin) ? bot.nearest_bin(bot.owner) : null //bot_pursuits.dm
	table = length(to_table) ? bot.nearest_table(bot.owner) : null
	target = bin || table

/datum/bot_goal/clear_bag/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/clear_bag/S = new
	S.steps = list()
	if(bin)
		var/datum/bot_step/move_to/walk = new
		walk.step_target = bin
		S.steps += walk
		S.steps += new /datum/bot_step/paced/empty_into(bin, to_bin)
	if(table)
		var/datum/bot_step/move_to/walk = new
		walk.step_target = table
		S.steps += walk
		S.steps += new /datum/bot_step/paced/empty_into(table, to_table)
	return list(S)

/datum/bot_strategy/clear_bag/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_goal/clear_bag/on_success(datum/bot_brain/bot)
	bot_tally("cleared out a bag")

/// Each thing out of the bag and into the bin, or onto the table, one click at a time.
/datum/bot_step/paced/empty_into
	max_clicks = 21
	var/atom/into
	var/list/things
	var/done = 0

/datum/bot_step/paced/empty_into/New(atom/A, list/L)
	. = ..()
	into = A
	things = L ? L.Copy() : list()

/datum/bot_step/paced/empty_into/start(datum/bot_brain/bot)
	return !QDELETED(into) && bot.owner.Adjacent(into)

/datum/bot_step/paced/empty_into/do_click(datum/bot_brain/bot)
	while(length(things))
		var/obj/item/I = things[1]
		things.Cut(1, 2)
		if(QDELETED(I) || !bot.is_carried(I))
			continue
		if(!bot.ready_in_hand(I))
			bot_log_verbose(bot, "couldn't get [I] out of the bag")
			continue
		bot.owner.a_intent = INTENT_HELP
		if(istype(into, /obj/structure/table))
			// Set on it. Not clicked on it: a screwdriver on a table starts taking it apart, and a box does its own thing.
			bot.human_pause(into)
			bot.owner.face_atom(into)
			bot.owner.transferItemToLoc(I, get_turf(into))
		else
			bot.use_item_on(I, into) //a bin takes it in
		if(I.loc != bot.owner)
			done++
		else
			bot_log_verbose(bot, "[I] didn't go into [into]")
		return TRUE
	return FALSE

/datum/bot_step/paced/empty_into/finish(datum/bot_brain/bot)
	if(done)
		bot_log(bot, "cleared [done] thing\s out of my bag into [into]")
	return GOAL_STEP_SUCCESS

#undef BOT_BAG_BIN
#undef BOT_BAG_TABLE
