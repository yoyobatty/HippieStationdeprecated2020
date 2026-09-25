// Tesla engine setup: a Station Engineer/CE assembles and powers the particle
// accelerator, wires up the tesla emitters, brings the containment field generators
// online, and wrenches down the tesla coils/grounding rods - the full round-start
// checklist a real engineer works through, in the order requested.
//
// All of this bypasses attackby()/Topic()/interact() (which expect a real tool item and
// a do_after, or a real `usr`) in favor of setting the same construction-state/anchored
// vars those tool interactions would ultimately set, then calling the same internal
// procs the UI itself calls (part_scan(), toggle_power(), turn_on(), connect_to_network())
// - identical approach to the cryo/sleeper/thermomachine/chem_dispenser work elsewhere
// in this system (see treat_patient.dm, synthesize_medicine.dm).
//
// Construction-state defines (PA_CONSTRUCTION_*, EMITTER_*, FG_*) are #undef'd at the
// end of their own source files (particle_control.dm, emitter.dm, field_generator.dm),
// so they're NOT safely referenceable by name from a file compiled after them - their
// literal values are hardcoded below instead, each labelled with the macro name they
// correspond to (confirmed via source read, not assumed from general SS13 knowledge).

/datum/bot_brain/proc/is_engineer_job()
	var/role = owner.mind?.assigned_role
	return role == "Station Engineer" || role == "Chief Engineer"

#define BOT_ENGINE_REACH 100
#define BOT_ENGINE_LOCAL_REACH 40

/datum/bot_brain/proc/find_pa_console()
	var/obj/machinery/particle_accelerator/control_box/best
	var/best_dist
	for(var/obj/machinery/particle_accelerator/control_box/CB in GLOB.machines)
		if(CB.z != owner.z)
			continue
		var/dist = get_dist(owner, CB)
		if(dist > BOT_ENGINE_REACH)
			continue
		if(!best || dist < best_dist)
			best = CB
			best_dist = dist
	return best

// The turf to measure the rest of the engine room's components against - the PA
// console if one's known, otherwise just the bot's own position. Used by the PA-part
// finders below (their own parts genuinely cluster around the console) - NOT by the
// emitter/field generator/coil/grounding rod finders, which anchor on the tesla
// generator itself instead (tesla_component_anchor(), below) for a confirmed, concrete
// reason: this station's supermatter engine sits in the SAME area type
// (/area/engine/engineering) as part of the tesla setup and has its own anchored
// emitters, which the PA console's reach used to be wide enough to sweep in as false
// candidates despite sitting 50+ tiles from the actual tesla generator (confirmed via
// the map source - the real tesla emitters sit ~9 tiles from it).
/datum/bot_brain/proc/engine_room_anchor()
	var/obj/machinery/particle_accelerator/control_box/CB = find_pa_console()
	return CB ? get_turf(CB) : get_turf(owner)

// See engine_room_anchor()'s comment above for why this exists as a separate anchor.
/datum/bot_brain/proc/find_tesla_generator()
	for(var/obj/machinery/the_singularitygen/tesla/T in GLOB.machines)
		if(T.z == owner.z)
			return T
	return null

// Returns null, NOT engine_room_anchor(), when the tesla generator can't be found -
// unlike find_incomplete_pa_target() (which genuinely has no other reference point and
// falls back to the console on purpose), every finder anchored on THIS proc exists
// specifically to stay away from the supermatter's own parts, which sit close enough to
// the PA console (~38 tiles, confirmed via the map source) to fall WITHIN
// BOT_ENGINE_LOCAL_REACH of it, while sitting safely outside that same reach of the tesla
// generator itself (~47-53 tiles). Falling back to the console the moment the tesla
// generator goes missing (destroyed by a real in-round tesla event) would silently let
// the supermatter's own emitters/coils/rods back into range - confirmed in-game: a
// Station Engineer bot activated supermatter emitters well into a round, after the real
// tesla generator had stopped existing. Returning null here instead means every proc
// anchored on this one finds nothing at all once the generator's gone, rather than risk
// grabbing the wrong engine's parts.
/datum/bot_brain/proc/tesla_component_anchor()
	var/obj/machinery/the_singularitygen/tesla/T = find_tesla_generator()
	return T ? get_turf(T) : null

// Console first, then every physical part within a few tiles of it (the cross-shaped
// layout in particle_accelerator.dm's own header comment) - whichever's still missing
// its wrench+wire+screwdriver assembly (construction_state 3 == PA_CONSTRUCTION_COMPLETE).
/datum/bot_brain/proc/find_incomplete_pa_target()
	var/obj/machinery/particle_accelerator/control_box/CB = find_pa_console()
	if(!CB)
		return null
	if(CB.construction_state < 3)
		return CB
	for(var/obj/structure/particle_accelerator/P in range(4, CB))
		if(P.construction_state < 3)
			return P
	return null

// A console whose own construction is done, isn't already running, and (per a real
// part_scan()) has every part correctly placed and assembled - AND every other piece of
// the engine is already ready. This ordering is critical, not cosmetic: powering the PA
// before containment is fully up can spawn a tesla ball with nothing in place yet to
// contain it, and having the plain gravitational singularity generator still sitting in
// the beam risks BOTH a tesla ball and a singularity spawning together. The PA is
// therefore only ever considered "ready to power on" once nothing else is left to do.
/datum/bot_brain/proc/find_ready_pa_console()
	var/obj/machinery/particle_accelerator/control_box/CB = find_pa_console()
	if(!CB)
		bot_log_verbose(src, "find_ready_pa_console: no PA console found at all")
		return null
	if(CB.active)
		bot_log_verbose(src, "find_ready_pa_console: [CB] already active")
		return null
	if(CB.construction_state < 3)
		bot_log_verbose(src, "find_ready_pa_console: [CB] construction_state=[CB.construction_state], not complete")
		return null
	for(var/obj/structure/particle_accelerator/P in range(4, CB))
		if(P.construction_state < 3)
			bot_log_verbose(src, "find_ready_pa_console: [P] construction_state=[P.construction_state], not complete")
			return null
	var/obj/machinery/the_singularitygen/leftover_singgen = find_singularity_generator_to_remove()
	if(leftover_singgen)
		bot_log_verbose(src, "find_ready_pa_console: [leftover_singgen] still needs removing")
		return null
	var/obj/machinery/power/emitter/incomplete_emitter = find_incomplete_tesla_emitter()
	if(incomplete_emitter)
		bot_log_verbose(src, "find_ready_pa_console: [incomplete_emitter] still needs activating")
		return null
	var/obj/machinery/field/generator/incomplete_fg = find_incomplete_field_generator()
	if(incomplete_fg)
		bot_log_verbose(src, "find_ready_pa_console: [incomplete_fg] still needs activating")
		return null
	var/obj/machinery/power/tesla_coil/unanchored_coil = find_unanchored_tesla_coil()
	if(unanchored_coil)
		bot_log_verbose(src, "find_ready_pa_console: [unanchored_coil] still needs wrenching down")
		return null
	var/obj/machinery/power/grounding_rod/unanchored_rod = find_unanchored_grounding_rod()
	if(unanchored_rod)
		bot_log_verbose(src, "find_ready_pa_console: [unanchored_rod] still needs wrenching down")
		return null
	return CB

