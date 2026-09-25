/datum/bot_goal/acquire_captains_id/resolve_target(datum/bot_brain/bot)
	target = locate(/obj/structure/closet/secure_closet/captains) in world

/datum/bot_goal/acquire_captains_id/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/id_access(), new /datum/bot_strategy/emag(), new /datum/bot_strategy/brute_force())

/datum/bot_strategy/id_access/New()
	. = ..()
	// Gather the full hacking kit BEFORE even setting off, not reactively at the door.
	// The captain's office is known (empirically - see GOAP_REFERENCE.md's access
	// research) to sit behind a command-tier airlock with shielded wiring, so a bot
	// without captain access is essentially certain to need all five tools to get in
	// regardless of which strategy eventually opens the closet. Discovering that only
	// after walking all the way to the door, failing, walking all the way to fetch ONE
	// tool, walking back, failing again on the next missing tool, etc. is exactly the
	// thrashing a real player would never do - they'd check their toolbelt first. See
	// ensure_tools below.
	steps = list(new /datum/bot_step/ensure_tools(), new /datum/bot_step/move_to(), new /datum/bot_step/interact(), new /datum/bot_step/pickup_from_target(/obj/item/card/id/captains_spare))

// Deliberately always feasible, not gated on actually having captain access: a real
// person doesn't pre-compute whether their ID will work before walking over, they just
// go try the door. This is also the strategy whose move_to step is what actually
// exercises try_hack_door()'s reinforced-airlock stripping (bot_items.dm) - a bot
// without captain access but carrying the full tool kit can still hack its way into
// the office even though it'll fail at the closet itself and fall through to
// emag/brute_force. Gating this on GetAccess() (as it used to) meant every strategy
// required some prerequisite already in hand, so a bare-handed bot with nothing gave
// up instantly without ever trying.
/datum/bot_strategy/id_access/is_feasible(datum/bot_brain/bot)
	return TRUE

// Everything strip_airlock_security()/try_hack_door() (bot_items.dm) actually needs to
// wire-hack a command-tier airlock open from scratch. Insulated gloves aren't a tool,
// but they belong in this same "go get this before setting off" list for the same
// reason the tools do - a real electrician wouldn't touch a live panel bare-handed any
// more than they'd try it without a screwdriver, and equip_insulated_gloves()
// (bot_items.dm) needs them in hand/worn before every hands-on airlock interaction to
// actually stop the shock airlock/attackby() can deal out.
GLOBAL_LIST_INIT(captains_id_required_tools, list(
	/obj/item/screwdriver,
	/obj/item/wirecutters,
	/obj/item/weldingtool,
	/obj/item/crowbar,
	/obj/item/multitool,
	/obj/item/clothing/gloves/color/yellow,
))

/datum/bot_step/ensure_tools
	// Tracks whether a toolbelt fetch has already been attempted this strategy attempt
	// (persists across suspend/resume - this step instance isn't recreated by
	// resume_goal(), only current_goal/current_strategy get stashed and restored, see
	// bot_items.dm's seek_tool_for_obstacle()) - so a station with no toolbelt anywhere
	// doesn't burn a fresh goal_suspend_count cycle EVERY single re-check.
	var/tried_toolbelt = FALSE
	// Same one-shot idea as tried_toolbelt above, for consolidate_id_into_pda()
	// (bot_items.dm) - only worth attempting once regardless of whether it succeeded
	// (no PDA carried, say), never worth retrying on every re-check.
	var/tried_id_consolidation = FALSE
	// Per-tool-type fetch attempt counts, see execute()'s loop.
	var/list/fetch_attempts
	var/tried_refuel = FALSE
	var/tried_axe = FALSE

