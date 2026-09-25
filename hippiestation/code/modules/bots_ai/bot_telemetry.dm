// Bot telemetry - records what a bot's BODY does, not just what its brain decides.
//
// The decision log (bot_log) says "prying the door open"; it can't say whether the jaws of life
// were in hand, how long the bot then stood there, or where items physically went. This records
// that ground truth so behaviour can be judged the way a watching player would judge it:
//
//  - a sample of every bot every half second: position, facing, tiles moved, goal/step, both
//    hands, the action in progress (covers do_afters), urgency, health
//  - an event for every pickup, drop, stow and equip, captured on the body itself (put_in_hand,
//    doUnEquip, equip_to_slot), so no code path can move items unseen - with where the item came
//    from and how far away it was
//  - an event for every interaction (use_item_on / use_atom), with where the item was beforehand
//  - "shortcut" events at the places the bot calls an engine proc directly instead of clicking
//    (try_to_crowbar, attack_self...), recording whether the item was actually in hand
//  - idle events: stretches of 3s+ with no movement, no action and no event
//  - goal start/success/give-up
//
// Output: data/logs/<round>/bot_telemetry.jsonl, one JSON object per line.
// Read it with: tools/bot_gym/analyze_telemetry.py <that file>

#define BOT_TELEMETRY_SAMPLE_INTERVAL 5 //deciseconds
#define BOT_TELEMETRY_IDLE_THRESHOLD 30 //deciseconds without movement, action or event

GLOBAL_LIST_EMPTY(bot_brains)
GLOBAL_VAR_INIT(bot_telemetry_running, FALSE)
GLOBAL_VAR(bot_telemetry_log)

/datum/bot_brain
	/// What the bot is doing right now that isn't walking - set around interactions, so samples
	/// taken mid do_after show the bot as busy, not idle.
	var/telemetry_action
	var/telemetry_action_start = 0
	var/turf/telemetry_last_turf
	/// Last time the bot moved, acted or produced an event.
	var/telemetry_last_activity = 0
	var/telemetry_idle_since = 0
	/// Believability counters, summarised by the Bot Gym. Keys: see telemetry_flag().
	var/list/telemetry_flags
	var/telemetry_last_pickup_time = -100

// ---------------------------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/New(mob/living/carbon/human/new_owner)
	. = ..()
	GLOB.bot_brains += src
	telemetry_last_activity = world.time
	if(!GLOB.bot_telemetry_running)
		GLOB.bot_telemetry_running = TRUE
		GLOB.bot_telemetry_log = "[GLOB.log_directory]/bot_telemetry.jsonl"
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(bot_telemetry_loop))
	telemetry_event("spawn", list("job" = owner?.mind?.assigned_role))

/datum/bot_brain/Destroy()
	GLOB.bot_brains -= src
	return ..()

/proc/bot_telemetry_loop()
	while(TRUE)
		for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
			if(!QDELETED(B) && !QDELETED(B.owner))
				B.telemetry_sample()
		sleep(BOT_TELEMETRY_SAMPLE_INTERVAL)

// ---------------------------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------------------------

/proc/bot_telemetry_short(path)
	var/text = "[path]"
	for(var/prefix in list("/datum/bot_goal/", "/datum/bot_strategy/", "/datum/bot_step/", "/obj/item/", "/obj/structure/", "/obj/machinery/"))
		if(findtext(text, prefix) == 1)
			return copytext(text, length(prefix) + 1)
	return text

/datum/bot_brain/proc/telemetry_write(list/record)
	if(!GLOB.bot_telemetry_log)
		return
	record["t"] = world.time
	record["b"] = owner ? owner.real_name : "?"
	WRITE_LOG(GLOB.bot_telemetry_log, json_encode(record))

/datum/bot_brain/proc/telemetry_event(kind, list/fields)
	var/list/record = list("k" = "e", "ev" = kind)
	if(fields)
		record += fields
	var/turf/T = get_turf(owner)
	if(T)
		record["x"] = T.x
		record["y"] = T.y
		record["z"] = T.z
	record["g"] = bot_telemetry_short(current_goal?.type)
	record["step"] = current_strategy && current_step_index ? bot_telemetry_short(current_strategy.steps[min(current_step_index, length(current_strategy.steps))]?.type) : null
	telemetry_write(record)
	telemetry_touch()

/datum/bot_brain/proc/telemetry_touch()
	telemetry_last_activity = world.time

/datum/bot_brain/proc/telemetry_flag(flag)
	LAZYSET(telemetry_flags, flag, LAZYACCESS(telemetry_flags, flag) + 1)

