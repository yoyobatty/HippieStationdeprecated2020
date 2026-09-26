/datum/bot_goal/acquire_tool
	// Set by New() when this goal was raised for a SPECIFIC missing tool (ensure_tools,
	// acquire_captains_id.dm, always knows exactly which one it's still missing) rather
	// than plain-wander's "grab anything useful" case (left null there). See
	// resolve_target()'s comment for why this changes target priority.
	var/needed_tool_type
	// The exact path is_reachable() found and verified, for the exact atom it verified
	// it to - see is_reachable()'s comment for why this gets reused directly by
	// move_to.execute() (bot_goals.dm) instead of letting pursue() compute a brand new
	// one. One-shot: cleared the moment move_to consumes it, never reused stale.
	var/list/cached_path
	var/atom/cached_path_target
	var/cached_path_cost = 0

/datum/bot_goal/acquire_tool/New(needed_tool_type)
	. = ..()
	src.needed_tool_type = needed_tool_type

// Priority search for "I need a tool". Two different situations:
// - A SPECIFIC tool type is needed (ensure_tools suspended the outer goal over it):
//   prioritize whatever source actually CONTAINS that type - a closet/locker first
//   (tool storage etc tend to stock a full, varied set), then a toolbox, then a loose
//   item - over "whatever tool-shaped thing is nearest" (see resolve_typed_target()).
//   Without this, the bot would cheerfully walk to the literal closest toolbox even if
//   it obviously can't contain the one tool actually missing (an "emergency toolbox"
//   only ever has a crowbar and a mini welder, say) - "succeed" at grabbing something,
//   anything, from it, and still be right back here needing the same tool a moment
//   later, having wasted the whole trip. This ALREADY scans and distance-sorts every
//   closet/toolbox/item on the station (whichever tier matches), so a previously-used
//   known-good source is naturally included and competes fairly on distance - it does
//   NOT get a separate, unconditional first-look here. That used to make the bot walk
//   all the way back to the first tool room it ever found, even while standing right
//   next to a second, never-visited one that would've been closer - the honest, full
//   scan below picks whichever is actually nearest, known or not.
// - No specific type (plain wandering picked this goal up on its own, or nothing
//   anywhere has the specific type needed): a known-good source (see on_success()
//   below) is checked first here instead - this tier isn't an exhaustive station-wide
//   scan (find_tool_goal() is visibility-only, the tiers below cap at the 6 closest by
//   raw distance), so a proven location is worth a quick check before falling back to
//   a blind, capped search that might miss it entirely.
// Each tier only runs if the previous one found nothing, and within a tier the closest
// reachable candidate wins.
/datum/bot_goal/acquire_tool/resolve_target(datum/bot_brain/bot)
	if(needed_tool_type)
		var/atom/typed = resolve_typed_target(bot)
		if(typed)
			target = typed
			return
		// Fall through to the generic tiers below if nothing anywhere actually has the
		// specific type - still better to grab something useful than nothing at all;
		// ensure_tools will just ask again next time it re-checks.

	var/atom/known = pick_reachable(bot, known_source_candidates(bot))
	if(known)
		bot_log(bot, "I've gotten tools from [known] before - heading back there")
		target = known
		return

	// find_tool_goal() (bot_items.dm) only checks visibility (oview(9)), never
	// reachability - it used to skip straight to `target = near` on anything merely
	// nearby, bypassing is_reachable()'s hacking-capability gate entirely. That let a
	// bot with 2 of 5 tools "find" a tool closet sitting behind a fully-shielded
	// airlock it had no way to open (needs the full set to strip, including the very
	// tool it was after) just because the closet happened to be in view, walk all the
	// way over, fail, and burn a whole cycle for nothing. is_reachable() below is the
	// same check the tiers further down already use via pick_reachable() - applying it
	// here too closes that loophole instead of only enforcing it selectively.
	var/atom/near = bot.find_tool_goal()
	if(near && !bot.is_failed_tool_target(near) && is_reachable(bot, near))
		target = near
		return

	// Nearest-by-raw-distance alone picked a target on the far side of a door the bot
	// couldn't get through (the map-straight-line-closest toolbox isn't necessarily
	// the closest one to actually WALK to), even though a genuinely nearby, already-
	// reachable storage room existed. A full pathfind per candidate is too expensive to
	// run for every toolbox/item on the station, so track the closest few by raw
	// distance and only pathfind-verify those - cheap but enough to skip an obviously-
	// blocked nearest candidate in favor of the next-nearest one that's actually
	// walkable.
	var/list/box_candidates = list()
	var/list/box_dists = list()
	for(var/obj/item/storage/toolbox/TB as anything in bot_instances_of(/obj/item/storage/toolbox))
		if(!isturf(TB.loc) || TB.anchored || bot.is_failed_tool_target(TB) || !same_z(bot, TB))
			continue
		// An artistic/crayon toolbox holds no tools at all - "succeeding" at grabbing from
		// it left the bot exactly as empty-handed as before.
		var/has_useful = FALSE
		for(var/obj/item/I in TB)
			if(bot.is_tool_or_toolbox(I) && !bot.already_carries_matching_tool(I))
				has_useful = TRUE
				break
		if(!has_useful)
			continue
		insert_by_distance(box_candidates, box_dists, TB, get_dist(bot.owner, TB))
	var/atom/best_box = pick_reachable(bot, box_candidates)
	if(best_box)
		target = best_box
		return

	var/list/item_candidates = list()
	var/list/item_dists = list()
	for(var/tool_root in GLOB.bot_tool_item_roots)
		for(var/obj/item/I as anything in bot_instances_of(tool_root))
			if(!isturf(I.loc) || I.anchored || bot.is_failed_tool_target(I) || !same_z(bot, I))
				continue
			// already_carries_matching_tool() (bot_items.dm): one screwdriver is exactly as
			// useful as two - this generic "grab anything useful" tier (reached when a
			// blocked obstruction has no idea which specific tool would help, so it just
			// asks for something/anything) used to happily target an exact duplicate of a
			// tool already in hand, a wasted trip that left the bot no better equipped.
			if(bot.already_carries_matching_tool(I))
				continue
			insert_by_distance(item_candidates, item_dists, I, get_dist(bot.owner, I))
	target = pick_reachable(bot, item_candidates)
	if(!target)
		// Every tier came up empty - assign_goal() (bot_goals.dm) will log "couldn't
		// find a target" right after this, but that alone doesn't say WHY. This does:
		// how many candidates each tier actually had to work with, so it's provable
		// whether that's a genuine "nothing exists reachable anywhere" case or just
		// every candidate in a capped list happening to be behind locked doors (see
		// MAX_TOOL_CANDIDATES's comment) while something open sat just past the cutoff.
		bot_log_verbose(bot, "acquire_tool: resolve_target found nothing - box candidates: [box_candidates.len], item candidates: [item_candidates.len]")