// Blocks the rest of the strategy until the bot is actually carrying every tool it
// will need - see id_access/New()'s comment for why this runs first instead of
// reactively at the door. Skips the requirement entirely if the bot already has
// legitimate captain access, since then it was never going to need to hack anything.
/datum/bot_step/ensure_tools/execute(datum/bot_brain/bot)
	var/obj/item/card/id/id_card = bot.owner.get_idcard(TRUE)
	if(id_card && (ACCESS_CAPTAIN in id_card.GetAccess()))
		bot_log_verbose(bot, "ensure_tools: already have captain access, skipping the tool check entirely")
		return GOAL_STEP_SUCCESS

	if(!tried_id_consolidation)
		tried_id_consolidation = TRUE
		bot.consolidate_id_into_pda()

	// Every one of the 5 required tools only declares ITEM_SLOT_BELT as a valid worn
	// slot (tools.dm) - so with no container, real carrying capacity is 1 belt slot +
	// 2 hands = 3 tools, one short of what this hack needs. A toolbelt
	// (/obj/item/storage/belt/utility) holds all of them in that SAME one belt slot,
	// which is worth grabbing if there's one right there - but it's still genuinely
	// optional (3 tools' worth of capacity gets by, just more cramped, and
	// pickup_tool_from_target()/stow_item() already cope with that), not worth a
	// dedicated trip across half the station for. Only bother if one's actually
	// nearby; a full station-wide hunt for something optional is exactly the kind of
	// detour a real person wouldn't bother with for a job this replaceable.
	var/obj/item/storage/belt/utility/belt = locate(/obj/item/storage/belt/utility) in bot.owner
	if(!tried_toolbelt && !belt)
		tried_toolbelt = TRUE
		var/obj/item/storage/belt/utility/nearby_belt = locate(/obj/item/storage/belt/utility) in oview(20, bot.owner)
		if(nearby_belt)
			bot_log(bot, "spotted a toolbelt nearby - grabbing it so every tool has somewhere to go")
			if(bot.seek_tool_for_obstacle(/obj/item/storage/belt/utility))
				return GOAL_STEP_PENDING
		else
			bot_log(bot, "no toolbelt nearby - not worth a special trip, continuing with bare hands/belt only")
	else if(belt && bot.owner.belt != belt)
		// Just being carried (in a hand, or - impossible for a belt-slot item, but
		// defensively checked anyway) isn't the same as actually WORN - equip_to_
		// appropriate_slot() (mob.dm) only equips into an EMPTY slot, so this can only
		// ever fail here if something else is already occupying the belt slot; in that
		// case there's nothing more to do, the tool-stowing fallback (stow_item(),
		// bot_items.dm) still works fine on a merely-held toolbelt anyway.
		bot.owner.equip_to_appropriate_slot(belt)

	var/list/have = list()
	var/list/missing = list()
	for(var/tool_type in GLOB.captains_id_required_tools)
		// can_eventually_provide_tool() (bot_items.dm), not find_carried_tool() directly -
		// crowbar and wirecutters are, on this list, potentially the SAME physical
		// "jaws of life" tool (crowbar/power <-> wirecutters/power): a bot currently
		// holding it in crowbar form would otherwise report wirecutters "missing" and go
		// fetch an entirely separate, redundant pair. can_eventually_provide_tool()
		// falls back to exactly find_carried_tool()'s own behavior for any type that
        // isn't part of a transform pair, so this is a strict improvement, not a
		// behavior change, for screwdriver/weldingtool/multitool/gloves. Also still
		// checks one level into a worn toolbelt/backpack via find_carried_tool()
		// internally - a plain "locate(type) in bot.owner" used to miss anything
		// stow_item() had put INTO the toolbelt (everything past the first 1-2 tools,
		// once the belt slot itself was taken), so a bot that had genuinely already
		// gathered everything kept reporting it all missing and going back out for more.
		if(bot.can_eventually_provide_tool(tool_type))
			have += tool_type
		else
			missing += tool_type
	bot_log_verbose(bot, "ensure_tools: have [have.len ? english_list(have) : "nothing"], missing [missing.len ? english_list(missing) : "nothing"]")
	// Best-effort: try each missing tool in turn, skipping any type already tried twice
	// (a source can "succeed" without actually delivering that type) or that no
	// reachable source exists for. Failing to find ONE tool used to fail the entire
	// strategy before it ever reached the door; now the bot proceeds with what it has
	// (the door hack itself still suspends to fetch anything critical it lacks).
	for(var/tool_type in missing)
		if(LAZYACCESS(fetch_attempts, tool_type) >= 2)
			continue
		LAZYSET(fetch_attempts, tool_type, LAZYACCESS(fetch_attempts, tool_type) + 1)
		if(bot.seek_tool_for_obstacle(tool_type))
			return GOAL_STEP_PENDING
		bot_log(bot, "couldn't find a source for [tool_type] - moving on without it")
		LAZYSET(fetch_attempts, tool_type, 2)
	if(missing.len)
		bot_log(bot, "done gathering - still missing [english_list(missing)], going ahead with what I have")
	// PREPARATION, not reaction: everything the break-in is known to need gets sorted out
	// here, before setting off - a nearly full welder (several shielded doors, ~6 units
	// each) and the fire axe (smashes tables and plain doors, and is the fallback that
	// breaks the locker itself). Otherwise the bot walks up to the captain's door and only
	// THEN realizes it's short of fuel/a weapon, and walks past the cabinet on the way.
	if(!tried_refuel && bot.welder_needs_fuel(18))
		tried_refuel = TRUE
		if(bot.suspend_goal_for(new /datum/bot_goal/acquire_fuel()))
			return GOAL_STEP_PENDING
	if(!tried_axe && !bot.has_strong_weapon() && bot.find_carried_tool(/obj/item/multitool))
		tried_axe = TRUE
		bot_log(bot, "getting the fire axe now, before heading for the captain's office")
		if(bot.suspend_goal_for(new /datum/bot_goal/acquire_fireaxe()))
			return GOAL_STEP_PENDING
	return GOAL_STEP_SUCCESS