/// Where an item is relative to the bot, as a player would see it.
/datum/bot_brain/proc/telemetry_item_where(obj/item/I)
	if(!I || QDELETED(I))
		return "none"
	if(I == owner.get_active_held_item())
		return "active_hand"
	if(I == owner.get_inactive_held_item())
		return "inactive_hand"
	if(I.loc == owner)
		return "worn"
	if(I.loc && I.loc.loc == owner)
		return "carried:[bot_telemetry_short(I.loc.type)]" //in the bot's own backpack/belt/pocket storage
	if(isturf(I.loc))
		return "floor"
	return "in:[bot_telemetry_short(I.loc?.type)]"

/// Target position and whether the bot is facing it - a player's click always turns them toward what they click.
/datum/bot_brain/proc/telemetry_target_fields(atom/A)
	var/turf/TT = get_turf(A)
	var/turf/me = get_turf(owner)
	if(!TT || !me)
		return list()
	var/facing = (TT == me) || !!(get_dir(me, TT) & owner.dir)
	if(!facing)
		telemetry_flag("not_facing_target")
	return list("tx" = TT.x, "ty" = TT.y, "d" = owner.dir, "facing" = facing)

/datum/bot_brain/proc/telemetry_hands()
	var/obj/item/A = owner.get_active_held_item()
	var/obj/item/B = owner.get_inactive_held_item()
	return list("ah" = A ? "[A.name]" : null, "ih" = B ? "[B.name]" : null)

// ---------------------------------------------------------------------------------------------
// Sampling
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/telemetry_sample()
	var/turf/T = get_turf(owner)
	var/moved = 0
	if(T && telemetry_last_turf && T != telemetry_last_turf && T.z == telemetry_last_turf.z)
		moved = get_dist(T, telemetry_last_turf) //get_dist() is -1 for the same turf, hence the T != check
	telemetry_last_turf = T
	if(moved || telemetry_action)
		telemetry_touch()
	var/list/record = list(
		"k" = "s",
		"x" = T?.x, "y" = T?.y, "z" = T?.z,
		"d" = owner.dir,
		"mv" = moved,
		"st" = state,
		"g" = bot_telemetry_short(current_goal?.type),
		"sg" = bot_telemetry_short(current_strategy?.type),
		"step" = current_strategy && current_step_index ? bot_telemetry_short(current_strategy.steps[min(current_step_index, length(current_strategy.steps))]?.type) : null,
		"act" = telemetry_action,
		"pk" = pursuing_kind,
		"pl" = length(current_path),
		"u" = get_urgency(),
		"hp" = owner.health,
		"inc" = owner.incapacitated() ? 1 : 0,
		"int" = owner.a_intent,
	)
	record += telemetry_hands()
	telemetry_write(record)
	// Idle tracking: report a stretch once it ends, with what the bot was supposedly doing.
	var/idle_for = world.time - telemetry_last_activity
	if(idle_for >= BOT_TELEMETRY_IDLE_THRESHOLD && owner.stat == CONSCIOUS && !owner.incapacitated())
		if(!telemetry_idle_since)
			telemetry_idle_since = telemetry_last_activity
	else if(telemetry_idle_since)
		var/duration = world.time - telemetry_idle_since
		telemetry_idle_since = 0
		telemetry_flag("idle_3s")
		telemetry_write(list("k" = "e", "ev" = "idle", "dur" = duration, "x" = T?.x, "y" = T?.y, "z" = T?.z,
			"g" = bot_telemetry_short(current_goal?.type), "st" = state, "pk" = pursuing_kind))

// ---------------------------------------------------------------------------------------------
// Body hooks - every item movement on a bot, whichever code path caused it
// ---------------------------------------------------------------------------------------------

/mob/living/carbon/human/put_in_hand(obj/item/I, hand_index, forced = FALSE, ignore_anim = TRUE)
	if(!bot_brain || !I)
		return ..()
	var/atom/from = I.loc
	var/from_where = bot_brain.telemetry_item_where(I)
	var/dist = get_dist(src, get_turf(I))
	. = ..()
	if(.)
		bot_brain.telemetry_on_pickup(I, from, from_where, dist)

/datum/bot_brain/proc/telemetry_on_pickup(obj/item/I, atom/from, from_where, dist)
	if(from_where == "active_hand" || from_where == "inactive_hand")
		return //swapping hands, not a pickup
	var/drawn = findtext(from_where, "carried:") == 1 || from_where == "worn"
	var/gap = world.time - telemetry_last_pickup_time
	telemetry_last_pickup_time = world.time
	if(!drawn)
		if(dist > 1)
			telemetry_flag("remote_pickup")
		if(gap < 3)
			telemetry_flag("pickup_burst")
	telemetry_event(drawn ? "draw" : "pickup", list("item" = "[I.name]", "type" = bot_telemetry_short(I.type),
		"from" = from_where, "from_type" = bot_telemetry_short(from?.type), "dist" = dist, "since_last_pickup" = gap))

