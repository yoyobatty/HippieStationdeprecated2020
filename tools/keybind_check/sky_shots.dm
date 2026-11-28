// Pictures of the sky with a real client: the old sky, then every theme, from open space and through the station's windows.
// Not part of the game: HARNESS=sky_shots.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh sky
// Pictures in data/previews/sky_*.png, notes in data/keycheck_sky.txt.
// The "before" pictures are the old layers put back as a theme of their own (below), in the same boot and from the same spots.
// data/sky_shots_which holds what to shoot: "all" (default), "before", a theme's type name ("ember"), "motion" (pairs of
// pictures a second apart, a walk, and each kind of fly-by), or "deep" (each far thing, the quasar running and on Low, and what
// a few rounds would pick), "port" (rotation, weather, and the giant event), "polish" (themes, twinkle, and rare events),
// "seams", "sharpness" (tools/sky_gen/v2/sky_sharpness.py), "scaling" (each of the map's Scaling Modes), "layers" (each layer alone), "batch" (what turns the clouds blocky), "walk" (a ghost flying, filmed by record.ps1), or "lobby_ghost" (observing from the lobby).

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
		parts += "[replacetext("[L.type]", "/obj/screen/parallax_layer/", "")]([L.icon_state], [L.speed], vis [length(L.vis_contents)], at [L.drawn_x],[L.drawn_y])"
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

/// Holds the sky at `angle` (the sun's line with no speed) and lays H's layers out again for it
/proc/sky_port_hold_angle(mob/living/carbon/human/H, angle)
	var/list/sun = SSparallax.body_places["sun"]
	SSparallax.turn_line = list(angle + 90 - arctan(sun[1], sun[2]), world.time, 0)
	H.hud_used.update_parallax_pref(H)
	sleep(15)

/// Some rolls leave too little open sky for a giant. Take the picture only once one actually starts.
/proc/sky_shoot_giant(name)
	for(var/attempt in 1 to 6)
		if(SSparallax.sky_event("giant"))
			kc_log("giant event started on attempt [attempt]")
			sleep(70 SECONDS)
			sky_shot(name)
			return
		SSparallax.set_theme(new /datum/sky_theme/quiet)
	kc_log("No sky roll had room for a giant event")

/proc/sky_shoot_polish(mob/living/carbon/human/H)
	var/turf/clear_space = locate(110, 60, SSmapping.station_start)
	if(isspaceturf(clear_space))
		H.forceMove(clear_space)
	rand_seed(5)
	SSsun.can_fire = FALSE
	SSparallax.flyby_art()
	SSparallax.next_flyby = world.time + 1 HOURS
	SSparallax.next_sky_event = world.time + 1 HOURS
	for(var/theme_type in list(/datum/sky_theme/ember, /datum/sky_theme/violet, /datum/sky_theme/verdant, /datum/sky_theme/gold, /datum/sky_theme/quiet))
		SSparallax.set_theme(new theme_type)
		sky_port_hold_angle(H, 0)
		var/tag = replacetext("[theme_type]", "/datum/sky_theme/", "")
		sky_shot("sky_polish_[tag]")
	for(var/frame in 1 to 4)
		sky_shot("sky_polish_twinkle_[frame]")
		sleep(15)

	// The 270-second comet splits at 121.5 seconds. Sample before, during and after the split.
	SSparallax.send_comet(270 SECONDS, TRUE, 0.45)
	var/began = world.time
	for(var/second in list(107, 119, 122, 127, 136, 158))
		sleep(max(world.tick_lag, began + (second SECONDS) - world.time))
		sky_shot("sky_polish_breakup_[second]")
	for(var/obj/screen/sky_art/piece/P in SSparallax.flyby.vis_contents)
		qdel(P)

	if(SSparallax.sky_event("supernova"))
		began = world.time
		for(var/second in list(20, 45, 61, 80))
			sleep(max(world.tick_lag, began + (second SECONDS) - world.time))
			sky_shot("sky_polish_supernova_[second]")
	for(var/obj/screen/sky_art/piece/P in SSparallax.flyby.vis_contents)
		qdel(P)
	SSsun.can_fire = TRUE
	sky_shoot_giant("sky_polish_giant")

