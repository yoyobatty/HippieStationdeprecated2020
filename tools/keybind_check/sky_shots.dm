// Pictures of the sky with a real client: the old sky, then every theme, from open space and through the station's windows.
// Not part of the game: HARNESS=sky_shots.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh sky
// Pictures in data/previews/sky_*.png, notes in data/keycheck_sky.txt.
// The "before" pictures are the old layers put back as a theme of their own (below), in the same boot and from the same spots.
// data/sky_shots_which holds what to shoot: "all" (default), "before", a theme's type name ("ember"), "motion" (pairs of
// pictures a second apart, a walk, and each kind of fly-by), or "deep" (each far thing, the quasar running and on Low, and what
// a few rounds would pick).

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
			sky_shots_run(src)

/proc/sky_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

// ---- The sky as it was: tg's two star layers, its planet and one of Hippie's galaxies (what the default High preference drew
// on a round with no gas or asteroids)

/obj/screen/parallax_layer/legacy
	icon = 'icons/effects/parallax.dmi'
	icon_state = "layer1"
	speed = 0.6
	layer = 1

/obj/screen/parallax_layer/legacy/two
	icon_state = "layer2"
	speed = 1
	layer = 2

/obj/screen/parallax_layer/body/planet/legacy
	icon = 'icons/effects/parallax.dmi'
	icon_state = "planet"

/obj/screen/parallax_layer/body/planet/legacy/galaxy
	icon_state = "galaxy"
	speed = 1
	layer = 1

/datum/sky_theme/legacy
	name = "the old sky"
	weight = 0

/datum/sky_theme/legacy/build_layers()
	return list(new /obj/screen/parallax_layer/legacy, new /obj/screen/parallax_layer/legacy/two, new /obj/screen/parallax_layer/body/planet/legacy, new /obj/screen/parallax_layer/body/planet/legacy/galaxy)

// ---- Where to stand

/// Open space with the station along one side of the view: mostly sky, some hull for scale.
/proc/sky_space_spot()
	var/turf/best
	var/best_score = 0
	for(var/turf/open/space/T in world)
		if(!is_station_level(T.z) || T.x < 12 || T.y < 12 || T.x > world.maxx - 12 || T.y > world.maxy - 12)
			continue
		if((T.x + T.y * 3) % 7) //a sample of them is plenty
			continue
		var/hull = 0
		var/total = 0
		for(var/turf/near in range(7, T))
			total++
			if(!isspaceturf(near))
				hull++
		var/share = hull / total
		if(share < 0.12 || share > 0.30)
			continue
		var/score = 1 - abs(share - 0.2)
		if(score > best_score)
			best_score = score
			best = T
	kc_log("space spot ([best?.x],[best?.y],[best?.z]) score [best_score]")
	return best

/// A floor inside with the most space in sight: a window seat.
/proc/sky_window_spot()
	var/turf/best
	var/best_seen = 0
	for(var/turf/open/floor/T in world)
		if(!is_station_level(T.z) || T.density)
			continue
		var/area/A = T.loc
		if(!A.requires_power || istype(A, /area/space))
			continue
		var/seen = 0
		for(var/turf/open/space/S in view(7, T))
			seen++
		if(seen > best_seen)
			best_seen = seen
			best = T
	kc_log("window spot ([best?.x],[best?.y],[best?.z]) in [get_area(best)], [best_seen] space tiles in view")
	return best

/proc/sky_lights(turf/T, on)
	var/list/areas = list()
	for(var/turf/near in range(9, T))
		areas |= get_area(near)
	for(var/area/A as anything in areas)
		A.lightswitch = on
		A.power_change()

/proc/sky_layer_text(client/C)
	var/list/parts = list()
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		parts += "[replacetext("[L.type]", "/obj/screen/parallax_layer/", "")]([L.icon_state], [L.speed], vis [length(L.vis_contents)], at [L.pixel_w],[L.pixel_z])"
	return parts.Join("; ")

