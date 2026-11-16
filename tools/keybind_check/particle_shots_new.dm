// Pictures and checks of the particles in particle_smoke.dm, particle_tools.dm, particle_mobs.dm and particle_destruction.dm,
// with a real client. particle_shots.dm does the ones in particle_fx.dm.
// Not part of the game: HARNESS=particle_shots_new.dm SENDER=shot.ps1 SHOT_MINUTES=8 tools/keybind_check/run.sh particles_new
// It uses the real station (a hallway, maintenance, the emergency shuttle). Pictures in data/previews/particle_n*.png, notes in
// data/keycheck_particles_new.txt: each line says what was held or made, and a line starting WRONG is a failure.

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
			particle_new_run(src)

/proc/particle_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// A clear floor near the middle of the first station area of a type, with clear floor four tiles each way along its row
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
			for(var/turf/near in range(4, T))
				if((near.y == T.y || (near.x == T.x && abs(near.y - T.y) <= 2)) && (near.density || !istype(near, /turf/open/floor) || (locate(/obj/structure) in near) || (locate(/obj/machinery/door) in near)))
					clear = FALSE
					break
			if(clear)
				return T

/// A floor in the first station area of a type with nothing on it and three clear floors in a row each side: room to run
/proc/particle_run_spot(area_type)
	for(var/area/A in GLOB.sortedAreas)
		if(!istype(A, area_type))
			continue
		for(var/turf/open/floor/T in A)
			if(!is_station_level(T.z))
				continue
			var/clear = TRUE
			for(var/dx in -3 to 3)
				var/turf/open/floor/near = locate(T.x + dx, T.y, T.z)
				if(!istype(near) || near.loc != A || (locate(/obj/structure) in near) || (locate(/obj/machinery/door) in near))
					clear = FALSE
					break
			if(clear)
				return T

/// "ok" or "WRONG": whether a thing holds the shared emitter of a kind
/proc/kc_holds(atom/movable/thing, kind, wanted = TRUE)
	var/holds = !!(particle_fx(kind) in thing.vis_contents)
	return "[kind] [holds ? "held" : "not held"] [holds == wanted ? "ok" : "WRONG"]"

/// Bursts of a kind's particle set now in the world
/proc/kc_bursts(kind)
	var/list/how = GLOB.particle_fx_kinds[kind]
	var/found = 0
	for(var/obj/effect/particle_fx/burst/B in world)
		if(B.particles && istype(B.particles, how[1]) && B.particles.type == how[1])
			found++
	return found

/proc/kc_burst_line(kind)
	var/found = kc_bursts(kind)
	return "[kind] x[found] [found ? "ok" : "WRONG"]"