/// A sky layer's kind: "stars", "clouds" (the theme's nebulae), "band" (the galaxy's band) or "other" (the bodies, far things,
/// asteroids, dust, fly-bys)
/proc/sky_layer_kind(obj/screen/parallax_layer/L)
	if(istype(L, /obj/screen/parallax_layer/stars))
		return "stars"
	if(istype(L, /obj/screen/parallax_layer/nebula))
		var/obj/screen/parallax_layer/nebula/N = L
		var/list/cloud = SSparallax.theme.nebula[N.index]
		return cloud[1] == "band" ? "band" : "clouds"
	return "other"

/// Whether a layer is of a kind (sky_layer_kind()) or, given a type path, of that type
/proc/sky_layer_is(obj/screen/parallax_layer/L, what)
	if(copytext(what, 1, 2) == "/")
		return "[L.type]" == what
	return sky_layer_kind(L) == what

/// Shows only the client's layers of one kind (sky_layer_kind()), or "all"
/proc/sky_seams_show(client/C, part)
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		L.invisibility = (part == "all" || part == sky_layer_kind(L)) ? 0 : INVISIBILITY_ABSTRACT

/// Lines in the sky: the Gilded Band held at 0 and 20 degrees from open space, each kind of layer alone, then all again with every
/// layer and piece of shared art drawn nearest-neighbour (PIXEL_SCALE). tools/sky_gen/v2/seam_check.py finds the straight lines.
/proc/sky_shoot_seams(mob/living/carbon/human/H)
	var/client/C = H.client
	var/turf/clear_space = locate(110, 60, SSmapping.station_start)
	SSsun.can_fire = FALSE
	SSparallax.flyby_art()
	SSparallax.next_flyby = world.time + 1 HOURS
	SSparallax.next_sky_event = world.time + 1 HOURS
	SSparallax.set_theme(new /datum/sky_theme/gold)
	if(isspaceturf(clear_space))
		H.forceMove(clear_space)
	for(var/sampling in list("smooth", "nearest"))
		if(sampling == "nearest")
			for(var/name in SSparallax.sky_art)
				var/obj/screen/sky_art/A = SSparallax.sky_art[name]
				A.appearance_flags |= PIXEL_SCALE
		for(var/angle in list(0, 20))
			sky_port_hold_angle(H, angle)
			if(sampling == "nearest")
				for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
					L.appearance_flags |= PIXEL_SCALE
			for(var/part in list("all", "stars", "clouds", "band"))
				sky_seams_show(C, part)
				sleep(5)
				kc_log("seams [sampling] [angle] [part]: sky_turn_angle [sky_turn_angle()], at ([H.x],[H.y]); [sky_layer_text(C)]")
				sky_shot("sky_seams_[sampling]_[angle]_[part]")
			sky_seams_show(C, "all")
	for(var/name in SSparallax.sky_art)
		var/obj/screen/sky_art/A = SSparallax.sky_art[name]
		A.appearance_flags &= ~PIXEL_SCALE
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		L.appearance_flags &= ~PIXEL_SCALE
	SSsun.can_fire = TRUE
	// The sky turning with the sun as in a round (the shots above hold it still): the same art, drawn while its turn animates
	SSparallax.turn_line = null
	SSparallax.sun_moved()
	H.hud_used.update_parallax_pref(H)
	sleep(3 SECONDS)
	kc_log("seams live: sky_turn_angle [sky_turn_angle()], turn line [json_encode(SSparallax.turn_line)]")
	for(var/part in list("all", "stars", "clouds", "band", "other"))
		sky_seams_show(C, part)
		sleep(5)
		kc_log("seams live [part]: sky_turn_angle [sky_turn_angle()]; [sky_layer_text(C)]")
		sky_shot("sky_seams_live_[part]")
	// Does BYOND filter a sprite smoothly only when its own transform scales it? A hair of scale on every piece of art and layer
	for(var/name in SSparallax.sky_art)
		var/obj/screen/sky_art/A = SSparallax.sky_art[name]
		var/matrix/M = matrix(A.transform)
		M.Scale(1.002)
		A.transform = M
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		var/matrix/M = matrix(L.transform)
		M.Scale(1.002)
		L.transform = M
	for(var/part in list("all", "band", "other"))
		sky_seams_show(C, part)
		sleep(5)
		sky_shot("sky_seams_live_scaled_[part]")
	sky_seams_show(C, "all")