// The plain gravitational singularity spawner, if one's sitting in the same area as the
// PA/engine room - NOT its /tesla subtype, which is the one we actually want the PA
// feeding. Having both in the beam risks spawning a singularity alongside the tesla
// ball, so this one gets permanently dragged out rather than just moved temporarily.
// Distance-based (tesla_component_anchor(), like the emitter/field generator/coil/rod
// finders), NOT a strict get_area(G) == get_area(engine_room_anchor()) match - this map
// tags the tesla setup's own rooms inconsistently (confirmed via the map source: one
// real corner emitter sits in /area/engine/engineering, another in /area/engine/
// port_engineering, and the plain singularity generator's own room is a THIRD tag
// again) - an exact-area requirement anchored on the PA console's own area never
// matched the generator's room at all, so this returned null on every single check,
// permanently blocking the goal from ever running (confirmed in-game: "couldn't find a
// target for remove_singularity_generator" on every cycle from round start).
// removed_singularity_generators (bot_brain.dm var) is checked here too - NOT just
// distance. find_turf_outside_area() (below), the no-storage fallback destination,
// only walks until it crosses the NEAREST area boundary - often just a few tiles, nowhere
// close to BOT_ENGINE_LOCAL_REACH away. Confirmed in-game as an infinite loop: the bot
// "successfully" nudged the same generator a short hop outside its original room, this
// distance check still found it well within reach on the very next scan, grabbed it
// again, nudged it again, forever - "goal succeeded" repeating with zero real progress.
// Distance alone can never distinguish "genuinely still needs removing" from "was just
// removed to a spot that happens to still be within reach" - once a specific generator
// has actually been dragged out once, it stays excluded for the rest of the round
// regardless of where it ends up, the same permanent-once-handled idea as
// known_tool_sources (bot_items.dm) uses for successful tool sources.
/datum/bot_brain/proc/find_singularity_generator_to_remove()
	var/turf/anchor = tesla_component_anchor()
	if(!anchor) //tesla generator gone - see tesla_component_anchor()'s comment
		return null
	// "Secure Storage 2" already holds its own spare singularity generator as
	// pre-placed stock. Skip anything whose own bordering door IS the storage door -
	// genuinely nothing left to do with it. Uses poddoor_bordering_area(), NOT
	// find_poddoor_gating() - the latter deliberately skips a door that's currently open
	// ("already open, nothing to do", correct for ITS job of finding an entry door to
	// open), which meant this check went blind the instant the storage door was left
	// open behind an actual delivery - confirmed in-game: right after dragging the real
	// stray generator in, the bot immediately grabbed the spare too, since the storage
	// door being open at that exact moment made it fail to recognize the spare as
	// already-stored at all.
	var/obj/machinery/door/poddoor/storage_door = find_engine_secure_storage()
	for(var/obj/machinery/the_singularitygen/G in GLOB.machines)
		if(istype(G, /obj/machinery/the_singularitygen/tesla))
			continue //keep this one - it's what the PA is supposed to feed
		if(G.anchored)
			continue //don't touch the one in storage, we set this one anchored as a hack
		if(G.z != owner.z)
			continue
		if(G in removed_singularity_generators)
			continue
		if(get_dist(anchor, G) > BOT_ENGINE_LOCAL_REACH)
			continue //a combat/armory singularity generator elsewhere isn't this bot's business
		if(is_failed_engine_part(G))
			continue //a real pursuit already failed reaching this one - see on_give_up() below
		if(storage_door && poddoor_bordering_area(G) == storage_door)
			continue //already sitting in secure storage - pre-placed stock, not a stray part
		return G
	return null

// Walks straight out from `near` in each cardinal direction, one tile at a time, and
// returns the first tile that's crossed into a different area - NOT just any
// unobstructed tile within a radius (orange(12,...) used to pick from anywhere in a
// 12-tile circle, including tiles only reachable via a completely different, possibly
// unconnected route - confirmed in-game: it picked a "plating" tile in a maintenance
// pocket the pathfinder couldn't find any legitimate route to at all). Walking a single
// contiguous line and stopping the instant something blocks it guarantees the result is
// actually connected to `near` by a straight, walkable corridor.
/datum/bot_brain/proc/find_turf_outside_area(area/avoid_area, atom/near)
	var/turf/start = get_turf(near)
	if(!start)
		return null
	for(var/d in GLOB.cardinals)
		var/turf/T = start
		for(var/i in 1 to 10)
			var/turf/next = get_step(T, d)
			if(!next || next.density || isspaceturf(next))
				break //blocked this direction - try the next cardinal
			var/blocked = FALSE
			for(var/atom/movable/AM in next)
				if(AM.density)
					blocked = TRUE
					break
			if(blocked)
				break
			T = next
			if(get_area(T) != avoid_area)
				return T
	return null

// /obj/machinery/power/emitter/anchored specifically, NOT the plain base type - the
// spare/decommissioned emitters sitting in "Secure Storage" (setup_tesla_engine.dm's
// remove_singularity_generator section has the full story on that room) are plain,
// never-anchored /obj/machinery/power/emitter instances, while every real emitter
// actually wired into this engine is mapped as the /anchored subtype. Scanning the
// broader base type used to make the bot discover that distinction the slow way - walk
// there, fail to path, give up - once per spare, every single time a round starts.
// Filtering by type here means it's never even considered a candidate to begin with.
// Range-gated on distance to the tesla generator (anchor) - keeps combat/armory or
// supermatter-side emitters out of consideration entirely - but PICKED by distance to
// the bot's own current position, not to the anchor. The anchor is a single fixed point,
// so every real emitter near it reads as roughly equally "close" to IT regardless of
// where the bot actually is - the old best-by-anchor-distance comparison then just fell
// back to GLOB.machines' arbitrary creation order among near-ties, confirmed in-game as
// the bot bouncing between far corners of the engine room (bottom-middle, then top-right,
// then back) instead of clearing whatever's nearest to it first like a real engineer
// walking the room would.
/datum/bot_brain/proc/find_incomplete_tesla_emitter()
	var/turf/anchor = tesla_component_anchor()
	if(!anchor) //tesla generator gone - see tesla_component_anchor()'s comment
		return null
	var/turf/bot_turf = get_turf(owner)
	var/obj/machinery/power/emitter/best
	var/best_dist
	for(var/obj/machinery/power/emitter/anchored/E in GLOB.machines)
		if(E.z != owner.z)
			continue
		if(E.active && E.state == 2 && !E.locked) //EMITTER_WELDED
			continue //already fully set up
		if(is_failed_engine_part(E))
			continue //a real pursuit already failed on this one - see on_give_up() below
		if(get_dist(anchor, E) > BOT_ENGINE_LOCAL_REACH) //stay near the engine room - a combat/armory emitter elsewhere isn't this bot's business
			continue
		var/dist = get_dist(bot_turf, E)
		if(!best || dist < best_dist)
			best = E
			best_dist = dist
	return best