/datum/bot_strategy/emag/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/use_item(item_type = /obj/item/card/emag), new /datum/bot_step/interact(), new /datum/bot_step/pickup_from_target(/obj/item/card/id/captains_spare))

/datum/bot_strategy/emag/is_feasible(datum/bot_brain/bot)
	return locate(/obj/item/card/emag) in bot.owner

/datum/bot_strategy/brute_force
	max_attempts = 1

/datum/bot_strategy/brute_force/New()
	. = ..()
	steps = list(new /datum/bot_step/ensure_weapon(), new /datum/bot_step/move_to(), new /datum/bot_step/attack_until_broken(), new /datum/bot_step/interact(), new /datum/bot_step/pickup_from_target(/obj/item/card/id/captains_spare))

// Deliberately always feasible, same reasoning as id_access/is_feasible() above - the
// strategy now proactively fetches (and wields) a fire axe itself via ensure_weapon
// below rather than needing one already in hand to even be considered. Gating this on
// force>=20 up front (what it used to check) meant a bot that hadn't stumbled across a
// strong enough weapon by pure luck could never even ATTEMPT brute force, no matter how
// badly id_access/emag had already failed.
/datum/bot_strategy/brute_force/is_feasible(datum/bot_brain/bot)
	return TRUE

// Guarantees the bot is holding (and wielding, for a two-handed weapon like the fire
// axe) something with force>=20 - attack_until_broken's own threshold - before the rest
// of brute_force even tries to swing. Whatever's already in hand is good enough if it
// already clears that bar (a real, if unlikely, find); otherwise this fetches the fire
// axe specifically via suspend_goal_for() (bot_items.dm, the same suspend/resume
// machinery ensure_tools uses for ordinary tools), the one weapon this whole design
// guarantees exists and is reachable (opened with just a multitool, see
// acquire_fireaxe below) rather than hoping the bot happens to be carrying something
// else strong enough.
/datum/bot_step/ensure_weapon
	// One-shot per strategy attempt, same idea as ensure_tools' tried_* vars - persists
	// across the suspend/resume cycle (this step instance isn't recreated by
	// resume_goal()), so a station with no fire axe anywhere doesn't burn a fresh
	// goal_suspend_count cycle every single re-check.
	var/tried_fireaxe = FALSE
	var/tried_multitool = FALSE

