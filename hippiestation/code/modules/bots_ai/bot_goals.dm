#define GOAL_STEP_PENDING 0
#define GOAL_STEP_SUCCESS 1
#define GOAL_STEP_FAIL -1

/datum/bot_goal
	var/atom/target
	var/list/datum/bot_strategy/strategies
	var/flavor_success //optional line said aloud on success, see goal_succeeded()

/datum/bot_goal/proc/resolve_target(datum/bot_brain/bot)
	return

/datum/bot_goal/proc/get_strategies(datum/bot_brain/bot)
	return list()

// Called by give_up_goal() right before it ends this goal - a hook for a goal to
// remember why it failed so a future resolve_target() call doesn't just pick the exact
// same doomed target again. See acquire_tool's override: resolve_target() there picks
// the nearest tool by raw distance with no reachability check, so a target on the far
// side of a currently-unreachable door would otherwise get re-picked on every retry.
/datum/bot_goal/proc/on_give_up(datum/bot_brain/bot)
	return

// Called by goal_succeeded() right before it ends this goal - the positive-memory
// counterpart to on_give_up() above. See acquire_tool's override: a closet/toolbox that
// actually yielded a tool gets remembered so a future acquire_tool prefers it over
// re-scanning the whole station from scratch.
/datum/bot_goal/proc/on_success(datum/bot_brain/bot)
	return

/datum/bot_strategy
	var/list/datum/bot_step/steps
	var/attempts = 0
	var/max_attempts = 1

/datum/bot_strategy/proc/is_feasible(datum/bot_brain/bot)
	return FALSE

/datum/bot_step/proc/execute(datum/bot_brain/bot)
	return GOAL_STEP_FAIL

/datum/bot_step/move_to
	var/atom/step_target

/datum/bot_step/move_to/execute(datum/bot_brain/bot)
	// Each shielded airlock strip burns ~6 units of welding fuel, and route planning refuses
	// shielded doors once the welder can't fully strip one - so a bot that spent its fuel on
	// the doors so far got "no path" to the captain's locker from the Bridge (right after
	// fetching the axe) and gave the whole goal up. Top up BEFORE setting off on the leg.
	// Not once the bot is already at/near the locker or has moved on to brute force: every
	// shielded door is behind it by then and fuel no longer matters (it stood at the locker
	// and went off to refill its welder).
	if(istype(bot.current_goal, /datum/bot_goal/acquire_captains_id) && !bot.suspended_goal 		&& !istype(bot.current_strategy, /datum/bot_strategy/brute_force) 		&& bot.current_goal.target && get_dist(bot.owner, bot.current_goal.target) > 12 		&& world.time >= bot.fuel_retry_time && bot.welder_needs_fuel())
		bot.fuel_retry_time = world.time + 1800
		bot_log(bot, "my welder is low on fuel - topping it up before the next stretch")
		if(bot.suspend_goal_for(new /datum/bot_goal/acquire_fuel()))
			return GOAL_STEP_PENDING
	var/atom/T = step_target || bot.current_goal?.target
	if(!T)
		return GOAL_STEP_FAIL
	// acquire_tool (goals/acquire_tool.dm) may have already verified a real path to
	// this exact target while picking it as a candidate - reuse it directly instead of
	// letting pursue() run a brand new search that isn't guaranteed to find the same
	// route (see is_reachable()'s comment). One-shot: cleared the moment it's read, so
	// a LATER retry against the same target (after failing partway, say) always gets a
	// fresh, current search rather than a stale cached one.
	var/list/cached
	var/datum/bot_goal/acquire_tool/AT = bot.current_goal
	if(istype(AT) && AT.cached_path_target == T && AT.cached_path && AT.cached_path.len)
		cached = AT.cached_path
		AT.cached_path = null
		AT.cached_path_target = null
	bot.pursue(T, "goal", force = TRUE, precomputed_path = cached)
	return GOAL_STEP_PENDING

/datum/bot_step/interact
	var/atom/step_target

