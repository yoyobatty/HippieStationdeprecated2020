// Paradise ports of 2026-11-27, third set, with a real client: pool water (calm with a swimmer, floaters and a sunk toolbox; a
// splash; the wave machine on strong; drained), fishing (the line out to a bobber, the reel window in a fight), and the
// singularity's spiral with no space tiles in it. Not part of the game:
// MAP=testbench HARNESS=port_shots3.dm SENDER=shot.ps1 tools/keybind_check/run.sh ports3
// Pictures in data/previews/port3_*.png, log in data/keycheck.txt.

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
			port_shots3_run(src)

/proc/port_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)

/proc/port_look(client/C, turf/T)
	C.perspective = EYE_PERSPECTIVE
	C.eye = T

/area/bot_gym/port_shots3
	name = "Port Shots Pool"
	dynamic_lighting = DYNAMIC_LIGHTING_ENABLED

/proc/port_shots3_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1

	// A pool room in the middle of a block of wall
	var/datum/turf_reservation/res = SSmapping.RequestBlockReservation(40, 34)
	var/bx = res.bottom_left_coords[1]
	var/by = res.bottom_left_coords[2]
	var/z = res.bottom_left_coords[3]
	var/area/bot_gym/port_shots3/A = new
	var/x0 = bx + 13
	var/y0 = by + 12
	for(var/turf/T in block(locate(bx, by, z), locate(res.top_right_coords[1], res.top_right_coords[2], z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		var/inside = T.x >= x0 && T.x < x0 + 13 && T.y >= y0 && T.y < y0 + 9
		T.ChangeTurf(inside ? /turf/open/floor/plasteel/white : /turf/closed/wall)
	for(var/lamp_x in list(x0 + 2, x0 + 6, x0 + 10))
		var/obj/machinery/light/lamp = new(locate(lamp_x, y0 + 8, z))
		lamp.setDir(NORTH)
		lamp.update(FALSE)
	for(var/turf/T in block(locate(x0 + 3, y0 + 2, z), locate(x0 + 9, y0 + 5, z)))
		T.ChangeTurf(/turf/open/pool)
	sleep(2 SECONDS)
	var/turf/open/pool/middle = locate(x0 + 6, y0 + 3, z)
	kc_log("pool: [middle.type] edge [middle.icon_state], waves [middle.waves ? length(middle.waves.tiles) : 0] tiles")

	var/mob/living/carbon/human/H = new(locate(x0 + 6, y0 + 1, z))
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(3 SECONDS)
	port_look(C, locate(x0 + 6, y0 + 4, z))
	kc_log("water effects on for the client: [H.hud_used?.water_effects_on]")

	var/mob/living/carbon/human/swimmer = new(locate(x0 + 2, y0 + 4, z))
	swimmer.equipOutfit(/datum/outfit/job/assistant)
	swimmer.status_flags |= GODMODE
	swimmer.forceMove(locate(x0 + 5, y0 + 4, z))
	kc_log("swimmer waist deep [!!swimmer.GetComponent(/datum/component/pool_submerged)]")
	for(var/path in list(/obj/item/bikehorn/rubberducky, /obj/item/toy/beach_ball, /obj/item/toy/poolnoodle/red))
		var/obj/item/I = new path(locate(x0 + 2, y0 + 3, z))
		I.forceMove(locate(x0 + rand(4, 8), y0 + rand(2, 5), z))
	var/obj/item/storage/toolbox/mechanical/sunk = new(locate(x0 + 2, y0 + 3, z))
	sunk.forceMove(locate(x0 + 7, y0 + 2, z))
	kc_log("floaters [length(GLOB.pool_things_afloat)], toolbox sunk [!!sunk.GetComponent(/datum/component/pool_sunk)]")
	sleep(3 SECONDS)
	port_shot("port3_pool_1_calm")

	// A splash: something thrown in
	var/obj/item/storage/toolbox/emergency/thrown = new(locate(x0 + 6, y0 + 1, z))
	thrown.throw_at(locate(x0 + 6, y0 + 4, z), 5, 2)
	sleep(4)
	port_shot("port3_pool_2_splash")
	sleep(2 SECONDS)

	// The wave machine on strong
	middle.waves.set_machine(POOL_WAVES_STRONG)
	sleep(4 SECONDS)
	port_shot("port3_pool_3_waves_strong")
	sleep(3)
	port_shot("port3_pool_4_waves_strong_b")

	// Fishing in the pool: the line out to a bobber, then a fight and the reel window
	var/obj/item/fishing_rod/rod = new(H)
	H.put_in_hands(rod)
	middle.waves.set_machine(POOL_WAVES_OFF)
	H.forceMove(locate(x0 + 1, y0 + 6, z))
	H.setDir(EAST)
	rod.use_on(locate(x0 + 5, y0 + 4, z), H)
	sleep(2 SECONDS)
	kc_log("fishing: cast [!!rod.session]")
	port_shot("port3_fish_1_line")
	var/datum/fishing_session/session = rod.session
	session?.bite()
	session.hooked = GLOB.fishing_catches[/datum/fishing_catch/salmon]
	session.length_cm = 80
	session.start_fight()
	sleep(2 SECONDS)
	port_shot("port3_fish_2_fight")
	port_shot("popup_port3_fish_3_reel_window")
	qdel(session)

	// Drained
	for(var/turf/open/pool/T in block(locate(x0 + 3, y0 + 2, z), locate(x0 + 9, y0 + 5, z)))
		T.filled = FALSE
		T.update_icon()
	port_look(C, locate(x0 + 6, y0 + 4, z))
	sleep(2 SECONDS)
	kc_log("drained: swimmer still waist deep [!!swimmer.GetComponent(/datum/component/pool_submerged)]")
	port_shot("port3_pool_5_drained")

	// The singularity's spiral, with the plating round it to tear up and junk thrown in
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
	H.forceMove(locate(sx, sy - 6, sz))
	port_look(C, locate(sx, sy - 1, sz))
	var/obj/singularity/S = new(locate(sx, sy, sz), 1500)
	S.move_self = FALSE
	sleep(10 SECONDS) // two fires of eating space it made already
	var/list/junk_types = list(/obj/item/storage/toolbox/mechanical, /obj/item/extinguisher, /obj/item/wrench, /obj/item/crowbar/red)
	for(var/i in 1 to 16)
		var/turf/T = locate(sx + round(4.5 * cos(i * 22.5)), sy + round(4.5 * sin(i * 22.5)), sz)
		var/junk = pick(junk_types)
		var/obj/item/I = new junk(T)
		I.throw_at(S, 14, 3, spin = TRUE)
	var/spiralling = 0
	var/space_copies = 0
	for(var/i in 1 to 6)
		sleep(2)
		for(var/obj/effect/temp_visual/singularity_swallow/V in range(8, S))
			spiralling++
			if(V.icon == 'icons/turf/space.dmi')
				space_copies++
	kc_log("singularity spiral: [spiralling] sightings, [space_copies] of them space tiles")
	port_shot("port3_singularity")
	qdel(S)

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
