/datum/bot_brain
	var/list/current_path
	var/pursuing_kind
	var/atom/pursue_target
	var/stuck_timer_id
	// Read by bot_can_astar_pass_permissive() (bot_pathing_permissive.dm) - repath()
	// toggles this around its two permissive passes so climbing over furniture is only
	// ever chosen when there's truly no other way through, not just because it's
	// shorter than walking around.
	var/pathing_allow_climb = TRUE
	// Set only around the "smash through tables" pathing pass (needs a strong weapon).
	var/pathing_allow_smash_tables = FALSE
	// Climbing a structure moves the bot in the STRUCTURE's own facing direction
	// (obj/structure/proc/do_climb()), not toward wherever the path actually wants to
	// go, and crossing one tile of furniture takes two separate climb_structure() calls
	// (climb onto it, then climb off) - each a ~2s do_mob() channel that can outlast a
	// single stuck-timeout window. That combination can leave a bot re-climbing the same
	// tile indefinitely without ever converging on progress. These track repeated
	// stuck-timeouts at the exact same node so that loop gets cut short instead of
	// running forever - see on_stuck_timeout().
	var/turf/last_stuck_turf
	var/stuck_repeat_count = 0
	// Tracks repeated failures to clear the SAME blocking object (a door that keeps
	// failing to hack, etc) - turf-identity tracking above isn't reliable for this:
	// repath() can legitimately produce a slightly different current_path each retry
	// (e.g. bot_reachable_permissive's pass 2 "succeeding" toward the same unhackable
	// door every time) even though the actual obstacle never changes, which let a
	// pursuit stuck on one un-clearable object loop indefinitely instead of ever
	// hitting the turf-based repeat cutoff - see try_clear_obstruction()'s
	// handle_blocker_failure() (bot_items.dm).
	var/atom/last_failed_blocker
	var/failed_blocker_count = 0
	// Same idea as failed_areas (bot_brain.dm) but per-obstacle instead of per-area:
	// handle_blocker_failure() giving up on one door only means THAT pursuit stops
	// walking into it - the count resets on every fresh pursue() (bot_movement.dm), so
	// without this, a brand new pursuit (the goal's next strategy, or just ordinary
	// wandering afterward) that happens to route through the exact same currently-
	// unhackable door would cheerfully walk back into it and grind through the same
	// 3-4 failed attempts again. This makes that avoidance persist for a while, the
	// same way failed_areas does for whole areas.
	var/list/failed_blockers
	// Set by repath() right before it gives up, so callers of on_pursuit_finished()
	// (bot_brain.dm) can log WHY a pursuit failed, not just that it did - see
	// bot_log_verbose() below.
	var/last_path_fail_reason
	// Set while step_next_node() is inside try_clear_obstruction() (bot_items.dm), which
	// can yield for real time - clear_one_blocker() -> climb_structure() runs a ~2s
	// do_mob() channel, and seek_tool_for_obstacle() can suspend the current pursuit
	// and start a brand new one (going to fetch a missing tool) from several calls
	// deep inside that same yield. Both mean current_path/pursuing_kind/pursue_target
	// can change out from under the outer step_next_node() call while it's still
	// suspended waiting for try_clear_obstruction() to return. pursue() checks this to
	// defer a nested pursuit's repath() to next tick instead of racing the outer call,
	// and step_next_node() checks pursuing_kind/pursue_target against what it started
	// with to detect exactly that replacement and bail out cleanly - see both procs.
	var/busy_clearing = FALSE
	// Guards repath() itself against re-entrancy - see repath()'s comment.
	var/repathing = FALSE
	// Set by do_repath() when a NEW pursuit replaced the one it was computing a route for
	// while it was yielding inside the pathfinder - see repath().
	var/repath_superseded = FALSE

