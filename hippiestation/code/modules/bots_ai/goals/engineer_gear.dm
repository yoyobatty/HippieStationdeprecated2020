// Engineers kit themselves out early in the round, the way a player does: insulated gloves first
// (they spend the shift around live power - cable repair, APCs, SMES), and the Chief Engineer also
// takes their cloak out of their own locker and wears it. Found through the ordinary tool-fetching
// goal (acquire_tool), so a CE goes to their locker, a station engineer to the electrical supplies.

/datum/bot_brain
	var/next_engineer_gear_check_time = 0

/datum/bot_brain/proc/is_power_engineer_job()
	var/role = owner.mind?.assigned_role
	return role == "Station Engineer" || role == "Chief Engineer"

/// What this engineer should be wearing, as list(item type = slot), in the order to fetch them.
/datum/bot_brain/proc/engineer_gear_wanted()
	. = list()
	if(!is_power_engineer_job())
		return
	.[/obj/item/clothing/gloves/color/yellow] = ITEM_SLOT_GLOVES
	if(owner.mind?.assigned_role == "Chief Engineer")
		.[/obj/item/clothing/neck/cloak/ce] = ITEM_SLOT_NECK

/datum/bot_brain/proc/is_wearing(item_type, slot)
	var/obj/item/worn = owner.get_item_by_slot(slot)
	return istype(worn, item_type)

/datum/bot_brain/proc/try_engineer_gear_round()
	var/list/wanted = engineer_gear_wanted()
	for(var/item_type in wanted)
		if(!is_wearing(item_type, wanted[item_type]))
			return assign_goal(new /datum/bot_goal/engineer_gear())
	return FALSE

/datum/bot_goal/engineer_gear

/datum/bot_goal/engineer_gear/resolve_target(datum/bot_brain/bot)
	target = bot.owner

/datum/bot_goal/engineer_gear/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/S = new /datum/bot_strategy/engineer_gear()
	S.steps = list()
	var/list/wanted = bot.engineer_gear_wanted()
	for(var/item_type in wanted)
		var/datum/bot_step/wear_item/W = new
		W.item_type = item_type
		W.slot = wanted[item_type]
		S.steps += W
	return list(S)

/datum/bot_strategy/engineer_gear/is_feasible(datum/bot_brain/bot)
	return TRUE

/// Wear an item of item_type in slot: already worn -> done; carried -> put it on; otherwise go and
/// fetch it (pausing this goal) and put it on when back.
/datum/bot_step/wear_item
	var/item_type
	var/slot
	var/fetch_attempted = FALSE

/datum/bot_step/wear_item/execute(datum/bot_brain/bot)
	if(bot.is_wearing(item_type, slot))
		return GOAL_STEP_SUCCESS
	var/obj/item/I = bot.find_carried_tool(item_type)
	if(I)
		return bot.wear(I, slot) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	var/obj/item/path = item_type
	if(fetch_attempted)
		bot_log(bot, "couldn't find [initial(path.name)] anywhere I can get to")
		return GOAL_STEP_FAIL
	fetch_attempted = TRUE
	bot_log(bot, "going to get [initial(path.name)] to wear")
	if(bot.suspend_goal_for(new /datum/bot_goal/acquire_tool(item_type)))
		return GOAL_STEP_PENDING
	return GOAL_STEP_FAIL

/// Puts on a worn item the way a player does: in hand first, then onto the body. Whatever was in
/// that slot goes into the bag, not onto the floor (the CE's black gloves, a hard hat...).
/datum/bot_brain/proc/wear(obj/item/I, slot)
	if(!ready_in_hand(I))
		return FALSE
	human_pause(owner)
	swap_out_worn(owner.get_item_by_slot(slot), I)
	if(!owner.equip_to_slot_if_possible(I, slot, FALSE, TRUE, TRUE))
		return FALSE
	bot_log(src, "put on [I]")
	return TRUE