// F.anchored required, NOT just F.active - the same "Secure Storage" spare-parts
// problem the emitter finder solved via its /anchored SUBTYPE (see that proc's comment)
// applies here too, just with a plain var instead of a subtype: every REAL field
// generator is pre-anchored via its own map override (anchored=1, state=2 - confirmed
// via the map source), while the spares sitting in storage have neither set. Without
// this check, an unanchored spare read as just as "incomplete" as an unanchored real
// one (this finder used to treat "not yet active" as the only signal), and since
// distance alone doesn't separate them either (storage sits well within ordinary reach
// of the tesla generator, unlike the ~50-tile-distant supermatter case), the round got
// stuck retrying spares and never reached the coils/grounding rods behind them in the
// checklist order.
// Picked by distance to the bot's own position, range-gated on distance to the tesla
// generator - see find_incomplete_tesla_emitter()'s comment above for why (same fix,
// same reason: the anchor is fixed, so "closest to the anchor" barely distinguishes
// between coils/rods/generators clustered tightly around it, leaving the pick to fall
// back to arbitrary GLOB.machines order instead of whichever one the bot could clear
// next without crossing the whole room).
/datum/bot_brain/proc/find_incomplete_field_generator()
	var/turf/anchor = tesla_component_anchor()
	if(!anchor) //tesla generator gone - see tesla_component_anchor()'s comment
		return null
	var/turf/bot_turf = get_turf(owner)
	var/obj/machinery/field/generator/best
	var/best_dist
	for(var/obj/machinery/field/generator/F in GLOB.machines)
		if(F.z != owner.z || F.active || !F.anchored)
			continue
		if(is_failed_engine_part(F))
			continue
		if(get_dist(anchor, F) > BOT_ENGINE_LOCAL_REACH)
			continue
		var/dist = get_dist(bot_turf, F)
		if(!best || dist < best_dist)
			best = F
			best_dist = dist
	return best

/datum/bot_brain/proc/find_unanchored_tesla_coil()
	var/turf/anchor = tesla_component_anchor()
	if(!anchor) //tesla generator gone - see tesla_component_anchor()'s comment
		return null
	var/turf/bot_turf = get_turf(owner)
	var/obj/machinery/power/tesla_coil/best
	var/best_dist
	for(var/obj/machinery/power/tesla_coil/TC in GLOB.machines)
		if(TC.z != owner.z || TC.anchored)
			continue
		if(is_failed_engine_part(TC))
			continue
		if(get_dist(anchor, TC) > BOT_ENGINE_LOCAL_REACH)
			continue
		var/dist = get_dist(bot_turf, TC)
		if(!best || dist < best_dist)
			best = TC
			best_dist = dist
	return best

/datum/bot_brain/proc/find_unanchored_grounding_rod()
	var/turf/anchor = tesla_component_anchor()
	if(!anchor) //tesla generator gone - see tesla_component_anchor()'s comment
		return null
	var/turf/bot_turf = get_turf(owner)
	var/obj/machinery/power/grounding_rod/best
	var/best_dist
	for(var/obj/machinery/power/grounding_rod/GR in GLOB.machines)
		if(GR.z != owner.z || GR.anchored)
			continue
		if(is_failed_engine_part(GR))
			continue
		if(get_dist(anchor, GR) > BOT_ENGINE_LOCAL_REACH)
			continue
		var/dist = get_dist(bot_turf, GR)
		if(!best || dist < best_dist)
			best = GR
			best_dist = dist
	return best

// A poddoor's real, player-facing open mechanism is its matching remote control button
// (a SEPARATE /obj/machinery/button/door object elsewhere, sharing the poddoor's `id`) -
// try_to_activate_door() on a poddoor itself is a deliberate no-op (poddoor.dm), and
// crowbar-prying only works when it's already unpowered. Confirmed in-game: a "Secure
// Storage" poddoor blocking the singularity generator's real drop-off point had exactly
// this button sitting in the ordinary corridor right outside it.
/datum/bot_brain/proc/find_matching_door_button(obj/machinery/door/poddoor/P)
	if(!P || !P.id)
		return null
	var/obj/machinery/button/door/best
	var/best_dist
	for(var/obj/machinery/button/door/B in GLOB.machines)
		if(B.z != owner.z || B.id != P.id)
			continue
		var/dist = get_dist(owner, B)
		if(!best || dist < best_dist)
			best = B
			best_dist = dist
	return best

// Whichever nearby poddoor directly borders the SAME area as `target` - i.e. the door
// actually gating access to wherever `target` sits, as opposed to some OTHER unrelated
// poddoor nearby (this map has two distinct "Secure Storage" rooms near the engine:
// one holds the live singularity generator itself, a separate one holds spare parts -
// conflating them is exactly what left an earlier version of this fix unable to even
// reach the generator to grab it, having only ever learned to open the OTHER door).
// Area equality ALONE is not enough here and was confirmed wrong in-game: a
// station-wide area type like /area/engine/port_engineering is one single area
// instance/object shared by every tile tagged with it, however physically far apart -
// it is NOT guaranteed to be one contiguous region. A poddoor 40+ tiles away near a
// completely unrelated room (the brig/execution chamber, as it happened) can border a
// tile that merely shares the SAME area type by coincidence, and get_area(T) ==
// target_area is blind to that. A real gating door has to be physically close to the
// target too - BOT_ENGINE_LOCAL_REACH (the same cap the emitter/field
// generator/coil/rod/singularity-generator finders use) is the same reasonable bound
// for "close enough to plausibly be this room's own entrance."
/datum/bot_brain/proc/find_poddoor_gating(atom/target)
	var/area/target_area = get_area(target)
	if(!target_area)
		return null
	for(var/obj/machinery/door/poddoor/P in GLOB.machines)
		if(P.z != owner.z || !P.density)
			continue //already open - nothing to do
		if(get_dist(target, P) > BOT_ENGINE_LOCAL_REACH)
			continue //same area type, but nowhere near the target physically
		for(var/d in GLOB.cardinals)
			var/turf/T = get_step(P, d)
			if(T && get_area(T) == target_area)
				return P
	return null

