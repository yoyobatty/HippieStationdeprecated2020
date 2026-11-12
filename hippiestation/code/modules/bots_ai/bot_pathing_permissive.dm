// An active containment field (containment_field.dm) or field generator with live
// fields is density=FALSE BY DESIGN - a real player crosses one deliberately, eyes
// open, knowing it'll shock them. The default engine obstruction check
// (reachableTurftest(), AStar.dm) is purely density-based, so it happily plans a route
// straight through one - a bot then walks it over and over (confirmed in-game:
// Bumped()/Crossed() on the field object calls shock()+bump_field() on every attempt,
// even when the mob-level CanPass() correctly refuses the actual step), getting
// paralyzed repeatedly instead of routing around. Checked by both bot_reachable_strict()
// and bot_reachable_permissive() below - a bot has no more business walking through a
// live field than through a locked door it can't hack.
/proc/bot_turf_has_active_field(turf/T)
	// Asked on every step of every route the bots plan, 2.7 million times a round: what's where is kept as the fields come and go
	// (below), instead of every turf's contents being gone through for one.
	if(GLOB.bot_field_turfs[T])
		return TRUE //a containment field exists at all only while its field connection is live
	if(!GLOB.bot_field_generator_turfs[T])
		return FALSE
	for(var/obj/machinery/field/generator/G in T)
		if(LAZYLEN(G.fields))
			return TRUE //fields.len>0 means its own Bumped()/shock() are live too (field_generator.dm)
	return FALSE

/// Turf -> how many containment fields are on it.
GLOBAL_LIST_EMPTY(bot_field_turfs)
/// Turf -> how many field generators are on it. They can be unwrenched and dragged about, so they're kept track of as they move.
GLOBAL_LIST_EMPTY(bot_field_generator_turfs)

/proc/bot_count_field_turf(list/counts, turf/T, change)
	if(!isturf(T))
		return
	var/now = counts[T] + change
	if(now > 0)
		counts[T] = now
	else
		counts -= T

/obj/machinery/field/containment/Initialize()
	. = ..()
	bot_count_field_turf(GLOB.bot_field_turfs, loc, 1)

/obj/machinery/field/containment/Destroy()
	bot_count_field_turf(GLOB.bot_field_turfs, loc, -1)
	return ..()

/obj/machinery/field/generator/Initialize()
	. = ..()
	bot_count_field_turf(GLOB.bot_field_generator_turfs, loc, 1)

/obj/machinery/field/generator/Destroy()
	bot_count_field_turf(GLOB.bot_field_generator_turfs, loc, -1)
	return ..()

/obj/machinery/field/generator/Moved(atom/OldLoc, Dir)
	. = ..()
	bot_count_field_turf(GLOB.bot_field_generator_turfs, OldLoc, -1)
	bot_count_field_turf(GLOB.bot_field_generator_turfs, loc, 1)

// A space turf can still be safely crossed without magboots if there's something dense
// adjacent to push off from - the exact real mechanic get_spacemove_backup() (mob_
// movement.dm) already grants a player: bracing against a wall or anchored object lets
// you propel yourself across, magboots or not (bot_step_towards()'s Process_Spacemove()
// call, bot_movement.dm, runs that exact same real check before every bot step too).
// simulated_only used to treat "not eva_ready" as "cannot path through ANY space tile at
// all" - stricter than the game actually is. Confirmed in-game: a well-traveled exterior
// route right next to a solid wall (players cross it regularly) became completely
// unroutable the instant a bot lost is_eva_ready() there for lacking magboots alone -
// even standing right next to that exact wall, with a real hardsuit/mask/tank on, unable
// to plan a route anywhere, including back the way it came.
//
// Gated on is_space_protected_without_boots() (gear_up_eva.dm), NOT just "is there
// something to push off" - a bot with no hardsuit/tank at all would suffocate/take
// pressure damage out there regardless of push-off physics, so the exception only ever
// applies to a bot that's genuinely survivable in vacuum and just missing the stability
// magboots give.
/proc/bot_turf_has_pushoff_backup(turf/T)
	// The walls round it first: beside the hull that's the answer nearly every time, in eight reads. This is asked for every space tile a
	// suited bot's route search looks at, and it used to step through everything on the tiles round it (pipes, cables, items) to find out.
	for(var/dir in GLOB.alldirs)
		var/turf/adjacent = get_step(T, dir)
		if(adjacent && adjacent.density)
			return TRUE
	if(locate(/obj/structure/lattice) in range(1, T))
		return TRUE //a lattice within a tile is enough to move by - /atom/movable/Process_Spacemove() (atoms_movable.dm)
	for(var/atom/movable/AM in orange(1, T)) // a typed loop over orange() is filtered natively
		if(AM.density && AM.anchored)
			return TRUE
	return FALSE

