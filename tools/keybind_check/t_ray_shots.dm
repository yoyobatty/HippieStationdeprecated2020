// Pictures of the T-ray view with a real client, before and after, plus a count of loose ends across the station and the view's cost.
// Not part of the game: HARNESS=t_ray_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh tray
// Pictures in data/previews/tray_*.png, numbers in data/keycheck_tray.txt. The "before" pictures are the old flash, which is still
// t_ray_scan(): caught in the 0.8 seconds of every 2 it showed. It cuts a cable and lays a dead run for the loose ends and the dead
// cables, stashes a satchel and a pressure plate, and checks a still view builds nothing and a walk misses nothing.
// With data/tray_probe present it also logs the emissive twins' settings and lights every tile round the viewer with a white emissive
// square in the dark: tiles that stay black are ones BYOND isn't drawing at all (see_in_dark), not ones the lighting covers.

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
			tray_shots_run(src)

/proc/tray_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/tray_hidden(obj/O)
	return O.level == 1 && (O.invisibility == INVISIBILITY_MAXIMUM || HAS_TRAIT(O, TRAIT_T_RAY_VISIBLE))

/// The floor with the most hidden cables, pipes and disposals round it, all three kinds if it can.
/proc/tray_pick_spot()
	var/turf/best
	var/best_score = -1
	var/looked = 0
	for(var/obj/structure/disposalpipe/P in world)
		if(!is_station_level(P.z) || !tray_hidden(P) || !istype(get_area(P), /area/hallway))
			continue
		var/turf/open/floor/T = P.loc
		if(!istype(T) || T.density || (locate(/obj/machinery) in T) || (locate(/obj/structure) in T) && !(locate(/obj/structure/disposalpipe) in T))
			continue
		if(++looked > 400)
			break
		var/cables = 0
		var/pipes = 0
		var/disposals = 0
		for(var/obj/O in range(6, T))
			if(!tray_hidden(O))
				continue
			if(istype(O, /obj/structure/cable))
				cables++
			else if(istype(O, /obj/machinery/atmospherics))
				pipes++
			else if(istype(O, /obj/structure/disposalpipe))
				disposals++
		var/score = (cables && 1000) + (pipes && 1000) + (disposals && 1000) + cables + pipes + disposals
		if(score > best_score)
			best_score = score
			best = T
	kc_log("spot [best] ([best?.x],[best?.y]) in [get_area(best)], score [best_score], [looked] looked at")
	return best

/// Loose ends over the whole station, to see how noisy the red dots are, with a few of each kind's places to check by eye.
/proc/tray_census()
	var/list/counts = list("cables" = 0, "pipes" = 0, "disposals" = 0)
	var/list/loose = list("cables" = 0, "pipes" = 0, "disposals" = 0)
	var/list/where = list("cables" = list(), "pipes" = list(), "disposals" = list())
	for(var/obj/O in world)
		if(!is_station_level(O.z) || O.level != 1 || !isturf(O.loc))
			continue
		var/kind = GLOB.t_ray_kinds[O.type]
		if(!(kind in counts))
			continue
		counts[kind]++
		var/ends = t_ray_loose_ends(O)
		if(ends)
			loose[kind]++
			var/list/places = where[kind]
			if(places.len < 12)
				places += "[O.type] ([O.x],[O.y]) [get_area(O)] ends=[ends][tray_hidden(O) ? " hidden" : ""]"
	for(var/kind in counts)
		kc_log("census [kind]: [counts[kind]] on the station, [loose[kind]] with a loose end")
		for(var/line in where[kind])
			kc_log("  [line]")

/proc/tray_image_text(image/I)
	return "plane [I.plane] layer [I.layer] alpha [I.alpha] color [I.color] blend [I.blend_mode] flags [I.appearance_flags] rt [I.render_target] rs [I.render_source] invis [I.invisibility] filters [length(I.filters)] icon [I.icon]:[I.icon_state] over [length(I.overlays)] under [length(I.underlays)] px [I.pixel_x],[I.pixel_y] vis [length(I.vis_contents)]"

/// Why some twins light the dark and some don't: their settings, then the dark shot again with each of them changed.
/proc/tray_probe(datum/t_ray_view/V)
	var/list/sampled = list()
	var/list/twins = list()
	for(var/atom/movable/thing as anything in V.shown)
		var/list/entry = V.shown[thing]
		var/key = "[thing.type] [entry[2]]"
		for(var/image/I in entry[4])
			if(I.plane == EMISSIVE_PLANE)
				twins += I
				if(!sampled[key])
					sampled[key] = TRUE
					kc_log("probe [key] at ([thing.x],[thing.y]) twin: [tray_image_text(I)]")
					kc_log("   source: plane [thing.plane] layer [thing.layer] flags [thing.appearance_flags] blend [thing.blend_mode] rt [thing.render_target] color [thing.color] over [length(thing.overlays)] under [length(thing.underlays)] vis [length(thing.vis_contents)]")
	// A white emissive square on every tile round the viewer: the tiles that stay dark show what's masking them
	var/turf/centre = get_turf(V.viewer)
	var/list/cards = list()
	for(var/turf/T in range(4, centre))
		var/image/card = image('icons/effects/alphacolors.dmi', T, "white")
		card.plane = EMISSIVE_PLANE
		cards += card
	V.viewer_client.images += cards
	sleep(10)
	tray_shot("tray_probe_1_cards")
	V.viewer_client.images -= cards
	kc_log("viewer see_in_dark [V.viewer.see_in_dark] with the view at range [V.range]")