/mob/living/carbon/human/doUnEquip(obj/item/I, force, newloc, no_move, invdrop = TRUE)
	if(!bot_brain || !I)
		return ..()
	var/was = bot_brain.telemetry_item_where(I)
	. = ..()
	if(. && !QDELETED(I))
		var/now = isturf(I.loc) ? "floor" : "in:[bot_telemetry_short(I.loc?.type)]"
		bot_brain.telemetry_event(isturf(I.loc) ? "drop" : "unequip", list("item" = "[I.name]", "was" = was, "to" = now))

/mob/living/carbon/human/equip_to_slot(obj/item/I, slot)
	if(!bot_brain || !I)
		return ..()
	var/was = bot_brain.telemetry_item_where(I)
	. = ..()
	if(was == "floor" || findtext(was, "in:") == 1)
		bot_brain.telemetry_flag("equip_without_holding")
	bot_brain.telemetry_event("equip", list("item" = "[I.name]", "slot" = slot, "from" = was))

// ---------------------------------------------------------------------------------------------
// Interaction hooks
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/use_item_on(obj/item/I, atom/A, harm = FALSE)
	var/where = telemetry_item_where(I)
	var/started = world.time
	telemetry_action = "use [I] on [A]"
	. = ..()
	telemetry_action = null
	telemetry_event("use", list("item" = "[I]", "item_was" = where, "target" = "[A]", "target_type" = bot_telemetry_short(A?.type),
		"dist" = get_dist(owner, A), "harm" = harm, "dur" = world.time - started, "ok" = .) + telemetry_target_fields(A))

/datum/bot_brain/use_atom(atom/A)
	var/started = world.time
	telemetry_action = "click [A]"
	. = ..()
	telemetry_action = null
	telemetry_event("click", list("target" = "[A]", "target_type" = bot_telemetry_short(A?.type), "dist" = get_dist(owner, A),
		"dur" = world.time - started) + telemetry_target_fields(A))

/// Call right before a direct engine call that a player would perform by clicking with an item
/// (try_to_crowbar, attack_self, attackby...). Records whether the item was actually in hand.
/datum/bot_brain/proc/telemetry_shortcut(proc_name, obj/item/I, atom/target)
	var/where = telemetry_item_where(I)
	var/in_hand = (where == "active_hand" || where == "inactive_hand")
	var/worn_ok = (where == "worn" && istype(I, /obj/item/clothing)) //worn clothing toggled via its action button (magboots) is legitimate; a tool clipped to the belt is not
	if(!in_hand && !worn_ok)
		telemetry_flag("tool_not_in_hand")
	telemetry_event("shortcut", list("proc" = proc_name, "item" = "[I]", "item_was" = where, "in_hand" = in_hand, "legit" = in_hand || worn_ok,
		"target" = target ? "[target]" : null, "dist" = target ? get_dist(owner, target) : null) + (target ? telemetry_target_fields(target) : list()))

/// Call where the bot moves an object it isn't holding (forceMove etc) - never something a player can do.
/datum/bot_brain/proc/telemetry_teleport(atom/movable/AM, atom/destination)
	telemetry_flag("item_teleport")
	telemetry_event("teleport_item", list("item" = "[AM]", "from" = bot_telemetry_short(AM?.loc?.type),
		"to" = bot_telemetry_short(destination?.type), "dist" = get_dist(owner, AM)))

// ---------------------------------------------------------------------------------------------
// Goal hooks
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/assign_goal(datum/bot_goal/goal)
	. = ..()
	if(.)
		telemetry_event("goal_start", list("goal" = bot_telemetry_short(goal.type), "target" = "[goal.target]",
			"target_dist" = get_dist(owner, goal.target), "nested" = suspended_goal ? bot_telemetry_short(suspended_goal.type) : null))

/datum/bot_brain/goal_succeeded()
	telemetry_event("goal_end", list("goal" = bot_telemetry_short(current_goal?.type), "result" = "success"))
	return ..()

/datum/bot_brain/give_up_goal()
	telemetry_flag("gave_up")
	telemetry_event("goal_end", list("goal" = bot_telemetry_short(current_goal?.type), "result" = "gave_up"))
	return ..()

/// A machine panel button pressed the way a player would (SSU "dispense", etc) - legitimate, logged for pacing analysis.
/datum/bot_brain/proc/telemetry_ui_action(obj/machinery/M, action)
	telemetry_event("ui_action", list("machine" = "[M]", "action" = action, "dist" = get_dist(owner, M)) + telemetry_target_fields(M))