/datum/bot_step/interact/execute(datum/bot_brain/bot)
	var/atom/T = step_target || bot.current_goal?.target
	if(!T)
		return GOAL_STEP_FAIL
	// Breaking a locker's lock bust_open()s it (closets.dm: the lock breaks AND open() is
	// called), so a locker smashed with the axe is already standing open - and a bare-hand
	// click on an open closet CLOSES it, which is exactly how the bot broke the locker,
	// then shut it again and couldn't take the ID.
	if(istype(T, /obj/structure/closet))
		var/obj/structure/closet/C = T
		if(C.opened)
			return GOAL_STEP_SUCCESS
		return bot.open_closet(C) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL //unlock-then-open, see open_closet() (bot_items.dm)
	return bot.use_atom(T) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/use_item
	var/item_type
	var/atom/step_target

/datum/bot_step/use_item/New(item_type, atom/step_target)
	. = ..()
	src.item_type = item_type
	src.step_target = step_target

/datum/bot_step/use_item/execute(datum/bot_brain/bot)
	var/atom/T = step_target || bot.current_goal?.target
	var/obj/item/I = item_type ? (locate(item_type) in bot.owner) : null
	if(!T || !I)
		return GOAL_STEP_FAIL
	return bot.use_item_on(I, T) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/pickup_from_target
	var/item_type

/datum/bot_step/pickup_from_target/New(item_type)
	. = ..()
	src.item_type = item_type

/datum/bot_step/pickup_from_target/execute(datum/bot_brain/bot)
	var/atom/T = bot.current_goal?.target
	if(!T)
		return GOAL_STEP_FAIL
	// Both hands busy with a wielded two-hander means nothing can be picked up.
	var/obj/item/twohanded/held_two = bot.owner.get_active_held_item()
	if(istype(held_two) && held_two.wielded)
		bot.stow_or_drop(held_two)
	// A closet's `contents` list holds its items regardless of `opened` - BYOND's
	// `for(var/x in container)` walks contents directly, it isn't gated by any
	// gameplay-visible "is this actually open" flag. Without this check, a strategy
	// whose interact step silently failed (e.g. attack_hand() denied for lack of
	// access) would still let this step reach in and grab the item anyway, making the
	// whole point of id_access/emag/brute_force as distinct strategies moot.
	if(istype(T, /obj/structure/closet))
		var/obj/structure/closet/C = T
		if(!C.opened)
			bot_log_verbose(bot, "pickup_from_target: [C] isn't open (locked=[C.locked], broken=[C.broken], welded=[C.welded])")
			return GOAL_STEP_FAIL
	// /obj/structure/closet/open() (closets.dm) calls dump_contents() the instant it
	// opens, which forceMove()s everything straight out onto the closet's turf - so by
	// the time this step runs (right after interact opened it), the item is no longer
	// "in" T at all. Search both: T itself, for anything that DOESN'T dump on open
	// (most non-closet targets), and T's turf, for the closet case.
	for(var/obj/item/I in T)
		if(item_type && !istype(I, item_type))
			continue
		if(bot.try_pickup_target(I))
			return GOAL_STEP_SUCCESS
	var/turf/drop_turf = get_turf(T)
	if(drop_turf && drop_turf != T)
		for(var/obj/item/I in drop_turf)
			if(item_type && !istype(I, item_type))
				continue
			if(bot.try_pickup_target(I))
				return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

// Grabs every tool it can find at the target, not just the first - a locked airlock
// hack needs a whole set (screwdriver, wirecutters, welder, crowbar, multitool), and a
// real person clearing out a tool locker takes everything useful in one trip rather
// than walking back and forth once per tool. Paced one item per CLICK_CD_MELEE, the
// same cadence handle_combat()/attack_until_broken() already use for every other
// hands-on action - grabbing all 5 in a single synchronous instant read as an obviously
// inhuman "vacuum" rather than someone actually picking things up one at a time.
/datum/bot_step/pickup_tool_from_target
	var/list/obj/item/pending_items
	var/got_any = FALSE
	// True if the target actually had at least one useful tool in it, even if every
	// single one got filtered out as a duplicate the bot already carries - see
	// grab_next()'s comment for why this matters separately from got_any.
	var/saw_any_tool = FALSE
	// The container being emptied (a toolbox's contents sit INSIDE it, not on a turf).
	var/atom/pickup_source
	// True if at least one non-duplicate tool was actually targeted for pickup.
	var/had_pending = FALSE