// Same area-matching search as find_poddoor_gating() above, but WITHOUT the "already
// open - nothing to do" skip - that skip is correct for find_poddoor_gating()'s own job
// (which door needs opening to reach this, where an open door means nothing to open),
// but wrong for asking a purely structural question ("which room is this atom in") that
// shouldn't change depending on whether the door happens to be open at query time.
// Confirmed as a real bug: find_singularity_generator_to_remove() reused find_poddoor_
// gating() for exactly this purpose, and the instant a delivery left the storage door
// open behind it, the very next check couldn't recognize that door at all - the spare
// generator already sitting in storage stopped reading as "in storage" and got grabbed
// right back up as if it were a second stray part.
/datum/bot_brain/proc/poddoor_bordering_area(atom/target)
	var/area/target_area = get_area(target)
	if(!target_area)
		return null
	for(var/obj/machinery/door/poddoor/P in GLOB.machines)
		if(P.z != owner.z)
			continue
		if(get_dist(target, P) > BOT_ENGINE_LOCAL_REACH)
			continue
		for(var/d in GLOB.cardinals)
			var/turf/T = get_step(P, d)
			if(T && get_area(T) == target_area)
				return P
	return null

// The poddoor-gated "secure storage" alcove near the engine room - the intended
// drop-off for the stray singularity generator (find_singularity_generator_to_remove(),
// above), not a dead end. Player-facing name convention ("Secure Storage") is the only
// signal available here; scoped to double the ordinary engine-part reach since storage
// tends to sit a bit further out from the core PA/emitter/coil cluster than those parts
// themselves.
/datum/bot_brain/proc/find_engine_secure_storage()
	var/turf/anchor = engine_room_anchor()
	var/obj/machinery/door/poddoor/best
	var/best_dist
	for(var/obj/machinery/door/poddoor/P in GLOB.machines)
		if(P.z != owner.z)
			continue
		if(!findtext(P.name, "storage"))
			continue
		var/dist = get_dist(anchor, P)
		if(dist > BOT_ENGINE_LOCAL_REACH * 2)
			continue
		if(!best || dist < best_dist)
			best = P
			best_dist = dist
	return best

// "Singularity" is this map's shared id for the engine room's radiation shutters
// (/obj/machinery/door/poddoor/shutters/preopen - starts OPEN, confirmed via the map
// source) and their control buttons (req_access_txt="11", which the Chief Engineer/
// Station Engineer's own ID already satisfies). Pressing a button toggles based on
// current state (/obj/item/assembly/control/activate(), doorcontrol.dm: openclose =
// M.density), so a single press on an open shutter closes it - no need to check which
// specific direction "closed" is.
/datum/bot_brain/proc/find_open_engine_shutter()
	for(var/obj/machinery/door/poddoor/shutters/S in GLOB.machines)
		if(S.z != owner.z || S.id != "Singularity" || S.density)
			continue //already closed, or a shutter belonging to some other room entirely
		return S
	return null

// Deliberately NOT "nearest to the tesla generator" - confirmed via the map source that
// one of this room's four "Singularity" shutter buttons sits a single tile from the PA
// console itself (the control booth's buttons line the same narrow corridor the console
// stands in), while the other three sit a further 3-5 tiles out. Picking blind-nearest
// could easily land on that one-tile button, putting the bot right next to the
// accelerator exactly when the shutters seal it in - the opposite of what closing them
// is for. A minimum safety radius from the console specifically (not just "far from the
// tesla generator", which the close button already satisfies) rules that one out in
// favor of a farther candidate.
/datum/bot_brain/proc/find_engine_shutter_button()
	var/turf/anchor = tesla_component_anchor()
	if(!anchor) //tesla generator gone - see tesla_component_anchor()'s comment
		return null
	var/obj/machinery/particle_accelerator/control_box/CB = find_pa_console()
	var/obj/machinery/button/door/best
	var/best_dist
	for(var/obj/machinery/button/door/B in GLOB.machines)
		if(B.z != owner.z || B.id != "Singularity")
			continue
		if(CB && get_dist(CB, B) <= 2)
			continue //too close to the console/accelerator itself - not a safe place to be when the shutters close
		var/dist = get_dist(anchor, B)
		if(dist > BOT_ENGINE_LOCAL_REACH * 2) //same generous margin find_engine_secure_storage() uses - shutter controls sit at the room's exits, not its core
			continue
		if(!best || dist < best_dist)
			best = B
			best_dist = dist
	return best

#undef BOT_ENGINE_REACH
#undef BOT_ENGINE_LOCAL_REACH

/datum/bot_brain/proc/try_engineering_round()
	if(!is_engineer_job())
		return FALSE
	// Safety-critical order: clear the stray singularity generator and get every piece
	// of containment (emitters, field generators, coils, grounding rods) physically
	// assembled and running FIRST, and only power on the particle accelerator once
	// nothing else is left to do - find_ready_pa_console() itself re-checks every one
	// of these, so even if this list's order ever drifts, the PA still can't go live
	// early. Powering it first, before containment exists, is exactly how a tesla ball
	// gets loose and wrecks the station.
	//
	// Coils/grounding rods BEFORE field generators specifically (not just "somewhere
	// before the PA") - confirmed in-game: once enough field generators are active, the
	// live containment fields between them can fully box in a coil that hasn't been
	// wrenched down yet, and a field never turns itself back off once formed. The bot
	// correctly refuses to walk through a live field (bot_pathing_permissive.dm) rather
	// than risk the shock, which is the right call - but that means an unwrenched coil
	// sealed inside the field ring becomes permanently unreachable for the rest of the
	// round. Coils/rods have no dependency on field generators being active at all
	// (purely physical, wrench-only work), so there's no reason to risk that ordering -
	// only the field generators themselves genuinely need to go after the emitters
	// (they only ever get power from being shot by one).
	if(assign_goal(new /datum/bot_goal/remove_singularity_generator()))
		return TRUE
	if(assign_goal(new /datum/bot_goal/assemble_pa_part()))
		return TRUE
	if(assign_goal(new /datum/bot_goal/activate_tesla_emitter()))
		return TRUE
	if(assign_goal(new /datum/bot_goal/wrench_tesla_coil()))
		return TRUE
	if(assign_goal(new /datum/bot_goal/wrench_grounding_rod()))
		return TRUE
	if(assign_goal(new /datum/bot_goal/activate_field_generator()))
		return TRUE
	if(assign_goal(new /datum/bot_goal/activate_particle_accelerator()))
		return TRUE
	// Last step, once the PA is actually live: close the radiation shutters behind
	// itself on the way out, same as a real engineer clearing the room and sealing it
	// - see close_engine_shutters below for the full mechanism.
	return assign_goal(new /datum/bot_goal/close_engine_shutters())

// Same immediate-rechain idea as continue_medical_round() (treat_patient.dm) - finish
// one component, go straight to the next instead of waiting out the normal wander pace.
/datum/bot_brain/proc/continue_engineering_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_engineering_round)))

// ============================================================
// Particle accelerator assembly - one part (or the console itself) per trip.
// ============================================================

