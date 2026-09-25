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
	for(var/obj/machinery/field/F in T)
		if(istype(F, /obj/machinery/field/containment))
			return TRUE //exists at all only while its field connection is live
		if(istype(F, /obj/machinery/field/generator))
			var/obj/machinery/field/generator/G = F
			if(LAZYLEN(G.fields))
				return TRUE //fields.len>0 means its own Bumped()/shock() are live too (field_generator.dm)
	return FALSE

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
	for(var/A in orange(1, T))
		if(isturf(A))
			var/turf/adjacent = A
			if(adjacent.density)
				return TRUE
		else
			var/atom/movable/AM = A
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
/turf/proc/bot_reachable_strict(caller, turf/T, ID, simulated_only)
	if(T && !T.density && !(simulated_only && SSpathfinder.space_type_cache[T.type] && !bot_turf_crossable_without_boots(T, caller)) && !bot_turf_has_active_field(T) && !LinkBlockedWithAccess(T, caller, ID))
		return TRUE

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
	if(T && !T.density && !(simulated_only && SSpathfinder.space_type_cache[T.type] && !bot_turf_crossable_without_boots(T, caller)) && !bot_turf_has_active_field(T) && !bot_link_blocked_permissive(T, caller, ID))
		return TRUE

/turf/proc/bot_link_blocked_permissive(turf/T, caller, ID)
	var/adir = get_dir(src, T)
	var/rdir = ((adir & MASK_ODD)<<1)|((adir & MASK_EVEN)>>1)
	for(var/obj/structure/window/W in src)
		if(!W.CanAStarPass(ID, adir) && !bot_can_break_through(W, caller))
			return TRUE
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
		return !A.density || ((!A.welded || can_unweld) && A.hasPower())
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
	if(!istype(caller))
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

// Drop-in replacement for /turf/proc/Distance as get_path_to()'s cost function (AStar.dm
// uses it for both the edge cost and the heuristic).
/turf/proc/bot_weighted_distance(turf/T)
	return get_dist(src, T) + bot_turf_penalty(T)

// Total weighted cost of a found path (nodes + obstacle penalties), for comparing routes.
/proc/bot_path_cost(list/path)
	. = 0
	if(!path)
		return
	for(var/turf/T in path)
		. += 1 + bot_turf_penalty(T)