/proc/particle_new_run(client/C)
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
		kc_log("WRONG: no open stretch of hallway found")
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
	H.setDir(SOUTH)
	kc_log("hwmode [winget(C, null, "hwmode")], spot ([spot.x],[spot.y]) in [get_area(spot)]")
	var/list/made = list()
	var/z = spot.z

	// ---- Smoke and steam
	var/obj/structure/chair/wood/burning = new(locate(spot.x + 2, spot.y, z))
	burning.fire_act(1000, 100)
	var/obj/machinery/shower/shower = new(locate(spot.x - 2, spot.y, z))
	shower.current_temperature = "boiling"
	shower.interact(H)
	var/obj/machinery/microwave/oven = new(locate(spot.x + 4, spot.y, z))
	oven.operating = TRUE
	oven.update_icon()
	var/obj/machinery/portable_atmospherics/canister/toxins/can = new(locate(spot.x - 4, spot.y, z))
	can.valve_open = TRUE
	can.process_atmos()
	var/obj/item/clothing/mask/cigarette/cig = new(H)
	H.equip_to_appropriate_slot(cig)
	cig.light()
	made += list(burning, shower, oven, can)
	sleep(15)
	cig.process()
	sleep(3)
	kc_log("burning chair: [kc_holds(burning, "burning_smoke")]")
	kc_log("shower: [kc_holds(shower, "shower_drops")], [kc_holds(shower, "shower_steam")]")
	kc_log("microwave: [kc_holds(oven, "cook_steam")]")
	kc_log("plasma canister: [kc_holds(can, "gas_wisp_plasma")]")
	kc_log("cigarette in [H.wear_mask == cig ? "the mouth" : "the wrong place"]: [kc_burst_line("cig_smoke")]")
	particle_shot("particle_n1_smoke")
	burning.extinguish()
	shower.interact(H)
	oven.operating = FALSE
	oven.update_icon()
	can.valve_open = FALSE
	can.process_atmos()
	kc_log("put out: [kc_holds(burning, "burning_smoke", FALSE)]; shower off: [kc_holds(shower, "shower_drops", FALSE)], [kc_holds(shower, "shower_steam", FALSE)]; microwave off: [kc_holds(oven, "cook_steam", FALSE)]; valve shut: [kc_holds(can, "gas_wisp_plasma", FALSE)]")
	qdel(cig)
	QDEL_LIST(made)
	for(var/obj/effect/mist/M in range(5, spot))
		qdel(M)
	sleep(15)

	// ---- Tools and machines
	var/obj/structure/girder/girder = new(locate(spot.x + 1, spot.y, z))
	var/obj/item/weldingtool/largetank/welder = new(H)
	H.put_in_hands(welder)
	welder.attack_self(H)
	var/obj/machinery/vending/cola/vendor = new(locate(spot.x - 2, spot.y, z))
	var/obj/machinery/door/airlock/door = new(locate(spot.x - 4, spot.y, z))
	var/obj/item/gun/ballistic/automatic/pistol/gun = new(H)
	made += list(girder, vendor, door)
	sleep(5)
	spawn(0)
		welder.use_tool(girder, H, 40, 0)
	sleep(8)
	var/welding = 0
	for(var/obj/effect/particle_fx/F in get_turf(girder))
		welding++
	kc_log("welding ([welder.isOn() ? "lit" : "NOT lit"]): [welding] emitter on the girder's floor [welding == 1 ? "ok" : "WRONG"]")
	var/obj/effect/particle_effect/water/water = new(locate(spot.x - 3, spot.y - 1, z))
	for(var/i in 1 to 4)
		step(water, EAST)
	H.setDir(SOUTH)
	gun.shoot_live_shot(H, 0, null, 0)
	vendor.obj_break()
	door.wires.on_pulse(WIRE_BOLTS)
	sleep(2)
	kc_log("extinguisher water: [kc_burst_line("water_mist")]")
	kc_log("gun: [kc_burst_line("muzzle_smoke")]")
	kc_log("vending machine broken: [kc_burst_line("break_smoke")], [kc_burst_line("sparks")]")
	kc_log("door wire pulsed: [kc_burst_line("wire_sparks")]")
	particle_shot("particle_n2_tools")
	sleep(40)
	welding = 0
	for(var/obj/effect/particle_fx/F in get_turf(girder))
		welding++
	kc_log("weld over: [welding] emitters left [welding ? "WRONG" : "ok"]")
	qdel(welder)
	qdel(gun)
	qdel(water)
	QDEL_LIST(made)
	sleep(10)

	// ---- Mobs
	var/mob/living/carbon/human/alight = new(locate(spot.x + 2, spot.y, z))
	alight.fire_stacks = 5
	alight.IgniteMob()
	var/mob/living/carbon/human/corpse = new(locate(spot.x - 2, spot.y, z))
	corpse.death()
	corpse.timeofdeath = world.time - 5 MINUTES
	var/datum/component/rot/corpse/rot = corpse.LoadComponent(/datum/component/rot/corpse)
	rot.process()
	var/obj/structure/chair/melting = new(locate(spot.x + 4, spot.y, z))
	melting.acid_act(50, 20)
	var/mob/living/carbon/human/glowing = new(locate(spot.x - 4, spot.y, z))
	glowing.radiation = 2000
	glowing.handle_mutations_and_radiation()
	made += list(alight, corpse, melting, glowing)
	sleep(15)
	H.add_splatter_floor(get_turf(H), TRUE)
	sleep(2)
	kc_log("on fire ([alight.on_fire ? "burning" : "NOT burning"]): [kc_holds(alight, "mob_fire")], [kc_holds(alight, "burning_smoke")]")
	kc_log("rotting body: [kc_holds(corpse, "stink")]")
	kc_log("acid on a chair (level [melting.acid_level]): [kc_holds(melting, "acid")]")
	kc_log("irradiated: [kc_holds(glowing, "rad_glint")]")
	kc_log("drip: [kc_burst_line("blood_drip")]")
	particle_shot("particle_n3_mobs")
	alight.ExtinguishMob()
	glowing.radiation = 0
	glowing.handle_mutations_and_radiation()
	melting.acid_level = 1
	melting.acid_processing()
	qdel(rot)
	kc_log("put out: [kc_holds(alight, "mob_fire", FALSE)]; rot gone: [kc_holds(corpse, "stink", FALSE)]; acid spent: [kc_holds(melting, "acid", FALSE)]; dose gone: [kc_holds(glowing, "rad_glint", FALSE)]")
	QDEL_LIST(made)
	for(var/obj/effect/decal/cleanable/mess in range(5, spot))
		qdel(mess)
	sleep(10)

	// ---- Things breaking
	var/obj/structure/window/fulltile/glass = new(locate(spot.x + 2, spot.y, z))
	var/turf/wall_at = locate(spot.x - 2, spot.y, z)
	var/turf/closed/wall/wall = wall_at.PlaceOnTop(/turf/closed/wall)
	var/turf/rock_at = locate(spot.x + 4, spot.y, z)
	var/turf/closed/mineral/rock = rock_at.PlaceOnTop(/turf/closed/mineral)
	sleep(5)
	glass.deconstruct(FALSE)
	wall.dismantle_wall()
	rock.gets_drilled()
	sleep(2)
	kc_log("window smashed: [kc_burst_line("glass_shards")]")
	kc_log("wall taken down: [kc_burst_line("rubble")], [kc_burst_line("rubble_dust")]")
	kc_log("rock dug: [kc_burst_line("rock_chips")]")
	particle_shot("particle_n4_breaking")
	sleep(15)
	for(var/obj/thing in range(5, spot))
		if(istype(thing, /obj/item) || istype(thing, /obj/structure/girder) || istype(thing, /obj/effect/decal/cleanable))
			qdel(thing)

	// A pile: six hundred bursts asked for on one tile at once, both ways of asking (what a pile of things all breaking does,
	// without the six hundred sounds)
	var/before = GLOB.particle_bursts
	var/turf/pile_at = locate(spot.x + 3, spot.y, z)
	var/started = REALTIMEOFDAY
	for(var/i in 1 to 300)
		particle_burst(pile_at, "glass_shards")
		new /obj/effect/particle_fx/burst(pile_at, "rubble")
	var/standing = 0
	for(var/obj/effect/particle_fx/burst/B in pile_at)
		if(!QDELETED(B))
			standing++
	kc_log("600 bursts asked for on one tile: [before] -> [GLOB.particle_bursts] counted, [standing] standing (the most allowed is [PARTICLE_BURSTS_MAX]) [(GLOB.particle_bursts <= PARTICLE_BURSTS_MAX && standing <= PARTICLE_BURSTS_MAX) ? "ok" : "WRONG"], [REALTIMEOFDAY - started] ds")
	particle_shot("particle_n4_pile")
	sleep(20)
	// The count is the whole station's: a spark or a drip somewhere else is fine, one still on the pile's tile isn't
	var/list/left = list()
	var/left_here = 0
	var/found = 0
	for(var/obj/effect/particle_fx/burst/B in world)
		if(QDELETED(B))
			continue
		found++
		left += "[B.particles?.type] at ([B.x],[B.y],[B.z])"
		if(B.loc == pile_at)
			left_here++
	kc_log("after it: [GLOB.particle_bursts] counted, [found] in the world, [left_here] on the pile's tile [(left_here || found != GLOB.particle_bursts) ? "WRONG" : "ok"][length(left) ? ": [left.Join("; ")]" : ""]")

	// ---- A singularity, for a moment
	var/obj/singularity/hole = new(locate(spot.x + 4, spot.y, z), 50)
	sleep(12)
	kc_log("singularity: [length(hole.pull_fx)] emitters, [length(hole.vis_contents)] in vis_contents [length(hole.pull_fx) == 8 ? "ok" : "WRONG"]")
	particle_shot("particle_n5_singularity")
	hole.expand(STAGE_TWO)
	sleep(12)
	kc_log("grown to [hole.current_size]: [length(hole.pull_fx)] emitters, sized for [hole.pull_size] [hole.pull_size == hole.current_size ? "ok" : "WRONG"]")
	particle_shot("particle_n5_singularity_big")
	qdel(hole)
	H.forceMove(spot)
	sleep(10)

	// ---- Dust kicked up running through maintenance
	var/turf/dusty = particle_run_spot(/area/maintenance)
	if(dusty)
		H.forceMove(dusty)
		sleep(15) //SSair_dust looks at who can see what once a second
		var/mob/living/carbon/human/runner = new(locate(dusty.x - 3, dusty.y, dusty.z))
		var/kicked = 0
		for(var/i in 1 to 6)
			step(runner, EAST)
			kicked += kc_bursts("foot_dust")
			if(i == 4)
				particle_shot("particle_n6_foot_dust")
			sleep(2)
		kc_log("running through [get_area(dusty)]: foot dust seen [kicked] times over 6 steps [kicked ? "ok" : "WRONG (it's a 40% chance a step: run it again before believing this)"]")
		qdel(runner)

		// ---- A fire, with its smoke and its embers by heat
		for(var/turf/open/T in range(1, dusty))
			T.atmos_spawn_air("plasma=60;o2=120;TEMP=900")
		sleep(30)
		var/fires = 0
		var/list/kinds = list()
		var/smoking = 0
		for(var/obj/effect/hotspot/hot in range(7, dusty))
			fires++
			if(hot.ember_kind)
				kinds[hot.ember_kind]++
				if(particle_fx("fire_smoke") in hot.vis_contents)
					smoking++
				if(!(particle_fx(hot.ember_kind) in hot.vis_contents))
					kc_log("WRONG: a fire says [hot.ember_kind] and doesn't hold it")
		var/list/told = list()
		for(var/kind in kinds)
			told += "[kinds[kind]] [kind]"
		kc_log("fire: [fires] hotspots in view, embers: [told.Join(", ")]; [smoking] smoking [smoking ? "ok" : "WRONG"]")
		particle_shot("particle_n7_fire")
		var/obj/effect/hotspot/one
		for(var/obj/effect/hotspot/hot in range(7, dusty))
			if(hot.ember_kind)
				one = hot
				break
		if(one)
			one.temperature = PARTICLE_FIRE_HOT + 1000
			one.update_color()
			kc_log("made hotter: [one.ember_kind] [one.ember_kind == "ember_hot" ? "ok" : "WRONG"], [kc_holds(one, "ember_hot")], [kc_holds(one, "ember", FALSE)]")
	else
		kc_log("WRONG: no open stretch of maintenance found")

	// ---- The emergency shuttle's engines
	var/obj/docking_port/mobile/emergency/shuttle = SSshuttle.emergency
	var/obj/structure/shuttle/engine/propulsion/engine
	for(var/obj/structure/shuttle/engine/propulsion/E in shuttle?.engine_list)
		engine = E
		break
	if(engine)
		shuttle.hyperspace_sound(HYPERSPACE_WARMUP, list())
		var/turf/beside = get_step(engine, engine.dir) || get_turf(engine)
		H.forceMove(beside)
		sleep(15)
		kc_log("shuttle engine facing [dir2text(engine.dir)] at ([engine.x],[engine.y],[engine.z]): [length(engine.vis_contents)] in vis_contents [engine.exhaust ? "ok" : "WRONG"]")
		particle_shot("particle_n8_exhaust")
		shuttle.hyperspace_sound(HYPERSPACE_END, list())
		kc_log("jump over: [engine.exhaust ? "still burning WRONG" : "out ok"]")
	else
		kc_log("no emergency shuttle engine found: exhaust not pictured")

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