/datum/bot_goal/assemble_pa_part/resolve_target(datum/bot_brain/bot)
	target = bot.find_incomplete_pa_target()

/datum/bot_goal/assemble_pa_part/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/assemble_pa())

/datum/bot_goal/assemble_pa_part/on_success(datum/bot_brain/bot)
	bot.continue_engineering_round()

/datum/bot_strategy/assemble_pa/New()
	. = ..()
	steps = list(new /datum/bot_step/ensure_pa_tools(), new /datum/bot_step/move_to(), new /datum/bot_step/complete_pa_part())

/datum/bot_strategy/assemble_pa/is_feasible(datum/bot_brain/bot)
	return TRUE

// Wrench, screwdriver, and a cable coil are ALL needed to fully assemble a PA part
// (see complete_pa_part below) - fetched once up front, same "check the toolbelt before
// setting off" idea as ensure_tools (acquire_captains_id.dm). Cable coil isn't in
// GLOB.bot_tool_items (it's consumable, not a tool), so pickup_tool_from_target's
// is_tool_or_toolbox() filter would silently skip it if fetched via acquire_tool against
// a closet/toolbox target - acquire_item_type is used for it instead, which grabs the
// exact target item with no such filtering.
/datum/bot_step/ensure_pa_tools/execute(datum/bot_brain/bot)
	// can_eventually_provide_tool() (bot_items.dm), NOT find_carried_tool() directly -
	// wrench/power and screwdriver/power are the SAME physical "hand drill" tool (see
	// that proc's comment), so the bot can never carry both forms at once. Requiring
	// both PRESENT here would be checking for something impossible whenever the CE's
	// actual starting tool is one of the transforming pairs. complete_pa_part()
	// transforms it into whichever specific form each step needs, right when it needs it.
	if(!bot.can_eventually_provide_tool(/obj/item/wrench))
		if(bot.suspend_goal_for(new /datum/bot_goal/acquire_tool(/obj/item/wrench)))
			return GOAL_STEP_PENDING
		return GOAL_STEP_FAIL
	if(!bot.can_eventually_provide_tool(/obj/item/screwdriver))
		if(bot.suspend_goal_for(new /datum/bot_goal/acquire_tool(/obj/item/screwdriver)))
			return GOAL_STEP_PENDING
		return GOAL_STEP_FAIL
	var/obj/item/stack/cable_coil/CC = bot.find_carried_tool(/obj/item/stack/cable_coil)
	if(!CC || CC.get_amount() < 1)
		var/datum/bot_goal/acquire_item_type/coil_goal = new()
		coil_goal.item_type = /obj/item/stack/cable_coil
		if(bot.suspend_goal_for(coil_goal))
			return GOAL_STEP_PENDING
		return GOAL_STEP_FAIL
	return GOAL_STEP_SUCCESS

// Target is either the control_box or a plain /obj/structure/particle_accelerator
// part - two unrelated type trees that each declare construction_state/anchored
// independently rather than sharing a common typed ancestor for them, so this branches
// on istype() and works with a real typed local in each arm (rather than fighting DM's
// static type inference on a shared untyped var, which infers /atom - and neither
// construction_state nor update_icon() exist on plain /atom - regardless of how the
// var's declared).
//
// Does exactly ONE real construction_state transition per call via use_item_on(), which
// routes through the genuine attackby() (melee_attack_chain(), bot_items.dm) instead of
// setting construction_state/anchored directly - a bot used to jump straight to
// construction_state 3, skipping the wrench->wire->screwdriver sequence a real engineer
// does (and never actually touching the tools at all, an obvious "cheese" watching it
// happen). on_success() (below) requeues continue_engineering_round(), which re-resolves
// the SAME target (still < PA_CONSTRUCTION_COMPLETE) and runs this step again for the
// next transition - three consecutive calls in place, same as three consecutive real
// clicks, no extra travel needed since the bot's already standing there.
/datum/bot_step/complete_pa_part/execute(datum/bot_brain/bot)
	var/atom/target = bot.current_goal?.target
	if(!target || QDELETED(target))
		return GOAL_STEP_FAIL
	if(!istype(target, /obj/machinery/particle_accelerator/control_box) && !istype(target, /obj/structure/particle_accelerator))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(target))
		return GOAL_STEP_FAIL
	var/before_state = target:construction_state
	var/obj/item/tool
	switch(before_state)
		if(0) //PA_CONSTRUCTION_UNSECURED
			tool = bot.find_or_transform_tool(/obj/item/wrench)
		if(1) //PA_CONSTRUCTION_UNWIRED
			tool = bot.find_carried_tool(/obj/item/stack/cable_coil)
		if(2) //PA_CONSTRUCTION_PANEL_OPEN
			tool = bot.find_or_transform_tool(/obj/item/screwdriver)
		else
			return GOAL_STEP_FAIL //already PA_CONSTRUCTION_COMPLETE, or an unrecognized state
	if(!tool)
		return GOAL_STEP_FAIL //ensure_pa_tools should have prevented this, but don't cheese it if it somehow didn't
	bot.use_item_on(tool, target)
	// Checking the real post-call state, not trusting a return value - same pattern as
	// grab_patient/grab_singgen (treat_patient.dm/this file) for procs with no reliable
	// success signal of their own. attackby() silently no-ops (did_something stays
	// FALSE) for reasons use_item_on() can't see from the outside - isinspace() blocking
	// the wrench step, or a cable coil with 0 length left after use(1).
	if(target:construction_state == before_state)
		return GOAL_STEP_FAIL
	bot_log(bot, "worked on [target] (construction_state [before_state] -> [target:construction_state])")
	return GOAL_STEP_SUCCESS

// ============================================================
// Powering on the assembled PA.
// ============================================================

/datum/bot_goal/activate_particle_accelerator/resolve_target(datum/bot_brain/bot)
	target = bot.find_ready_pa_console()

/datum/bot_goal/activate_particle_accelerator/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/power_up_pa())

/datum/bot_goal/activate_particle_accelerator/on_success(datum/bot_brain/bot)
	bot.continue_engineering_round()

/datum/bot_strategy/power_up_pa/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/power_up_pa())

/datum/bot_strategy/power_up_pa/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/power_up_pa/execute(datum/bot_brain/bot)
	var/obj/machinery/particle_accelerator/control_box/CB = bot.current_goal?.target
	if(!CB || QDELETED(CB))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(CB))
		return GOAL_STEP_FAIL
	if(!CB.part_scan()) //re-validates every part's exact position/facing itself - the real assembly check, not duplicated here
		bot_log_verbose(bot, "power_up_pa: part_scan() failed on [CB] - a part must be missing, misaligned, or facing the wrong way")
		return GOAL_STEP_FAIL
	CB.strength = CB.strength_upper_limit
	CB.strength_change()
	if(!CB.active)
		CB.toggle_power()
	CB.update_icon()
	bot_log(bot, "powered on the particle accelerator at strength [CB.strength]")
	return GOAL_STEP_SUCCESS