/proc/bot_turf_crossable_without_boots(turf/T, caller)
	var/mob/living/carbon/human/H = caller
	if(!istype(H) || !H.bot_brain || !H.bot_brain.is_space_protected_without_boots())
		return FALSE
	return bot_turf_has_pushoff_backup(T)

// Same as the default /turf/proc/reachableTurftest() (AStar.dm), plus the active-field
// check above - used as the bot's own STRICT (pass 1) adjacent proc instead of the
// engine default, so field-hazard avoidance applies to the very first pathfinding
// attempt, not just the permissive fallback.
// Walking off dry floor into pool water knocks you down in it (pool_main.dm Entered()), and lying in water
// drowns you - a person walks around the pool, not through it. Moving within it or climbing out is fine.
/proc/bot_steps_into_pool(turf/from, turf/T)
	return istype(T, /turf/open/pool) && !istype(from, /turf/open/pool)

/// Making an arrest or in a fight: in after them, taking the fall into the water like anybody does (pool_main.dm Entered()). Anybody in
/// the pool used to be out of Security's reach (the user, 2026-11-04).
/proc/bot_may_jump_in(mob/living/carbon/human/H)
	var/datum/bot_brain/B = istype(H) ? H.bot_brain : null
	return B && (B.pursuing_kind == "arrest" || B.pursuing_kind == "combat")

/// Lava and chasms are floor as far as the engine's route check goes. With a walkway or stepping stones over them, they are.
/proc/bot_turf_is_deadly(turf/T)
	if(GLOB.bot_open_trapdoors[T])
		return TRUE
	if(istype(T, /turf/open/space/transit)) //off the side of a shuttle under way: thrown out into deep space (transit.dm)
		return TRUE
	if(istype(T, /turf/open/lava))
		var/turf/open/lava/L = T
		return !L.is_safe()
	if(istype(T, /turf/open/chasm))
		var/datum/component/chasm/C = T.GetComponent(/datum/component/chasm)
		return !C?.is_safe()
	return FALSE

/// Trapdoors standing open (hippiestation/code/game/machinery/trapdoors.dm). There's one in every cell on the Hippie map, and it opens when
/// the timer stops: an officer walking in for a prisoner went down it, into the disposal pipes, and lost them.
GLOBAL_LIST_EMPTY(bot_open_trapdoors)

/// Somebody sat in a chair fills their tile - there is no swapping places with them, and the engine's own route
/// check doesn't look at mobs at all. A bot used to plan straight down a row of taken shuttle seats to the free
/// one at the end, bump the first sitter until it gave up, and plan the same route again.
/proc/bot_turf_has_seated_mob(turf/T)
	for(var/mob/living/L in T)
		if(L.density && (L.buckled || bot_parked_mule(L)))
			return TRUE
	return FALSE

/// A MULE that isn't going anywhere fills its tile the same: nobody swaps places with one, or pushes it along. A route was planned
/// straight through it all the same, walked into it three times and given up, and the next errand's route went through it again: a
/// Captain between the two parked in MetaStation's Cargo Bay stood there for nine minutes with the way out open beside them, and
/// bots walked into a MULE about 650 times a shift. One on its way somewhere is left to get out of the way.
/proc/bot_parked_mule(mob/living/simple_animal/bot/mulebot/M)
	return istype(M) && M.density && (!M.on || M.mode == BOT_IDLE)

/turf/proc/bot_reachable_strict(caller, turf/T, ID, simulated_only)
	if(!T || T.density)
		return FALSE
	if(istype(T, /turf/open/pool) && !istype(src, /turf/open/pool) && !bot_may_jump_in(caller)) //bot_steps_into_pool()
		return FALSE
	if(bot_turf_is_deadly(T))
		return FALSE
	if(GLOB.bot_hazard_turfs[T] && bot_steps_into_hazard(src, T, caller))
		return FALSE
	if(simulated_only && SSpathfinder.space_type_cache[T.type] && !bot_turf_crossable_without_boots(T, caller))
		return FALSE
	return !bot_turf_has_active_field(T) && !bot_link_blocked_strict(T, caller, ID)