// precomputed_path: an already-verified route (acquire_tool's is_reachable(),
// goals/acquire_tool.dm, is the current source) to use AS-IS instead of running a
// fresh repath() - see that proc's comment for why a second independent A* search
// isn't guaranteed to agree with the one that already proved this target reachable.
/datum/bot_brain/proc/pursue(atom/target, kind, force = FALSE, list/precomputed_path)
	if(!force && pursuing_kind == kind && pursue_target == target && current_path)
		return TRUE
	var/turf/target_turf = get_turf(target)
	var/turf/owner_turf = get_turf(owner)
	bot_log_verbose(src, "pursue([target] @ [bot_coord(target_turf)], kind=[kind], force=[force]) from [bot_coord(owner_turf)]")
	stop_pursuit()
	if(!target)
		return FALSE
	pursuing_kind = kind
	pursue_target = target
	last_stuck_turf = null
	stuck_repeat_count = 0
	last_failed_blocker = null
	failed_blocker_count = 0

	if(precomputed_path && precomputed_path.len && !busy_clearing && !repathing)
		bot_log_verbose(src, "pursue: reusing already-verified path (skipping a fresh repath())")
		current_path = precomputed_path.Copy()
		last_path_fail_reason = null
		step_next_node()
		return TRUE

	// busy_clearing is TRUE while an OUTER step_next_node() call is inside
	// try_clear_obstruction() (seek_tool_for_obstacle(), bot_items.dm, can call pursue()
	// from there, suspending the current goal to go fetch a tool). repathing is TRUE
	// any time we're anywhere inside an outer do_repath() call on this SAME bot_brain -
	// which covers a second, distinct nesting: do_repath()'s own failure branch calls
	// finish_pursuit(FALSE) synchronously, and THAT can cascade all the way through
	// give_up_goal() -> end_goal() -> resume_goal() -> run_current_step() -> pursue()
	// for a resumed goal, all still nested inside the original do_repath() call (it
	// hasn't returned - it's paused mid-body at the finish_pursuit() call). Either way,
	// current_path/pursuing_kind/pursue_target set above are shared with whichever
	// outer call is still running, and calling repath() synchronously here would just
	// get rejected by repath()'s own reentrancy guard - leaving this new pursuit with
	// no path AND nothing driving it forward (no timer, no registered signal), since a
	// rejected repath() call does neither. Deferring to next tick lets every outer call
	// unwind first, so by the time this runs, it's a clean, ordinary repath().
	if(busy_clearing || repathing)
		addtimer(CALLBACK(src, PROC_REF(repath)), 1)
		return TRUE
	return repath()

/datum/bot_brain/proc/repath()
	// get_path_to()/AStar() (code/__HELPERS/AStar.dm) calls stoplag() internally on
	// every invocation - pathfinding YIELDS, it's never a single synchronous
	// computation. With up to four passes now (direct/adjacent x no-climb/climb),
	// repath() can yield many times across a real multi-tick span, during which some
	// OTHER trigger (a stale stuck-timer, a signal) could call repath() again on this
	// same bot - two overlapping cascades interleaving their pathfinds and clobbering
	// each other's current_path. Guard against that directly, the same way
	// busy_clearing guards step_next_node()'s obstruction-clearing yield.
	if(repathing)
		bot_log_verbose(src, "repath: already repathing, ignoring reentrant call")
		return FALSE
	repathing = TRUE
	repath_superseded = FALSE
	. = do_repath()
	repathing = FALSE
	// A new pursue() arrived while this one was still inside the (yielding) pathfinder.
	// Its own repath() was rejected by the guard above, so nobody was going to compute
	// ITS route - and the old computation used to finish anyway and install a path to
	// the OLD destination under the NEW pursuit's name (a bot told to fetch gloves walked
	// to Brig Control, the destination of the wander pursuit it had been computing).
	// do_repath() now discards that stale result; run the current pursuit's own repath.
	if(repath_superseded)
		repath_superseded = FALSE
		if(pursuing_kind && pursue_target)
			return repath()
	return .

/datum/bot_brain/proc/supersede_repath()
	bot_log_verbose(src, "repath: pursuit was replaced while pathfinding - discarding the stale route")
	current_path = null
	repath_superseded = TRUE
	return FALSE

