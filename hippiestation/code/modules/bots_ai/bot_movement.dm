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
	/// Until when this bot stays where it is because somebody asked it to (hold_still_for()).
	var/stand_still_until = 0
	// Set around the climbing pass when it's run for a stroll or an everyday errand (a bot hemmed in by
	// furniture, see is_hemmed_in()): over a table, yes - through a locked door or a window, still no.
	var/pathing_climb_only = FALSE
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
	/// When the route search in progress began: one going on for half a minute has died under itself (repath()).
	var/repath_started_at = 0
	// Set by do_repath() when a NEW pursuit replaced the one it was computing a route for
	// while it was yielding inside the pathfinder - see repath().
	var/repath_superseded = FALSE

/datum/bot_brain
	/// Where it was, and since when, for watch_for_freeze().
	var/turf/freeze_watch_turf
	var/freeze_watch_since = 0

/// On its way somewhere for an errand and not a step taken in a minute and a half: whatever's gone wrong under it, a person would
/// have given up and done something else long since. Bots stood for six and ten minutes on one walk (the user: "standing or
/// pacing"), the move to it never finishing and never failing. Not while it's held, cuffed, down, seated or being dragged.
/datum/bot_brain/proc/watch_for_freeze()
	var/turf/here = get_turf(owner)
	if(here != freeze_watch_turf || !pursuing_kind || state != BOT_STATE_GOAL || !current_goal)
		freeze_watch_turf = here
		freeze_watch_since = world.time
		return
	if(world.time - freeze_watch_since < 90 SECONDS || owner.incapacitated() || owner.handcuffed || owner.buckled || owner.pulledby)
		return
	bot_log(src, "hasn't moved in [round((world.time - freeze_watch_since) / 10)]s on its way to [pursue_target] for [current_goal.type] - giving that up")
	bot_tally("unfroze")
	freeze_watch_since = world.time
	busy_clearing = FALSE //whatever it was waiting on in there has long since stopped mattering
	repathing = FALSE
	stop_pursuit()
	give_up_goal()

/// Whether the walk in progress keeps to where the bot is allowed to go: a stroll, keeping up with someone it's
/// tagging along with (bot_chatter.dm), or everyday work (bot_goal.lawful).
/datum/bot_brain/proc/pursuit_is_lawful()
	// A greytider that hacked its way somewhere it has no access to gets back out the same way. One cook got into maintenance on a raid
	// and spent the rest of the shift in there, giving up 24 dishes at the end of the route search for want of a door its ID opened.
	if(greytider && stray_without_access())
		return FALSE
	if(pursuing_kind == "wander" || pursuing_kind == "follow" || pursuing_kind == "item" || pursuing_kind == "locker") //a scientist once hacked the kitchen door for a bottle of enzyme
		return TRUE
	return pursuing_kind == "goal" && current_goal?.lawful

/datum/bot_brain
	/// Places an everyday errand lately found no way into -> until when errands there are let be (no_way_in_lately()).
	var/list/no_way_into

/// What a place is, for no_way_into: the room, but not maintenance (one area in pieces, doors between them) nor the room it's in
/// (a way it can't get across its own room is something in the way, not a locked door). A Bot Gym arena is all one room: the tile.
/datum/bot_brain/proc/no_way_key(atom/A)
	var/turf/T = get_turf(A)
	if(!T)
		return null
	if(gym_run)
		return T
	var/area/where = T.loc
	if(istype(where, /area/maintenance) || where == get_area(owner))
		return null
	return where

/// An everyday errand found no way there: errands in the same room are let be for two minutes. Turning each one down after a few
/// tries only rested that one thing, and a room is full of them: a botanist cut off from Hydroponics by bad air went for one tray
/// after another and gave up 76 times, an engineer outside Engineering 72 times on the supermatter's kit.
/datum/bot_brain/proc/note_no_way_in(atom/destination)
	var/key = no_way_key(destination)
	if(key)
		LAZYSET(no_way_into, key, world.time + 2 MINUTES)

/datum/bot_brain/proc/no_way_in_lately(atom/A)
	if(!no_way_into)
		return FALSE
	var/key = no_way_key(A)
	return key && LAZYACCESS(no_way_into, key) > world.time

/datum/bot_brain
	/// A Bot Gym scenario's stand-in for being somewhere its ID has no business (stray_without_access()).
	var/gym_strayed = FALSE