// ============================================================
// Tesla emitters - anchor, weld, join the powernet, unlock, and switch on.
// ============================================================

/datum/bot_goal/activate_tesla_emitter/resolve_target(datum/bot_brain/bot)
	target = bot.find_incomplete_tesla_emitter()

/datum/bot_goal/activate_tesla_emitter/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/activate_emitter())

/datum/bot_goal/activate_tesla_emitter/on_success(datum/bot_brain/bot)
	bot.continue_engineering_round()

// A pursuit that genuinely fails (not just "no target found") means this exact emitter
// is unreachable regardless of gear/tools - see is_failed_engine_part()'s comment
// (bot_goals.dm) for the real case this fixes: a "Secure Storage" alcove of spare,
// never-wired emitters behind a sealed door, indistinguishable from the real ones by
// find_incomplete_tesla_emitter()'s plain GLOB.machines scan. Without this, the round
// picked the exact same doomed emitter every single retry, forever, and never reached
// field generators/coils/rods behind it in the checklist.
/datum/bot_goal/activate_tesla_emitter/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.failed_engine_parts, target, world.time + rand(600, 1200))

/datum/bot_strategy/activate_emitter/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/activate_emitter())

/datum/bot_strategy/activate_emitter/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/activate_emitter/execute(datum/bot_brain/bot)
	var/obj/machinery/power/emitter/E = bot.current_goal?.target
	if(!E || QDELETED(E))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(E))
		return GOAL_STEP_FAIL
	E.anchored = TRUE
	E.state = 2 //EMITTER_WELDED
	E.connect_to_network()
	E.locked = FALSE
	E.active = TRUE
	E.shot_number = 0
	E.fire_delay = E.maximum_fire_delay
	E.update_icon()
	bot_log(bot, "activated [E]")
	return GOAL_STEP_SUCCESS

// ============================================================
// Containment field generators - weld, anchor, and turn on. These aren't wired to a
// powernet at all (field_generator.dm has no connect_to_network() call anywhere) - they
// only ever get power from being shot (bullet_act()), so their charge is set directly
// here to the real max (field_generator_max_power == 250) rather than leaving them to
// start at the mapped default and immediately stall out with nothing feeding them.
// ============================================================

/datum/bot_goal/activate_field_generator/resolve_target(datum/bot_brain/bot)
	target = bot.find_incomplete_field_generator()

/datum/bot_goal/activate_field_generator/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/activate_field_gen())

/datum/bot_goal/activate_field_generator/on_success(datum/bot_brain/bot)
	bot.continue_engineering_round()

// See activate_tesla_emitter/on_give_up() above - same fix, same reason.
/datum/bot_goal/activate_field_generator/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.failed_engine_parts, target, world.time + rand(600, 1200))

/datum/bot_strategy/activate_field_gen/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/activate_field_generator())

/datum/bot_strategy/activate_field_gen/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/activate_field_generator/execute(datum/bot_brain/bot)
	var/obj/machinery/field/generator/F = bot.current_goal?.target
	if(!F || QDELETED(F))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(F))
		return GOAL_STEP_FAIL
	F.anchored = TRUE
	F.state = 2 //FG_WELDED
	F.power = 250 //field_generator_max_power
	F.turn_on() //async (spawn/sleep chain) - fields form ~1.5s later against whichever neighbors are ALSO already active by then, same as a real multi-generator startup
	bot_log(bot, "activated [F]")
	return GOAL_STEP_SUCCESS

// ensure_wrench (defined once, in treat_patient.dm) is pair-aware - the hand drill in
// either mode satisfies it, and each wrench_* step below transforms it at point of use
// via find_or_transform_tool().

// ============================================================
// Tesla coils - wrench down, which alone joins the powernet here (no separate weld
// step, unlike the emitter/field generator - confirmed in coil.dm, wrenching calls
// connect_to_network() directly).
// ============================================================

/datum/bot_goal/wrench_tesla_coil/resolve_target(datum/bot_brain/bot)
	target = bot.find_unanchored_tesla_coil()

/datum/bot_goal/wrench_tesla_coil/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/wrench_coil())

/datum/bot_goal/wrench_tesla_coil/on_success(datum/bot_brain/bot)
	bot.continue_engineering_round()

// See activate_tesla_emitter/on_give_up() (above) - same fix, same reason.
/datum/bot_goal/wrench_tesla_coil/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.failed_engine_parts, target, world.time + rand(600, 1200))

/datum/bot_strategy/wrench_coil/New()
	. = ..()
	steps = list(new /datum/bot_step/ensure_wrench(), new /datum/bot_step/move_to(), new /datum/bot_step/wrench_tesla_coil())

/datum/bot_strategy/wrench_coil/is_feasible(datum/bot_brain/bot)
	return TRUE

// Real wrench click via use_item_on() -> the actual attackby()/default_unfasten_wrench()
// (coil.dm) - same fix as complete_pa_part()'s (setup_tesla_engine.dm, above): this used
// to jump straight to anchored=TRUE/icon_state without ever touching a wrench, the same
// kind of cheese already fixed for PA assembly. default_unfasten_wrench() sets the exact
// same icon_state and calls connect_to_network() itself, so this isn't a shortcut -
// wrenching is genuinely the only step a coil needs (confirmed in coil.dm: no separate
// weld step, unlike the emitter/field generator).
/datum/bot_step/wrench_tesla_coil/execute(datum/bot_brain/bot)
	var/obj/machinery/power/tesla_coil/TC = bot.current_goal?.target
	if(!TC || QDELETED(TC))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(TC))
		return GOAL_STEP_FAIL
	var/obj/item/wrench = bot.find_or_transform_tool(/obj/item/wrench)
	if(!wrench)
		return GOAL_STEP_FAIL //ensure_wrench should have prevented this, but don't cheese it if it somehow didn't
	var/before_anchored = TC.anchored
	bot.use_item_on(wrench, TC)
	// Checking the real post-call state, not trusting a return value - same pattern as
	// complete_pa_part()/grab_patient/grab_singgen.
	if(TC.anchored == before_anchored)
		return GOAL_STEP_FAIL
	bot_log(bot, "wrenched down [TC]")
	return GOAL_STEP_SUCCESS

// ============================================================
// Grounding rods - wrench down only. Purely passive damage/redirect targets, they
// never join a powernet (no connect_to_network() call anywhere in coil.dm for this type).
// ============================================================

/datum/bot_goal/wrench_grounding_rod/resolve_target(datum/bot_brain/bot)
	target = bot.find_unanchored_grounding_rod()

/datum/bot_goal/wrench_grounding_rod/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/wrench_rod())

/datum/bot_goal/wrench_grounding_rod/on_success(datum/bot_brain/bot)
	bot.continue_engineering_round()