/datum/bot_brain/proc/do_repath()
	var/turf/destination = get_turf(pursue_target)
	if(!destination)
		last_path_fail_reason = "target [pursue_target] has no turf (deleted/moved off-map?)"
		bot_log_verbose(src, "repath abort: [last_path_fail_reason]")
		finish_pursuit(FALSE)
		return FALSE
	if(get_turf(owner) == destination)
		finish_pursuit(TRUE)
		return FALSE

	// An ATOM target (an item, a toolbox, a door, ...) only ever needs adjacency to
	// interact with - use_atom()/use_item_on()/try_pickup_target() all just check
	// owner.Adjacent(), never the bot's exact tile. A bot already standing diagonally
	// next to a toolbox on a table doesn't need to climb up onto the table first any
	// more than a real player would - they'd just reach over and take what they need.
	// This used to only recognize "arrived" by exact-tile match above, so a target
	// merely adjacent (very commonly true right after some other pursuit ends nearby)
	// triggered a full pathfind - and if the only route TO the exact tile required
	// climbing (true for anything sitting on a table), that climb happened for
	// literally no reason. Deliberately excluded for a bare turf target (isturf(
	// pursue_target)) - "wander" pursuits and anything that needs the bot actually ON
	// the destination tile (try_sit_down() et al) still need the real thing, not just
	// "close enough."
	if(!isturf(pursue_target) && owner.Adjacent(pursue_target))
		finish_pursuit(TRUE)
		return FALSE

	var/obj/item/card/id/id_card = owner.get_idcard(TRUE)
	// can_path_through_space() (gear_up_eva.dm) logged explicitly here - a "no path"
	// failure right next to a real space tile is ambiguous from the outside otherwise:
	// looks identical whether simulated_only correctly excluded space (gear genuinely
	// missing/lapsed right at this exact repath) or the destination is unreachable for
	// an entirely different reason with space allowed regardless. This line makes that
	// distinction directly readable instead of inferred from surrounding gear-up logs.
	bot_log_verbose(src, "repath: [bot_coord(get_turf(owner))] -> [destination] @ [bot_coord(destination)], id=[id_card ? id_card : "none"], access=[id_card ? english_list(id_card.GetAccess()) : "none"], can_path_through_space=[can_path_through_space()]")

	// Ordering matters here: climbing must be the true last resort, tried only after
	// EVERY non-climbing option - both reaching the exact destination AND just getting
	// adjacent to it - has failed. use_atom()/try_pickup_target() only ever need
	// adjacency, never the exact tile (an item sitting on a table, or in a rack, is
	// reachable by simply standing next to it), so if a no-climb route to some
	// neighboring turf exists, that's always preferable to climbing onto the
	// destination itself.
	//
	// Only ONE adjacent candidate is picked (the closest open cardinal neighbor, by
	// plain distance - no pathfinding involved in the pick itself), not "try every
	// direction". A previous version tried up to 4 directions per tier via a loop that
	// called back into the pathfinder repeatedly; get_path_to() yields internally
	// (stoplag() in AStar.dm) on every call, and that many yields in one repath() call
	// turned out to make hard-to-diagnose interleaving/timing bugs a real risk - a
	// single logged case showed a successful adjacent-turf path apparently being
	// discarded by the very next tier check. One candidate keeps repath() to at most
	// four total pathfind calls (direct/adjacent x no-climb/climb), matching its
	// original pre-adjacency cost.
	// Every open cardinal neighbor, closest first - not just one. pick_adjacent_turf()
	// used to hand back only the single nearest candidate, filtered solely on the
	// TURF's own density - which says nothing about a dense OBJECT sitting on that turf
	// (another table, a rack, ...). An item in the middle of a table cluster often has
	// its nearest "open-looking" neighbor be yet another table tile, which still fails a
	// no-climb pathfind exactly like the destination did - so this fell straight through
	// to climbing even when a genuinely walk-up floor tile existed on another side.
	// Trying every candidate through the real no-climb pathfind (not just the nearest
	// one) before ever considering climbing fixes that: climbing stays the true last
	// resort, not just what happened to be geometrically closest.
	var/list/adjacent_candidates = adjacent_turf_candidates(destination)
	bot_log_verbose(src, "adjacent fallback candidates: [adjacent_candidates.len ? english_list(adjacent_candidates) : "none"]")

	var/atom/my_target = pursue_target
	var/my_kind = pursuing_kind

	// For an ATOM target, adjacency is all that's ever needed (see the comment above) -
	// trying it FIRST, before the exact destination tile, matters when the destination
	// is boxed in by other dense objects of the same kind (several tesla emitters/field
	// generators sitting right next to each other, confirmed in-game): a failed
	// exact-tile pathfind there isn't a quick no - AStar still explores extensively
	// before concluding there's no route (maxnodes=300), costing several REAL seconds
	// even though it ultimately finds nothing, while the adjacent-candidate route
	// succeeds almost immediately. That gap (repeatedly ~6-8s per component, confirmed
	// via timestamped logs) was exactly what read as the bot "pausing" after every task.
	// A turf target (isturf(pursue_target) - wander, sit-down, anything that needs the
	// bot actually ON the tile) keeps destination-first, since "adjacent" was never a
	// valid substitute for those to begin with.
	var/try_adjacent_first = !isturf(pursue_target)

	if(try_adjacent_first)
		for(var/turf/candidate in adjacent_candidates)
			current_path = try_path_to_no_climb(candidate, id_card)
			if(pursue_target != my_target || pursuing_kind != my_kind)
				return supersede_repath()
			if(current_path && current_path.len)
				break

	if(!current_path || !current_path.len)
		current_path = try_path_to_no_climb(destination, id_card)
		if(pursue_target != my_target || pursuing_kind != my_kind)
			return supersede_repath()

	if(!try_adjacent_first && (!current_path || !current_path.len))
		for(var/turf/candidate in adjacent_candidates)
			current_path = try_path_to_no_climb(candidate, id_card)
			if(pursue_target != my_target || pursuing_kind != my_kind)
				return supersede_repath()
			if(current_path && current_path.len)
				break

	if(!current_path || !current_path.len)
		bot_log_verbose(src, "no no-climb route at all (direct or adjacent) - trying with climbing allowed")
		if(try_adjacent_first)
			for(var/turf/candidate in adjacent_candidates)
				current_path = try_path_to_climb(candidate, id_card)
				if(pursue_target != my_target || pursuing_kind != my_kind)
					return supersede_repath()
				if(current_path && current_path.len)
					break
		if(!current_path || !current_path.len)
			current_path = try_path_to_climb(destination, id_card)
			if(pursue_target != my_target || pursuing_kind != my_kind)
				return supersede_repath()
		if(!try_adjacent_first && (!current_path || !current_path.len))
			for(var/turf/candidate in adjacent_candidates)
				current_path = try_path_to_climb(candidate, id_card)
				if(pursue_target != my_target || pursuing_kind != my_kind)
					return supersede_repath()
				if(current_path && current_path.len)
					break

	if(!current_path || !current_path.len)
		// No route with what the bot has - would something it could go and get open one?
		// (a welder for a welded door, or in an emergency a weapon lying nearby; bot_breach.dm)
		if(try_unlock_route(destination, id_card))
			return supersede_repath() //now fetching it; repath() re-plans for that pursuit
		current_path = null
		last_path_fail_reason = "no path found in any pass (dist=[get_dist(owner, destination)], area=[get_area_name(destination)])"
		bot_log(src, "no path to [destination] @ [bot_coord(get_turf(destination))] ([get_area_name(destination)])")
		dump_neighbor_diagnostics(get_turf(owner))
		finish_pursuit(FALSE)
		return FALSE

	last_path_fail_reason = null
	step_next_node()
	return TRUE

