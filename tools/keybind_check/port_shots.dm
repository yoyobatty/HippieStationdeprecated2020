// The Paradise ports of 2026-11-27 with a real client, in one boot: fires (tg's sprite in one room, the merged flames in a twin
// room lit at the same moment), lava's heat haze off and on, a stage four singularity eating a pile of junk (things spiral in),
// and someone standing on a crate trolley's crates. Logs the fires' sizes and the wind under them, to set the flames' lean.
// Not part of the game: MAP=testbench HARNESS=port_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh ports
// Pictures in data/previews/port_*.png, log in data/keycheck.txt.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			port_shots_run(src)

/// The game window as a player has it: the map fitted to its pane. Zoom is a saved skin setting, and another harness can
/// leave it at a fixed size, which drew the map at 1x in a corner of the pane. Logs what it was and is.
/proc/port_fit_map(client/C)
	var/was = winget(C, "mapwindow.map", "zoom")
	winset(C, "mapwindow.map", "zoom=0")
	sleep(5)
	kc_log("map zoom [was] -> [winget(C, "mapwindow.map", "zoom")], map [winget(C, "mapwindow.map", "size")], view [C.view]")

/// Fills a block with wall, so a scene built in it sits in a station-like mass, never at the edge of the map
/proc/port_fill_walls(x1, y1, x2, y2, z, area/A)
	for(var/turf/T in block(locate(x1, y1, z), locate(x2, y2, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/closed/wall)

/// Points the camera at a turf, the way a player standing there would see it, wherever the mob is
/proc/port_look(client/C, turf/T)
	C.perspective = EYE_PERSPECTIVE
	C.eye = T

/proc/port_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/area/bot_gym/port_shots
	name = "Port Shots Room"
	dynamic_lighting = DYNAMIC_LIGHTING_ENABLED

/// A walled room of w x h floor tiles, its bottom left floor tile at (x, y, z), two small lamps on its north wall
/proc/port_room(x, y, z, w, h, area/A)
	for(var/dx in -1 to w)
		for(var/dy in -1 to h)
			var/turf/T = locate(x + dx, y + dy, z)
			var/area/old_area = T.loc
			old_area.contents -= T
			A.contents += T
			T.change_area(old_area, A)
			if(dx == -1 || dy == -1 || dx == w || dy == h)
				T.ChangeTurf(/turf/closed/wall)
			else
				T.ChangeTurf(/turf/open/floor/plasteel)
	for(var/lamp_x in list(x + 1, x + w - 2))
		var/obj/machinery/light/small/lamp = new(locate(lamp_x, y + h - 1, z))
		lamp.setDir(NORTH)
		lamp.update(FALSE)

/proc/port_ignite(turf/middle)
	for(var/turf/open/T in range(1, middle))
		T.atmos_spawn_air("plasma=40;TEMP=293")
	middle.hotspot_expose(1500, CELL_VOLUME)

/// Fire sizes and the wind under the fires, for the flames' lean
/proc/port_fire_stats(label)
	var/list/sizes = list(0, 0, 0)
	var/list/pushes = list()
	var/hot = 0
	for(var/obj/effect/hotspot/H as anything in SSair.hotspots)
		if(!H.flames_merged)
			continue
		sizes[H.flame_size]++
		if(H.flame_hot)
			hot++
		var/turf/open/T = H.loc
		pushes += istype(T) ? T.pressure_difference : 0
	sortTim(pushes, GLOBAL_PROC_REF(cmp_numeric_asc))
	var/n = length(pushes)
	var/pct = n ? "p50 [pushes[max(1, round(n * 0.5))]], p90 [pushes[max(1, round(n * 0.9))]], max [pushes[n]]" : "none"
	kc_log("[label]: merged fires small/middling/big [sizes[1]]/[sizes[2]]/[sizes[3]], hot [hot], wind kPa [pct], all hotspots [length(SSair.hotspots)]")

/proc/port_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1

	// The rooms sit in the middle of a block of wall, at least 12 tiles from its edges, so the view never runs off the map
	var/datum/turf_reservation/rooms = SSmapping.RequestBlockReservation(64, 34)
	var/x0 = rooms.bottom_left_coords[1] + 13
	var/y0 = rooms.bottom_left_coords[2] + 13
	var/z = rooms.bottom_left_coords[3]
	var/area/bot_gym/port_shots/A = new
	port_fill_walls(rooms.bottom_left_coords[1], rooms.bottom_left_coords[2], rooms.top_right_coords[1], rooms.top_right_coords[2], z, A)
	port_room(x0, y0, z, 9, 7, A) // A: tg's fire
	port_room(x0 + 12, y0, z, 9, 7, A) // B: merged flames
	port_room(x0 + 24, y0, z, 13, 7, A) // C: lava and the trolley
	var/datum/turf_reservation/open = SSmapping.RequestBlockReservation(50, 50)
	var/area/bot_gym/arena = new
	var/sx = open.bottom_left_coords[1] + 25
	var/sy = open.bottom_left_coords[2] + 25
	var/sz = open.bottom_left_coords[3]
	for(var/turf/T in block(locate(sx - 22, sy - 22, sz), locate(sx + 22, sy + 22, sz)))
		var/area/old_area = T.loc
		old_area.contents -= T
		arena.contents += T
		T.change_area(old_area, arena)
		T.ChangeTurf(/turf/open/floor/plating)

	var/mob/living/carbon/human/H = new(locate(x0 + 4, y0, z))
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/atmos)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(3 SECONDS)
	port_fit_map(C)
	kc_log("hwmode [winget(C, null, "hwmode")], graphics [C.prefs.graphics_quality()]")

	// Fires: room A the old way, room B merged, lit together
	var/turf/fire_a = locate(x0 + 4, y0 + 4, z)
	var/turf/fire_b = locate(x0 + 16, y0 + 4, z)
	for(var/turf/T in block(locate(x0 - 1, y0 - 1, z), locate(x0 + 9, y0 + 7, z)))
		GLOB.merged_flames_off_turfs[T] = TRUE
	port_ignite(fire_a)
	port_ignite(fire_b)
	for(var/round in 1 to 3)
		sleep(round == 1 ? 4 SECONDS : 5 SECONDS)
		port_fire_stats("fire after [round * 5] s")
		GLOB.heat_haze_allowed = FALSE
		port_look(C, locate(x0 + 4, y0 + 3, z))
		sleep(1.5 SECONDS)
		port_shot("port_fire_[round]_1_before")
		GLOB.heat_haze_allowed = TRUE
		port_look(C, locate(x0 + 16, y0 + 3, z))
		sleep(3 SECONDS)
		port_shot("port_fire_[round]_2_after")
	for(var/i in 1 to 8)
		sleep(1 SECONDS)
		port_fire_stats("fire later [i]")

	// Lava and the trolley: room C
	var/cx = x0 + 24
	for(var/turf/T in block(locate(cx + 6, y0 + 3, z), locate(cx + 11, y0 + 6, z)))
		T.ChangeTurf(/turf/open/lava/smooth)
	var/obj/structure/crate_trolley/trolley = new(locate(cx + 2, y0 + 3, z))
	for(var/i in 1 to 3)
		var/obj/structure/closet/crate/crate = new
		trolley.crates += crate
		crate.forceMove(trolley)
	trolley.load_changed()
	var/mob/living/carbon/human/rider = new(locate(cx + 1, y0 + 3, z))
	rider.equipOutfit(/datum/outfit/job/cargo_tech)
	rider.status_flags |= GODMODE
	trolley.start_climb(rider)
	kc_log("trolley rider buckled [rider.buckled == trolley], pixel_y [rider.pixel_y], crates [length(trolley.crates)]")
	port_look(C, locate(cx + 6, y0 + 3, z))
	GLOB.heat_haze_allowed = FALSE
	sleep(3 SECONDS)
	port_shot("port_lava_1_before")
	GLOB.heat_haze_allowed = TRUE
	sleep(4 SECONDS)
	kc_log("heat haze on for the client: [H.hud_used?.heat_haze_on]")
	port_shot("port_lava_2_after")
	sleep(3)
	port_shot("port_lava_3_after")

	// Singularity: stage four, held still, eating a pile of junk
	var/list/junk_types = list(/obj/item/wrench, /obj/item/crowbar, /obj/item/stack/rods/ten, /obj/item/stack/sheet/metal/five, /obj/item/screwdriver, /obj/item/storage/toolbox/mechanical, /obj/item/extinguisher, /obj/item/tank/internals/oxygen)
	for(var/i in 1 to 80)
		var/turf/T = locate(sx + rand(-9, 9), sy + rand(-9, 9), sz)
		var/junk = pick(junk_types)
		new junk(T)
	H.forceMove(locate(sx, sy - 6, sz))
	port_look(C, locate(sx, sy - 1, sz))
	sleep(2 SECONDS)
	var/obj/singularity/S = new(locate(sx, sy, sz), 1500)
	S.move_self = FALSE
	sleep(6 SECONDS)
	kc_log("singularity stage [S.current_size], energy [S.energy], dissipate every [S.dissipate_delay + 1] fires by [S.dissipate_strength]")
	for(var/i in 1 to 4)
		port_shot("port_singularity_[i]")
		sleep(2)
	qdel(S)

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