/proc/tray_lights(turf/T, on)
	var/list/areas = list()
	for(var/turf/near in range(9, T))
		areas |= get_area(near)
	for(var/area/A as anything in areas)
		A.lightswitch = on
		A.power_change()

/proc/tray_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	tray_census()
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1, which gives up three minutes on
	var/turf/spot = tray_pick_spot()
	var/mob/living/carbon/human/H = new(spot)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/engineer)
	H.ckey = C.ckey
	sleep(3 SECONDS)

	// Something stashed under the floor, a hidden pressure plate, and a cut cable for loose ends and a dead run
	var/list/floors = list()
	for(var/turf/open/floor/F in range(4, spot))
		if(F != spot && F.intact && !(locate(/obj/structure) in F) && !(locate(/obj/machinery) in F))
			floors += F
	if(floors.len >= 2)
		var/turf/stash_at = floors[1]
		var/obj/item/storage/backpack/satchel/flat/S = new(stash_at)
		S.hide(TRUE)
		var/obj/item/pressure_plate/plate = new(floors[floors.len])
		plate.hide(TRUE)
		kc_log("satchel at ([stash_at.x],[stash_at.y]), plate at ([plate.x],[plate.y])")
	var/obj/structure/cable/cut
	for(var/obj/structure/cable/K in range(4, spot))
		if(tray_hidden(K) && K.linked_dirs && (K.linked_dirs & (K.linked_dirs - 1)) && K.powernet?.avail && get_dist(K, spot) >= 2)
			cut = K
			break
	if(cut)
		kc_log("cutting the cable at ([cut.x],[cut.y])")
		cut.deconstruct()
	// A dead run: three layer-one cables a row in front, which join nothing that has power
	var/list/dead_run = list()
	for(var/dx in -1 to 1)
		var/turf/open/floor/F = locate(spot.x + dx, spot.y + 2, spot.z)
		if(istype(F) && F.intact)
			dead_run += new /obj/structure/cable/layer1(F)
	kc_log("dead run of [dead_run.len] at y [spot.y + 2]")
	sleep(2 SECONDS)

	// Before: the old flash, from the handheld (range 3) and the goggles (range 1)
	t_ray_scan(H, 8, 3)
	sleep(2)
	tray_shot("tray_before_1_scanner_lit")
	sleep(10)
	t_ray_scan(H, 8, 1)
	sleep(2)
	tray_shot("tray_before_2_goggles_lit")
	sleep(10)
	tray_lights(spot, FALSE)
	sleep(2 SECONDS)
	t_ray_scan(H, 8, 3)
	sleep(2)
	tray_shot("tray_before_3_scanner_dark")
	sleep(10)
	tray_lights(spot, TRUE)
	sleep(2 SECONDS)

	// After: the scanner held and switched on
	var/obj/item/t_scanner/scanner = new(spot)
	H.put_in_hands(scanner)
	scanner.attack_self(H)
	sleep(25)
	var/datum/t_ray_view/V = GLOB.t_ray_views[H]
	kc_log("view [V ? "up" : "missing"]: range [V?.range], [length(V?.shown)] things shown, [length(C.images)] client images")
	tray_shot("tray_after_1_scanner_lit")
	// Standing still for 3 seconds builds nothing new, and a look costs this much
	var/built_before = V?.built
	var/list/snapshot = list()
	for(var/thing in V?.shown)
		var/list/entry = V.shown[thing]
		snapshot[thing] = entry.Copy(1, 4)
	sleep(3 SECONDS)
	kc_log("standing still: [V ? V.built - built_before : "?"] images built in 3 s (should be 0)")
	for(var/atom/thing as anything in snapshot)
		var/list/before = snapshot[thing]
		var/list/after = V.shown[thing]
		if(!after)
			kc_log("  gone: [thing.type] ([thing.x],[thing.y])")
		else if(before[1] != after[1] || before[2] != after[2] || before[3] != after[3])
			var/obj/structure/cable/K = thing
			kc_log("  changed: [thing.type] ([thing.x],[thing.y]) state [before[2]] -> [after[2]], appearance [before[1] != after[1] ? "changed" : "same"][istype(K) ? ", powernet avail [K.powernet?.avail] view [K.powernet?.viewavail]" : ""]")
	if(V)
		var/turf/centre = get_turf(H)
		var/n = 0
		var/tick_before = TICK_USAGE_REAL
		for(var/i in 1 to 50)
			for(var/obj/O in range(V.range, centre))
				if(O.level == 1)
					n++
		var/cost_range = TICK_USAGE_TO_MS(tick_before) / 50
		tick_before = TICK_USAGE_REAL
		for(var/i in 1 to 50)
			for(var/obj/O in range(V.range, centre))
				if(O.level != 1)
					continue
				var/kind = GLOB.t_ray_kinds[O.type]
				if(O.invisibility == INVISIBILITY_MAXIMUM || HAS_TRAIT(O, TRAIT_T_RAY_VISIBLE))
					n += kind ? 1 : 0
		var/cost_checks = TICK_USAGE_TO_MS(tick_before) / 50
		tick_before = TICK_USAGE_REAL
		for(var/i in 1 to 50)
			for(var/obj/O in range(V.range, centre))
				if(O.level != 1)
					continue
				var/kind = GLOB.t_ray_kinds[O.type]
				if(kind)
					n += t_ray_loose_ends(O)
		var/cost_ends = TICK_USAGE_TO_MS(tick_before) / 50
		tick_before = TICK_USAGE_REAL
		for(var/i in 1 to 50)
			V.look()
		var/cost = TICK_USAGE_TO_MS(tick_before) / 50
		var/turf/east = get_step(centre, EAST)
		tick_before = TICK_USAGE_REAL
		for(var/i in 1 to 25)
			V.look_edge(centre, east)
			V.look_edge(east, centre)
		var/cost_step = TICK_USAGE_TO_MS(tick_before) / 50
		V.look()
		kc_log("a step's look: [round(cost_step * 1000, 1)] us")
		var/objs = 0
		var/level_one = 0
		for(var/obj/O in range(V.range, centre))
			objs++
			if(O.level == 1)
				level_one++
		kc_log("a look at range [V.range] with [length(V.shown)] things: [round(cost * 1000, 1)] us; range() walk alone [round(cost_range * 1000, 1)] us, with the checks [round(cost_checks * 1000, 1)] us, with loose ends [round(cost_ends * 1000, 1)] us; [objs] objs in range, [level_one] underfloor")
	tray_lights(spot, FALSE)
	sleep(2 SECONDS)
	tray_shot("tray_after_2_scanner_dark")
	if(fexists("data/tray_probe") && V)
		tray_probe(V)
	tray_lights(spot, TRUE)
	sleep(2 SECONDS)
	// Each filter
	for(var/i in 1 to 3)
		scanner.cycle_t_ray_filter(H)
		sleep(5)
		tray_shot("tray_after_[2 + i]_filter_[scanner.t_ray_filter]")
	scanner.cycle_t_ray_filter(H) // back to everything
	// Walking: the view keeps up
	var/built_walk = V?.built
	for(var/i in 1 to 3)
		H.Move(get_step(H, EAST), EAST)
		sleep(3)
	kc_log("walked 3 east: [V ? V.built - built_walk : "?"] images built, [length(V?.shown)] things shown")
	if(V)
		var/shown_walking = length(V.shown)
		var/built_full = V.built
		V.look()
		kc_log("full look after the walk: [length(V.shown)] things shown (walking had [shown_walking]), [V.built - built_full] images built (should be 0)")
	tray_shot("tray_after_6_walked")
	for(var/i in 1 to 3)
		H.Move(get_step(H, WEST), WEST)
		sleep(3)
	// Off: everything goes
	scanner.attack_self(H)
	sleep(5)
	kc_log("scanner off: view [GLOB.t_ray_views[H] ? "still up" : "gone"], [length(C.images)] client images")

	// The engineering goggles in T-ray mode
	var/obj/item/clothing/glasses/meson/engine/goggles = new(spot)
	H.equip_to_slot_or_del(goggles, ITEM_SLOT_EYES)
	goggles.toggle_mode(H, TRUE)
	goggles.toggle_mode(H, TRUE)
	sleep(25)
	kc_log("goggles mode [goggles.mode]: view range [GLOB.t_ray_views[H]?.range]")
	tray_shot("tray_after_7_goggles")
	goggles.toggle_mode(H, TRUE)
	sleep(5)
	kc_log("goggles mode [goggles.mode]: view [GLOB.t_ray_views[H] ? "still up" : "gone"]")

	// An engineering hardsuit helmet's T-ray, in the dark
	var/obj/item/clothing/suit/space/hardsuit/engine/suit = new(spot)
	qdel(H.head) // the outfit's hard hat and hazard vest
	qdel(H.wear_suit)
	H.equip_to_slot_or_del(suit, ITEM_SLOT_OCLOTHING)
	suit.ToggleHelmet()
	var/obj/item/clothing/head/helmet/space/hardsuit/engine/helmet = H.head
	if(istype(helmet))
		for(var/datum/action/item_action/toggle_t_ray/A in helmet.actions)
			A.Trigger()
		sleep(25)
		kc_log("helmet T-ray [helmet.t_ray_on]: view range [GLOB.t_ray_views[H]?.range], [length(helmet.actions)] helmet buttons")
		tray_lights(spot, FALSE)
		sleep(2 SECONDS)
		tray_shot("tray_after_8_helmet_dark")
	else
		kc_log("no helmet came up: [H.head]")

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