// Every open cardinal-adjacent turf to `dest`, closest-to-the-bot first - no
// pathfinding involved, just a density/type check on each of the 4 neighbors (turf AND
// anything dense sitting on it - a neighbor that's itself another table tile is not a
// genuinely open candidate, even though the turf itself isn't dense) and a plain
// distance sort, so this is effectively free to call. See do_repath()'s comment for why
// every candidate gets tried instead of just the nearest.
/datum/bot_brain/proc/adjacent_turf_candidates(turf/dest)
	var/list/candidates = list()
	var/list/dists = list()
	for(var/d in GLOB.cardinals)
		var/turf/neighbor = get_step(dest, d)
		if(!neighbor || neighbor == get_turf(owner))
			continue
		if(neighbor.density || !istype(neighbor, /turf/open))
			continue
		if(isspaceturf(neighbor) && !can_path_through_space())
			continue
		if(bot_turf_has_active_field(neighbor))
			continue //an active containment field/generator shocks on every step or bump attempt (bot_pathing_permissive.dm) - never a genuinely open candidate
		var/blocked = FALSE
		for(var/atom/movable/AM in neighbor)
			if(AM.density)
				blocked = TRUE
				break
		if(blocked)
			continue
		var/d2 = get_dist(owner, neighbor)
		var/insert_at = candidates.len + 1
		for(var/i in 1 to candidates.len)
			if(d2 < dists[i])
				insert_at = i
				break
		candidates.Insert(insert_at, neighbor)
		dists.Insert(insert_at, d2)
	return candidates