/// LinkBlockedWithAccess() (AStar.dm) and bot_turf_has_seated_mob() together, with the same answers: one pass over each turf's
/// contents instead of four. Asked for every neighbour of every tile a search opens, two million times a shift.
/turf/proc/bot_link_blocked_strict(turf/T, caller, ID)
	var/adir = get_dir(src, T)
	// locate() first (native, ~20 ns a thing): a loop over the tile steps the VM for each thing on it (~85 ns) and most tiles
	// have neither (2026-11-11)
	if(locate(/obj/structure/window) in src)
		for(var/obj/structure/window/W in src)
			if(!W.CanAStarPass(ID, adir))
				return TRUE
	if(locate(/obj/machinery/door/window) in src)
		for(var/obj/machinery/door/window/W in src)
			if(!W.CanAStarPass(ID, adir))
				return TRUE
	var/rdir = ((adir & MASK_ODD)<<1)|((adir & MASK_EVEN)>>1)
	for(var/atom/movable/AM as anything in T)
		if(isobj(AM))
			var/obj/O = AM
			if((O.density || O.astar_always_asks) && !O.CanAStarPass(ID, rdir, caller))
				return TRUE
		else if(isliving(AM))
			var/mob/living/L = AM
			if(L.density && (L.buckled || bot_parked_mule(L))) //bot_turf_has_seated_mob()
				return TRUE
	return FALSE

// Mirrors code/__HELPERS/AStar.dm's reachableTurftest()/LinkBlockedWithAccess(), but
// treats as passable anything the bot could actually force its way through given its
// real toolkit (clear_one_blocker() in bot_items.dm): a locked (bolted) airlock, as
// long as it's unwelded, powered, and the traveling ID would otherwise have access;
// a climbable structure (tables, racks, ...), the same MouseDrop_T mechanic
// clear_one_blocker() already drives reactively; and a window, if the bot is
// currently carrying something with force to break it. This is "passable if we could
// get through it," not "passable no matter what" - see bot_can_astar_pass_permissive()
// and bot_can_break_through(). Used as a fallback second pathfinding pass when the
// normal (obstruction-respecting) one finds no route, so a bot only ever plans through
// an obstacle when there's no legitimate way around - see bot_movement.dm's repath().
/turf/proc/bot_reachable_permissive(caller, turf/T, ID, simulated_only)
	if(!T || T.density)
		return FALSE
	if(istype(T, /turf/open/pool) && !istype(src, /turf/open/pool) && !bot_may_jump_in(caller)) //bot_steps_into_pool()
		return FALSE
	if(bot_turf_is_deadly(T))
		return FALSE
	if(GLOB.bot_hazard_turfs[T] && bot_steps_into_hazard(src, T, caller))
		return FALSE
	if(simulated_only && SSpathfinder.space_type_cache[T.type] && !bot_turf_crossable_without_boots(T, caller))
		return FALSE
	return !bot_turf_has_active_field(T) && !bot_link_blocked_permissive(T, caller, ID)

/turf/proc/bot_link_blocked_permissive(turf/T, caller, ID)
	var/adir = get_dir(src, T)
	var/rdir = ((adir & MASK_ODD)<<1)|((adir & MASK_EVEN)>>1)
	if(locate(/obj/structure/window) in src) // locate() first, as in bot_link_blocked_strict()
		for(var/obj/structure/window/W in src)
			if(!W.CanAStarPass(ID, adir) && !bot_can_break_through(W, caller))
				return TRUE
	if(locate(/obj/machinery/door/window) in src)
		for(var/obj/machinery/door/window/W in src)
			if(!W.CanAStarPass(ID, adir) && !bot_can_break_through(W, caller))
				return TRUE
	for(var/obj/O in T)
		if(!bot_can_astar_pass_permissive(O, ID, rdir, caller))
			return TRUE
	return FALSE