// Closet first, then toolbox, then a loose item of the exact needed type - see
// resolve_target()'s comment for why. locate(needed_tool_type) in X is a direct
// contents check (one level, same as everywhere else in this module), so this only ever
// picks a source that's actually going to solve the problem, not just something
// tool-shaped.
/datum/bot_goal/acquire_tool/proc/resolve_typed_target(datum/bot_brain/bot)
	// ONE distance-ranked list across closets, toolboxes and loose items - NOT a strict
	// closet > toolbox > item priority. That old tier order sent a bot to a tool closet
	// 134 tiles away in the far south-east while Primary Tool Storage (loose screwdrivers
	// and toolboxes on tables) sat ~26 tiles from it, purely because "a closet" outranked
	// "a loose item" regardless of distance. Nearest reachable source that actually holds
	// the needed type wins; a loose item gets a small penalty since it only yields that
	// one tool while a closet/toolbox is usually a whole set in one trip.
	var/list/candidates = list()
	var/list/dists = list()
	for(var/obj/structure/closet/C as anything in bot_instances_of(/obj/structure/closet))
		if(QDELETED(C) || bot.is_failed_tool_target(C) || !same_z(bot, C))
			continue
		if(!closet_accessible(bot, C))
			continue
		if(!(locate(needed_tool_type) in C))
			continue
		insert_by_distance(candidates, dists, C, get_dist(bot.owner, C))
	for(var/obj/item/storage/toolbox/TB as anything in bot_instances_of(/obj/item/storage/toolbox))
		if(!isturf(TB.loc) || TB.anchored || bot.is_failed_tool_target(TB) || !same_z(bot, TB))
			continue
		if(!(locate(needed_tool_type) in TB))
			continue
		insert_by_distance(candidates, dists, TB, get_dist(bot.owner, TB))
	for(var/obj/item/I as anything in bot_instances_of(needed_tool_type))
		if(!isturf(I.loc) || I.anchored || bot.is_failed_tool_target(I) || !same_z(bot, I))
			continue
		insert_by_distance(candidates, dists, I, get_dist(bot.owner, I) + 8)
	return pick_reachable(bot, candidates)