// Passes 1-2 of the pathfind cascade: a legit (fully unlocked) route, then one
// allowing hacking/breaking through locked doors and windows - but never climbing.
// Kept separate from the climb pass (try_path_to_climb() below) so repath() can
// exhaust every non-climbing option, direct AND adjacent, before climbing is even
// considered - see repath()'s comment for why that ordering matters.
/datum/bot_brain/proc/try_path_to_no_climb(turf/dest, obj/item/card/id/id_card)
	// adjacent = bot_reachable_strict() (bot_pathing_permissive.dm), NOT the engine
	// default reachableTurftest() - same obstruction rules, plus refuses to route
	// through an active containment field/generator, which the default's pure density
	// check can't see (density=FALSE by design - a real player crosses one on purpose).
	var/list/path = get_path_to(owner, dest, /turf/proc/Distance, 300, 250, adjacent = /turf/proc/bot_reachable_strict, id = id_card, simulated_only = !can_path_through_space())
	bot_log_verbose(src, "  pass 1 (legit route) to [dest] @ [bot_coord(dest)]: [path ? "[path.len] nodes" : "no path"]")
	if(path && path.len)
		return path

	// No legitimate (unlocked) route - try again allowing routes through a locked (but
	// unwelded, powered, access-satisfied) airlock or a window it can break, but still
	// NOT through climbable furniture.
	pathing_allow_climb = FALSE
	path = get_path_to(owner, dest, /turf/proc/bot_weighted_distance, 300, 250, adjacent = /turf/proc/bot_reachable_permissive, id = id_card, simulated_only = !can_path_through_space())
	pathing_allow_climb = TRUE
	// dest's own name is ambiguous when an adjacent-turf pass shares the destination's
	// exact turf type (e.g. two carpet tiles both print as "the carpet") - always show
	// coordinates here too, not just in pass 1, so log traces can actually tell which
	// specific turf a given pass/result belongs to.
	bot_log_verbose(src, "  pass 2 (hack/break, no climb) to [dest] @ [bot_coord(dest)]: [path ? "[path.len] nodes" : "no path"]")
	if(path && path.len)
		bot_log(src, "no open route to [dest] - trying a route through a locked door instead")
		return path

	// Still nothing, and the bot is armed: a real player with an axe just smashes the
	// table in their way rather than clambering over it (a climb stuns and makes them
	// drop what they're holding). Only tried BEFORE the climbing pass, so a bot without a
	// strong weapon still climbs exactly as before.
	if(has_strong_weapon() && destruction_allowed()) //calm bots climb over furniture instead (pass 3)
		pathing_allow_climb = FALSE
		pathing_allow_smash_tables = TRUE
		path = get_path_to(owner, dest, /turf/proc/bot_weighted_distance, 300, 250, adjacent = /turf/proc/bot_reachable_permissive, id = id_card, simulated_only = !can_path_through_space())
		pathing_allow_smash_tables = FALSE
		pathing_allow_climb = TRUE
		bot_log_verbose(src, "  pass 2b (hack/break, smash tables) to [dest] @ [bot_coord(dest)]: [path ? "[path.len] nodes" : "no path"]")
		if(path && path.len)
			bot_log(src, "no clear route to [dest] - planning to smash through furniture with my weapon")
	return path

// Last-resort pass: also allows routing over climbable furniture. Only called once
// try_path_to_no_climb() has failed for BOTH the real destination and every adjacent
// turf (repath()) - a bot should climb a table only when there is truly no other way
// to get close enough, never merely because climbing happens to be shorter.
/datum/bot_brain/proc/try_path_to_climb(turf/dest, obj/item/card/id/id_card)
	var/list/path = get_path_to(owner, dest, /turf/proc/bot_weighted_distance, 300, 250, adjacent = /turf/proc/bot_reachable_permissive, id = id_card, simulated_only = !can_path_through_space())
	bot_log_verbose(src, "  pass 3 (allow climbing) to [dest] @ [bot_coord(dest)]: [path ? "[path.len] nodes" : "no path"]")
	if(path && path.len)
		bot_log(src, "no route to [dest] without climbing - climbing over furniture instead")
	return path