/// Somewhere its ID doesn't let it in or out of: maintenance, with no maintenance access.
/datum/bot_brain/proc/stray_without_access()
	if(gym_run)
		return gym_strayed
	if(!istype(get_area(owner), /area/maintenance))
		return FALSE
	var/obj/item/card/id/card = route_card()
	return !(ACCESS_MAINT_TUNNELS in card?.access)

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
	haul_load = state == BOT_STATE_GOAL ? owner.pulling : null
	haul_waiting_since = 0
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
	if(repathing && world.time > repath_started_at + 30 SECONDS)
		bot_log(src, "a route search has been running since [DisplayTimeText(world.time - repath_started_at)] ago - counting it as dead")
		repathing = FALSE
	if(repathing)
		bot_log_verbose(src, "repath: already repathing, ignoring reentrant call")
		return FALSE
	repathing = TRUE
	repath_started_at = world.time
	repath_superseded = FALSE
	begin_reach_scope() //one flood cache for the whole cascade - see bot_path_to() (bot_pathing_permissive.dm)
	// Whatever runs under the search (an arrival, a pick-up, a goal's next step) can runtime. Uncaught, that left `repathing` set for
	// good, every walk after it was turned away as "already repathing", and the bot never took another step: an assistant shut in
	// Engineering had five doors opened for it and stood where it was for the rest of the shift, a harmonica's runtime the cause.
	try
		. = do_repath()
	catch(var/exception/e)
		bot_log_exception(src, "repath", e)
		. = FALSE
	end_reach_scope()
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

	var/obj/item/card/id/id_card = route_card()
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
	// A mob is reached from where the game lets a hand reach it (Adjacent()), not from any tile beside it: the cow behind its pen's border
	// windows and Ian sat on the HoP's desk windoor were walked up to on the glass side, and the petting failed there every time.
	var/atom/movable/reach_mob = (isliving(pursue_target) && isturf(pursue_target.loc)) ? pursue_target : null
	var/list/adjacent_candidates = adjacent_turf_candidates(destination, reach_mob)
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

	// A stroll doesn't climb furniture either (see try_path_to_no_climb()) - unless the bot is hemmed in by it: one
	// that went over a table after a tool, on an errand that allowed it, has to be able to come back the same way.
	// A Quartermaster once stood in a corner of Technical Storage behind two tables for six minutes.
	if((!current_path || !current_path.len) && (!pursuit_is_lawful() || is_hemmed_in()))
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
		if(!pursuit_is_lawful() && try_unlock_route(destination, id_card))
			return supersede_repath() //now fetching it; repath() re-plans for that pursuit
		current_path = null
		last_path_fail_reason = "no path found in any pass (dist=[get_dist(owner, destination)], area=[get_area_name(destination)])"
		bot_log(src, "no path to [destination] @ [bot_coord(get_turf(destination))] ([get_area_name(destination)])")
		if(pursuing_kind == "goal" && pursuit_is_lawful())
			note_no_way_in(destination)
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
/// With reach (a mob on dest), only the tiles it could be reached from by hand: not across a border window or a shut windoor.
/datum/bot_brain/proc/adjacent_turf_candidates(turf/dest, atom/movable/reach)
	var/list/candidates = list()
	var/list/dists = list()
	// The four straight neighbours, and only with none of those to stand on, the corners it can be reached from (the game's own
	// Adjacent(): across a table, not round a wall). The cautery in Hippie's and Box's Surgery is on the table in the corner, with
	// a table either side of it: a player takes it across the corner, and to a bot there was "no way to it by its own doors", so no
	// operation there could ever have its tools.
	for(var/corners in 0 to 1)
		if(corners && length(candidates))
			break
		for(var/d in (corners ? GLOB.diagonals : GLOB.cardinals))
			var/turf/neighbor = get_step(dest, d)
			if(!neighbor || neighbor == get_turf(owner))
				continue
			if(neighbor.density || !istype(neighbor, /turf/open))
				continue
			if(isspaceturf(neighbor) && !can_path_through_space() && !bot_turf_crossable_without_boots(neighbor, owner))
				continue //somewhere the bot could stand and still move - the same rule the route search goes by
			if(bot_turf_has_active_field(neighbor))
				continue //an active containment field/generator shocks on every step or bump attempt (bot_pathing_permissive.dm) - never a genuinely open candidate
			var/blocked = FALSE
			for(var/atom/movable/AM in neighbor)
				if(!AM.density)
					continue
				// Somebody standing there moves, or swaps places. Counted as in the way, a machine with one tile free beside it
				// couldn't be reached while they were: the Booze-O-Mat is one, and a bartender with Pun Pun behind the bar went minutes without a glass.
				var/mob/living/stood_there = AM
				if(!istype(stood_there) || stood_there.buckled)
					blocked = TRUE
					break
			if(blocked)
				continue
			if(corners && !dest.Adjacent(neighbor))
				continue
			if(reach && !neighbor.Adjacent(reach, reach, owner)) //stood here, as the bot would reach for it
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
	// On a stroll or an everyday errand, a door this ID doesn't open isn't walked through just because somebody
	// has left it open (bot_doors.dm) - unless the bot is shut in somewhere, and it's the way out.
	pathing_no_tailgating = pursuit_is_lawful() && !is_shut_in()
	var/list/path = bot_path_to(dest, /turf/proc/Distance_cardinal, /turf/proc/bot_reachable_strict, id_card, !can_path_through_space())
	pathing_no_tailgating = FALSE
	bot_log_verbose(src, "  pass 1 (legit route) to [dest] @ [bot_coord(dest)]: [path ? "[path.len] nodes" : "no path"]")
	// Not back through a room it's just got out of for want of air (goals/refill_internals.dm).
	if(path && path.len && path_crosses_bad_air(path))
		bot_log_verbose(src, "  that way's through somewhere it couldn't breathe - not that way")
		path = null
	if(path && path.len)
		return path
	// Someone out for a stroll who finds the way barred just picks somewhere else - they don't hack a door or
	// smash a window to get to a random spot, and neither does anyone going about their ordinary work. The goals
	// written to get through anything, fetches for them, combat and arrests still get every fallback.
	if(pursuit_is_lawful())
		return path

	// No legitimate (unlocked) route - try again allowing routes through a locked (but
	// unwelded, powered, access-satisfied) airlock or a window it can break, but still
	// NOT through climbable furniture.
	pathing_allow_climb = FALSE
	path = bot_path_to(dest, /turf/proc/bot_weighted_distance, /turf/proc/bot_reachable_permissive, id_card, !can_path_through_space())
	pathing_allow_climb = TRUE
	// dest's own name is ambiguous when an adjacent-turf pass shares the destination's
	// exact turf type (e.g. two carpet tiles both print as "the carpet") - always show
	// coordinates here too, not just in pass 1, so log traces can actually tell which
	// specific turf a given pass/result belongs to.
	bot_log_verbose(src, "  pass 2 (hack/break, no climb) to [dest] @ [bot_coord(dest)]: [path ? "[path.len] nodes" : "no path"]")
	if(path && path.len && path_crosses_bad_air(path))
		path = null
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
		path = bot_path_to(dest, /turf/proc/bot_weighted_distance, /turf/proc/bot_reachable_permissive, id_card, !can_path_through_space())
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
	pathing_climb_only = pursuit_is_lawful()
	var/list/path = bot_path_to(dest, /turf/proc/bot_weighted_distance, /turf/proc/bot_reachable_permissive, id_card, !can_path_through_space())
	pathing_climb_only = FALSE
	bot_log_verbose(src, "  pass 3 (allow climbing) to [dest] @ [bot_coord(dest)]: [path ? "[path.len] nodes" : "no path"]")
	if(path && path.len && path_crosses_bad_air(path))
		return null
	if(path && path.len)
		bot_log(src, "no route to [dest] without climbing - climbing over furniture instead")
	return path