// A candidate on a different z-level than the bot is never reachable through
// get_path_to() (this codebase's pathfinder doesn't cross z-levels), so get_dist()'s
// plain 2D math treating it as "close" purely by raw X/Y coordinates is actively
// misleading - it can rank a same-XY-but-different-level candidate (a shuttle that's
// undocked and moved to a completely different part of the z-stack, say) as the
// nearest option, ahead of a genuinely reachable one, and every one of those gets a
// full failed pathfind before pick_reachable() ever falls through to something usable.
/datum/bot_goal/acquire_tool/proc/same_z(datum/bot_brain/bot, atom/A)
	var/turf/T = get_turf(A)
	var/turf/OT = get_turf(bot.owner)
	return T && OT && T.z == OT.z

// A secure, locked closet (a safe, a secure equipment locker, ...) needs its OWN
// access check to open (togglelock()/open(), closets.dm), completely separate from
// whatever door leads to the room it's sitting in - reaching the room at all (even by
// hacking through a locked door to get there) doesn't help if the closet itself then
// refuses to open for lack of access. Without this, a bot could commit to an entire
// break-in just to find the one thing inside it still locked - checking C.allowed()
// up front means a locker the bot's ID was never going to open in the first place gets
// skipped as a candidate entirely, not discovered as a wasted trip.
/datum/bot_goal/acquire_tool/proc/closet_accessible(datum/bot_brain/bot, obj/structure/closet/C)
	return !(C.secure && C.locked && !C.allowed(bot.owner))

// A room/container the bot has SUCCEEDED at pulling a tool from before (on_success()
// below) - filtered down to ones still actually there and still holding what's needed.
// A source the bot personally emptied out (or that got cleaned out by someone/something
// else since) drops out naturally via the "still has a tool" check rather than needing
// its own separate bookkeeping to notice that.
/datum/bot_goal/acquire_tool/proc/known_source_candidates(datum/bot_brain/bot)
	var/list/candidates = list()
	var/list/dists = list()
	for(var/atom/A in bot.known_tool_sources)
		if(QDELETED(A) || !isturf(A.loc) || bot.is_failed_tool_target(A) || !same_z(bot, A))
			continue
		if(istype(A, /obj/structure/closet) && !closet_accessible(bot, A))
			continue //got re-secured/locked since it last worked, or access changed
		if(needed_tool_type)
			if(!(locate(needed_tool_type) in A))
				continue
		else
			var/has_any = FALSE
			for(var/obj/item/I in A)
				if(bot.is_tool_or_toolbox(I))
					has_any = TRUE
					break
			if(!has_any)
				continue
		insert_by_distance(candidates, dists, A, get_dist(bot.owner, A))
	return candidates

// Keeps `sorted` ascending by distance (parallel to `dists`), capped at the closest
// MAX_TOOL_CANDIDATES entries - a bounded insertion instead of sorting the whole
// candidate set. Was briefly raised to 15 on a theory that a cluster of locked doors
// near spawn could fill all 6 nearest slots with inaccessible rooms - reverted after a
// test showed the full 15-candidate window populated and EVERY one still failing
// reachability, which isn't a "ran out of candidates" symptom at all (that run's real
// problem turned out to be the bot stuck cycling in a pool - see do_step_next_node()'s
// swimming check, bot_movement.dm). Back to 6: no evidence it was ever the bottleneck,
// and checking more candidates only adds pathfinding load for no proven benefit.
#define MAX_TOOL_CANDIDATES 20
/datum/bot_goal/acquire_tool/proc/insert_by_distance(list/sorted, list/dists, atom/A, d)
	var/insert_at = sorted.len + 1
	for(var/i in 1 to sorted.len)
		if(d < dists[i])
			insert_at = i
			break
	if(insert_at > MAX_TOOL_CANDIDATES)
		return
	sorted.Insert(insert_at, A)
	dists.Insert(insert_at, d)
	if(sorted.len > MAX_TOOL_CANDIDATES)
		sorted.Cut(MAX_TOOL_CANDIDATES + 1, sorted.len + 1)
		dists.Cut(MAX_TOOL_CANDIDATES + 1, dists.len + 1)
#undef MAX_TOOL_CANDIDATES