/datum/bot_step/pickup_tool_from_target/execute(datum/bot_brain/bot)
	var/atom/T = bot.current_goal?.target
	if(!T)
		return GOAL_STEP_FAIL
	// A closet's `contents` list holds its items regardless of `opened` - BYOND's
	// `for(var/x in container)` below walks contents directly, unguarded by any
	// gameplay-visible "is this actually open" flag (the exact same gotcha
	// pickup_from_target, below, already guards against). Without this check, a bot
	// could reach into a closed-but-UNLOCKED locker's contents and take tools straight
	// through the shut door - interact() (the step immediately before this one in
	// grab_tool_from_locker, acquire_tool.dm) is supposed to have already opened it, but
	// nothing here ever verified that actually happened before reading contents.
	if(istype(T, /obj/structure/closet))
		var/obj/structure/closet/C = T
		if(!C.opened)
			bot_log_verbose(bot, "pickup_tool_from_target: [C] isn't open (locked=[C.locked], broken=[C.broken], welded=[C.welded])")
			return GOAL_STEP_FAIL
	// Came for something specific and already have it (grabbed it in passing, say): done - don't
	// rummage through the locker anyway. Telemetry caught a bot that already had the insulated
	// gloves walk on to the electrical locker and take the toolbox out of it.
	var/datum/bot_goal/acquire_tool/fetch = bot.current_goal
	var/needed_type = istype(fetch) ? fetch.needed_tool_type : null
	if(!pending_items && bot.tool_need_already_satisfied())
		return GOAL_STEP_SUCCESS
	if(!pending_items)
		pending_items = list()
		saw_any_tool = FALSE
		pickup_source = T
		// already_carries_matching_tool() (bot_items.dm) skips a specific tool type the
		// bot already has one of - one screwdriver does the job exactly as well as two,
		// and grabbing a duplicate here used to be exactly the kind of pointless
		// "successful" trip that left the bot no better equipped than before it
		// started. A toolbox target itself never matches this (the check only ever
		// matches actual tool types), so it's always still worth grabbing.
		for(var/obj/item/I in T)
			if(!bot.is_tool_or_toolbox(I))
				continue
			saw_any_tool = TRUE
			if(bot_wants_from_locker(bot, I, needed_type))
				pending_items += I
		// /obj/structure/closet/open() dumps its contents onto its own turf the instant
		// it opens (see pickup_from_target's comment above) - a toolbox item's own
		// storage contents aren't affected by this, only a closet/locker target is.
		if(istype(T, /obj/structure/closet))
			var/turf/drop_turf = get_turf(T)
			if(drop_turf && drop_turf != T)
				for(var/obj/item/I in drop_turf)
					if(!bot.is_tool_or_toolbox(I))
						continue
					saw_any_tool = TRUE
					if(bot_wants_from_locker(bot, I, needed_type))
						pending_items += I
		// A specific need is met by one item - take the first match, not every copy.
		if(needed_type && length(pending_items) > 1)
			pending_items.Cut(2)
		got_any = FALSE
		had_pending = pending_items.len > 0
	return grab_next(bot)