/// Fewer tiles than this to walk to without climbing or forcing anything, and the bot is hemmed in.
#define BOT_HEMMED_IN_TILES 12

/// Whether the bot is shut in a pocket of floor by furniture: only a handful of tiles it can walk to by the
/// ordinary rules. It got in over a table, and gets out the same way.
/datum/bot_brain/proc/is_hemmed_in()
	var/turf/start = get_turf(owner)
	if(!start)
		return FALSE
	var/obj/item/card/id/id_card = route_card()
	var/simulated_only = !can_path_through_space()
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/at = 1
	while(at <= length(queue))
		var/turf/T = queue[at++]
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(T, d)
			if(!next || seen[next] || !T.bot_reachable_strict(owner, next, id_card, simulated_only))
				continue
			seen[next] = TRUE
			queue += next
			if(length(queue) >= BOT_HEMMED_IN_TILES)
				return FALSE
	return TRUE

#undef BOT_HEMMED_IN_TILES

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
	// A route is for where the bot was when it was planned. A shuttle that has gone with it aboard leaves every tile of it on another
	// level, and a step "towards" one went straight off the side into hyperspace; the dock a shuttle has left is open space where the
	// route had floor. A shaft miner and an assistant were thrown into deep space off the mining shuttle and died that way, the same
	// minute. The step fails and the walk is planned again from where the bot is.
	var/turf/here = get_turf(owner)
	if(!here || next_node.z != here.z || get_dist(here, next_node) > 1 || bot_turf_is_deadly(get_step(here, get_dir(here, next_node))))
		return FALSE
	if(SSpathfinder.space_type_cache[next_node.type] && !SSpathfinder.space_type_cache[here.type] && !bot_turf_crossable_without_boots(next_node, owner) && !can_path_through_space())
		back_off_from_space(here, next_node)
		return FALSE
	// Walking into an airlock opens it (Bumped()): not one with vacuum behind it, without a suit (bot_door_opens_on_vacuum(), bot_items.dm).
	var/obj/machinery/door/airlock/door = locate() in next_node
	if(door && door.density && !is_space_protected_without_boots() && bot_door_opens_on_vacuum(door, here))
		return FALSE
	if(op_team)
		op_mind_jetpack(next_node) //goals/nuke_ops.dm
	// With gravity under it Process_Spacemove() says yes, five procs down, from this same has_gravity(): asked here first. Without
	// gravity it's asked as before.
	if(!owner.has_gravity() && !owner.Process_Spacemove(get_dir(owner, next_node)))
		return FALSE
	// Somebody dragging something big on the next tile: wait for them, or go round. Walking into them swaps places (living.dm), and
	// what they're dragging can't follow them on to a tile with somebody on it: engineers taking emitters along the central hallway
	// lost hold of them to passers-by eight and ten times a shift.
	for(var/mob/living/L in next_node)
		if(L != owner && L.pulling?.density && !isliving(L.pulling))
			return FALSE
	make_way_through(next_node)
	// Somebody stood on the next tile with something heavy in tow (a crate, a canister, a prisoner on their feet): walking into them
	// swaps places, and what's dragged can't come on to the tile they're now on, so the pull breaks. A crate went that way in a
	// doorway twelve times in twelve shifts, each with somebody stood in it. Round them if there's room; if not, "coming through"
	// and a wait for them to move, as a person dragging a crate would.
	if(owner.pulling?.density)
		var/mob/living/in_way = haul_blocker(next_node)
		if(in_way)
			if(haul_round(next_node))
				return TRUE
			if(!haul_waiting_since)
				haul_waiting_since = world.time
				bot_log(src, "[in_way] is in the way with [owner.pulling] in tow - waiting for them to move")
			coming_through(in_way)
			return FALSE
	haul_waiting_since = 0
	// Put off this very tile a moment ago by somebody walking on to it, and they're still stood there: it's theirs for now, and it waits
	// behind them (do_step_next_node() holds the walk without counting it stuck). Two bots after the one tile (beside a man held for
	// Security, at a newscaster to smash, the spot short of a suspect, the tile at a door that won't open) walked into each other and swapped
	// places (living.dm MobBump()) once a second for as long as it lasted: half of what a 12-shift batch counted as pacing (bugs1112base,
	// 33 of 66). Now they take turns, ten seconds each at most.
	if(yields_tile(next_node))
		return FALSE
	var/list/stood_there
	if(locate(/mob/living/carbon/human) in next_node)
		for(var/mob/living/carbon/human/stander in next_node)
			if(stander != owner && stander.bot_brain && (stander.mobility_flags & MOBILITY_STAND))
				LAZYADD(stood_there, stander)
	. = step_towards(owner, next_node)
	// Places swapped: whoever's now where this bot was remembers the tile it was put off (yields_tile())
	for(var/mob/living/carbon/human/moved as anything in stood_there)
		if(moved.bot_brain && get_turf(moved) == here && get_turf(owner) == next_node)
			moved.bot_brain.swapped_off_turf = next_node
			moved.bot_brain.swapped_off_until = world.time + 10 SECONDS