// Returns the first of `candidates` (already nearest-first) that's actually reachable,
// or null if none of them check out - a real person doesn't walk up to a door they
// already know is locked and they have nothing to open it with just to "try anyway."
// This used to fall back to candidates[1] unconditionally as a last resort (see git
// history), which is exactly what put a bot with zero tools on a beeline for Auxiliary
// Base Construction it had no way into - the user's report was blunt about it: "they
// can't access it without tools, so why consider it?" That fallback existed to dodge a
// bootstrapping deadlock (a bot with nothing, surrounded only by locked rooms, could
// never pick ANY target at all) - but the real fix for that is letting the OUTER goal
// (acquire_captains_id) fail cleanly and retry later, giving ordinary wandering a chance
// to opportunistically pick up tools it walks past in the meantime (find_item_goal(),
// already wired into handle_wander()) rather than the bot confidently marching on a
// target it has no way to reach. See handle_wander()'s goal_giveup_time check
// (bot_brain.dm) for the retry half of this.
//
// Two phases, tried in order:
// 1. A genuinely OPEN route - the strict default get_path_to(), no hacking involved.
//    Always preferred: a room the bot can just walk into beats one it has to fight a
//    locked door for, exactly like a real person would check the obvious, available
//    room first.
// 2. A locked-but-HACKABLE route (bot_reachable_permissive, the same permissive check
//    repath() itself falls back to) - but ONLY once the bot already carries a
//    screwdriver and multitool, the minimum try_hack_door() (bot_items.dm) needs to do
//    anything at all. This keeps a hack-required room from being CONFIDENTLY preferred
//    over a genuinely open one the bot could just walk into - it doesn't mean a
//    hack-required room is off the table entirely when nothing open exists at all; see
//    the unconditional last-resort fallback below for that case.
/datum/bot_goal/acquire_tool/proc/pick_reachable(datum/bot_brain/bot, list/candidates)
	if(!candidates.len || QDELETED(bot))
		return null
	bot.begin_reach_scope() //candidates share one flood cache - see bot_path_to() (bot_pathing_permissive.dm)
	. = pick_reachable_candidate(bot, candidates)
	bot.end_reach_scope()

/datum/bot_goal/acquire_tool/proc/pick_reachable_candidate(datum/bot_brain/bot, list/candidates)
	// Take the cheapest of the first few reachable candidates rather than just the first:
	// the nearest fuel tank was reachable only by smashing a plasma window, while another
	// (through doors the bot had already hacked open) was barely further away.
	var/atom/best
	var/best_cost = 1e9
	var/list/best_path
	var/found = 0
	for(var/atom/A in candidates)
		if(QDELETED(bot) || QDELETED(bot.owner))
			return null
		if(is_reachable(bot, A))
			bot_log_verbose(bot, "pick_reachable: [A] ([get_area_name(A)], dist [get_dist(bot.owner, A)]) is reachable (route cost [cached_path_cost])")
			if(!best || cached_path_cost < best_cost)
				best = A
				best_cost = cached_path_cost
				best_path = cached_path
			found++
			if(found >= 3 || best_cost <= get_dist(bot.owner, A) + 5)
				break
		else
			bot_log_verbose(bot, "pick_reachable: [A] ([get_area_name(A)], dist [get_dist(bot.owner, A)]) is NOT reachable - [describe_blocker(bot, A)]")
	if(best)
		cached_path = best_path
		cached_path_target = best
		cached_path_cost = best_cost
		return best
	return null

// Diagnostic only: for a candidate that failed the strict check, finds the permissive
// (hack/break) route and reports the first door on it the bot's ID doesn't open, so the
// log says WHY it was rejected (locked, no access, welded) or that no route exists at all.
/datum/bot_goal/acquire_tool/proc/describe_blocker(datum/bot_brain/bot, atom/A)
	var/turf/T = get_turf(A)
	if(!T)
		return "no turf"
	var/obj/item/card/id/id_card = bot.owner.get_idcard(TRUE)
	var/list/path = bot.bot_path_to(T, /turf/proc/bot_weighted_distance, /turf/proc/bot_reachable_permissive, id_card, !bot.can_path_through_space())
	if(!path || !path.len)
		return "no route at all, even through locked doors"
	for(var/turf/P in path)
		for(var/obj/machinery/door/D in P)
			if(D.density && !D.allowed(bot.owner))
				return "first blocked by [D] ([get_area_name(D)]) - access [D.req_access ? "required" : "unknown"], locked=[istype(D, /obj/machinery/door/airlock) ? "[D:locked]" : "n/a"], welded=[D.welded]"
	return "permissive route exists (all doors on it open to my ID?) - strict check disagrees"