/// Sharpness pictures for tools/sky_gen/v2/sky_sharpness.py: the Gilded Band from open space, each kind of layer alone, held at
/// 20, 20.35 and 20.7 degrees (shimmer is what changes between them besides the turn). data/sky_shots_tag names the set.
/proc/sky_shoot_sharpness(mob/living/carbon/human/H)
	var/client/C = H.client
	var/tag = fexists("data/sky_shots_tag") ? trim(file2text("data/sky_shots_tag")) : "now"
	var/turf/clear_space = locate(110, 60, SSmapping.station_start)
	SSsun.can_fire = FALSE
	SSparallax.flyby_art()
	SSparallax.next_flyby = world.time + 1 HOURS
	SSparallax.next_sky_event = world.time + 1 HOURS
	rand_seed(5)
	SSparallax.set_theme(new /datum/sky_theme/gold)
	if(isspaceturf(clear_space))
		H.forceMove(clear_space)
	for(var/part in list("all", "stars", "clouds", "band", "other"))
		for(var/step in 0 to 2)
			var/angle = 20 + step * 0.35
			sky_port_hold_angle(H, angle)
			sky_seams_show(C, part)
			sleep(5)
			kc_log("sharpness [tag] [part] [angle]: sky_turn_angle [sky_turn_angle()]")
			sky_shot("sky_sharp_[tag]_[part]_[step]")
	sky_seams_show(C, "all")
	SSsun.can_fire = TRUE

/// The map's Scaling Mode (Icons menu: Nearest Neighbor is zoom-mode=distort, Point Sampling normal, Bilinear blur) against the
/// sky's scaled art: Violet Deep from open space, held at 0 degrees, everything and then the clouds alone, under each mode, and
/// the clouds once more as a ghost. Keegan's playtest (2026-11-28, Point Sampling, a ghost) showed the 2x clouds in hard blocks
/// where this harness, on the skin's default distort, drew them smooth. sky_sharpness.py's blocks score reads the pictures.
/// The player's own mode is put back at the end: it's a saved parameter.
/proc/sky_shoot_scaling(mob/living/carbon/human/H)
	var/client/C = H.client
	var/own_mode = winget(C, "mapwindow.map", "zoom-mode")
	kc_log("scaling: player's zoom-mode [own_mode], zoom [winget(C, "mapwindow.map", "zoom")]")
	var/turf/clear_space = locate(110, 60, SSmapping.station_start)
	SSsun.can_fire = FALSE
	SSparallax.flyby_art()
	SSparallax.next_flyby = world.time + 1 HOURS
	SSparallax.next_sky_event = world.time + 1 HOURS
	rand_seed(5)
	SSparallax.set_theme(new /datum/sky_theme/violet)
	if(isspaceturf(clear_space))
		H.forceMove(clear_space)
	sky_port_hold_angle(H, 0)
	for(var/mode in list("distort", "normal", "blur"))
		winset(C, "mapwindow.map", "zoom-mode=[mode]")
		for(var/part in list("all", "clouds"))
			sky_seams_show(C, part)
			sleep(10)
			kc_log("scaling [mode] [part]: zoom-mode now [winget(C, "mapwindow.map", "zoom-mode")], sky_turn_angle [sky_turn_angle()]")
			sky_shot("sky_scaling_[mode]_[part]")
	var/mob/dead/observer/ghost = H.ghostize(TRUE)
	sleep(2 SECONDS)
	if(ghost)
		sky_port_hold_angle(ghost, 0)
		winset(C, "mapwindow.map", "zoom-mode=normal")
		sky_seams_show(C, "clouds")
		sleep(10)
		kc_log("scaling ghost normal clouds: mob [C.mob.type] at ([C.mob.x],[C.mob.y]), sky_turn_angle [sky_turn_angle()]")
		sky_shot("sky_scaling_ghost_normal_clouds")
	sky_seams_show(C, "all")
	winset(C, "mapwindow.map", "zoom-mode=[own_mode]")
	kc_log("scaling: zoom-mode put back to [winget(C, "mapwindow.map", "zoom-mode")]")
	SSsun.can_fire = TRUE