// Dumps what's actually on each cardinal-adjacent turf when a pathfind fails
// completely (0 nodes on all three passes) - if a bot's genuinely sealed off from
// every direction, that shows up here directly instead of needing another round trip.
/datum/bot_brain/proc/dump_neighbor_diagnostics(turf/from)
	if(!from)
		return
	for(var/d in GLOB.cardinals)
		var/turf/T = get_step(from, d)
		if(!T)
			bot_log_verbose(src, "neighbor [dir2text(d)]: off-map")
			continue
		var/list/blockers = list()
		for(var/obj/O in T)
			if(O.density)
				blockers += "[O]([O.type])"
		bot_log_verbose(src, "neighbor [dir2text(d)]: [T] @ [bot_coord(T)], density=[T.density], objs=[blockers.len ? english_list(blockers) : "none dense"]")

// Movement is driven entirely by explicit step_towards() calls on our own timer, not
// walk_to(). A real player never goes through walk_to() either - ordinary movement is
// direct per-tick Move() calls from key input, which is exactly what step_towards()
// does. walk_to() is an NPC-convenience wrapper for "keep walking toward X on your
// own", and its internal continuous-stepping state is what was getting desynced by a
// climb's forceMove() (climb_structure()/do_climb(), structures.dm, moves the mob
// outside the normal movement pathway walk_to() expects) - sometimes for a single
// tile, sometimes for the rest of the pursuit. Driving every step ourselves sidesteps
// that fragility entirely: step_towards() has never once failed to move the mob when
// nothing was actually in the way, in any of the cases that came up while chasing this.
// This also means movement no longer depends on COMSIG_MOVABLE_MOVED firing/being
// unsuppressed at the right moment - step_next_node() always knows synchronously
// whether its own step worked, so the whole class of "signal fired while busy_clearing
// suppressed it" timing races doesn't exist anymore. finish_pursuit() below still calls
// walk(owner, 0), harmless, in case anything ever leaves a native walk() directive
// active on the mob from outside this system.
// A real player's own movement is gated by Process_Spacemove() - client/Move()'s input
// handler (mob_movement.dm) calls it before every single step, and in zero-g that's
// what actually performs the "push off a dense neighbor" mechanic
// (get_spacemove_backup(), atoms_movable.dm) letting a player move at all without
// magboots, as long as SOMETHING dense is adjacent. step_towards() (a raw BYOND
// builtin) calls Move() directly and never goes through that gate at all - confirmed
// in-game: a bot standing on an open space tile in the solar array, right next to dense
// solar array structures a real player could push off of, just never moved; plain
// step_towards() calls were silently doing nothing. Calling Process_Spacemove() first,
// exactly like the real input path does, fixes that - it's a no-op returning
// immediately true whenever gravity's actually present (atoms_movable.dm:
// "if(has_gravity(src)): return 1"), so this costs nothing outside actual zero-g.
/datum/bot_brain/proc/bot_step_towards(turf/next_node)
	if(!next_node)
		return FALSE
	if(!owner.Process_Spacemove(get_dir(owner, next_node)))
		return FALSE
	return step_towards(owner, next_node)

// step_next_node() re-invokes itself via addtimer to keep walking (see its own
// comment) - previously that self-perpetuation went through on_pursuit_moved(), which
// wrapped it in try/catch specifically so a crash wouldn't silently kill the whole
// movement chain forever (nothing else would ever reschedule it). Keep that same
// protection here now that step_next_node() reschedules itself directly.
/datum/bot_brain/proc/step_next_node()
	try
		do_step_next_node()
	catch(var/exception/e)
		bot_log_exception(src, "step_next_node", e)
		repath() //self-heal: never let a crash here leave the pursuit permanently dead

