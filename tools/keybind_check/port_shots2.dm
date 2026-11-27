// Paradise ports of 2026-11-27, second set, with a real client: pAIs running machines (the face over each, the face on its
// screen or a lit lens, each pAI in its own mood), checks that each machine answers its pAI, pulling one out and an EMP; then a
// stage four singularity with things thrown at it, shot quickly, for the spiral they make going in.
// Not part of the game: MAP=testbench HARNESS=port_shots2.dm SENDER=shot.ps1 tools/keybind_check/run.sh ports2
// Pictures in data/previews/port2_*.png, log in data/keycheck.txt.

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
			port_shots2_run(src)

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

/area/bot_gym/port_shots2
	name = "Port Shots Room"
	dynamic_lighting = DYNAMIC_LIGHTING_ENABLED

/proc/port2_room(x, y, z, w, h, area/A)
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
				T.ChangeTurf(/turf/open/floor/plasteel/dark)
	for(var/lamp_x in list(x + 2, x + w - 3))
		var/obj/machinery/light/small/lamp = new(locate(lamp_x, y + h - 1, z))
		lamp.setDir(NORTH)
		lamp.update(FALSE)

/proc/port2_pai(turf/T, emotion, pai_name)
	var/obj/item/paicard/card = new(T)
	var/mob/living/silicon/pai/pai = new(card)
	pai.name = pai_name
	pai.real_name = pai_name
	card.setPersonality(pai)
	card.setEmotion(emotion)
	return card

/proc/port_shots2_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1

	// The room sits in the middle of a block of wall, at least 12 tiles from its edges, so the view never runs off the map
	var/datum/turf_reservation/rooms = SSmapping.RequestBlockReservation(52, 31)
	var/x0 = rooms.bottom_left_coords[1] + 13
	var/y0 = rooms.bottom_left_coords[2] + 13
	var/z = rooms.bottom_left_coords[3]
	var/area/bot_gym/port_shots2/A = new
	port_fill_walls(rooms.bottom_left_coords[1], rooms.bottom_left_coords[2], rooms.top_right_coords[1], rooms.top_right_coords[2], z, A)
	port2_room(x0, y0, z, 24, 5, A)

	var/mob/living/carbon/human/H = new(locate(x0 + 6, y0, z))
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/scientist)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(3 SECONDS)
	port_fit_map(C)

	var/list/machine_types = list(/obj/machinery/computer/arcade/battle, /obj/machinery/biogenerator, /obj/machinery/microwave, /obj/machinery/smartfridge, /obj/machinery/autolathe, /obj/machinery/rnd/production/protolathe, /obj/machinery/vending/cola, /obj/machinery/jukebox)
	var/list/machines = list()
	var/list/cards = list()
	for(var/i in 1 to length(machine_types))
		var/path = machine_types[i]
		var/obj/machinery/M = new path(locate(x0 + 1 + (i - 1) * 3, y0 + 3, z))
		machines += M
		var/obj/item/paicard/card = port2_pai(locate(x0 + 1 + (i - 1) * 3, y0 + 2, z), 1 + ((i * 2) % 9), "pAI [i]")
		cards += card
		H.forceMove(locate(x0 + 1 + (i - 1) * 3, y0 + 2, z))
		H.put_in_active_hand(card)
		card.load_into_machine(H, M) // two seconds' slotting in
		var/datum/component/pai_host/host = M.GetComponent(/datum/component/pai_host)
		var/mob/living/silicon/pai/pai = card.pai
		kc_log("[M.name]: hosted [!!host], card in port [istype(card.loc, /obj/effect/abstract/pai_port)], screen [host?.get_screen() ? "yes" : "none"], ui status for its pAI [M.ui_status(pai, GLOB.default_state)], pAI looks out from [pai.client ? "-" : "(no client) "][pai.get_host_machine() == M]")
	sleep(2 SECONDS)
	H.forceMove(locate(x0 + 6, y0, z))
	port_look(C, locate(x0 + 6, y0 + 2, z))
	sleep(2 SECONDS)
	port_shot("port2_pai_1_left")
	port_look(C, locate(x0 + 18, y0 + 2, z))
	sleep(2 SECONDS)
	port_shot("port2_pai_2_right")

	// A mood change shows on the face and the screen
	var/obj/item/paicard/arcade_card = cards[1]
	arcade_card.setEmotion(8)
	var/obj/machinery/arcade = machines[1]
	var/datum/component/pai_host/arcade_host = arcade.GetComponent(/datum/component/pai_host)
	kc_log("arcade pAI angry: hologram [arcade_host?.hologram?.icon_state], screen overlays [length(arcade_host?.screen_face?.overlays)]")
	port_look(C, locate(x0 + 6, y0 + 2, z))
	sleep(1 SECONDS)
	port_shot("port2_pai_3_angry")

	// Pulling one out, an EMP throwing one out, and power going
	var/obj/machinery/microwave/microwave = machines[3]
	H.forceMove(locate(microwave.x, microwave.y - 1, z))
	var/datum/component/pai_host/microwave_host = microwave.GetComponent(/datum/component/pai_host)
	microwave_host.try_pull_out(H)
	var/obj/item/paicard/microwave_card = cards[3]
	kc_log("pulled out: host gone [!microwave.GetComponent(/datum/component/pai_host)], card on the floor [isturf(microwave_card.loc)], name back [microwave.name]")
	var/obj/machinery/vending/vendor = machines[7]
	vendor.emp_act(EMP_LIGHT)
	var/obj/item/paicard/vendor_card = cards[7]
	kc_log("EMP: host gone [!vendor.GetComponent(/datum/component/pai_host)], card out [isturf(vendor_card.loc)], vendor talks again [!vendor.shut_up]")

	// Singularity: things thrown into a stage four
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
	sleep(8 SECONDS)
	kc_log("singularity size [S.current_size]")
	var/list/junk_types = list(/obj/item/storage/toolbox/mechanical, /obj/item/storage/toolbox/emergency, /obj/item/extinguisher, /obj/item/tank/internals/oxygen, /obj/item/wrench, /obj/item/crowbar/red)
	for(var/shot in 1 to 3)
		for(var/i in 1 to 16)
			var/angle = i * 22.5
			var/turf/T = locate(sx + round(4.5 * cos(angle)), sy + round(4.5 * sin(angle)), sz)
			var/junk = pick(junk_types)
			var/obj/item/I = new junk(T)
			I.throw_at(S, 14, 3, spin = TRUE)
		var/swallows = 0
		for(var/delay in 1 to 4)
			sleep(2)
			swallows = 0
			for(var/obj/effect/temp_visual/singularity_swallow/V in range(8, S))
				swallows++
			if(swallows >= 3)
				break
		kc_log("spiral round [shot]: [swallows] things spiralling in")
		port_shot("port2_singularity_[shot]")
		sleep(1 SECONDS)
	qdel(S)

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