/// What a sky object is and how it's drawn, for the notes: type, sheet and state, flags, scale and blend
/proc/sky_draw_text(atom/movable/A)
	var/matrix/M = A.transform
	return "[A.type] [A.icon]:[A.icon_state] flags [A.appearance_flags] scale [M ? "[M.a],[M.e] turn [M.b],[M.d]" : "none"] blend [A.blend_mode] alpha [A.alpha] layer [A.layer] plane [A.plane] overlays [length(A.overlays)]"

/// Each of the client's sky layers alone, Violet Deep from open space held at 0 degrees (sky_layer_<n>.png), with what it draws
/// and how in the notes: sky_sharpness.py's blocks score names a layer drawn in hard blocks (Keegan's playtest, 2026-11-28).
/proc/sky_shoot_layers(mob/living/carbon/human/H)
	var/client/C = H.client
	var/turf/clear_space = locate(110, 60, SSmapping.station_start)
	SSsun.can_fire = FALSE
	SSparallax.flyby_art()
	SSparallax.next_flyby = world.time + 1 HOURS
	SSparallax.next_sky_event = world.time + 1 HOURS
	rand_seed(5)
	SSparallax.set_theme(new /datum/sky_theme/violet)
	if(isspaceturf(clear_space))
		H.forceMove(clear_space)
	SSevents.can_fire = FALSE
	// data/sky_shots_first_theme: a theme to show first and switch away from (two runs that began on Quiet Black drew a rainbow over
	// the whole map, with the GPU under a heavy load from elsewhere)
	if(fexists("data/sky_shots_first_theme"))
		var/first = text2path("/datum/sky_theme/[trim(file2text("data/sky_shots_first_theme"))]")
		if(first)
			SSparallax.set_theme(new first)
			H.hud_used.update_parallax_pref(H)
			sleep(3 SECONDS)
			kc_log("layers: first theme [SSparallax.theme.name]")
	var/list/covers = list()
	for(var/obj/screen/fullscreen/F in C.screen)
		covers += "[F.type]:[F.icon_state]"
	kc_log("layers: full-screen effects before clearing: [covers.Join(", ")]; mob at ([H.x],[H.y],[H.z])")
	H.clear_fullscreens()
	sky_port_hold_angle(H, 0)
	kc_log("layers: zoom-mode [winget(C, "mapwindow.map", "zoom-mode")]; home [C.parallax_home ? sky_draw_text(C.parallax_home) : "none"]")
	// data/sky_shots_layers_with: a kind of layer ("clouds") or a layer type ("/obj/screen/parallax_layer/body/deep") kept on with
	// each layer in turn: which layer changes how it looks
	var/with = fexists("data/sky_shots_layers_with") ? trim(file2text("data/sky_shots_layers_with")) : null
	if(with)
		for(var/obj/screen/parallax_layer/other as anything in C.parallax_layers)
			other.invisibility = sky_layer_is(other, with) ? 0 : INVISIBILITY_ABSTRACT
		sleep(5)
		kc_log("layers: [with] alone")
		sky_shot("sky_layer_0")
	var/index = 0
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		index++
		for(var/obj/screen/parallax_layer/other as anything in C.parallax_layers)
			other.invisibility = (other == L || (with && sky_layer_is(other, with))) ? 0 : INVISIBILITY_ABSTRACT
		sleep(5)
		kc_log("layer [index]: [sky_draw_text(L)]; holder [L.holder ? sky_draw_text(L.holder) : "none"]")
		for(var/atom/movable/A in L.vis_contents)
			kc_log("layer [index] carries: [sky_draw_text(A)]")
		sky_shot("sky_layer_[index]")
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		L.invisibility = 0
	SSsun.can_fire = TRUE
	SSevents.can_fire = TRUE

