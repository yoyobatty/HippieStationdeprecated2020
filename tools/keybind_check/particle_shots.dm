// Pictures of the particles with a real client: each kind set off beside the viewer and pictured a moment later.
// Not part of the game: HARNESS=particle_shots.dm SENDER=shot.ps1 SHOT_MINUTES=8 tools/keybind_check/run.sh particles
// It uses the real station (the supermatter, a hallway, maintenance). Pictures in data/previews/particle_*.png, notes in
// data/keycheck_particles.txt. The last pictures are sparks again on Low graphics: the plane is hidden, the old sprite is all there is.

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
			particle_shots_run(src)

/proc/particle_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// A clear floor near the middle of the first station area of a type, with clear floor east of it.
/proc/particle_spot(area_type)
	for(var/area/A in GLOB.sortedAreas)
		if(!istype(A, area_type))
			continue
		for(var/turf/open/floor/T in A)
			if(!is_station_level(T.z))
				continue
			if((locate(/obj/structure) in T) || (locate(/obj/machinery) in T))
				continue
			var/clear = TRUE
			for(var/turf/near in range(4, T)) //open floor four tiles each way along the row, and two up and down
				if((near.y == T.y || (near.x == T.x && abs(near.y - T.y) <= 2)) && (near.density || !istype(near, /turf/open/floor)))
					clear = FALSE
					break
			if(clear)
				return T

/proc/particle_count(turf/T)
	var/bursts = 0
	var/held = 0
	for(var/obj/effect/particle_fx/burst/B in range(7, T))
		bursts++
	for(var/turf/near in range(7, T))
		for(var/obj/effect/particle_fx/F in near.vis_contents)
			held++
		for(var/atom/movable/thing in near)
			for(var/obj/effect/particle_fx/F in thing.vis_contents)
				held++
	return "[bursts] bursts, [held] shared emitters held"