/datum/bot_step/ensure_weapon/execute(datum/bot_brain/bot)
	bot.recover_set_down_items()
	if(bot.ready_fireaxe())
		return GOAL_STEP_SUCCESS

	var/obj/item/I = bot.owner.get_active_held_item()
	if(I && I.force >= 20)
		return GOAL_STEP_SUCCESS

	// The cabinet only opens with a multitool - get one first if it's missing.
	if(!tried_multitool && !bot.find_carried_tool(/obj/item/multitool))
		tried_multitool = TRUE
		if(bot.seek_tool_for_obstacle(/obj/item/multitool))
			return GOAL_STEP_PENDING

	if(!tried_fireaxe)
		tried_fireaxe = TRUE
		if(bot.suspend_goal_for(new /datum/bot_goal/acquire_fireaxe()))
			return GOAL_STEP_PENDING
		bot_log(bot, "couldn't find a fire axe anywhere reachable")

	return GOAL_STEP_FAIL

// A dedicated sub-goal for ensure_weapon above, built on acquire_tool's reachability
// machinery (same_z(), the two-phase pick_reachable()/is_reachable(), the
// failed-target blacklist) via parent_type - a fire axe cabinet needs exactly the same
// "is there an actual walkable/hackable route to this container" reasoning a tool closet
// does, just scanning a different object type and with its own get_strategies() (the
// cabinet's specific unlock/open/take sequence below, nothing to do with
// grab_tool_from_locker/grab_tools_from_toolbox).
/datum/bot_goal/acquire_fireaxe
	parent_type = /datum/bot_goal/acquire_tool

/datum/bot_goal/acquire_fireaxe/resolve_target(datum/bot_brain/bot)
	var/list/candidates = list()
	var/list/dists = list()
	// A fire axe lying loose (one this bot or another set down) beats walking to a cabinet:
	// no unlocking, and usually far closer - a bot once walked past one on the floor to go
	// to the Atmospherics cabinet.
	for(var/obj/item/twohanded/fireaxe/F as anything in bot_instances_of(/obj/item/twohanded/fireaxe))
		if(QDELETED(F) || !isturf(F.loc) || bot.is_failed_tool_target(F) || !same_z(bot, F))
			continue
		insert_by_distance(candidates, dists, F, max(0, get_dist(bot.owner, F) - 10))
	for(var/obj/structure/fireaxecabinet/C as anything in bot_instances_of(/obj/structure/fireaxecabinet))
		if(QDELETED(C) || !C.fireaxe || bot.is_failed_tool_target(C) || !same_z(bot, C))
			continue
		insert_by_distance(candidates, dists, C, get_dist(bot.owner, C))
	target = pick_reachable(bot, candidates)

/datum/bot_goal/acquire_fireaxe/get_strategies(datum/bot_brain/bot)
	bot_log(bot, "heading to [target] @ [bot_coord(get_turf(target))] ([get_area_name(target)]) to get the fire axe")
	if(istype(target, /obj/item/twohanded/fireaxe))
		return list(new /datum/bot_strategy/grab_loose_fireaxe())
	return list(new /datum/bot_strategy/get_fireaxe())

/datum/bot_strategy/grab_loose_fireaxe/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/pickup_item())

/datum/bot_strategy/grab_loose_fireaxe/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_strategy/get_fireaxe/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/open_fireaxe_cabinet())

/datum/bot_strategy/get_fireaxe/is_feasible(datum/bot_brain/bot)
	return TRUE