/// Keegan's playtest as it went (2026-11-28): the sky rolled before anyone joined, the player observing from the lobby before the
/// round starts, then the round starting with the sky turning live. Violet Deep, Parallax Insane, Graphics High, as his
/// preferences are. Pictures from open space before the round, just after it starts, half a minute on, then held at 0 degrees
/// (sky_lobby_ghost_*.png) for sky_sharpness.py's blocks score.
/proc/sky_shoot_lobby_ghost(client/C)
	SSparallax.set_theme(new /datum/sky_theme/violet)
	C.prefs.parallax = PARALLAX_INSANE
	C.prefs.set_graphics_quality(GRAPHICS_QUALITY_HIGH)
	C.fps = 60
	var/wait_for_lobby = world.time + 60 SECONDS
	while(!istype(C.mob, /mob/dead/new_player) && world.time < wait_for_lobby)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/mob/dead/new_player/N = C.mob
	var/mob/dead/observer/ghost = new()
	ghost.started_as_observer = TRUE
	N.close_spawn_windows()
	ghost.key = N.key
	ghost.client = C
	ghost.set_ghost_appearance()
	qdel(N)
	sleep(2 SECONDS)
	var/turf/clear_space = locate(110, 60, SSmapping.station_start)
	ghost.forceMove(clear_space)
	SSparallax.next_flyby = world.time + 1 HOURS
	SSparallax.next_sky_event = world.time + 1 HOURS
	sleep(3 SECONDS)
	text2file("go", "data/keycheck_sendkeys")
	kc_log("lobby ghost: [C.mob.type] at ([C.mob.x],[C.mob.y],[C.mob.z]), state [SSticker.current_state], zoom-mode [winget(C, "mapwindow.map", "zoom-mode")], theme [SSparallax.theme.name], sky_turn_angle [sky_turn_angle()]; [sky_layer_text(C)]")
	sky_shot("sky_lobby_ghost_pregame")
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	kc_log("lobby ghost started: state [SSticker.current_state], at ([C.mob.x],[C.mob.y]), theme [SSparallax.theme.name], sky_turn_angle [sky_turn_angle()]")
	sky_shot("sky_lobby_ghost_start")
	sleep(30 SECONDS)
	kc_log("lobby ghost 30 s on: sky_turn_angle [sky_turn_angle()]")
	sky_shot("sky_lobby_ghost_live")
	for(var/part in list("clouds", "all"))
		sky_seams_show(C, part)
		sleep(10)
		sky_shot("sky_lobby_ghost_live_[part]")
	SSsun.can_fire = FALSE
	sky_port_hold_angle(ghost, 0)
	for(var/part in list("all", "clouds"))
		sky_seams_show(C, part)
		sleep(10)
		kc_log("lobby ghost held [part]: sky_turn_angle [sky_turn_angle()]")
		sky_shot("sky_lobby_ghost_held_[part]")
	sky_seams_show(C, "all")
	SSsun.can_fire = TRUE

/// Why the 2x clouds come out in blocks with every layer on (2026-11-28): alone they're smooth, and the deep stars (layer 2, drawn
/// at their own size, just under the clouds) are enough to turn them blocky. If BYOND takes a batch's texture filtering from
/// the first sprite in it, a sprite with a scale of its own, or the deep stars drawn after the clouds, puts it right. Violet
/// Deep held at 0 degrees, the clouds and the deep stars on: as they are, the deep stars' art scaled 1.001, moved 0.01 px,
/// and drawn above the clouds; then every layer with every unscaled piece of art scaled 1.001 (sky_batch_*.png).
/proc/sky_shoot_batch(mob/living/carbon/human/H)
	var/client/C = H.client
	var/turf/clear_space = locate(110, 60, SSmapping.station_start)
	SSsun.can_fire = FALSE
	SSevents.can_fire = FALSE
	SSparallax.flyby_art()
	SSparallax.next_flyby = world.time + 1 HOURS
	SSparallax.next_sky_event = world.time + 1 HOURS
	rand_seed(5)
	SSparallax.set_theme(new /datum/sky_theme/violet)
	if(isspaceturf(clear_space))
		H.forceMove(clear_space)
	H.clear_fullscreens()
	sky_port_hold_angle(H, 0)
	var/obj/screen/parallax_layer/deep
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		if(istype(L, /obj/screen/parallax_layer/stars/deep))
			deep = L
		L.invisibility = (L.type == /obj/screen/parallax_layer/stars/deep || sky_layer_kind(L) == "clouds") ? 0 : INVISIBILITY_ABSTRACT
	var/obj/screen/sky_art/art = SSparallax.star_art("stars_deep", 2)
	var/list/variants = list(
		"as_is" = matrix(),
		"scaled" = matrix(1.001, 0, 0, 0, 1.001, 0),
		"moved" = matrix(1, 0, 0.01, 0, 1, 0.01))
	for(var/name in variants)
		art.transform = variants[name]
		sleep(10)
		kc_log("batch [name]: deep stars' art [sky_draw_text(art)]")
		sky_shot("sky_batch_[name]")
	art.transform = matrix()
	var/old_layer = deep.layer
	deep.layer = 3.5
	deep.holder.layer = 3.5
	art.layer = 3.5
	sleep(10)
	kc_log("batch above: deep stars' layer [deep.layer], holder [deep.holder.layer]")
	sky_shot("sky_batch_above")
	deep.layer = old_layer
	deep.holder.layer = old_layer
	art.layer = old_layer
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		L.invisibility = 0
	sleep(10)
	sky_shot("sky_batch_all_as_is")
	var/list/scaled = list()
	for(var/name in SSparallax.sky_art)
		var/obj/screen/sky_art/A = SSparallax.sky_art[name]
		var/matrix/M = A.transform
		if(!M || (M.a == 1 && M.e == 1 && M.b == 0 && M.d == 0))
			var/matrix/hair = matrix(M)
			hair.Scale(1.001)
			A.transform = hair
			scaled += name
	sleep(10)
	kc_log("batch all scaled: [scaled.Join(", ")]")
	sky_shot("sky_batch_all_scaled")
	SSsun.can_fire = TRUE
	SSevents.can_fire = TRUE