/// Waiting with something in tow for somebody to move out of the way (bot_step_towards()): since when. A wait, not being stuck, for
/// HAUL_WAIT; after that it counts as stuck as anything else does.
/datum/bot_brain/var/haul_waiting_since = 0
#define HAUL_WAIT (20 SECONDS)

/// The tile this bot was last swapped off by somebody walking on to it (bot_step_towards()), and until when it leaves it to them while
/// they're stood on it (yields_tile())
/datum/bot_brain/var/turf/swapped_off_turf
/datum/bot_brain/var/swapped_off_until = 0

/// Somebody swapped it off `T` a moment ago and is still stood there, and this isn't a fight: it lets them have it, and waits. A wait, not
/// being stuck (do_step_next_node(), on_stuck_timeout()): it used to count as stuck, reroute the same way and give the walk up.
/datum/bot_brain/proc/yields_tile(turf/T)
	if(!T || T != swapped_off_turf || world.time >= swapped_off_until || state == BOT_STATE_COMBAT)
		return FALSE
	for(var/mob/living/carbon/human/there in T)
		if(there != owner && there.stat == CONSCIOUS && (there.mobility_flags & MOBILITY_STAND))
			return TRUE
	return FALSE

/// Somebody on the tile who'd be swapped with: on their feet (a body lying there is walked over, and what's dragged follows on)
/datum/bot_brain/proc/haul_blocker(turf/next_node)
	for(var/mob/living/L in next_node)
		if(L != owner && L != owner.pulling && L.density)
			return L