// The real 3-step sequence /obj/structure/fireaxecabinet (fireaxe.dm) actually needs:
// a multitool unlocks it (attackby()'s TOOL_MULTITOOL branch -> toggle_lock(), its own
// do_after(20) - a normal synchronous call here already waits that out, same as
// strip_airlock_security()'s welder/wirecutters calls, bot_items.dm), a bare-hand click
// opens it (attack_hand(), refuses outright while still locked), and a second bare-hand
// click takes the axe out. Wielding it at the end matters, not just cosmetic - the axe's
// own force is only 5 unwielded (force_unwielded, twohanded.dm) and only 24
// (force_wielded) once .wield() is called, and attack_until_broken() needs >=20 to do
// anything at all.
/datum/bot_step/open_fireaxe_cabinet/execute(datum/bot_brain/bot)
	var/obj/structure/fireaxecabinet/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || !bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	if(!C.fireaxe)
		bot_log(bot, "the fire axe cabinet is already empty")
		return GOAL_STEP_FAIL

	if(C.locked)
		var/obj/item/multitool/mt = bot.find_carried_tool(/obj/item/multitool)
		if(!mt)
			bot_log(bot, "need a multitool to unlock the fire axe cabinet")
			return GOAL_STEP_FAIL
		// A table climb (very common on the way to a bridge cabinet) leaves the bot stunned
		// for a moment, and the cabinet's own do_after() refuses to run while incapacitated
		// - the unlock silently failed. Wait the stun out, and allow one retry.
		var/waited_ticks = 0
		while((bot.owner.incapacitated() || !(bot.owner.mobility_flags & MOBILITY_USE)) && waited_ticks < 40)
			sleep(2)
			waited_ticks += 2
		bot_log(bot, "unlocking the fire axe cabinet")
		for(var/attempt in 1 to 2)
			bot.use_item_on(mt, C)
			if(!C.locked)
				break
			sleep(5)
		if(C.locked)
			bot_log(bot, "couldn't unlock the fire axe cabinet")
			return GOAL_STEP_FAIL
		bot.stow_or_drop(mt)

	if(!C.open)
		bot.use_atom(C)
	if(!C.open)
		bot_log(bot, "couldn't get the fire axe cabinet open")
		return GOAL_STEP_FAIL

	// wield() (twohanded.dm) refuses unless the OTHER hand is completely empty, and
	// attack_hand()'s put_in_hands() (taking the axe out, right below) prefers the
	// active hand - clearing both out first means the axe lands cleanly instead of
	// needing a second pass to free up whatever's left over.
	bot.free_hand_for(null)
	if(C.fireaxe)
		bot.use_atom(C)
	if(!bot.find_carried_tool(/obj/item/twohanded/fireaxe))
		bot_log(bot, "couldn't get the fire axe out of the cabinet")
		return GOAL_STEP_FAIL
	if(!bot.ready_fireaxe())
		bot_log(bot, "couldn't get a proper two-handed grip on the fire axe")
		return GOAL_STEP_FAIL
	bot_log(bot, "got the fire axe, ready to swing it")
	return GOAL_STEP_SUCCESS

// Refill a nearly-empty welder at a fuel tank (a shielded airlock strip burns most of a
// full welder, and an empty one silently blocks every shielded door after that). Same
// parent_type reuse of acquire_tool's reachability machinery as acquire_fireaxe above.
/datum/bot_goal/acquire_fuel
	parent_type = /datum/bot_goal/acquire_tool

/datum/bot_goal/acquire_fuel/resolve_target(datum/bot_brain/bot)
	var/list/candidates = list()
	var/list/dists = list()
	for(var/obj/structure/reagent_dispensers/fueltank/T as anything in bot_instances_of(/obj/structure/reagent_dispensers/fueltank))
		if(QDELETED(T) || bot.is_failed_tool_target(T) || !same_z(bot, T))
			continue
		if(!T.reagents || !T.reagents.has_reagent(/datum/reagent/fuel))
			continue
		insert_by_distance(candidates, dists, T, get_dist(bot.owner, T))
	target = pick_reachable(bot, candidates)

/datum/bot_goal/acquire_fuel/get_strategies(datum/bot_brain/bot)
	bot_log(bot, "heading to [target] @ [bot_coord(get_turf(target))] ([get_area_name(target)]) to refill my welder")
	return list(new /datum/bot_strategy/refuel_welder())

/datum/bot_strategy/refuel_welder/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/refuel_welder())

/datum/bot_strategy/refuel_welder/is_feasible(datum/bot_brain/bot)
	return !!bot.find_carried_tool(/obj/item/weldingtool)

// fueltank/attackby() (reagent_dispenser.dm) refills a welder that's switched OFF and
// EXPLODES the tank if it's lit - so make sure it's off first.
/datum/bot_step/refuel_welder/execute(datum/bot_brain/bot)
	var/obj/structure/reagent_dispensers/fueltank/T = bot.current_goal?.target
	var/obj/item/weldingtool/W = bot.find_carried_tool(/obj/item/weldingtool)
	if(!istype(T) || QDELETED(T) || !W || !bot.owner.Adjacent(T))
		return GOAL_STEP_FAIL
	if(W.welding)
		W.attack_self(bot.owner)
	if(W.welding)
		bot_log(bot, "can't switch my welder off - not risking the fuel tank")
		return GOAL_STEP_FAIL
	bot.use_item_on(W, T)
	if(W.get_fuel() < W.max_fuel * 0.5)
		bot_log(bot, "couldn't refill my welder at [T]")
		return GOAL_STEP_FAIL
	bot_log(bot, "refilled my welder")
	bot.stow_or_drop(W)
	bot.recover_set_down_items()
	return GOAL_STEP_SUCCESS