GLOBAL_VAR_INIT(sky_walk_log, FALSE)

/// Every slide of the deep stars' and the dust's layers while sky_shoot_walk() runs: where to, over how long
/obj/screen/parallax_layer/slide_to(x, y, time)
	if(GLOB.sky_walk_log && (type == /obj/screen/parallax_layer/stars/deep || type == /obj/screen/parallax_layer/dust))
		kc_log("slide [world.time] [replacetext("[type]", "/obj/screen/parallax_layer/", "")] [x],[y] over [time || 0] (was [drawn_x],[drawn_y])")
	return ..()

/// A recording of the sky while a ghost flies (record.ps1 films data/previews/<name>/), with each step logged
/proc/sky_walk_clip(client/C, name, list/legs)
	text2file("[name] 7", "data/keycheck_record")
	sleep(15) // ffmpeg starting
	GLOB.sky_walk_log = TRUE
	for(var/list/leg in legs)
		var/dir = leg[1]
		for(var/step in 1 to leg[2])
			var/mob/M = C.mob
			var/turf/from = M.loc
			C.Move(get_step(M, dir), dir)
			kc_log("step [world.time] [dir2text(dir)] ([from?.x],[from?.y]) -> ([M.x],[M.y]) glide_size [M.glide_size]")
			sleep(world.tick_lag)
		sleep(6)
	GLOB.sky_walk_log = FALSE
	var/deadline = world.time + 20 SECONDS
	while(!fexists("data/keycheck_record_done") && world.time < deadline)
		sleep(2)
	fdel("data/keycheck_record_done")

/// Keegan, 2026-11-28: the sky wobbles a little as a ghost flies, side to side flying left and right, up and down flying up and
/// down. A ghost flies a tile a tick (client/Move() sends a mob that isn't living straight to its Move(), with the default glide).
/// Violet Deep held at 0 degrees, from open space: the far layers alone (stars, clouds, band) and then everything, each filmed
/// while the ghost flies east, west, north and south (data/previews/sky_walk_*/; tools/sky_gen/v2/sky_motion.py measures them).
/proc/sky_shoot_walk(mob/living/carbon/human/H)
	var/client/C = H.client
	var/turf/clear_space = locate(110, 60, SSmapping.station_start)
	SSsun.can_fire = FALSE
	SSevents.can_fire = FALSE
	SSparallax.flyby_art()
	SSparallax.next_flyby = world.time + 1 HOURS
	SSparallax.next_sky_event = world.time + 1 HOURS
	rand_seed(5)
	SSparallax.set_theme(new /datum/sky_theme/violet)
	if(isspaceturf(clear_space))
		H.forceMove(clear_space)
	var/mob/dead/observer/ghost = H.ghostize(TRUE)
	sleep(2 SECONDS)
	sky_port_hold_angle(ghost, 0)
	kc_log("walk: [C.mob.type] at ([C.mob.x],[C.mob.y]), glide_size [C.mob.glide_size], tick_lag [world.tick_lag], fps [world.fps], client fps [C.fps]")
	var/list/legs = list(list(EAST, 12), list(WEST, 12), list(NORTH, 10), list(SOUTH, 10))
	for(var/obj/screen/parallax_layer/L as anything in C.parallax_layers)
		var/kind = sky_layer_kind(L)
		L.invisibility = (kind == "stars" || kind == "clouds" || kind == "band") ? 0 : INVISIBILITY_ABSTRACT
	sleep(10)
	sky_walk_clip(C, "sky_walk_far", legs)
	sky_seams_show(C, "all")
	sleep(10)
	sky_walk_clip(C, "sky_walk_all", legs)
	SSsun.can_fire = TRUE
	SSevents.can_fire = TRUE

