// Fetching a loose thing to work with: walk over, pick it up, keep it in hand.
//
// acquire_item_type (acquire_item_type.dm) ends in try_pickup_target(), which stows what it picks up
// wherever it fits - and a bucket fits on the head, where its water promptly goes down the bot's neck
// (bucket/equipped()). This is for the things a job holds and uses: nothing here is ever worn.

/// Picks a loose item up into a hand and leaves it there. Both hands full: one thing goes in the bag first.
/datum/bot_brain/proc/take_in_hand(obj/item/I)
	if(!I || QDELETED(I))
		return FALSE
	// Each way this goes wrong says so: of 67 pickups failed in a batch, 59 said nothing about why.
	if(!isturf(I.loc) || get_dist(owner, I) > 1)
		bot_log(src, "[I] isn't there to pick up ([isturf(I.loc) ? "[get_dist(owner, I)] tiles off" : "in [I.loc]"])")
		return FALSE
	telemetry_action = "pick up [I]"
	human_pause(I)
	telemetry_action = null
	if(QDELETED(I) || !isturf(I.loc) || get_dist(owner, I) > 1)
		bot_log(src, "[I] went before I could pick it up")
		return FALSE
	owner.face_atom(I)
	var/held_before = held_item_count()
	make_hand_free()
	if(held_item_count() < held_before) //a hand emptied for it is an input of its own, and the pickup is the next (hand_beat(), bot_human.dm)
		hand_beat()
		if(QDELETED(I) || !isturf(I.loc) || get_dist(owner, I) > 1)
			bot_log(src, "[I] went before I could pick it up")
			return FALSE
		owner.face_atom(I)
	if(!owner.put_in_hands(I))
		bot_log(src, "[I] wouldn't go in my hand ([owner.has_active_hand() ? "holding [owner.get_active_held_item() || "nothing"]" : "no hand that works"])")
		return FALSE
	bot_log(src, "picked up [I]")
	just_taken = WEAKREF(I)
	just_taken_at = world.time
	return TRUE

/// What it last picked up, and when: make_hand_free() keeps it and sets the other hand's load down instead
/datum/bot_brain/var/datum/weakref/just_taken
/datum/bot_brain/var/just_taken_at = 0

/// One hand empty, whatever it takes: into the bag if the bag will have it, either hand's load, or else set down for a
/// moment (set_down_items). put_in_hands() with both hands full tips what it's given onto the floor, and with a full
/// bag and a toolbox in hand that was a bot's dinner, off the counter and down at its feet. A hand that isn't there, or is
/// hurt past use, counts as full: one-handed, it's the one hand that's freed.
/datum/bot_brain/proc/make_hand_free()
	use_a_working_hand()
	var/obj/item/active = owner.get_active_held_item()
	var/obj/item/inactive = owner.get_inactive_held_item()
	if(!active || (!inactive && other_hand_works()) || put_away(active, allow_equip = FALSE) || (inactive && put_away(inactive, allow_equip = FALSE)))
		return
	// Not what it's only just picked up, when the other hand's had its load longer: a circuit build that wanted the battery and the
	// assembly in hand, with a tool in the other, set the battery down to take the assembly and the assembly to take the battery, 12
	// times in a row (tools/bot_gym/hollow_goals.py, 2026-11-22).
	if(inactive && other_hand_works() && just_taken?.resolve() == active && world.time < just_taken_at + 10 SECONDS && just_taken?.resolve() != inactive)
		owner.swap_hand()
		active = owner.get_active_held_item()
	bot_log(src, "setting [active] down for a moment")
	owner.dropItemToGround(active)
	LAZYADD(set_down_items, active)

/// The nearest loose item of item_type within `reach` tiles that the bot might walk to, of those it knows of (bot_knowledge.dm). A Bot
/// Gym bot only sees its own arena's.
/datum/bot_brain/proc/find_loose_item(item_type, reach = 60)
	glance_at_items()
	var/obj/item/best
	var/best_dist
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		if(QDELETED(I) || !isturf(I.loc) || I.anchored || I.z != owner.z || on_a_shuttle_without_me(I) || !knows_of(I))
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
