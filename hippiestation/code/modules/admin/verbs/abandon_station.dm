// Admin verb that dresses the station up as if it was abandoned after something went horribly wrong:
// dirt, dried blood, litter, remains, graffiti, cobwebs and wrecked floors, and optionally broken
// lights/APCs/doors/consoles/windows. Mobs are never touched.
//
// Anything that could vent or overheat the station (windows, airlocks) is only broken when every open
// turf around it holds ordinary room air, so exterior windows, airlocks to space and engine/toxins
// chambers are left alone.

#define ABANDON_GRAFFITI_WORDS list("run", "help", "get out", "why", "no hope", "dont look", "its inside", "they came", "sorry", "hide", "gone", "rip")

/client/proc/cmd_admin_abandon_station()
	set category = "Special Verbs"
	set name = "Abandon Station"
	set desc = "Makes the station look abandoned and wrecked: dirt, dried blood, litter, remains, graffiti, and optionally broken lights, APCs, doors, consoles and interior windows."

	if(!check_rights(R_FUN))
		return

	var/choice = input(src, "How bad should it look?", "Abandon Station") as null|anything in list("Light", "Moderate", "Heavy")
	if(!choice)
		return
	var/intensity = (choice == "Light") ? 1 : (choice == "Moderate") ? 2 : 3
	var/sabotage = alert(src, "Also wreck infrastructure? (break lights, APCs, consoles, vendors, interior windows; force open/bolt, weld or break some airlocks)", "Abandon Station", "Yes", "No", "Cancel")
	if(!sabotage || sabotage == "Cancel")
		return
	if(alert(src, "This will trash the whole station ([choice][sabotage == "Yes" ? ", with infrastructure damage" : ""]). It can't be undone. Continue?", "Abandon Station", "Yes", "No") != "Yes")
		return

	var/wreck = (sabotage == "Yes")
	message_admins("[key_name_admin(usr)] is making the station look abandoned ([choice][wreck ? ", infrastructure wrecked" : ""]).")
	log_admin("[key_name(usr)] used Abandon Station ([choice][wreck ? ", infrastructure wrecked" : ""]).")
	SSblackbox.record_feedback("tally", "admin_verb", 1, "Abandon Station") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(abandon_station), intensity, wreck, usr)

/proc/abandon_station(intensity = 2, wreck = FALSE, mob/admin)
	var/start = REALTIMEOFDAY
	var/list/stats = list("turfs" = 0, "decals" = 0, "scenes" = 0, "graffiti" = 0, "lights" = 0, "apcs" = 0, "doors" = 0, "machines" = 0, "windows" = 0)

	for(var/area_type in GLOB.the_station_areas)
		var/area/A = GLOB.areas_by_type[area_type]
		if(!A)
			continue
		var/is_maint = istype(A, /area/maintenance)
		for(var/turf/open/floor/T in A)
			stats["turfs"]++
			abandon_wreck_contents(T, intensity, wreck, stats)
			abandon_decorate_turf(T, intensity, is_maint, stats)
			CHECK_TICK

	var/elapsed = round((REALTIMEOFDAY - start) / 10, 0.1)
	var/summary = "Abandon Station finished in [elapsed]s: [stats["turfs"]] floors, [stats["decals"]] decals, [stats["scenes"]] remains, [stats["graffiti"]] graffiti"
	if(wreck)
		summary += ", [stats["lights"]] lights, [stats["apcs"]] APCs, [stats["doors"]] airlocks, [stats["machines"]] machines, [stats["windows"]] windows"
	message_admins("[summary].")
	log_admin("[admin ? key_name(admin) : "Unknown"]'s [summary].")