/proc/sky_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	var/which = "all"
	if(fexists("data/sky_shots_which"))
		which = trim(file2text("data/sky_shots_which"))
	GLOB.master_mode = "extended"
	if(which == "lobby_ghost")
		sky_shoot_lobby_ghost(C)
		text2file("done", "data/keycheck_shots_done")
		sleep(5)
		kc_log("done")
		winset(C, null, "command=.quit")
		sleep(5)
		del(world)
		return
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
	C.fps = 60
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
	else if(which != "before" && which != "deep" && which != "port" && which != "polish" && which != "seams" && which != "sharpness" && which != "scaling" && which != "layers" && which != "batch" && which != "walk")
		var/theme_type = text2path("/datum/sky_theme/[which]")
		if(theme_type)
			themes += theme_type
		else
			kc_log("Unknown sky theme: [which]")

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

	if(which == "port") // the Paradise port's fixes and additions (2026-11-27)
		var/datum/sky_theme/theme = new /datum/sky_theme/ember
		theme.neighbour = "world_gas" // the ringed world, whatever the theme has
		SSparallax.set_theme(theme)
		H.forceMove(space_spot)
		sleep(15)
		// The sky held at three angles: the same picture turned about the middle, nothing sliding against anything else.
		// The sun held still meanwhile, or its next move would set the sky turning again
		SSsun.can_fire = FALSE
		for(var/angle in list(0, 60, 120))
			sky_port_hold_angle(H, angle)
			kc_log("port turn [angle]: sky_turn_angle [sky_turn_angle()], painted sun at [sky_sun_bearing()]; [sky_layer_text(C)]")
			sky_shot("sky_port_turn_[angle]")
		sky_port_hold_angle(H, 0)
		SSsun.can_fire = TRUE
		// An ash storm over Lavaland
		SSparallax.lavaland_ash_storm(TRUE)
		sleep(SKY_WEATHER_FADE + 2 SECONDS)
		sky_shot("sky_port_ash")
		SSparallax.lavaland_ash_storm(FALSE)
		// Aurora Caelus's curtains and a radiation storm's shimmer
		SSparallax.aurora_caelus_sky(TRUE)
		SSparallax.rad_storm_sky(TRUE)
		sleep(SKY_WEATHER_FADE + 2 SECONDS)
		sky_shot("sky_port_caelus_rad")
		SSparallax.aurora_caelus_sky(FALSE)
		SSparallax.rad_storm_sky(FALSE)
		sleep(SKY_WEATHER_FADE + 2 SECONDS)
		// The ion storm's aurora on Lavaland, and the giant, each at its peak
		SSparallax.event_until = 0
		kc_log("port event: [SSparallax.sky_event("aurora")]")
		sleep(50 SECONDS)
		sky_shot("sky_port_aurora")
		SSparallax.end_aurora()
		SSparallax.event_until = 0
		sky_shoot_giant("sky_port_giant")
	if(which == "polish")
		sky_shoot_polish(H)
	if(which == "seams")
		sky_shoot_seams(H)
	if(which == "sharpness")
		sky_shoot_sharpness(H)
	if(which == "scaling")
		sky_shoot_scaling(H)
	if(which == "layers")
		sky_shoot_layers(H)
	if(which == "batch")
		sky_shoot_batch(H)
	if(which == "walk")
		sky_shoot_walk(H)

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