/datum/bot_brain/proc/coming_through(mob/living/in_way)
	if(world.time < next_coming_through)
		return
	next_coming_through = world.time + 30 SECONDS
	owner.face_atom(in_way)
	bot_say(owner, pick("Coming through!", "Mind your back!", "Heavy load, make way.", "Excuse me, coming through."))

/// Space where the way on was and no suit: a person steps back from the edge rather than wait on the lip while the air rushes out past
/// them. A bot stood there for its reroute, and the rush of air threw it out into the gap (gym: the floor ahead turns to space).
/datum/bot_brain/proc/back_off_from_space(turf/here, turf/space)
	if(!bot_turf_borders_space(here))
		return
	var/turf/best
	for(var/direction in GLOB.cardinals)
		var/turf/open/T = get_step(here, direction)
		if(!istype(T) || T.density || SSpathfinder.space_type_cache[T.type] || bot_turf_borders_space(T) || is_blocked_turf(T, TRUE))
			continue
		if(!best || get_dist(T, space) > get_dist(best, space))
			best = T
	if(best && step_towards(owner, best))
		bot_log(src, "space where the way on was - stepping back from the edge")

/proc/bot_turf_borders_space(turf/T)
	for(var/direction in GLOB.cardinals)
		var/turf/next = get_step(T, direction)
		if(next && SSpathfinder.space_type_cache[next.type])
			return TRUE
	return FALSE

/// Somebody on the next tile who isn't a fight: places are only swapped with both on help intent (living.dm), and a bot that had been
/// shooting stayed on harm. Two operatives holding by the nuke stood in the infiltrator's doorway, and the one with the disk was stuck
/// four tiles from it until it gave up. It goes on help, and a bot there that isn't fighting does too, as a teammate would at "coming through".
/datum/bot_brain/proc/make_way_through(turf/next_node)
	if(owner.pulling?.density)
		haul_past(next_node)
	if(state == BOT_STATE_COMBAT || owner.a_intent == INTENT_HELP && !(locate(/mob/living/carbon/human) in next_node))
		return
	for(var/mob/living/carbon/human/H in next_node)
		if(H == owner || H == attacker || H == pursue_target || H.bot_brain?.attacker == owner)
			return
		owner.a_intent = INTENT_HELP
		if(H.bot_brain && H.bot_brain.state != BOT_STATE_COMBAT)
			H.a_intent = INTENT_HELP

/datum/bot_brain/var/next_coming_through = 0

/// Dragging something big (an emitter, a canister) with somebody stood in the way. A swap of places (living.dm) leaves what's dragged
/// behind, as there's somebody now on the tile it was to follow on to, and the pull breaks: an engineer taking an emitter to the blob
/// lost it on the same crewman three times running. "Coming through" - a bot that's there steps aside off the way, as a crewmate would.
/datum/bot_brain/proc/haul_past(turf/next_node)
	var/turf/here = get_turf(owner)
	var/turf/behind = get_turf(owner.pulling)
	var/turf/after = length(current_path) >= 2 ? current_path[2] : null
	for(var/mob/living/carbon/human/H in next_node)
		if(H == owner || !H.bot_brain || H.bot_brain.state == BOT_STATE_COMBAT || H.incapacitated() || H.buckled || H.pulledby || H.pulling)
			continue
		for(var/d in GLOB.alldirs)
			var/turf/T = get_step(next_node, d)
			if(!T || T == here || T == behind || T == after || T.density || isspaceturf(T) || is_blocked_turf(T))
				continue
			if(H.Move(T, d))
				coming_through(H)
				break

/// Dragging something big with somebody still stood on the next tile, who didn't step aside (a player, somebody busy): round them, on to
/// a free tile that's next to where the way goes after them. Swapping places with them leaves what's dragged behind.
/datum/bot_brain/proc/haul_round(turf/next_node)
	var/turf/here = get_turf(owner)
	var/turf/behind = get_turf(owner.pulling)
	var/turf/after = length(current_path) >= 2 ? current_path[2] : null
	if(!after)
		return FALSE
	for(var/turf/T in orange(1, here))
		if(T == next_node || T == behind || get_dist(T, after) > 1 || T.density || isspaceturf(T) || is_blocked_turf(T))
			continue
		if(owner.Move(T, get_dir(here, T)))
			if(current_path[1] == next_node)
				current_path.Cut(1, 2)
			return TRUE
	return FALSE