// Scatters stuff on tables, knocks chairs about and (if wrecking) breaks the machinery/windows on this turf.
/proc/abandon_wreck_contents(turf/open/floor/T, intensity, wreck, list/stats)
	var/has_table = locate(/obj/structure/table) in T
	for(var/atom/movable/AM in T)
		if(QDELETED(AM))
			continue
		if(isitem(AM))
			var/obj/item/I = AM
			if(has_table && !I.anchored && prob(25 * intensity))
				var/turf/open/dest = get_step(T, pick(GLOB.alldirs))
				if(istype(dest) && !is_blocked_turf(dest, TRUE))
					I.forceMove(dest)
			continue
		if(istype(AM, /obj/structure/chair))
			if(prob(30 * intensity))
				AM.setDir(pick(GLOB.cardinals))
			continue
		if(!wreck)
			continue
		if(istype(AM, /obj/machinery/light))
			var/obj/machinery/light/L = AM
			if(prob(30 * intensity))
				L.break_light_tube(TRUE)
				stats["lights"]++
		else if(istype(AM, /obj/structure/window))
			var/obj/structure/window/W = AM
			if(prob(5 * intensity) && !(W.flags_1 & NODECONSTRUCT_1) && abandon_air_is_safe(T))
				W.spawnDebris(T)
				qdel(W)
				stats["windows"]++
		else if(istype(AM, /obj/machinery/door/airlock))
			abandon_wreck_airlock(AM, intensity, stats)
		else if(istype(AM, /obj/machinery/power/apc))
			var/obj/machinery/power/apc/C = AM
			if(prob(6 * intensity))
				C.set_broken()
				stats["apcs"]++
			else if(C.cell && prob(25 * intensity)) // drained, so the lights die off over the round
				C.cell.charge = C.cell.maxcharge * rand(0, 40) / 100
				stats["apcs"]++
		else if(istype(AM, /obj/machinery/computer) || istype(AM, /obj/machinery/vending))
			var/obj/machinery/M = AM
			if(prob(8 * intensity) && !(M.stat & BROKEN))
				M.obj_break()
				M.update_icon()
				stats["machines"]++

/proc/abandon_wreck_airlock(obj/machinery/door/airlock/D, intensity, list/stats)
	if(D.locked || D.welded || (D.stat & BROKEN))
		return
	if(!abandon_air_is_safe(get_turf(D)))
		return
	var/roll = rand(1, 100)
	if(roll <= 5 * intensity)
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(abandon_force_airlock), D)
	else if(roll <= 8 * intensity)
		if(!D.density)
			return
		D.welded = TRUE
		D.update_icon()
	else if(roll <= 11 * intensity)
		D.obj_break()
		D.update_icon()
	else
		return
	stats["doors"]++

// Pried open and left bolted that way, the way people escaping would leave it.
/proc/abandon_force_airlock(obj/machinery/door/airlock/D)
	if(QDELETED(D))
		return
	D.autoclose = FALSE
	if(D.density && !D.open(2))
		return
	if(QDELETED(D))
		return
	D.locked = TRUE
	D.update_icon()

// TRUE when every open turf around T holds ordinary room air, i.e. opening it up won't vent or cook anything.
/proc/abandon_air_is_safe(turf/T)
	for(var/turf/N in range(1, T))
		if(isclosedturf(N))
			continue
		if(isspaceturf(N))
			return FALSE
		var/datum/gas_mixture/G = N.return_air()
		if(!G)
			return FALSE
		var/pressure = G.return_pressure()
		if(pressure < 80 || pressure > 130 || G.return_temperature() < 250 || G.return_temperature() > 340)
			return FALSE
	return TRUE