// The actual two-phase check pick_reachable() runs per candidate - split out so a
// single ungated candidate (find_tool_goal()'s "something's right here" shortcut in
// resolve_target()) can be checked the same strict way, WITHOUT pick_reachable()'s own
// "fall back to the nearest one anyway" behavior, which only makes sense when there's a
// real multi-candidate list to fall back within.
// maxnodes/maxnodedepth (300, 250) deliberately match try_path_to_no_climb()'s own pass
// 1 call exactly (bot_movement.dm) - this check exists to predict what the REAL pursuit
// will be able to do, so it needs to explore the graph the same distance that pursuit
// actually will. A tighter budget here than the real walk uses can't explain a false
// POSITIVE (this saying reachable when the real walk then hits a locked door - a
// smaller search only misses valid routes, it doesn't invent one to something the
// access check would refuse), but matching them removes it as a variable and keeps
// this genuinely predictive rather than an approximation with its own separate quirks.
// Stores whatever path it verifies into cached_path/cached_path_target (see the header
// var comment) so move_to.execute() (bot_goals.dm) can walk the EXACT route just
// proven, instead of letting pursue() run a brand new, separate A* search of its own a
// moment later. That second search sharing the same parameters, position and ID doesn't
// guarantee it finds the same route - get_path_to()/AStar() (AStar.dm) draws its
// working state from a POOLED reusable datum (SSpathfinder.mobs.getfree()), and ties in
// the heap's cost ordering aren't guaranteed to resolve identically between two
// independent runs - so a bot could pick this exact candidate BECAUSE a valid, access-
// clear route was found to it, and then the real walk's own fresh search lands on a
// different, worse route to the very same tile that happens to cross a door the ID
// doesn't clear. Reusing the verified path sidesteps that entirely: there's only ever
// one search, so there's nothing left to diverge from.
/datum/bot_goal/acquire_tool/proc/is_reachable(datum/bot_brain/bot, atom/A)
	if(QDELETED(bot) || QDELETED(bot.owner))
		return FALSE
	bot.begin_reach_scope() //its tiles and passes share one flood cache - see bot_path_to() (bot_pathing_permissive.dm)
	. = check_reachable(bot, A)
	bot.end_reach_scope()

/datum/bot_goal/acquire_tool/proc/check_reachable(datum/bot_brain/bot, atom/A)
	if(QDELETED(bot) || QDELETED(bot.owner))
		return FALSE
	var/turf/T = get_turf(A)
	if(!T)
		return FALSE
	// Already standing on/next to it: nothing to path (AStar returns nothing for
	// start == end, which used to read as "unreachable").
	if(get_turf(bot.owner) == T || bot.owner.Adjacent(A))
		return TRUE
	var/obj/item/card/id/id_card = bot.owner.get_idcard(TRUE)
	// The REAL walk (repath(), bot_movement.dm) doesn't insist on standing on the item's
	// own tile - it falls back to any open neighbouring tile, because use_atom()/pickup
	// only need adjacency. Most tools sit on tables/racks (a dense, non-walkable tile), so
	// a check against ONLY the item's own tile rejected nearly every real tool source as
	// "unreachable" (Primary Tool Storage, EVA, ...) while the bot could in fact walk up
	// to them fine. Mirror that: the item's tile first, then each open neighbour.
	var/list/dests = list(T)
	dests += bot.adjacent_turf_candidates(T)
	for(var/turf/D in dests)
		// adjacent = bot_reachable_strict() (bot_pathing_permissive.dm) - see
		// try_path_to_no_climb()'s comment (bot_movement.dm) for why this isn't just the
		// engine default: an active containment field/generator is density=FALSE by
		// design, so the default check alone would call a route straight through one
		// "reachable" when it's really a hazard the bot would keep getting shocked by.
		var/list/path = bot.bot_path_to(D, /turf/proc/Distance, /turf/proc/bot_reachable_strict, id_card, !bot.can_path_through_space())
		if(QDELETED(bot.owner))
			return FALSE
		if(path && path.len)
			cached_path = path
			cached_path_target = A
			cached_path_cost = bot_path_cost(path)
			return TRUE
	// can_eventually_provide_tool(), not find_carried_tool() - a bot holding the hand
	// drill in wrench form is just as able to wire-hack a door (one attack_self() away
	// from a screwdriver) as one already holding a plain screwdriver.
	if(bot.can_eventually_provide_tool(/obj/item/screwdriver) && bot.find_carried_tool(/obj/item/multitool))
		for(var/turf/D in dests)
			bot.pathing_allow_climb = FALSE
			var/list/path = bot.bot_path_to(D, /turf/proc/bot_weighted_distance, /turf/proc/bot_reachable_permissive, id_card, !bot.can_path_through_space())
			bot.pathing_allow_climb = TRUE
			if(QDELETED(bot.owner))
				return FALSE
			if(path && path.len)
				bot_log(bot, "[A] is behind a locked door, but I've got what I need to hack it - heading there")
				cached_path = path
				cached_path_target = A
				cached_path_cost = bot_path_cost(path)
				return TRUE
		// Last resort, same as the real walk (repath()): a route that also climbs over
		// furniture (a captain's desk, a table). Without this a fire axe cabinet just past
		// a desk read as "unreachable" even though the bot walks/climbs there fine.
		for(var/turf/D in dests)
			var/list/path = bot.bot_path_to(D, /turf/proc/bot_weighted_distance, /turf/proc/bot_reachable_permissive, id_card, !bot.can_path_through_space())
			if(QDELETED(bot.owner))
				return FALSE
			if(path && path.len)
				bot_log(bot, "[A] is reachable if I climb over some furniture - heading there")
				cached_path = path
				cached_path_target = A
				cached_path_cost = bot_path_cost(path)
				return TRUE
	return FALSE