/datum/bot_step/attack_until_broken
	var/swings = 0
	var/tried_rearm = FALSE

/datum/bot_step/attack_until_broken/execute(datum/bot_brain/bot)
	var/obj/structure/closet/C = bot.current_goal?.target
	if(!istype(C) || !bot.owner.Adjacent(C))
		bot_log(bot, "not next to the locker - can't swing at it")
		return GOAL_STEP_FAIL
	if(C.broken || !C.locked)
		put_weapon_away(bot)
		return GOAL_STEP_SUCCESS
	var/obj/item/I = bot.owner.get_active_held_item()
	if(!I || I.force < 20)
		// Hack/tool use between steps may have stowed and unwielded the axe, or set it down.
		bot.recover_set_down_items()
		bot.ready_fireaxe()
		I = bot.owner.get_active_held_item()
	if(!I || I.force < 20)
		// Still nothing (the axe got displaced somewhere untracked, e.g. picking a tool up
		// into an occupied hand drops what was there): go find a fire axe - a loose one
		// nearby, else a cabinet - and come back to this same step.
		if(!tried_rearm)
			tried_rearm = TRUE
			bot_log(bot, "lost my weapon - going to find a fire axe again")
			if(bot.suspend_goal_for(new /datum/bot_goal/acquire_fireaxe()))
				return GOAL_STEP_PENDING
		bot_log(bot, "nothing strong enough in hand to break the locker (holding [I ? I : "nothing"])")
		return GOAL_STEP_FAIL
	swings++
	if(swings > 15)
		return GOAL_STEP_FAIL
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.use_item_on(I, C, TRUE)
	if(C.broken || !C.locked)
		put_weapon_away(bot)
		return GOAL_STEP_SUCCESS
	addtimer(CALLBACK(src, PROC_REF(retry), bot), CLICK_CD_MELEE)
	return GOAL_STEP_PENDING

// A wielded fire axe fills BOTH hands, so the next steps (open the locker, pick the ID
// up) couldn't take anything - the locker was broken open, but the bot never got the ID
// out of it. Put the axe down first.
/datum/bot_step/attack_until_broken/proc/put_weapon_away(datum/bot_brain/bot)
	var/obj/item/twohanded/W = bot.owner.get_active_held_item()
	if(istype(W) && W.wielded)
		bot.stow_or_drop(W)

/datum/bot_step/attack_until_broken/proc/retry(datum/bot_brain/bot)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return
	bot.run_current_step()

// TEMPORARY debug hook: nothing else constructs a bot_goal yet. Throwaway test
// scaffolding, not part of the goal system's API.
/client/proc/admin_assign_captains_id_goal()
	set name = "Assign Bot Goal: Captain's Spare ID"
	set category = "Fun"
	set desc = "Debug: assigns the acquire_captains_id GOAP goal to a selected bot."

	if(!check_rights(R_FUN))
		return
	var/list/bots = list()
	for(var/mob/living/carbon/human/H in GLOB.bot_crew_members)
		bots[H.real_name] = H
	if(!bots.len)
		to_chat(usr, "<span class='warning'>No bot crew members exist.</span>")
		return
	var/picked = input(usr, "Pick a bot", "Assign Goal") as null|anything in bots
	if(!picked)
		return
	var/mob/living/carbon/human/H = bots[picked]
	if(!H.bot_brain)
		return
	if(H.bot_brain.assign_goal(new /datum/bot_goal/acquire_captains_id()))
		message_admins("[key_name(usr)] assigned [H] the acquire_captains_id goal.")
	else
		to_chat(usr, "<span class='warning'>Couldn't assign goal (already pursuing one, or no target found).</span>")