/// A bot's pull that it didn't end itself goes in the log with what ended it. Pulls came to nothing with no line at all, and the give-up
/// that followed was put down to whatever had been said before. The proc that let go is read off the call stack (caller); a bot
/// letting go itself is a bot proc calling stop_pulling() directly, and isn't logged.
/mob/living/carbon/human/stop_pulling()
	if(bot_brain && pulling)
		bot_brain.pull_ended(pulling, caller)
	return ..()

/// What a goal's walk set off dragging (pursue()); the walk stops if it's lost on the way (do_step_next_node())
/datum/bot_brain/var/atom/movable/haul_load

/datum/bot_brain/proc/pull_ended(atom/movable/AM, callee/from)
	var/callee/first = from
	if(!first)
		return
	var/first_proc = "[first.proc]"
	// Its own hand: a bot proc letting go, or taking hold of something else.
	if(findtext(first_proc, "/bot_") || findtext(first_proc, "/start_pulling") && first.src == owner && findtext("[first.caller?.proc]", "/bot_"))
		if(AM == haul_load)
			haul_load = null
		return
	var/cause
	var/dist = get_dist(owner, AM)
	switch(copytext(first_proc, findlasttext(first_proc, "/") + 1))
		if("start_pulling")
			cause = "taken off it by [first.src]"
		if("update_mobility")
			cause = "knocked down"
		if("PushAM")
			cause = "walked into it"
		if("check_pulling", "Move_Pulled", "Move")
			if(AM.anchored || AM.move_resist > owner.move_force)
				cause = "it's fixed down"
			else if(!isturf(owner.loc))
				cause = "inside [owner.loc]"
			else if(dist > 1)
				cause = "left behind, [dist] tiles back"
	if(!cause)
		var/list/chain = list()
		var/callee/c = first
		while(c && length(chain) < 3)
			var/p = "[c.proc]"
			chain += copytext(p, findlasttext(p, "/") + 1)
			c = c.caller
		cause = "let go in [jointext(chain, " < ")]"
	var/list/near = list()
	for(var/mob/living/L in range(1, AM))
		if(L != owner && L != AM)
			near += "[L]"
	// Reported a moment later: a move that lets go (forceMove() into the sleeper, on to the operating table) does so before the thing
	// has gone anywhere, so where it ends up is only known after.
	addtimer(CALLBACK(src, PROC_REF(report_pull_lost), AM, cause, near), 1)

/datum/bot_brain/proc/report_pull_lost(atom/movable/AM, cause, list/near)
	if(QDELETED(AM) || QDELETED(owner))
		return
	var/mob/M = AM
	var/atom/buckled_to = ismob(M) ? M.buckled : null
	if(!isturf(AM.loc) || buckled_to || owner.pulling == AM)
		bot_log_verbose(src, "let go of [AM]: [isturf(AM.loc) ? (buckled_to ? "buckled to [buckled_to]" : "held again") : "into [AM.loc]"]")
		return
	bot_log(src, "lost hold of [AM]: [cause][length(near) ? " ([english_list(near)] by it)" : ""]")
	telemetry_event("pull_lost", list("target" = "[AM]", "cause" = cause, "by" = length(near)))

// step_next_node() re-invokes itself via addtimer to keep walking (see its own
// comment) - previously that self-perpetuation went through on_pursuit_moved(), which
// wrapped it in try/catch specifically so a crash wouldn't silently kill the whole
// movement chain forever (nothing else would ever reschedule it). Keep that same
// protection here now that step_next_node() reschedules itself directly.
/datum/bot_brain/proc/step_next_node()
	if(QDELETED(owner)) //gone while this timer was waiting
		return
	try
		do_step_next_node()
	catch(var/exception/e)
		bot_log_exception(src, "step_next_node", e)
		if(pursuing_kind)
			repath() //self-heal: never let a crash here leave the pursuit permanently dead
		else if(state == BOT_STATE_GOAL && current_goal)
			// The walk itself had ended; what crashed was the goal's next step, run from finish_pursuit(). Nothing
			// would ever run that step again (a doctor stood over its patient for the rest of the shift after a
			// runtime in the game's strip code) - count it as failed, so the goal retries or gives up.
			try
				advance_goal_step(FALSE)
			catch(var/exception/again)
				bot_log_exception(src, "step_next_node/advance_goal_step", again)
				give_up_goal()