// Blacklists whatever target this goal ended up with, so a future acquire_tool retry
// picks something else instead of the exact same target that just failed.
/datum/bot_goal/acquire_tool/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.failed_tool_targets, target, world.time + rand(600, 1200))

// Remembers a closet/toolbox that actually worked, for known_source_candidates() above
// to prefer next time - a real person remembers where the tool storage room is instead
// of re-searching the whole station every time they need a screwdriver. Loose single
// items (grab_item) aren't worth remembering - the item itself is now in the bot's
// hands, there's nothing left at that location to come back for.
/datum/bot_goal/acquire_tool/on_success(datum/bot_brain/bot)
	if(!target || !(istype(target, /obj/structure/closet) || istype(target, /obj/item/storage/toolbox)))
		return
	if(target in bot.known_tool_sources)
		return
	LAZYADD(bot.known_tool_sources, target)
	if(bot.known_tool_sources.len > 10)
		bot.known_tool_sources.Cut(1, 2) //drop the oldest, not worth growing unbounded over a long round

/datum/bot_goal/acquire_tool/get_strategies(datum/bot_brain/bot)
	// One place all of resolve_target()'s tiers funnel through once a target's actually
	// been picked, so there's always a clear "why" on the live admin feed regardless of
	// which tier found it - a bot breaking into a locked room used to only explain
	// itself at the DOOR (describe_pursuit_purpose(), bot_items.dm), nothing said why
	// that specific room was chosen as the destination in the first place.
	bot_log(bot, "heading to [target] @ [bot_coord(get_turf(target))] ([get_area_name(target)]) to get [needed_tool_type ? needed_tool_type : "whatever useful tools are there"]")
	if(istype(target, /obj/structure/closet))
		return list(new /datum/bot_strategy/grab_tool_from_locker())
	// A toolbox (/obj/item/storage/toolbox) is a container just like a closet is, just
	// not a /obj/structure/closet, and doesn't need an interact step first - its
	// contents (component/storage, storage.dm) are enumerable directly whether or not
	// it's been "opened", unlike a closet whose items live outside its contents
	// entirely until interact() opens it (dump_contents() on open). Worse, calling
	// attack_hand() on it (what interact does) while it's on the ground hits
	// /obj/item/attack_hand()'s base auto-pickup path (items.dm) since the storage
	// component's own on_attack_hand() no-ops for a ground item - so it just grabbed
	// the WHOLE closed box into a hand as a single item, doing nothing useful and
	// eating a hand slot that then made pickup_tool_from_target's own pickups fail via
	// make_room_for_item() dropping things unpredictably. Skip straight to picking the
	// tools out of it.
	if(istype(target, /obj/item/storage/toolbox))
		return list(new /datum/bot_strategy/grab_tools_from_toolbox())
	return list(new /datum/bot_strategy/grab_item())

/datum/bot_strategy/grab_tool_from_locker/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/interact(), new /datum/bot_step/pickup_tool_from_target())

/datum/bot_strategy/grab_tool_from_locker/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_strategy/grab_tools_from_toolbox/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/pickup_tool_from_target())

/datum/bot_strategy/grab_tools_from_toolbox/is_feasible(datum/bot_brain/bot)
	return TRUE