// See activate_tesla_emitter/on_give_up() (above) - same fix, same reason.
/datum/bot_goal/wrench_grounding_rod/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.failed_engine_parts, target, world.time + rand(600, 1200))

/datum/bot_strategy/wrench_rod/New()
	. = ..()
	steps = list(new /datum/bot_step/ensure_wrench(), new /datum/bot_step/move_to(), new /datum/bot_step/wrench_grounding_rod())

/datum/bot_strategy/wrench_rod/is_feasible(datum/bot_brain/bot)
	return TRUE

// Real wrench click via use_item_on() - see wrench_tesla_coil/execute()'s comment above,
// same fix, same reason.
/datum/bot_step/wrench_grounding_rod/execute(datum/bot_brain/bot)
	var/obj/machinery/power/grounding_rod/GR = bot.current_goal?.target
	if(!GR || QDELETED(GR))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(GR))
		return GOAL_STEP_FAIL
	var/obj/item/wrench = bot.find_or_transform_tool(/obj/item/wrench)
	if(!wrench)
		return GOAL_STEP_FAIL //ensure_wrench should have prevented this, but don't cheese it if it somehow didn't
	var/before_anchored = GR.anchored
	bot.use_item_on(wrench, GR)
	if(GR.anchored == before_anchored)
		return GOAL_STEP_FAIL
	bot_log(bot, "wrenched down [GR]")
	return GOAL_STEP_SUCCESS

// ============================================================
// Remove the stray gravitational singularity generator from the engine room - keeping
// both it and the tesla variant in the same beam path risks spawning a singularity
// alongside the tesla ball. Dragged out permanently (start_pulling(), same mechanic as
// escorting a patient to a sleeper - see treat_patient.dm), not just nudged aside.
// ============================================================

/datum/bot_goal/remove_singularity_generator
	var/turf/destination
	// Two DISTINCT poddoor-gated rooms exist near this engine, confirmed via the map's
	// own key legend - "Secure Storage" (id-matched button/door pair) holds the LIVE
	// singularity generator itself, "Secure Storage 2" (a separate id-matched pair)
	// holds spare/decommissioned parts and is where the removed generator gets dragged
	// to. Conflating them (an earlier version of this fix only ever opened the second
	// one) is exactly what left the bot unable to even reach the generator to grab it -
	// find_poddoor_gating(G) below finds whichever door actually borders the
	// GENERATOR's own room, independent of name, while find_engine_secure_storage()
	// finds the (different) drop-off room by name.
	var/obj/machinery/door/poddoor/entry_door
	var/obj/machinery/button/door/entry_button
	// The drop-off point and its matching button, if either exists near this engine room
	// - see find_engine_secure_storage()/find_matching_door_button() above. Both null
	// falls back to the old "just drag it clear of the engine room" behavior via plain
	// `destination`.
	var/obj/machinery/door/poddoor/storage_door
	var/obj/machinery/button/door/storage_button

/datum/bot_goal/remove_singularity_generator/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/the_singularitygen/G = bot.find_singularity_generator_to_remove()
	if(!G)
		return

	entry_door = bot.find_poddoor_gating(G)
	entry_button = entry_door ? bot.find_matching_door_button(entry_door) : null
	if(entry_door && !entry_button)
		return //sealed in with no way to open it at all - nothing this goal can do

	storage_door = bot.find_engine_secure_storage()
	if(storage_door == entry_door)
		storage_door = null //don't drag it right back into the room it just came out of
	storage_button = storage_door ? bot.find_matching_door_button(storage_door) : null
	if(!storage_door || !storage_button)
		// No (other) secure storage found nearby, or nothing to open it with - fall back
		// to the original behavior (drag it clear of the engine room) rather than
		// failing the whole goal outright. The exact drop-off spot matters far less than
		// getting the singularity generator out of the particle accelerator's beam.
		storage_door = null
		storage_button = null
		var/area/engine_area = get_area(G)
		destination = bot.find_turf_outside_area(engine_area, G)
		if(!destination)
			return //nothing usable at all - let assign_goal() report "no target" honestly

	target = G

/datum/bot_goal/remove_singularity_generator/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/remove_singgen(entry_door, entry_button, storage_door, storage_button, destination))

/datum/bot_goal/remove_singularity_generator/on_success(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	if(target)
		LAZYADD(bot.removed_singularity_generators, target)
	bot.continue_engineering_round()

// This goal has only ever ONE possible target (unlike the emitter/coil/rod finders,
// which pick from several candidates) - without this, an unreachable singularity
// generator was retried by try_engineering_round() EVERY single cycle forever (it's
// tried first, ahead of everything else in the checklist), with no cooldown or
// blacklist to ever let the round move past it - confirmed in-game: 7 identical
// failures to the same turf inside 90 seconds, blocking PA assembly/emitters entirely.
/datum/bot_goal/remove_singularity_generator/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	if(target)
		LAZYSET(bot.failed_engine_parts, target, world.time + rand(600, 1200))

/datum/bot_strategy/remove_singgen
	var/obj/machinery/door/poddoor/entry_door
	var/obj/machinery/door/poddoor/storage_door
	var/turf/destination

// Builds up to 4 phases, each only included if actually needed:
// 1. (entry_door set) unlock the way IN to the generator's own room
// 2. always: walk to the generator, grab it
// 3. (storage_door set) unlock the way IN to the drop-off room
// 4. deliver it - either a precomputed plain turf (destination set, the no-storage
//    fallback), or a lazily-computed one inside storage (move_to_storage, only once
//    storage_door is confirmed open - see that step's own comment for why it can't be
//    precomputed the same way).
/datum/bot_strategy/remove_singgen/New(obj/machinery/door/poddoor/entry_P, obj/machinery/button/door/entry_B, obj/machinery/door/poddoor/storage_P, obj/machinery/button/door/storage_B, turf/T)
	. = ..()
	entry_door = entry_P
	storage_door = storage_P
	destination = T
	steps = list()
	// .density, not just "was a door/button found" - the button TOGGLES rather than
	// only ever opening (doorcontrol.dm's activate(): openclose = M.density), so
	// pressing an ALREADY-open door's button CLOSES it instead. Confirmed as the actual
	// cause of a real failure: a second singularity generator's storage_door was the
	// exact same "Secure Storage 2" door a PREVIOUS delivery had already propped open -
	// pressing it again right before move_to_storage() shut it in the bot's own path,
	// which then correctly (if confusingly) reported the door closed and failed.
	if(entry_P && entry_B && entry_P.density)
		var/datum/bot_step/move_to/to_entry_button = new()
		to_entry_button.step_target = entry_B
		var/datum/bot_step/press_door_button/press_entry = new()
		press_entry.step_target = entry_B
		steps += list(to_entry_button, press_entry)
	steps += list(new /datum/bot_step/move_to(), new /datum/bot_step/grab_singgen()) //default target = goal.target (the generator)
	if(storage_P && storage_B && storage_P.density)
		var/datum/bot_step/move_to/to_storage_button = new()
		to_storage_button.step_target = storage_B
		var/datum/bot_step/press_door_button/press_storage = new()
		press_storage.step_target = storage_B
		steps += list(to_storage_button, press_storage, new /datum/bot_step/move_to_storage(storage_P))
	else if(storage_P)
		steps += list(new /datum/bot_step/move_to_storage(storage_P)) //already open - no need to press anything, just walk in
	else
		var/datum/bot_step/move_to/to_dest = new()
		to_dest.step_target = T
		steps += list(to_dest)
	steps += list(new /datum/bot_step/release_singgen())

/datum/bot_strategy/remove_singgen/is_feasible(datum/bot_brain/bot)
	if(storage_door)
		return TRUE //move_to_storage computes its own destination once the door's open
	return destination && !QDELETED(destination)

/datum/bot_step/grab_singgen/execute(datum/bot_brain/bot)
	var/obj/machinery/the_singularitygen/G = bot.current_goal?.target
	if(!G || QDELETED(G))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(G))
		return GOAL_STEP_FAIL
	if(bot.owner.pulling == G)
		return GOAL_STEP_SUCCESS
	bot.owner.start_pulling(G)
	// /mob/living/start_pulling() (living.dm) has no explicit "return TRUE" on success -
	// same gotcha fixed in grab_patient (treat_patient.dm); check the real post-call
	// state instead of trusting the return value.
	return (bot.owner.pulling == G) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/release_singgen/execute(datum/bot_brain/bot)
	var/obj/machinery/the_singularitygen/G = bot.current_goal?.target
	if(!G || QDELETED(G))
		return GOAL_STEP_FAIL
	bot.owner.stop_pulling()
	bot_log(bot, "moved [G] out of the engine room, clear of the particle accelerator's beam - left it @ [bot_coord(get_turf(G))]")
	return GOAL_STEP_SUCCESS