/datum/bot_brain/proc/do_step_next_node()
	// Climbing out of a pool (pool_main.dm) needs a dedicated ~2 second do_mob()
	// channel (try_escape_pool(), bot_items.dm, called every process() tick while
	// still swimming), and a do_mob() channel cancels the instant the user's state
	// changes mid-channel. This movement timer chain keeps running on its own separate
	// schedule regardless of swimming state, and every step_towards() attempt it fired
	// counted as exactly that kind of disruption - restarting the climb-out from
	// scratch every single time, forever, which is why a bot could fall in a pool and
	// never actually get back out. Defer entirely until back on dry land; nothing about
	// the path is lost by waiting, it's still sitting in current_path untouched.
	if(owner.swimming)
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), max(1, owner.movement_delay()), TIMER_STOPPABLE)
		return
	while(current_path && current_path.len && current_path[1] == get_turf(owner))
		current_path.Cut(1, 2)
	if(!current_path || !current_path.len)
		finish_pursuit(TRUE)
		return
	var/turf/next_node = current_path[1]
	bot_log_verbose(src, "step_next_node: [get_turf(owner)] -> [next_node] @ [bot_coord(next_node)], [current_path.len] nodes left")
	// try_clear_obstruction() (bot_items.dm) checks against the real movement engine
	// itself before touching anything, and can yield for real time (climbing a
	// structure).
	var/expected_kind = pursuing_kind
	var/atom/expected_target = pursue_target
	var/turf/before_clear = get_turf(owner)
	busy_clearing = TRUE
	try_clear_obstruction()
	busy_clearing = FALSE
	var/moved_during_clear = (get_turf(owner) != before_clear)

	// try_clear_obstruction() can, several calls deep (handle_blocker_failure() ->
	// seek_tool_for_obstacle(), bot_items.dm), suspend the CURRENT pursuit and start a
	// brand new one for a different target (e.g. going to fetch a missing tool) -
	// current_path/pursuing_kind/pursue_target are shared with that new pursuit. If
	// they no longer match what this call started with, this pursuit has been replaced
	// out from under us: current_path now belongs to (or is being asynchronously set
	// up for, see pursue()'s busy_clearing deferral) that new pursuit, not this one.
	// Touching it here - even just to check whether it's empty - would misread the new
	// pursuit's in-progress state as this one having instantly arrived. Bail out
	// entirely and let the new pursuit's own machinery drive it.
	if(pursuing_kind != expected_kind || pursue_target != expected_target)
		bot_log_verbose(src, "step_next_node: pursuit was replaced during obstruction-clearing (now [pursuing_kind]/[pursue_target]) - abandoning this call")
		return

	// The yield above may have let the bot's own movement (e.g. a climb) advance
	// current_path - so re-derive next_node fresh rather than trusting what was
	// captured before the yield.
	while(current_path && current_path.len && current_path[1] == get_turf(owner))
		current_path.Cut(1, 2)
	if(!current_path || !current_path.len)
		finish_pursuit(TRUE)
		return
	next_node = current_path[1]

	deltimer(stuck_timer_id)

	// try_clear_obstruction() itself already moved the bot this cycle (a climb) - don't
	// ALSO take a step_towards() step in the same synchronous instant on top of that.
	// Mechanically harmless (both are real, valid single-tile moves), but with zero
	// delay between "climb animation ends" and "already took another full step", it
	// visibly reads as teleporting 2 tiles at once instead of two separate, paced
	// steps. Just schedule the next real step after the normal per-tile delay, same as
	// every other step gets, instead of taking it immediately.
	if(moved_during_clear)
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), max(1, owner.movement_delay()), TIMER_STOPPABLE)
		return

	var/turf/left_turf = get_turf(owner)
	if(bot_step_towards(next_node))
		last_stuck_turf = null
		stuck_repeat_count = 0
		last_failed_blocker = null
		failed_blocker_count = 0
		// A goal-driven pursuit (move_to) only ever cleared BLOCKING obstructions in
		// its own path - it never looked at anything else, so a bot walking straight
		// through a tool storage room it wasn't specifically targeting (just passing
		// through en route to its actual target) completely ignored a tool sitting
		// right there even while still missing that exact type. Real players notice
		// and grab that in passing; check every tile advanced during a goal pursuit,
		// not just at the pre-picked destination - see grab_passing_tools() (bot_items.dm).
		grab_passing_tools()
		// Same idea, security-flavored - see close_airlock_behind()'s own comment.
		close_airlock_behind(left_turf)
		// Re-invoke ourselves after a normal per-tile delay, same pacing walk_to()'s
		// Lag parameter used to provide, just driven explicitly instead of trusted to
		// its own internal continuation.
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), max(1, owner.movement_delay()), TIMER_STOPPABLE)
	else
		// Didn't move this attempt. Retry soon rather than waiting out a long
		// stuck-timeout window for the very first failure - on_stuck_timeout()'s
		// repeat-counting/give-up logic still applies once this keeps failing at the
		// same node.
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(on_stuck_timeout), next_node), 10, TIMER_STOPPABLE)