/datum/bot_step/pickup_tool_from_target/proc/grab_next(datum/bot_brain/bot)
	while(pending_items.len)
		var/obj/item/I = pending_items[1]
		pending_items.Cut(1, 2)
		// Items inside the target toolbox legitimately have loc == the toolbox, not a turf -
		// requiring a turf here skipped every one of them, so a toolbox trip "succeeded"
		// (saw_any_tool) having picked up nothing at all.
		if(QDELETED(I) || (!isturf(I.loc) && I.loc != pickup_source))
			continue //picked up by someone/something else, or otherwise gone, since this step started
		if(bot.try_pickup_target(I))
			got_any = TRUE
		bot.owner.changeNext_move(CLICK_CD_MELEE)
		if(pending_items.len)
			addtimer(CALLBACK(src, PROC_REF(continue_grab), bot), CLICK_CD_MELEE)
			return GOAL_STEP_PENDING
		break
	// !got_any doesn't necessarily mean this trip was pointless - grab_passing_tools()
	// (bot_movement.dm) can grab the exact tool this container was going to provide
	// WHILE the bot was still walking here (it runs on every step of the pursuit, not
	// just on arrival), so by the time this step actually ran, everything left in the
	// box was correctly skipped as an already-carried duplicate. That's the goal
	// succeeding via a shortcut, not the strategy failing - reporting FAIL here used to
	// blacklist (on_give_up(), goals/acquire_tool.dm) a perfectly good, still-useful
	// toolbox for the crime of the bot getting lucky on the way there.
	var/result = got_any || (saw_any_tool && !had_pending)
	pending_items = null
	got_any = FALSE
	saw_any_tool = FALSE
	return result ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/pickup_tool_from_target/proc/continue_grab(datum/bot_brain/bot)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return //goal moved on (succeeded/failed/replaced) while we were waiting - don't act on stale state
	var/result = grab_next(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_step/pickup_item/execute(datum/bot_brain/bot)
	var/obj/item/I = bot.current_goal?.target
	if(!istype(I) || QDELETED(I))
		return GOAL_STEP_FAIL
	// grab_passing_tools() (bot_movement.dm) runs on every step of the move_to pursuit
	// that got the bot here, not just on arrival - it can (and did, per the "picked up
	// X" / "grabbed X in passing" pair right before an immediate second "picked up X")
	// already have grabbed this EXACT item while the bot was still walking toward it.
	// !isturf(I.loc) means it's no longer sitting where it was - already in the bot's
	// hand/belt/pocket - so calling try_pickup_target() again would just produce a
	// second, redundant "picked up X" log for an item that never left its possession,
	// which reads exactly like the bot pulling a duplicate out of thin air even though
	// nothing was actually duplicated.
	if(!isturf(I.loc))
		return GOAL_STEP_SUCCESS
	return bot.try_pickup_target(I) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_brain
	var/datum/bot_goal/current_goal
	var/datum/bot_strategy/current_strategy
	var/current_step_index = 0
	var/state_before_combat
	var/goal_giveup_time = 0
	var/fireaxe_retry_time = 0
	var/fuel_retry_time = 0
	var/list/set_down_items
	// A goal pursuit that hits a locked door it can't hack for lack of tools (see
	// seek_tool_for_obstacle(), bot_items.dm) suspends itself here and assigns a
	// throwaway acquire_tool goal in its place, rather than either giving up outright
	// or silently overwriting current_goal (which would lose the original goal's
	// strategy/step position with no way back). end_goal() restores and resumes
	// whichever goal is parked here once the tool-fetch finishes, success or not.
	var/datum/bot_goal/suspended_goal
	var/datum/bot_strategy/suspended_strategy
	var/suspended_step_index = 0
	// Counts consecutive suspend-for-tools cycles for the current outer goal (reset
	// whenever a fresh top-level goal is assigned or fully succeeds/gives up). Caps a
	// pathological case where the tool-fetch itself keeps failing on the same
	// obstacle the outer goal is also stuck on (e.g. two different goals both routing
	// through one door neither can get past) - each individual tool-fetch already
	// fails cleanly (handle_blocker_failure(), bot_items.dm), but nothing previously
	// stopped the outer goal from just suspending and trying again indefinitely.
	var/goal_suspend_count = 0
	// Targets acquire_tool (goals/acquire_tool.dm) has already tried and failed to
	// reach, mapped to a cooldown (same LAZYSET/world.time pattern as failed_areas/
	// failed_blockers) - resolve_target() excludes these so a retry doesn't just pick
	// the exact same unreachable tool again. See bot_goal/on_give_up().
	var/list/failed_tool_targets
	// Closets/toolboxes acquire_tool has actually pulled a needed tool from before -
	// see on_success() (goals/acquire_tool.dm). Plain list, not a cooldown map like
	// failed_tool_targets: a source that worked once is worth trying again indefinitely
	// (until it's empty or gone, which known_source_candidates() checks for directly),
	// there's no reason for this kind of memory to expire on a timer.
	var/list/known_tool_sources
	// See is_failed_engine_part() below.
	var/list/failed_engine_parts
	// Permanent, plain list (no cooldown) - see find_singularity_generator_to_remove()'s
	// comment (setup_tesla_engine.dm) for why distance alone can't tell "genuinely still
	// needs removing" apart from "was already removed to a spot that's still in reach".
	var/list/removed_singularity_generators
	// Cooldown map for setup_atmospherics.dm, same pattern as failed_engine_parts above -
	// kept as its own list (rather than sharing failed_engine_parts) since the two goals
	// run for different jobs and there's no reason a slow atmos pump retry should share a
	// cooldown clock with the engine room.
	var/list/failed_atmos_parts

/datum/bot_brain/proc/is_failed_tool_target(atom/A)
	var/cooldown = LAZYACCESS(failed_tool_targets, A)
	return cooldown && world.time < cooldown

// A COOLDOWN again, like failed_tool_targets above - NOT permanent. Briefly was made
// permanent to fix a real problem (the "Secure Storage" spare-parts emitters kept
// getting retried on a repeating cooldown, each cycle burning a ~17s frozen pathfind
// for a target that could never succeed), but permanence itself turned out wrong for
// the OTHER three callers (remove_singularity_generator, activate_field_generator,
// wrench_tesla_coil, wrench_grounding_rod): confirmed in-game, the singularity
// generator's very FIRST removal attempt fired before the bot had even geared up or
// left its spawn point, failed on distance/readiness alone (not genuine
// unreachability), and permanently blacklisting it off that one premature failure
// meant it could never be removed for the rest of the round even once the bot was
// fully ready and standing right next to it. The emitter spare-parts problem is now
// solved differently anyway (find_incomplete_tesla_emitter() filters by the /anchored
// subtype, so the unreachable spares are never even candidates - see that proc's
// comment), so nothing here still needs permanence.
/datum/bot_brain/proc/is_failed_engine_part(atom/A)
	var/cooldown = LAZYACCESS(failed_engine_parts, A)
	return cooldown && world.time < cooldown

// See failed_atmos_parts' declaration above.
/datum/bot_brain/proc/is_failed_atmos_part(atom/A)
	var/cooldown = LAZYACCESS(failed_atmos_parts, A)
	return cooldown && world.time < cooldown

/datum/bot_brain/proc/assign_goal(datum/bot_goal/goal)
	if(!goal)
		return FALSE
	if(state == BOT_STATE_GOAL && current_goal)
		return FALSE
	goal.resolve_target(src)
	if(!goal.target)
		bot_log(src, "couldn't find a target for [goal.type] (currently @ [bot_coord(get_turf(owner))])")
		return FALSE
	goal.strategies = goal.get_strategies(src)
	stop_pursuit()
	current_goal = goal
	state = BOT_STATE_GOAL
	if(!suspended_goal)
		goal_suspend_count = 0 //fresh top-level goal, not a tool-fetch nested under one
	try_next_strategy()
	return TRUE

/datum/bot_brain/proc/try_next_strategy()
	if(!current_goal || !current_goal.strategies || !current_goal.strategies.len)
		give_up_goal()
		return
	var/datum/bot_strategy/S = current_goal.strategies[1]
	current_goal.strategies.Cut(1, 2)
	if(!S.is_feasible(src))
		try_next_strategy()
		return
	current_strategy = S
	current_step_index = 1
	bot_log(src, "trying [S.type] for [current_goal.type] (target: [current_goal.target] @ [bot_coord(get_turf(current_goal.target))])")
	run_current_step()

/datum/bot_brain/proc/run_current_step()
	if(!current_strategy || !current_strategy.steps || current_step_index > current_strategy.steps.len)
		goal_succeeded()
		return
	// Capture what we need to log BEFORE calling execute() - a step (ensure_tools,
	// acquire_captains_id.dm, is the one that actually does this) can synchronously
	// give up the ENTIRE goal from inside its own execute() call (seek_tool_for_obstacle()
	// hitting goal_suspend_count's cap), which clears current_strategy/current_goal
	// before execute() even returns. Referencing current_strategy AFTER that call, as
	// this logging used to, crashed reading .steps off a now-null current_strategy.
	var/datum/bot_step/step = current_strategy.steps[current_step_index]
	var/step_type = step.type
	var/step_index = current_step_index
	var/step_count = current_strategy.steps.len
	var/result = step.execute(src)
	bot_log_verbose(src, "run_current_step: step [step_index]/[step_count] ([step_type]) -> [result == GOAL_STEP_PENDING ? "PENDING" : (result == GOAL_STEP_SUCCESS ? "SUCCESS" : "FAIL")]")
	if(result == GOAL_STEP_PENDING)
		return
	advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_brain/proc/on_goal_pursuit_finished(atom/target, success)
	bot_log_verbose(src, "on_goal_pursuit_finished: target=[target], success=[success]")
	advance_goal_step(success)

/datum/bot_brain/proc/advance_goal_step(success)
	if(!current_strategy)
		return
	if(!success)
		current_strategy.attempts++
		if(current_strategy.attempts < current_strategy.max_attempts)
			run_current_step()
		else
			bot_log(src, "[current_strategy.type] failed (target: [current_goal.target] @ [bot_coord(get_turf(current_goal.target))])")
			try_next_strategy()
		return
	current_step_index++
	run_current_step()

/datum/bot_brain/proc/goal_succeeded()
	bot_log(src, "goal [current_goal?.type] succeeded (target: [current_goal?.target] @ [bot_coord(get_turf(current_goal?.target))])")
	current_goal?.on_success(src)
	if(current_goal?.flavor_success)
		bot_say(owner, current_goal.flavor_success)
	end_goal()

/datum/bot_brain/proc/give_up_goal()
	bot_log(src, "giving up on [current_goal?.type] (target: [current_goal?.target] @ [bot_coord(get_turf(current_goal?.target))])")
	current_goal?.on_give_up(src)
	// Only the captain's-ID goal gets auto-retried (handle_wander(), bot_brain.dm) - this
	// used to be set on EVERY give-up, so a doctor losing track of a patient or a
	// security officer's suspect breaking free would, a minute or two later, send that
	// bot off to break into the captain's office.
	if(istype(current_goal, /datum/bot_goal/acquire_captains_id))
		goal_giveup_time = world.time + rand(600, 1200)
	end_goal()

/datum/bot_brain/proc/end_goal()
	// The goal that just ended may still have an active pursuit in flight (a move_to
	// step's self-rescheduling movement timer chain, bot_movement.dm) - without
	// cancelling it here, that pursuit keeps walking the bot toward a destination
	// nothing cares about anymore, and if it ever finishes, finish_pursuit() ->
	// on_goal_pursuit_finished() -> advance_goal_step() would run against whatever
	// current_strategy happens to be BY THEN (null, or a totally unrelated goal's
	// strategy if one was assigned since) - already guarded against crashing
	// (advance_goal_step() checks current_strategy first), but still wrong behavior.
	stop_pursuit()
	current_goal = null
	current_strategy = null
	current_step_index = 0
	state = state_before_combat || BOT_STATE_WANDER
	state_before_combat = null
	next_wander_time = world.time

	if(suspended_goal)
		current_goal = suspended_goal
		current_strategy = suspended_strategy
		current_step_index = suspended_step_index
		suspended_goal = null
		suspended_strategy = null
		suspended_step_index = 0
		state = BOT_STATE_GOAL
		bot_log(src, "resuming [current_goal.type] after fetching tools (target: [current_goal.target] @ [bot_coord(get_turf(current_goal.target))])")
		resume_goal()

/datum/bot_brain/proc/resume_goal()
	if(!current_goal || !current_strategy)
		state = BOT_STATE_WANDER
		return
	if(!current_strategy.is_feasible(src))
		try_next_strategy()
		return
	run_current_step()

/datum/bot_brain/proc/handle_goal()
	if(owner.buckled)
		owner.buckled.unbuckle_mob(owner, force = TRUE)

/// What a person would actually take out of a locker: the specific thing they came for, or - on a
/// general "grab something useful" trip - loose tools they don't already have. Never a whole
/// toolbox as a side-grab (it fills a hand for the rest of the trip).
/proc/bot_wants_from_locker(datum/bot_brain/bot, obj/item/I, needed_type)
	if(needed_type)
		return istype(I, needed_type)
	if(istype(I, /obj/item/storage/toolbox))
		return FALSE
	return !bot.already_carries_matching_tool(I)