// ============================================================
// Same idea as remove_singgen above, but the drop-off is behind a poddoor - press its
// matching remote button first (press_door_button), then compute the actual destination
// turf INSIDE storage only once the door is confirmed open (move_to_storage) rather than
// upfront, since find_turf_outside_area()'s walk-line is itself blocked by the poddoor's
// own density right up until then.
// ============================================================

/datum/bot_step/press_door_button
	var/atom/step_target

/datum/bot_step/press_door_button/execute(datum/bot_brain/bot)
	var/atom/T = step_target || bot.current_goal?.target
	if(!T || QDELETED(T))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(T))
		return GOAL_STEP_FAIL
	bot.use_atom(T)
	bot_log(bot, "pressed [T]")
	return GOAL_STEP_SUCCESS

/datum/bot_step/move_to_storage
	var/obj/machinery/door/poddoor/door

/datum/bot_step/move_to_storage/New(obj/machinery/door/poddoor/P)
	. = ..()
	door = P

/datum/bot_step/move_to_storage/execute(datum/bot_brain/bot)
	if(!door || QDELETED(door))
		return GOAL_STEP_FAIL
	// The button press (previous step) opens the door asynchronously (INVOKE_ASYNC,
	// doorcontrol.dm) - it doesn't block until the open animation actually finishes, so
	// density can still read TRUE for a moment right after pressing. A short wait here
	// (well under the animation itself) avoids reading that transient state as failure.
	sleep(10)
	if(door.density)
		return GOAL_STEP_FAIL
	// NOT find_turf_outside_area() (used by the no-storage fallback) - that walks until
	// the AREA changes, but this map's storage interior shares the exact same area as
	// the corridor right outside its own door (confirmed via the map source: "Secure
	// Storage 2"'s tiles are /area/engine/port_engineering, same as everything around
	// it), so that walk would never find a boundary to stop at and always return null.
	//
	// The door's own tile alone left the generator sitting right at the threshold, not
	// genuinely inside the room - confirmed in-game ("doesn't put it properly into the
	// storage room"). Instead, walk up to 3 tiles past the door in whichever cardinal
	// direction goes FARTHEST from the bot's current position (still on the corridor
	// side, since the door was just opened from there) - that's reliably the direction
	// leading INTO the room rather than back the way the bot came, without needing to
	// know the room's layout or detect any area boundary at all.
	var/turf/door_turf = get_turf(door)
	if(!door_turf)
		return GOAL_STEP_FAIL
	var/turf/dest = door_turf
	var/best_dist = get_dist(bot.owner, door_turf)
	for(var/d in GLOB.cardinals)
		var/turf/T = door_turf
		for(var/i in 1 to 3)
			var/turf/next = get_step(T, d)
			if(!next || next.density || isspaceturf(next) || !istype(next, /turf/open))
				break
			var/blocked = FALSE
			for(var/atom/movable/AM in next)
				if(AM.density)
					blocked = TRUE
					break
			if(blocked)
				break
			T = next
		if(T != door_turf && get_dist(bot.owner, T) > best_dist)
			dest = T
			best_dist = get_dist(bot.owner, T)
	bot.pursue(dest, "goal", force = TRUE)
	return GOAL_STEP_PENDING

// ============================================================
// Close the radiation shutters on the way out, once the PA is live - see
// find_open_engine_shutter()/find_engine_shutter_button() above for the mechanism.
// ============================================================

/datum/bot_goal/close_engine_shutters/resolve_target(datum/bot_brain/bot)
	// The PA must actually be ACTIVE first, not just "no target" for activate_particle_
	// accelerator - try_engineering_round() falls through to the NEXT goal in its list
	// the instant one goal fails to find a target, so without this check, a round where
	// the PA wasn't ready yet (assemble_pa_part/emitters/etc still not fully done) fell
	// straight through into closing the shutters instead, confirmed in-game: the bot
	// sealed the room before ever powering the accelerator on at all.
	var/obj/machinery/particle_accelerator/control_box/CB = bot.find_pa_console()
	if(!CB || !CB.active)
		return
	if(!bot.find_open_engine_shutter())
		return //nothing open left to close - goal correctly finds no target
	target = bot.find_engine_shutter_button()

/datum/bot_goal/close_engine_shutters/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/close_shutters())

/datum/bot_goal/close_engine_shutters/on_success(datum/bot_brain/bot)
	bot.continue_engineering_round()

// Blacklisted on failure like every other engine part goal (bot_goals.dm) - a button
// with no genuine route to it shouldn't be retried every single cycle either.
/datum/bot_goal/close_engine_shutters/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.failed_engine_parts, target, world.time + rand(600, 1200))

/datum/bot_strategy/close_shutters/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/press_door_button())

/datum/bot_strategy/close_shutters/is_feasible(datum/bot_brain/bot)
	return TRUE