// caller.bot_brain.pathing_allow_climb gates whether climbing counts as "passable" for
// this particular pathfind attempt - repath() runs the permissive pass twice, once with
// this off and once with it on, so climbing is only ever the deciding factor when it's
// truly the only way through (see bot_movement.dm's repath()).
/proc/bot_can_astar_pass_permissive(obj/O, ID, to_dir, caller)
	// The climbing pass run for somebody hemmed in on an everyday errand (pathing_climb_only, bot_movement.dm):
	// the ordinary rules, plus over the furniture - no forcing doors, no breaking anything.
	var/mob/living/carbon/human/walker = caller
	if(istype(walker) && walker.bot_brain?.pathing_climb_only)
		if(O.CanAStarPass(ID, to_dir, caller))
			return TRUE
		var/obj/structure/furniture = O
		return istype(furniture) && furniture.climbable
	// A closed firelock (firedoor.dm) is crowbar-pryable regardless of why it's closed
	// (try_to_crowbar() just calls open() outright, no access/power check at all) - a
	// real engineer forces one open by hand every time they enter a room the local air
	// alarm considers hazardous (an intentionally airless engine bay, say), same as this
	// checks for. Without this case it fell through to the generic O.CanAStarPass()
	// check below, which is just !density for a plain obj - permanently refusing any
	// route through a closed firelock even with the exact right tool in hand, since
	// nothing else here recognized it as openable at all.
	if(istype(O, /obj/machinery/door/firedoor))
		var/obj/machinery/door/firedoor/F = O
		if(!F.density)
			return TRUE
		if(F.operating)
			return FALSE
		var/mob/living/carbon/human/H = caller
		// Welded: passable only for a bot that can unweld it on arrival (bot_breach.dm).
		if(F.welded && !(istype(H) && H.bot_brain && H.bot_brain.can_unweld()))
			return FALSE
		// Shut on a fire: not a way through for anybody who'd burn (goals/respond_to_fire.dm).
		if(istype(H) && H.bot_brain && !H.bot_brain.heat_proof() && bot_fire_behind(F))
			return FALSE
		if(F.safety_mode && !F.hasPower() && !F.welded)
			return TRUE //hand release (door.dm try_safety_unlock()), no crowbar needed
		// can_eventually_provide_tool(), not find_carried_tool() - a bot holding the
		// jaws-of-life in wirecutters/power form is just as able to pry this open (one
		// attack_self() away from being a crowbar/power) as one already holding it in
		// crowbar form.
		return istype(H) && H.bot_brain && H.bot_brain.can_eventually_provide_tool(/obj/item/crowbar)
	if(istype(O, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/A = O
		// Not gated on check_access() or on already carrying the right tools - the
		// reactive obstruction-clearer (try_hack_door()/strip_airlock_security(),
		// bot_items.dm) can wire-hack a door open with no access at all, and if it's
		// missing tools when it gets there, it suspends the goal, goes and fetches
		// them, then resumes (seek_tool_for_obstacle()). So this only needs to rule
		// out what's genuinely a dead end: welded shut, no power to work with, or a
		// door handle_blocker_failure() (bot_items.dm) already gave up on recently -
		// without this, a fresh pursuit (a new goal strategy, or just wandering) would
		// cheerfully plan straight back through a door it just spent several failed
		// attempts on, since the per-pursuit failure count resets every pursue().
		var/mob/living/carbon/human/H = caller
		if(istype(H) && H.bot_brain)
			var/cooldown = LAZYACCESS(H.bot_brain.failed_blockers, A)
			if(cooldown && world.time < cooldown)
				return !A.density
		// A shielded (command/security-tier) airlock can only be hacked after stripping its
		// layers, which needs the full kit - without it the "hack through" route is a
		// fantasy (this is what sent a half-equipped bot through Security Maintenance
		// toward the captain's office and then stranded it at the door).
		if(A.security_level && istype(H) && H.bot_brain && !H.bot_brain.can_strip_security())
			return !A.density
		// Welded is no longer a dead end for a bot carrying a fuelled welder (bot_breach.dm).
		var/can_unweld = istype(H) && H.bot_brain && H.bot_brain.can_unweld()
		if(!A.density)
			return TRUE
		if(A.welded && !can_unweld)
			return FALSE
		if(A.hasPower())
			return TRUE
		// Unpowered: no hacking (the wires need power), but it still opens the way a player opens a dead
		// door - by hand if it has the safety_mode emergency release (door.dm try_safety_unlock(), the
		// arrivals dock airlocks), or with any crowbar (try_pry_door()). Bolts stop both. Treating every
		// dead airlock as a wall stranded bots aboard the arrivals shuttle whenever the dock lost power.
		if(A.locked)
			return FALSE
		return A.safety_mode || (istype(H) && H.bot_brain && H.bot_brain.can_eventually_provide_tool(/obj/item/crowbar))
	if(O.CanAStarPass(ID, to_dir, caller))
		return TRUE
	var/obj/structure/S = O
	if(istype(S) && S.climbable)
		var/mob/living/carbon/human/H = caller
		if(istype(H) && H.bot_brain && H.bot_brain.pathing_allow_climb)
			return TRUE
		if(istype(S, /obj/structure/table) && istype(H) && H.bot_brain && H.bot_brain.pathing_allow_smash_tables)
			return TRUE
	return bot_can_break_through(O, caller)

// caller is the /mob/living/carbon/human passed down from get_path_to() (the same mob
// whose ID we're pathing with) - mirrors clear_one_blocker()'s "no weapon, no breaking"
// rule, so this never plans a route through a window the bot has nothing to smash it
// with, right down to what's literally in its hands at pathing time.
/proc/bot_can_break_through(obj/O, mob/living/carbon/human/caller)
	if(!istype(caller) || caller.bot_brain?.pathing_climb_only)
		return FALSE
	// Only things that are actually meant to be smashed to get through (windows, grilles,
	// windoors). This used to be true for ANY dense object once the bot held a weapon, so
	// a bot with a fire axe planned its route straight THROUGH a filing cabinet (the
	// shortest line) and started chopping it up, instead of walking around it.
	if(!(istype(O, /obj/structure/window) || istype(O, /obj/structure/grille) || istype(O, /obj/machinery/door/window)))
		return FALSE
	// Only when the bot is in real danger, and only with a carried weapon that can actually
	// finish the job in time - this used to be "holding anything with force > 0", calm or not,
	// so a calm bot would plan through a window with a screwdriver (bot_breach.dm).
	if(!caller.bot_brain)
		return FALSE
	return caller.bot_brain.can_breach_now(O)


// Obstacle cost of stepping onto T, in extra "tiles" - only used by the permissive
// (hack/break) passes. Plain hop-count treated smashing a reinforced plasma window as
// exactly as cheap as walking through an open door, so the shortest route often went
// straight through a window that takes dozens of axe swings while a longer, already-
// hacked (bolted-open) route sat right there.
/proc/bot_turf_penalty(turf/T)
	. = 0
	for(var/obj/O in T)
		if(istype(O, /obj/structure/window))
			. += 60
		else if(istype(O, /obj/structure/grille))
			. += 10
		else if(istype(O, /obj/machinery/door/window))
			. += 20
		else if(istype(O, /obj/machinery/door/airlock))
			var/obj/machinery/door/airlock/A = O
			if(A.density)
				. += A.security_level ? 25 : 8
				if(A.welded)
					. += 15 //~4s to unweld
		else if(istype(O, /obj/machinery/door/firedoor))
			var/obj/machinery/door/firedoor/F = O
			if(F.density && F.welded)
				. += 15
		else if(istype(O, /obj/structure/table))
			. += 8

// Drop-in replacement for /turf/proc/Distance_cardinal as get_path_to()'s cost function (AStar.dm
// uses it for both the edge cost and the heuristic).
/turf/proc/bot_weighted_distance(turf/T)
	return abs(x - T.x) + abs(y - T.y) + bot_turf_penalty(T)

// Total weighted cost of a found path (nodes + obstacle penalties), for comparing routes.
/proc/bot_path_cost(list/path)
	. = 0
	if(!path)
		return
	for(var/turf/T in path)
		. += 1 + bot_turf_penalty(T)

// ---------------------------------------------------------------------------------------------
// Skipping hopeless searches
// ---------------------------------------------------------------------------------------------
// AStar() (code/__HELPERS/AStar.dm) doesn't fail fast: with no route, it expands every turf within
// maxnodedepth steps (maxnodes, 300, overrides it) before giving up - most of the station. One decision
// used to pay that over and over from the same spot under the same rules: pick_reachable() trying up to 20
// tool sources x 5 tiles x 3 passes, repath() trying a destination, each open neighbour and several passes.
// Reachability doesn't depend on which tile is being asked about, so once a search under some rules fails,
// one breadth-first flood of those rules answers every later tile: a tile the flood never reached is one
// AStar() couldn't reach either (same adjacency proc, never expands past BOT_PATH_FLOOD_STEPS), so skipping
// it changes nothing, and a tile it did reach gets the real search and the same path as always. Floods only
// live for one decision (begin/end_reach_scope()) so doors opening between decisions are always seen.

/// AStar() expands a node up to maxnodedepth (300) steps out, so it can still match one step past that
#define BOT_PATH_FLOOD_STEPS 301
/// Safety net if a runtime leaves a scope open: never trust floods older than this
#define BOT_REACH_FLOOD_TTL (5 SECONDS)

/datum/bot_brain
	/// Reachability floods for the decision in progress, keyed by reach_key(). Null outside a scope.
	var/list/reach_floods
	var/reach_scope_depth = 0
	var/reach_floods_time = 0

/// Opens a flood cache for one decision (repath(), pick_reachable(), is_reachable()). Nests.
/datum/bot_brain/proc/begin_reach_scope()
	if(!reach_scope_depth++)
		reach_floods = list()
		reach_floods_time = world.time

/datum/bot_brain
	/// "dest|adjacency" -> until when bot_sealed_pocket() has already said dest isn't shut in anywhere small.
	var/list/pockets_ruled_out

/datum/bot_brain/proc/end_reach_scope()
	if(reach_scope_depth > 0 && !--reach_scope_depth)
		reach_floods = null

/// Everything bot_reachable_strict()/bot_reachable_permissive() read that could change a route within one
/// decision - including try_unlock_route()'s hypothetical "if I had a welder / that toolbox" flags and the
/// urgency that decides whether breaking through is allowed. Anything new those procs start reading that can
/// change mid-decision has to go in here too, or a flood made under the old state skips a route it shouldn't.
/datum/bot_brain/proc/reach_key(turf/start, adjacent, obj/item/card/id/id_card, simulated_only)
	return "[REF(start)]|[reach_rules(adjacent, id_card, simulated_only)]"

/// reach_key() without where it starts from.
/datum/bot_brain/proc/reach_rules(adjacent, obj/item/card/id/id_card, simulated_only)
	return "[adjacent]|[REF(id_card)]|[simulated_only]|[pathing_allow_climb]|[pathing_climb_only]|[pathing_no_tailgating]|[pathing_allow_smash_tables]|[pathing_assume_welder]|[pathing_assume_nearby_weapons]|[get_urgency()]|[pathing_emag ? 1 : 0]|[bot_may_jump_in(owner) ? 1 : 0]|[shut_in_result ? 1 : 0]|[length(vacuum_doors)]"

// A whole region, kept a little while. A failed search that wasn't cut short has visited everything reachable from where it began, and
// from anywhere inside that, nothing outside it is reachable either: whatever such a tile reaches, the first one reached through it. So
// while the bot's still inside it, under the same rules, a destination outside it is no route, without searching. A superboom cut a
// piece out of the station and the bots shut in on the far side kept trying everywhere they used to go, flooding 2,700 tiles a time:
// two million tiles in three minutes, a third of every tick. Kept 20 seconds, so a door opened since is seen that much later, as by
// somebody who tried a moment ago.
#define BOT_REGION_FLOOD_TTL (20 SECONDS)

/datum/bot_brain
	/// reach_rules() -> list(every turf a failed search reached, until when it's trusted)
	var/list/region_floods

/datum/bot_brain/proc/outside_known_region(turf/start, turf/dest, rules)
	var/list/known = LAZYACCESS(region_floods, rules)
	if(!known || world.time > known[2])
		return FALSE
	// a list, or a /datum/path_region the path engine keeps (bot_path_engine.dm); one it has let go says neither
	var/region = known[1]
	return path_region_has(region, start) == 1 && path_region_has(region, dest) == 0

/datum/bot_brain/proc/remember_region(reached, rules)
	if(LAZYLEN(region_floods) > 8)
		region_floods.Cut()
	LAZYSET(region_floods, rules, list(reached, world.time + BOT_REGION_FLOOD_TTL))

/// get_path_to() for the bot's own route checks, minus searches a flood already proved hopeless (see above).
/datum/bot_brain/proc/bot_path_to(turf/dest, dist, adjacent, obj/item/card/id/id_card, simulated_only)
	var/turf/start = get_turf(owner)
	pathing_emag = !!emag_for_doors()
	var/rules = start && dest ? reach_rules(adjacent, id_card, simulated_only) : null
	if(rules && outside_known_region(start, dest, rules))
		return list() //what get_path_to() returns when it finds nothing
	var/key
	if(reach_floods && start)
		if(world.time > reach_floods_time + BOT_REACH_FLOOD_TTL)
			reach_floods.Cut()
			reach_floods_time = world.time
		key = reach_key(start, adjacent, id_card, simulated_only)
		var/reached = reach_floods[key]
		if(reached && path_region_has(reached, dest) == 0)
			return list() //what get_path_to() returns when it finds nothing
		var/list/sealed = reach_floods["sealed|[key]"]
		if(sealed && sealed[dest])
			return list()
	// No flood to go by yet: before paying for one, see whether dest is simply shut in somewhere small
	// (bot_sealed_pocket() below). Everything in the pocket is as unreachable as dest, so the rest of
	// this decision can skip it too.
	var/open_key = dest ? "[REF(dest)]|[adjacent]" : null
	if(start && dest && !(key && reach_floods[key]) && !(LAZYACCESS(pockets_ruled_out, open_key) > world.time))
		var/list/pocket = bot_sealed_pocket(owner, start, dest, adjacent, id_card, simulated_only)
		if(!pocket) //not shut in anywhere small: no need to look again for a while (a bot re-routes to the same place over and over)
			if(LAZYLEN(pockets_ruled_out) > 200)
				pockets_ruled_out.Cut()
			LAZYSET(pockets_ruled_out, open_key, world.time + 15 SECONDS)
		if(pocket)
			if(key)
				var/list/known = reach_floods["sealed|[key]"]
				if(known)
					known |= pocket
				else
					reach_floods["sealed|[key]"] = pocket
			return list()
	var/list/explored = (key || rules) ? list() : null
	var/list/path = get_path_to(owner, dest, dist, 300, 250, adjacent = adjacent, id = id_card, simulated_only = simulated_only, explored = explored)
	if(rules && !length(path) && explored["reached"] && !explored["depth_cut"] && get_turf(owner) == start && reach_rules(adjacent, id_card, simulated_only) == rules)
		remember_region(explored["reached"], rules) //the whole region (above)
	// A failed search under these rules: remember what's reachable under them, so the rest of this decision can
	// skip the hopeless tiles. Only if nothing moved or changed rules while get_path_to() was yielding.
	if(key && !length(path) && reach_floods && !reach_floods[key] && get_turf(owner) == start && reach_key(start, adjacent, id_card, simulated_only) == key)
		var/reached = explored["reached"] //a list, or a /datum/path_region (bot_path_engine.dm)
		if(!reached)
			return path //AStar() gave up before searching (too far, other z) - nothing learned
		// Usually free: a failed search that never hit its depth limit has already visited exactly everything
		// reachable from here. Only one cut short by maxnodedepth needs the proper flood.
		if(explored["depth_cut"])
			reached = bot_flood_reachable(owner, start, adjacent, id_card, simulated_only)
		if(reach_floods && reach_key(start, adjacent, id_card, simulated_only) == key)
			reach_floods[key] = reached
	return path

/// Every turf AStar() could reach from `start` with this adjacency proc: breadth first, BOT_PATH_FLOOD_STEPS out. A list, or a
/// /datum/path_region from the path engine (bot_path_engine.dm), which floods the same tiles with the station picture.
/proc/bot_flood_reachable(caller, turf/start, adjacent, id, simulated_only)
	if(path_engine_takes_flood(adjacent))
		var/shadow = world.params["path-flood"] == "shadow"
		var/started = TICK_USAGE_REAL
		var/native = path_engine_flood(caller, start, adjacent, id, simulated_only, BOT_PATH_FLOOD_STEPS, !shadow)
		if(native != PATH_ENGINE_FALLBACK)
			if(!shadow)
				return native
			// timed as it's used (a region), then again listing its tiles to check them
			GLOB.path_engine_check["flood native us"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) * 1000
			native = path_engine_flood(caller, start, adjacent, id, simulated_only, BOT_PATH_FLOOD_STEPS, FALSE, TRUE)
			started = TICK_USAGE_REAL
			var/list/dm = bot_flood_reachable_dm(caller, start, adjacent, id, simulated_only, FALSE) // in the same tick as the engine's
			GLOB.path_engine_check["flood dm us"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) * 1000
			path_flood_shadow_note("flood", dm, native, start, adjacent, caller, id, simulated_only)
			return dm
	return bot_flood_reachable_dm(caller, start, adjacent, id, simulated_only)

/proc/bot_flood_reachable_dm(caller, turf/start, adjacent, id, simulated_only, yields = TRUE)
	var/list/reached = list()
	reached[start] = TRUE
	var/list/frontier = list(start)
	for(var/steps in 1 to BOT_PATH_FLOOD_STEPS)
		var/list/next = list()
		for(var/turf/T as anything in frontier)
			for(var/dir in GLOB.cardinals)
				var/turf/N = get_step(T, dir)
				if(N && !reached[N] && call(T, adjacent)(caller, N, id, simulated_only))
					reached[N] = TRUE
					next += N
			if(yields)
				CHECK_TICK
		if(!length(next))
			break
		frontier = next
	return reached

// The flood only pays off from the second hopeless search of a decision on: the first still opens
// every turf the bot can reach - around 20,000 on the station - to learn the destination isn't one
// of them. Usually it's the destination that is shut in (a locker room, a secure store, a cell),
// and looking outward from it finds that out in a few dozen turfs: once everywhere that can reach
// the destination has been found, and the bot isn't standing in it, there is no route. "Can reach"
// is the search's own edge test asked in its own direction (can N step onto T), so the answer is
// exactly the one AStar() would have reached, just from the cheap end.

/// How far to look around a destination before deciding it isn't shut in anywhere small.
#define BOT_SEALED_POCKET_TURFS 300

/// Every turf that can reach `dest` under `adjacent`, as keys, if there are at most
/// BOT_SEALED_POCKET_TURFS of them and `start` isn't one - none of them can be reached from `start`.
/// Null if dest might be reachable, or is cut off but not in anywhere small.
/proc/bot_sealed_pocket(caller, turf/start, turf/dest, adjacent, id, simulated_only)
	if(start == dest || start.z != dest.z)
		return null
	if(path_engine_takes_flood(adjacent)) // the same flood in the path engine (bot_path_engine.dm)
		var/started = TICK_USAGE_REAL
		var/native = path_engine_pocket(caller, start, dest, adjacent, id, simulated_only, BOT_SEALED_POCKET_TURFS)
		if(native != PATH_ENGINE_FALLBACK)
			if(world.params["path-flood"] != "shadow")
				return native
			GLOB.path_engine_check["pocket native us"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) * 1000
			started = TICK_USAGE_REAL
			var/list/dm = bot_sealed_pocket_dm(caller, start, dest, adjacent, id, simulated_only)
			GLOB.path_engine_check["pocket dm us"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) * 1000
			path_flood_shadow_note("pocket", dm, native, dest, adjacent, caller, id, simulated_only)
			return dm
	return bot_sealed_pocket_dm(caller, start, dest, adjacent, id, simulated_only)

/proc/bot_sealed_pocket_dm(caller, turf/start, turf/dest, adjacent, id, simulated_only)
	// A hallway reached from dest settles it: dest isn't shut in anywhere small. Most destinations are a room or two off one, and
	// without this every one of them flooded the whole 300 turfs before saying so - 1.2 ms a route, 6% of a bot round's server time.
	var/static/list/hubs = typecacheof(list(/area/hallway)) //not maintenance: there's no getting into it from a hallway without the access for it, which most bots haven't got
	var/list/pocket = list()
	pocket[dest] = TRUE
	var/list/frontier = list(dest)
	var/found = 1
	while(length(frontier))
		var/list/next = list()
		for(var/turf/T as anything in frontier)
			for(var/dir in GLOB.cardinals)
				var/turf/N = get_step(T, dir)
				if(!N || pocket[N] || !call(N, adjacent)(caller, T, id, simulated_only))
					continue
				if(N == start || ++found > BOT_SEALED_POCKET_TURFS || hubs[N.loc.type])
					return null
				pocket[N] = TRUE
				next += N
		frontier = next
	return pocket


#undef BOT_SEALED_POCKET_TURFS
#undef BOT_PATH_FLOOD_STEPS
#undef BOT_REACH_FLOOD_TTL
#undef BOT_REGION_FLOOD_TTL

/// path-flood=shadow: the engine's flood against DM's, the same tick. Counts in GLOB.path_engine_check, written with the path checks.
/proc/path_flood_shadow_note(kind, list/dm, native, turf/from, adjacent, caller, id, simulated_only)
	var/list/check = GLOB.path_engine_check
	check["[kind]s checked"]++
	var/why
	if(!dm != !native)
		why = dm ? "DM found one, the engine none" : "the engine found one, DM none"
	else if(dm)
		var/list/tiles = native
		if(length(dm) != length(tiles))
			why = "[length(dm)] tiles against [length(tiles)]"
		else
			for(var/turf/T as anything in dm)
				if(!tiles[T])
					why = "the engine hasn't got [T.x],[T.y]"
					break
	if(!why)
		check["[kind]s same"]++
		if(!(check["[kind]s checked"] % 100))
			path_engine_write_check()
		return
	check["[kind]s different"]++
	if(length(GLOB.path_engine_samples) < 40)
		GLOB.path_engine_samples += "[kind] different: [why]; from [from.x],[from.y],[from.z] ([adjacent == /turf/proc/bot_reachable_permissive ? "permissive" : "strict"], [caller], simulated_only [simulated_only])"
		// which tiles only the engine has, and the steps joining them to the rest as DM's adjacency answers them
		var/list/engine_tiles = islist(native) ? native : list()
		var/shown = 0
		for(var/turf/T as anything in engine_tiles)
			if((dm && dm[T]) || shown >= 3)
				continue
			shown++
			var/list/ways = list()
			for(var/dir in GLOB.cardinals)
				var/turf/N = get_step(T, dir)
				if(N && engine_tiles[N])
					ways += "[dir2text(dir)] [N.type]: T onto it [call(T, adjacent)(caller, N, id, simulated_only)], it onto T [call(N, adjacent)(caller, T, id, simulated_only)]"
			var/list/things = list()
			for(var/atom/movable/AM as anything in T)
				if(isobj(AM) || ismob(AM))
					things += "[AM.type][AM.density ? " (dense)" : ""]"
			GLOB.path_engine_samples += "  engine only: [T.x],[T.y] [T.type] density [T.density] hazard [GLOB.bot_hazard_turfs[T]]; [jointext(ways, "; ")]; on it: [jointext(things, ", ")]"
	path_engine_write_check()