/datum/bot_brain/proc/do_step_next_node()
	// Out cold, stunned or held in a neck grab. A player's keys do nothing then (client/Move() checks MOBILITY_MOVE), but
	// this timer isn't a key press, step_towards() goes straight to Move(), and process() has stopped so nobody ends the
	// walk: an atmos tech walked round a kitchen at -80 health and crowbarred a firelock. It waits where it is, and carries
	// on if it comes round.
	if(!(owner.mobility_flags & MOBILITY_MOVE))
		deltimer(stuck_timer_id)
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), 5, TIMER_STOPPABLE)
		return
	// Asked to hold still (a doctor coming over to it, goals/treat_patient.dm): the walk waits where it is.
	if(world.time < stand_still_until && state != BOT_STATE_COMBAT && state != BOT_STATE_ARREST)
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), max(2, stand_still_until - world.time), TIMER_STOPPABLE)
		return
	// Climbing out of a pool (pool_main.dm) needs a dedicated ~2 second do_mob()
	// channel (try_escape_pool(), bot_items.dm, called every process() tick while
	// still swimming), and a do_mob() channel cancels the instant the user's state
	// changes mid-channel. This movement timer chain keeps running on its own separate
	// schedule regardless of swimming state, and every step_towards() attempt it fired
	// counted as exactly that kind of disruption - restarting the climb-out from
	// scratch every single time, forever, which is why a bot could fall in a pool and
	// never actually get back out. Defer entirely until back on dry land; nothing about
	// the path is lost by waiting, it's still sitting in current_path untouched. Not when it's in after somebody (bot_may_jump_in(),
	// bot_pathing_permissive.dm): it wades on to them, and only climbs out once it's done.
	if(owner.swimming && !(bot_may_jump_in(owner) && !owner.lying && owner.getOxyLoss() < 30))
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), max(1, owner.movement_delay()), TIMER_STOPPABLE)
		return
	// Dragging something that's come loose behind (somebody stood in its way, it caught on a corner): a player notices and goes back
	// for it. An engineer hauling an emitter to the blob used to walk the rest of the way with nothing in tow.
	var/datum/bot_step/hauling_step = (state == BOT_STATE_GOAL && current_strategy && current_step_index <= length(current_strategy.steps)) ? current_strategy.steps[current_step_index] : null
	if(hauling_step?.hauling && current_goal?.target && owner.pulling != current_goal.target)
		bot_log(src, "let go of [current_goal.target] on the way")
		stop_pursuit()
		hauling_step.lost_hold(src)
		return
	// The same for any goal's walk that set off with something in tow (pursue()): a crate, a prisoner, a body. It walked the rest of
	// the way with nothing, and the step at the end failed there instead ("lost them somewhere on the way over").
	if(hauling_step && haul_load && owner.pulling != haul_load)
		var/atom/movable/lost = haul_load
		haul_load = null
		bot_log(src, "let go of [lost] on the way - the walk stops here")
		stop_pursuit()
		hauling_step.lost_hold(src)
		return
	// Carried along its own way (a conveyor, a shove the right way): on from where it is now.
	var/turf/here = get_turf(owner)
	var/at = current_path ? current_path.Find(here) : 0
	if(at)
		current_path.Cut(1, at + 1)
	if(!current_path || !current_path.len)
		finish_pursuit(TRUE)
		return
	var/turf/next_node = current_path[1]
	// Knocked off it (shoved, slipped, pulled, thrown, or the arrivals shuttle moving under it): the next step isn't beside
	// it any more, and a step can't get there. It went on pushing at it until it counted itself stuck and gave up - 141 of
	// the 267 "still stuck" give-ups in a three-shift batch, half of Security's calls answered never. A person looks
	// where they are and finds the way again.
	if(here && (next_node.z != here.z || get_dist(here, next_node) > 1))
		bot_log(src, "off the way I was going ([next_node.z == here.z ? "[get_dist(here, next_node)] tiles" : "another level"] from the next step) - finding the way again")
		// The old route goes, as pursue() drops it: do_repath() only searches when there's none, and kept this one.
		current_path = null
		deltimer(stuck_timer_id)
		if(repathing)
			addtimer(CALLBACK(src, PROC_REF(repath)), 1) //as pursue() does with one already under way
		else
			repath()
		return
	bot_log_verbose(src, "step_next_node: [here] -> [next_node] @ ([next_node.x],[next_node.y],[next_node.z]), [current_path.len] nodes left") //bot_coord() written out and the turf found above: this is every step of every walk, two thirds of the trace
	// try_clear_obstruction() (bot_items.dm) checks against the real movement engine
	// itself before touching anything, and can yield for real time (climbing a
	// structure).
	var/expected_kind = pursuing_kind
	var/atom/expected_target = pursue_target
	var/turf/before_clear = get_turf(owner)
	busy_clearing = TRUE
	// In soft crit it can drag itself along, but it can't use a tool on anything in its way.
	if(!owner.incapacitated(ignore_restraints = TRUE))
		try_clear_obstruction()
	busy_clearing = FALSE
	if(QDELETED(owner))
		return //gone while clearing the way (it can yield): a nuke's blast gibbed one mid-step
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

	next_node = mind_the_footing(next_node) //bot_hazards.dm
	if(!next_node)
		finish_pursuit(TRUE) //beside it is as good as on it
		return
	// An emitter that's come on across the way since this stroll was planned (bot_hazards.dm): it isn't worth it, and the
	// next one's planned with the beam on the map.
	if(beam_ahead(next_node))
		bot_log(src, "an emitter's firing across the way ahead - not going that way")
		bot_tally("kept out of a beam")
		finish_pursuit(FALSE)
		return
	// Into the water off dry floor (bot_steps_into_pool(), bot_pathing_permissive.dm): only if it may go in now (bot_may_jump_in()), not
	// because it could when the route was planned. An officer that had climbed out short of breath was walked straight back in by the
	// route it fell in on, and drowned (bugs1112base run1). Whatever drives the walk decides again (handle_arrest(), handle_combat()): round
	// to the side, and a wait there for its breath (poolside_instead(), bot_items.dm).
	if(bot_steps_into_pool(get_turf(owner), next_node))
		if(!bot_may_jump_in(owner))
			bot_log(src, "not going into the water like this")
			if(pursuing_kind == "arrest" || pursuing_kind == "combat")
				stop_pursuit()
			else
				finish_pursuit(FALSE)
			return
		// In after them, it lowers itself in off the side, two seconds stood still (pool_main.dm MouseDrop_T()), as somebody who knows the
		// pool does. Walking in is a fall, a mouthful of water and six seconds on its back under it: 33 and 39 of suffocation in a shift,
		// past where it climbs out again (try_escape_pool(), bot_items.dm), so it never reached anybody in the water that way.
		if(!owner.swimming && owner.has_gravity())
			bot_log(src, "lowering myself into the pool after [pursue_target]")
			var/list/route = current_path
			busy_clearing = TRUE
			next_node.MouseDrop_T(owner, owner)
			busy_clearing = FALSE
			if(QDELETED(owner) || current_path != route)
				return //gone, or the walk was planned again while it was at it: that one drives it
			stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), max(1, owner.movement_delay()), TIMER_STOPPABLE)
			return
	var/turf/left_turf = get_turf(owner)
	if(bot_step_towards(next_node))
		quick_step_retries = 0
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
		swat_passing_mice() //bot_human.dm - crew squash mice in passing (they chew cables)
		// Same idea, security-flavored - see close_airlock_behind()'s own comment.
		close_airlock_behind(left_turf)
		// Re-invoke ourselves after a normal per-tile delay, same pacing walk_to()'s
		// Lag parameter used to provide, just driven explicitly instead of trusted to
		// its own internal continuation.
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), max(1, owner.movement_delay()), TIMER_STOPPABLE)
	else if(haul_waiting_since && world.time - haul_waiting_since < HAUL_WAIT)
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), 5, TIMER_STOPPABLE) //somebody in the way of what's in tow: wait on them
	else if(yields_tile(next_node))
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), 5, TIMER_STOPPABLE) //letting somebody have the tile it was just swapped off (bot_step_towards()): a wait, not stuck
	else if(quick_step_retries < BOT_QUICK_STEP_RETRIES)
		// Didn't move this attempt - usually a door still finishing its opening animation.
		// Step through the moment it's passable, like a person walking into it, instead of
		// standing still for a full second (telemetry: most mid-route stops were exactly this).
		quick_step_retries++
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), 2, TIMER_STOPPABLE)
	else
		// Still not moving after ~1s of quick retries: on_stuck_timeout()'s repeat-counting/
		// give-up logic takes over.
		quick_step_retries = 0
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

	// Letting somebody have the tile it was just swapped off (yields_tile()): a wait, not being stuck, and not a reason to reroute
	if(yields_tile(expected_node))
		stuck_timer_id = addtimer(CALLBACK(src, PROC_REF(step_next_node)), 5, TIMER_STOPPABLE)
		return

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
		if(try_clear_obstruction(stuck = TRUE))
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

#undef HAUL_WAIT