/proc/abandon_decorate_turf(turf/open/floor/T, intensity, is_maint, list/stats)
	if(QDELETED(T) || is_blocked_turf(T, TRUE))
		return

	// grime
	if(prob((is_maint ? 30 : 12) * intensity))
		new /obj/effect/decal/cleanable/dirt(T)
		stats["decals"]++

	// cobwebs gather in the top corners of rooms
	if(prob((is_maint ? 25 : 10) * intensity) && isclosedturf(get_step(T, NORTH)))
		if(isclosedturf(get_step(T, WEST)))
			new /obj/effect/decal/cleanable/cobweb(T)
			stats["decals"]++
		else if(isclosedturf(get_step(T, EAST)))
			new /obj/effect/decal/cleanable/cobweb/cobweb2(T)
			stats["decals"]++

	// torn up and scorched floors
	if(prob(2 * intensity))
		T.break_tile()
	else if(prob(1 * intensity))
		T.burn_tile()
		new /obj/effect/decal/cleanable/ash(T)
		stats["decals"]++
	else if(prob(0.3 * intensity))
		T.break_tile_to_plating()
		T = get_turf(T) // ChangeTurf replaced the turf datum in place
		if(!istype(T))
			return

	// dried blood
	if(prob(1.5 * intensity))
		new /obj/effect/decal/cleanable/blood/old(T)
		stats["decals"]++
	if(prob(0.3 * intensity))
		abandon_blood_trail(T, rand(3, 10))
		stats["decals"]++

	// litter
	if(prob(2 * intensity))
		var/litter = pick(
			/obj/item/trash/chips, /obj/item/trash/candy, /obj/item/trash/can, /obj/item/trash/sosjerky,
			/obj/item/trash/raisins, /obj/item/trash/popcorn, /obj/item/trash/plate, /obj/item/trash/tray,
			/obj/item/cigbutt, /obj/item/paper/crumpled, /obj/item/shard,
			/obj/effect/decal/cleanable/glass, /obj/effect/decal/cleanable/oil, /obj/effect/decal/cleanable/vomit/old,
			/obj/effect/decal/cleanable/shreds, /obj/effect/decal/cleanable/generic, /obj/effect/decal/cleanable/robot_debris)
		new litter(T)
		stats["decals"]++

	// what's left of someone
	if(prob(0.08 * intensity))
		abandon_remains_scene(T)
		stats["scenes"]++

	// last messages
	if(prob(0.12 * intensity))
		if(abandon_write_graffiti(T, pick(ABANDON_GRAFFITI_WORDS)))
			stats["graffiti"]++
		else
			new /obj/effect/decal/cleanable/crayon(T, pick("#8B0000", "#FF0000", "#FFFFFF", "#333333"), pick("skull", "danger", "biohazard", "nay", "rune1", "rune3", "rune5", "evac"))
			stats["graffiti"]++

/proc/abandon_blood_trail(turf/start, length)
	var/dir = pick(GLOB.cardinals)
	var/turf/T = start
	for(var/i in 1 to length)
		if(!isfloorturf(T) || is_blocked_turf(T, TRUE))
			return
		new /obj/effect/decal/cleanable/blood/drip(T)
		if(prob(25)) // stagger a bit
			dir = turn(dir, pick(90, -90))
		T = get_step(T, dir)

/proc/abandon_remains_scene(turf/T)
	if(prob(75))
		new /obj/effect/decal/remains/human(T)
		new /obj/effect/decal/cleanable/blood/old(T)
		if(prob(40))
			new /obj/effect/decal/cleanable/blood/gibs/old(T) // rots, so keep these rare
		if(prob(50))
			new /obj/effect/decal/cleanable/shreds(T)
	else
		new /obj/effect/decal/remains/robot(T)
		new /obj/effect/decal/cleanable/oil(T)
		new /obj/effect/decal/cleanable/robot_debris(T)
	for(var/turf/open/floor/N in orange(1, T))
		if(prob(40) && !is_blocked_turf(N, TRUE))
			new /obj/effect/decal/cleanable/blood/old(N)

// Writes text one letter per tile heading east, in blood-red crayon. Returns FALSE if it doesn't fit.
/proc/abandon_write_graffiti(turf/T, text)
	var/list/turf/tiles = list()
	var/turf/cur = T
	for(var/i in 1 to length(text))
		if(!isfloorturf(cur) || is_blocked_turf(cur, TRUE) || cur.loc != T.loc)
			return FALSE
		tiles += cur
		cur = get_step(cur, EAST)
	var/colour = pick("#8B0000", "#A00000", "#FFFFFF")
	for(var/i in 1 to length(text))
		var/letter = copytext(text, i, i + 1)
		if(letter == " ")
			continue
		new /obj/effect/decal/cleanable/crayon(tiles[i], colour, letter, "graffiti")
	return TRUE

#undef ABANDON_GRAFFITI_WORDS