/// Puts far things in the sky where they're sure to be seen from where H is: list(kind, x, y) each, in pixels from the middle
/// of the view. Everything else single is moved out of the way.
/proc/sky_deep_show(mob/living/carbon/human/H, list/things)
	var/datum/controller/subsystem/parallax/P = SSparallax
	P.deep_sky = list()
	for(var/place in list("sun", "world", "galaxy"))
		P.body_places[place] = list(5000, 5000)
	P.planet_x_offset = H.x + 200
	var/index = 0
	for(var/list/thing as anything in things)
		index++
		var/speed = 0.3
		P.deep_sky += list(list(thing[1], 25, 1, speed))
		P.body_places["deep[index]"] = list(thing[2] + (H.x - world.maxx / 2) * speed, thing[3] + (H.y - world.maxy / 2) * speed)
	for(var/name in P.sky_art)
		if(findtext(name, "deep ") == 1)
			qdel(P.sky_art[name])
			P.sky_art -= name
	var/client/C = H.client
	C.parallax_theme = null //makes the layers again
	H.hud_used.update_parallax_pref(H)
	sleep(10)

/proc/sky_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	var/which = "all"
	if(fexists("data/sky_shots_which"))
		which = trim(file2text("data/sky_shots_which"))
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1, which gives up three minutes on
	kc_log("hwmode [winget(C, null, "hwmode")], view [C.view], round's own theme [SSparallax.theme.name], planet anchor [SSparallax.planet_x_offset],[SSparallax.planet_y_offset]")

	var/turf/space_spot = sky_space_spot()
	var/turf/window_spot = sky_window_spot()
	// The planet where the pictures are taken: a little up and right of the middle of the view from open space
	SSparallax.planet_x_offset = space_spot.x + 25
	SSparallax.planet_y_offset = space_spot.y + 20

	var/mob/living/carbon/human/H = new(space_spot)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/space)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(2 SECONDS)
	H.hud_used.show_hud(HUD_STYLE_NOHUD)
	C.prefs.parallax = PARALLAX_INSANE //no throttle, every layer
	C.prefs.set_graphics_quality(GRAPHICS_QUALITY_HIGH)

	var/list/themes = list()
	if(which == "all" || which == "before")
		themes += /datum/sky_theme/legacy
	if(which == "all" || which == "motion" || which == "ships")
		for(var/path in subtypesof(/datum/sky_theme) - /datum/sky_theme/legacy)
			themes += path
			if(which != "all")
				break
	else if(which != "before" && which != "deep")
		themes += text2path("/datum/sky_theme/[which]")

	for(var/path in themes)
		var/datum/sky_theme/theme = new path
		SSparallax.set_theme(theme)
		var/tag = path == /datum/sky_theme/legacy ? "before" : replacetext("[path]", "/datum/sky_theme/", "")
		H.forceMove(space_spot)
		sleep(15)
		kc_log("[tag] ([theme.name]): [length(C.parallax_layers)] layers, [length(SSparallax.sky_art)] shared art; [sky_layer_text(C)]")
		sky_shot("sky_[tag]_1_space")
		if(window_spot)
			H.forceMove(window_spot)
			sleep(15)
			sky_shot("sky_[tag]_2_window")
			// and with the lamps off: what's left is the starlight coming in, in the sky's colour
			sky_lights(window_spot, FALSE)
			sleep(2 SECONDS)
			kc_log("[tag]: starlight [GLOB.starlight_color] (base [GLOB.base_starlight_color]), [length(GLOB.starlight)] space tiles giving it off")
			sky_shot("sky_[tag]_3_dark")
			sky_lights(window_spot, TRUE)
			sleep(1 SECONDS)

	if(which == "ships") // a ship is a few pixels and its path is random: four of them, a still picture first to tell them from
		H.forceMove(space_spot)
		sleep(15)
		sky_shot("sky_ships_0_none")
		var/obj/screen/sky_art/flyby/ships = SSparallax.flyby_art()
		for(var/i in 1 to 4)
			ships.launch("ship", 40)
			sleep(18)
			sky_shot("sky_ships_[i]")
			sleep(30)

	if(which == "deep")
		SSparallax.set_theme(new /datum/sky_theme/quiet)
		H.forceMove(space_spot)
		sleep(15)
		for(var/kind in list("nebula_ring", "nebula_bipolar", "nebula_remnant", "quasar"))
			sky_deep_show(H, list(list(kind, -60, 30)))
			kc_log("deep [kind]: [sky_layer_text(C)]")
			sky_shot("sky_deep_[kind]")
		// The quasar's jets run and its core flickers: two pictures a second and a half apart, then the same on Low
		sky_deep_show(H, list(list("quasar", -60, 30)))
		sleep(20)
		sky_shot("sky_deep_quasar_motion_a")
		sleep(15)
		sky_shot("sky_deep_quasar_motion_b")
		C.prefs.set_graphics_quality(GRAPHICS_QUALITY_LOW)
		H.hud_used.update_parallax_pref(H)
		sleep(10)
		kc_log("deep on Low: [sky_layer_text(C)]")
		sky_shot("sky_deep_quasar_low_a")
		sleep(15)
		sky_shot("sky_deep_quasar_low_b")
		C.prefs.set_graphics_quality(GRAPHICS_QUALITY_HIGH)
		// Two at once, as a round can have
		sky_deep_show(H, list(list("nebula_remnant", -150, 60), list("quasar", 170, -70)))
		sky_shot("sky_deep_two")
		// What rounds pick, and the sky of three of them as it would be
		var/list/counts = list()
		for(var/i in 1 to 200)
			SSparallax.pick_deep_sky(list(0, 120, 240))
			counts["[length(SSparallax.deep_sky)]"]++
			for(var/list/thing as anything in SSparallax.deep_sky)
				counts[thing[1]]++
		kc_log("200 rounds' picks: [json_encode(counts)]")
		for(var/i in 1 to 3)
			SSparallax.set_theme(new /datum/sky_theme/quiet)
			H.forceMove(space_spot)
			sleep(15)
			var/list/picked = list()
			for(var/list/thing as anything in SSparallax.deep_sky)
				picked += "[thing[1]] turned [thing[2]] size [thing[3]] at [json_encode(SSparallax.body_places["deep[length(picked) + 1]"])]"
			kc_log("round [i]: [picked.Join("; ")]")
			sky_shot("sky_deep_round_[i]")

	if(which == "motion")
		H.forceMove(space_spot)
		sleep(15)
		// Twinkle and drift: two pictures 1.5 seconds apart, standing still
		sky_shot("sky_motion_1_still_a")
		sleep(15)
		sky_shot("sky_motion_1_still_b")
		// and a third 20 seconds on: the clouds have drifted about 8 pixels by then
		sleep(200)
		sky_shot("sky_motion_1_still_c")
		// Each fly-by, caught half way across
		var/obj/screen/sky_art/flyby/F = SSparallax.flyby_art()
		for(var/kind in list("comet", "ship", "meteor"))
			F.launch(kind, 40)
			sleep(18)
			sky_shot("sky_motion_2_[kind]")
			sleep(30)
		// A walk: where the layers are, each step, and a picture mid-stride
		for(var/i in 1 to 6)
			step(H, EAST)
			if(i == 3)
				sky_shot("sky_motion_3_walking")
			kc_log("step [i] east at [H.x]: [sky_layer_text(C)]")
			sleep(2)
		sleep(10)
		sky_shot("sky_motion_3_walked")
		// Each Graphics quality and Parallax preference: what's on screen
		for(var/quality in list(GRAPHICS_QUALITY_LOW, GRAPHICS_QUALITY_MEDIUM, GRAPHICS_QUALITY_HIGH))
			C.prefs.set_graphics_quality(quality)
			H.hud_used.update_parallax_pref(H)
			kc_log("graphics [quality]: [length(C.parallax_layers)] layers; [sky_layer_text(C)]")
		for(var/pref in list(PARALLAX_LOW, PARALLAX_MED, PARALLAX_HIGH, PARALLAX_INSANE, PARALLAX_DISABLE))
			C.prefs.parallax = pref
			H.hud_used.update_parallax_pref(H)
			sleep(10)
			kc_log("parallax pref [pref]: [length(C.parallax_layers)] layers")
			sky_shot("sky_motion_4_parallax_[pref]")

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
