// What's in the way but could be moved out of it (the foundation's environment model; the plan's foundation/movables.dm). Lockers, crates,
// canisters, fuel and water tanks, ore boxes: dense, not fixed down, and light enough for a person to push or pull (PushAM() and
// can_be_pulled(), living.dm and atoms_movable.dm, by move_resist against the mover's move_force and pull_force).

/// The kinds a route through them costs more for (bot_turf_penalty(), the path engine's penalties): the fewer of them on a way through, the
/// better. A climbable one (a crate) costs what it always did: routes over crates are the climbing pass's, and stay as they were.
GLOBAL_LIST_INIT(bot_movable_penalty_types, typecacheof(bot_movable_penalty_kinds()))

/// A proc, not the global: the path engine's penalty table is made from it, and globals are made in the order they're written
/proc/bot_movable_penalty_kinds()
	return list(/obj/structure/closet, /obj/machinery/portable_atmospherics, /obj/structure/reagent_dispensers, /obj/structure/ore_box)

/// Never counted as movable, whatever their anchoring says: they're the station's walls and doors.
GLOBAL_LIST_INIT(bot_never_movable_types, typecacheof(list(/obj/structure/window, /obj/structure/grille, /obj/machinery/door, \
	/obj/machinery/field, /obj/structure/blob, /obj/structure/falsewall, /obj/structure/lattice, /obj/structure/transit_tube)))

/// A structure in the way that `user` could move out of it, by pushing or pulling.
/proc/bot_movable_obstacle(obj/O, mob/living/user)
	if(!isobj(O) || !O.density || O.anchored || !isturf(O.loc) || O.throwing)
		return FALSE
	if(!istype(O, /obj/structure) && !istype(O, /obj/machinery))
		return FALSE
	if(GLOB.bot_never_movable_types[O.type])
		return FALSE
	var/obj/structure/closet/C = O
	if(istype(C) && C.wall_mounted)
		return FALSE
	return bot_can_push(O, user) || bot_can_pull(O, user)

/proc/bot_can_push(obj/O, mob/living/user)
	return !O.anchored && (user ? user.move_force : MOVE_FORCE_DEFAULT) >= O.move_resist * MOVE_FORCE_PUSH_RATIO

/proc/bot_can_pull(obj/O, mob/living/user)
	return O.can_be_pulled(user, GRAB_PASSIVE, user ? user.pull_force : MOVE_FORCE_DEFAULT)

/// What a way through O costs on top of the step (bot_turf_penalty(), the path engine): a dense movable that has to be got out of the way.
/proc/bot_movable_penalty(obj/O)
	if(!O.density || O.anchored)
		return 0
	var/obj/structure/S = O
	if(istype(S) && S.climbable)
		return 0
	return BOT_MOVABLE_PATH_PENALTY

/// Something whose rupture hurts whoever's near it (the tactics library and threat reading go by this too)
/proc/bot_movable_volatile(obj/O)
	if(istype(O, /obj/structure/reagent_dispensers/fueltank))
		return TRUE
	var/obj/machinery/portable_atmospherics/canister/C = O
	if(istype(C))
		var/datum/gas_mixture/air = C.air_contents
		return air && (air.moles[/datum/gas/plasma] > 1 || air.moles[/datum/gas/tritium] > 1)
	return FALSE
