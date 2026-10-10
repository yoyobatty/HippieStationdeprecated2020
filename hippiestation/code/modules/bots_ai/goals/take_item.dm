// Fetching a loose thing to work with: walk over, pick it up, keep it in hand.
//
// acquire_item_type (acquire_item_type.dm) ends in try_pickup_target(), which stows what it picks up
// wherever it fits - and a bucket fits on the head, where its water promptly goes down the bot's neck
// (bucket/equipped()). This is for the things a job holds and uses: nothing here is ever worn.

/// Picks a loose item up into a hand and leaves it there. Both hands full: one thing goes in the bag first.
/datum/bot_brain/proc/take_in_hand(obj/item/I)
	if(!I || QDELETED(I) || !isturf(I.loc) || get_dist(owner, I) > 1)
		return FALSE
	telemetry_action = "pick up [I]"
	human_pause(I)
	telemetry_action = null
	if(QDELETED(I) || !isturf(I.loc) || get_dist(owner, I) > 1)
		return FALSE
	owner.face_atom(I)
	if(owner.get_active_held_item() && owner.get_inactive_held_item())
		put_away(owner.get_active_held_item(), allow_equip = FALSE)
	if(!owner.put_in_hands(I))
		return FALSE
	bot_log(src, "picked up [I]")
	return TRUE

/// The nearest loose item of item_type within `reach` tiles that the bot might walk to. A Bot Gym bot only sees its own arena's.
/datum/bot_brain/proc/find_loose_item(item_type, reach = 60)
	var/obj/item/best
	var/best_dist
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		if(QDELETED(I) || !isturf(I.loc) || I.anchored || I.z != owner.z)
			continue
		var/dist = get_dist(owner, I)
		if(dist > reach || (best && dist >= best_dist))
			continue
		if(gym_run && get_area(I) != get_area(owner))
			continue
		best = I
		best_dist = dist
	return best

/datum/bot_goal/take_item
	lawful = TRUE
	var/item_type

/datum/bot_goal/take_item/New(item_type)
	. = ..()
	src.item_type = item_type

/datum/bot_goal/take_item/resolve_target(datum/bot_brain/bot)
	target = bot.find_loose_item(item_type)

/datum/bot_goal/take_item/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/take_item/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_in_hand())
	return list(S)

/datum/bot_strategy/take_item/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/take_in_hand/execute(datum/bot_brain/bot)
	var/obj/item/I = bot.current_goal?.target
	if(istype(I) && bot.is_carried(I))
		return GOAL_STEP_SUCCESS //grabbed in passing on the way over
	return bot.take_in_hand(I) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