/proc/particle_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1

	var/turf/spot = particle_spot(/area/hallway/primary/central) || particle_spot(/area/hallway)
	if(!spot)
		kc_log("no open stretch of hallway found")
		kc_log("done")
		winset(C, null, "command=.quit")
		sleep(5)
		del(world)
		return
	var/mob/living/carbon/human/H = new(spot)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(2 SECONDS)
	H.hud_used.show_hud(HUD_STYLE_NOHUD)
	C.prefs.set_graphics_quality(GRAPHICS_QUALITY_HIGH)
	H.hud_used.plane_masters_update()
	var/obj/screen/plane_master/particles/PM = H.hud_used.plane_masters["[PARTICLE_PLANE]"]
	kc_log("hwmode [winget(C, null, "hwmode")], spot ([spot.x],[spot.y]) in [get_area(spot)], particle plane alpha [PM?.alpha] on High")
	var/turf/east = locate(spot.x + 2, spot.y, spot.z)
	var/turf/west = locate(spot.x - 2, spot.y, spot.z)
	var/turf/north = locate(spot.x, spot.y + 2, spot.z)

	particle_shot("particle_0_nothing")

	// Sparks
	do_sparks(4, FALSE, east)
	sleep(4)
	kc_log("sparks: [particle_count(spot)]")
	particle_shot("particle_1_sparks")
	sleep(25)

	// A bullet's hit and a laser's
	for(var/i in 1 to 3)
		new /obj/effect/temp_visual/impact_effect(west, rand(-8, 8), rand(-8, 8))
		new /obj/effect/temp_visual/impact_effect/red_laser(north, rand(-8, 8), rand(-8, 8))
	sleep(2)
	kc_log("impacts: [particle_count(spot)]")
	particle_shot("particle_2_impacts")
	sleep(10)

	// Blood
	H.add_splatter_floor(east, FALSE)
	sleep(2)
	kc_log("blood: [particle_count(spot)]")
	particle_shot("particle_3_blood")
	sleep(10)

	// Breath in the cold
	var/datum/gas_mixture/cold = new
	cold.copy_from(spot.return_air())
	cold.temperature = 250
	H.check_breath(cold)
	sleep(6)
	kc_log("cold breath: [length(H.vis_contents)] in the human's vis_contents")
	particle_shot("particle_4_breath")
	sleep(15)
	kc_log("after it: [length(H.vis_contents)] in the human's vis_contents")

	// Wind to a breach: a row of tiles with a strong wind east
	var/list/windy = list()
	for(var/dx in -3 to 3)
		var/turf/open/T = locate(spot.x + dx, spot.y - 1, spot.z)
		if(istype(T))
			windy += T
	for(var/pass in 1 to 6)
		for(var/turf/open/T as anything in windy)
			T.pressure_difference = 80
			T.pressure_direction = EAST
			T.high_pressure_movements()
		if(pass == 4)
			kc_log("wind: [length(GLOB.gusting_turfs)] tiles showing a gust; [particle_count(spot)]")
			particle_shot("particle_5_gust")
		sleep(3)
	sleep(35)
	kc_log("wind over: [length(GLOB.gusting_turfs)] tiles still showing a gust")

	// A vent filling a room
	var/obj/machinery/atmospherics/components/unary/vent_pump/vent
	for(var/obj/machinery/atmospherics/components/unary/vent_pump/V in range(10, spot))
		vent = V
		break
	if(vent)
		H.forceMove(get_step(vent, SOUTH) || get_turf(vent))
		sleep(8)
		vent.puff()
		sleep(8)
		kc_log("vent at ([vent.x],[vent.y]): [length(vent.vis_contents)] in vis_contents")
		particle_shot("particle_6_vent")
		sleep(25)
		kc_log("vent after: [length(vent.vis_contents)] in vis_contents")
		H.forceMove(spot)
		sleep(8)

	// Sparks on Low graphics: the sprite, no particles
	C.prefs.set_graphics_quality(GRAPHICS_QUALITY_LOW)
	H.hud_used.plane_masters_update()
	do_sparks(4, FALSE, east)
	sleep(4)
	kc_log("on Low: particle plane alpha [PM?.alpha]")
	particle_shot("particle_9_sparks_low")
	C.prefs.set_graphics_quality(GRAPHICS_QUALITY_HIGH)
	H.hud_used.plane_masters_update()
	sleep(20)

	// The supermatter's motes
	var/obj/machinery/power/supermatter_crystal/crystal = locate() in GLOB.machines
	if(crystal)
		H.forceMove(locate(crystal.x, crystal.y - 2, crystal.z))
		sleep(40)
		kc_log("supermatter: [length(crystal.vis_contents)] in vis_contents")
		particle_shot("particle_a_supermatter")

	// A tesla ball's crackle
	var/turf/tesla_at = locate(spot.x + 3, spot.y, spot.z)
	H.forceMove(spot)
	sleep(8)
	var/obj/singularity/energy_ball/ball = new(tesla_at, 50, TRUE)
	sleep(6)
	kc_log("tesla: [length(ball.vis_contents)] in vis_contents")
	particle_shot("particle_b_tesla")
	qdel(ball)

	// Embers over a plasma fire
	var/turf/open/fire_at = particle_spot(/area/maintenance)
	if(fire_at)
		H.forceMove(fire_at)
		sleep(10)
		for(var/turf/open/T in range(1, fire_at))
			T.atmos_spawn_air("plasma=60;o2=120;TEMP=900")
		sleep(30)
		var/fires = 0
		var/embers = 0
		for(var/obj/effect/hotspot/hot in range(7, fire_at))
			fires++
			if(particle_fx("ember") in hot.vis_contents)
				embers++
		kc_log("fire: [fires] hotspots in view, [embers] giving off embers")
		particle_shot("particle_c_embers")

	// A blast, small then big: last, since they set the hallway alight
	H.forceMove(spot)
	sleep(10)
	explosion(locate(spot.x + 3, spot.y, spot.z), 0, 0, 2, adminlog = FALSE)
	sleep(2)
	kc_log("small blast: [particle_count(spot)]")
	particle_shot("particle_7_blast_small")
	sleep(20)
	explosion(locate(spot.x - 4, spot.y, spot.z), 0, 2, 5, adminlog = FALSE)
	sleep(2)
	kc_log("big blast: [particle_count(spot)]")
	particle_shot("particle_8_blast_big")
	sleep(25)

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