/datum/bot_brain/proc/on_stuck_timeout(turf/expected_node)
	if(!current_path || !current_path.len || current_path[1] != expected_node)
		return
	if(repathing)
		return //a repath() is already mid-flight (it yields internally) - let it finish rather than racing it

	// Diagnostic: kept from when walk_to() was still in the picture - status effects
	// (stun, etc) that stop movement without anything being physically in the way
	// wouldn't otherwise show up anywhere. Still useful if a step ever fails for a
	// reason unrelated to pathing/obstructions.
	bot_log_verbose(src, "stuck-diagnostic: owner @ [bot_coord(get_turf(owner))], stat=[owner.stat], mobility_flags=[owner.mobility_flags], stunned=[owner.IsStun()], knockdown=[owner.IsKnockdown()], move_delay=[owner.movement_delay()], pulledby=[owner.pulledby], buckled=[owner.buckled]")

	// Genuinely can't move right now (e.g. climb_stun's Stun() right after climbing a
	// structure) - repath()ing or counting this against the give-up threshold is
	// pointless, the bot isn't going anywhere until this clears regardless of what the
	// path looks like. Just check back shortly without touching stuck_repeat_count.
	if(owner.IsStun() || owner.IsKnockdown() || owner.stat != CONSCIOUS || owner.swimming)
		bot_log_verbose(src, "still incapacitated - deferring stuck-check instead of repathing")
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(on_stuck_timeout), expected_node), 10, TIMER_STOPPABLE)
		return

	// Just came out of being incapacitated (a climb_stun is the common case) - if that
	// stun dropped anything (living.dm's update_mobility(), see recover_dropped_tools()'s
	// comment in bot_items.dm), THIS is the exact moment MOBILITY_PICKUP comes back, so
	// grab it back before moving another step away from it. recover_dropped_tools() used
	// to only be reached via a separately-scheduled addtimer racing against this same
	// "stun just cleared" moment - whichever fired first won, and the bot's own retry
	// below often won that race and walked off leaving a tool behind on the table,
	// needing a whole separate fetch trip later. Calling it directly, synchronously,
	// right here removes the race entirely: this IS the moment recovery needs to happen.
	recover_dropped_tools(get_turf(owner))

	// Fully mobile per every check above, yet the last attempt still didn't move it -
	// try again directly; this alone resolves most single-step misses (seen right
	// after a climb) without needing to fall through to obstruction-clearing/give-up.
	if(bot_step_towards(expected_node))
		bot_log_verbose(src, "step_towards() retry worked, continuing")
		last_stuck_turf = null
		stuck_repeat_count = 0
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), max(1, owner.movement_delay()), TIMER_STOPPABLE)
		return

	if(expected_node == last_stuck_turf)
		stuck_repeat_count++
	else
		last_stuck_turf = expected_node
		stuck_repeat_count = 1
	if(stuck_repeat_count >= 3)
		last_path_fail_reason = "stuck at [expected_node] @ [bot_coord(expected_node)] [stuck_repeat_count] times in a row"
		bot_log(src, "still stuck at [expected_node] after repeated attempts, giving up")
		last_stuck_turf = null
		stuck_repeat_count = 0
		finish_pursuit(FALSE)
		return

	bot_log(src, "stuck heading to [expected_node], rerouting")
	busy_clearing = TRUE
	try
		if(try_clear_obstruction())
			busy_clearing = FALSE
			return //pursuit was redirected (e.g. toward a tool) - it already repathed itself
	catch(var/exception/e)
		bot_log_exception(src, "on_stuck_timeout/try_clear_obstruction", e)
	busy_clearing = FALSE
	repath() //self-heal: always fall through to a plain repath if the smarter path crashed

/datum/bot_brain/proc/finish_pursuit(success)
	deltimer(stuck_timer_id)
	walk(owner, 0) //harmless safety net in case anything outside this system left a native walk() directive active
	current_path = null
	var/kind = pursuing_kind
	var/atom/target = pursue_target
	pursuing_kind = null
	pursue_target = null
	on_pursuit_finished(kind, target, success)

/datum/bot_brain/proc/stop_pursuit()
	deltimer(stuck_timer_id)
	if(!pursuing_kind)
		return
	walk(owner, 0)
	current_path = null
	pursuing_kind = null
	pursue_target = null
