// Pictures of floor depth (floor_depth.dm) with a real client: holes where tiles came off, flat, at three depths smoothed and
// crisp, and a picture a step walking past the pit.
// Not part of the game: HARNESS=floor_depth_shots.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh depth
// Pictures in data/previews/depth_*.png, notes in data/keycheck_depth.txt. tools/keybind_check/floor_depth_sheet.py makes the
// side-by-side sheet and the walking GIFs from them.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(depth_entered, 0)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/turf/open/floor/plating/Entered(atom/movable/AM)
	if(floor_sunken)
		GLOB.depth_entered++
	return ..()

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			depth_shots_run(src)

/proc/depth_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/depth_tiled(turf/T)
	var/turf/open/floor/F = T
	return istype(F) && !istype(F, /turf/open/floor/plating) && F.floor_tile && !F.density && !(locate(/obj/structure) in F) && !(locate(/obj/machinery) in F)

/// A tiled room big enough to stand in the middle of, with things under its floor
/proc/depth_pick_spot()
	var/turf/best
	var/best_score = -1
	for(var/turf/open/floor/F in world)
		if(!is_station_level(F.z) || !depth_tiled(F))
			continue
		var/tiled = 0
		var/under = 0
		for(var/turf/T in range(4, F))
			if(depth_tiled(T))
				tiled++
			for(var/obj/O in T)
				if(O.level == 1)
					under++
		var/score = tiled * (under >= 4 ? 10 : 1) + min(under, 30)
		if(score > best_score)
			best_score = score
			best = F
	kc_log("spot [best] ([best?.x],[best?.y]) in [get_area(best)], score [best_score]")
	return best

/proc/depth_pull(turf/open/floor/F, list/holes)
	if(!istype(F) || istype(F, /turf/open/floor/plating) || !F.floor_tile || F.density) // cables and pipes under it are fine
		return
	var/turf/open/floor/plating/P = F.remove_tile(null, TRUE, FALSE)
	if(istype(P))
		holes += P

/proc/depth_set(client/C, on)
	if(on)
		C.prefs.hippie_toggles &= ~FLOOR_DEPTH_DISABLED
	else
		C.prefs.hippie_toggles |= FLOOR_DEPTH_DISABLED
	var/obj/screen/plane_master/floor_depth_draw/PM = C.mob.hud_used?.plane_masters["[FLOOR_DEPTH_DRAW_PLANE]"]
	PM?.backdrop(C.mob)
	sleep(5)

GLOBAL_LIST_EMPTY(depth_current)

/// The tiles showing what's under them, against the counters
/proc/depth_log_unders(when)
	floor_depth_flush() // the pictures are settled a moment after the changes
	var/unders = 0
	var/copies = 0
	var/holes = 0
	for(var/turf/T in world)
		if(T.floor_sunken)
			holes++
		if(T.floor_under)
			unders++
			copies += length(T.floor_under)
	kc_log("[when]: [holes] holes (counter [GLOB.floor_depth_holes]), [unders] tiles showing what's under them (counter [GLOB.floor_depth_unders]) with [copies] hidden things copied")

/// The depth drawn with these settings in place of the game's own relays
/proc/depth_use(client/C, scale, crisp)
	C.screen -= GLOB.floor_depth_relays
	C.screen -= GLOB.depth_current
	GLOB.depth_current = make_floor_depth_relays(scale, crisp)
	C.screen += GLOB.depth_current
	sleep(5)

/proc/depth_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1, which gives up three minutes on
	kc_log("hwmode [winget(C, null, "hwmode")]")
	var/turf/spot = depth_pick_spot()
	var/mob/living/carbon/human/H = new(spot)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/engineer)
	H.ckey = C.ckey
	H.status_flags |= GODMODE
	sleep(3 SECONDS)

	// Holes: a 2x2 pit over whatever runs under the floor 3-5 tiles off, one tile down and left near the edge, one beside the
	// viewer, one against a wall
	var/list/holes = list()
	var/turf/pit_at = locate(spot.x + 3, spot.y + 2, spot.z)
	for(var/turf/T in range(5, spot))
		if(get_dist(T, spot) >= 3 && depth_tiled(T) && T.x > spot.x && (locate(/obj/structure/cable) in T))
			pit_at = T
			break
	kc_log("pit at ([pit_at.x],[pit_at.y]), [pit_at.x - spot.x],[pit_at.y - spot.y] from the viewer")
	// A cable run across the pit and a disposal pipe up through it, under the tiles until they come off
	for(var/dx in -2 to 3)
		var/turf/T = locate(pit_at.x + dx, pit_at.y, spot.z)
		if(depth_tiled(T))
			new /obj/structure/cable/layer1(T)
	for(var/dy in -2 to 3)
		var/turf/T = locate(pit_at.x + 1, pit_at.y + dy, spot.z)
		if(depth_tiled(T) || (locate(/obj/structure/cable) in T))
			var/obj/structure/disposalpipe/segment/D = new(T)
			D.setDir(NORTH)
			D.update_icon()
	for(var/dx in 0 to 1)
		for(var/dy in 0 to 1)
			depth_pull(locate(pit_at.x + dx, pit_at.y + dy, spot.z), holes)
	depth_pull(locate(spot.x - 5, spot.y - 3, spot.z), holes)
	depth_pull(locate(spot.x + 1, spot.y - 1, spot.z), holes)
	for(var/turf/open/floor/F in range(6, spot))
		var/turf/north = get_step(F, NORTH)
		if(get_dist(F, spot) >= 3 && depth_tiled(F) && iswallturf(north))
			depth_pull(F, holes)
			kc_log("hole against a wall at ([F.x],[F.y])")
			break
	var/sunk_turfs = 0
	for(var/turf/T in holes)
		if(T.floor_sunken && T.plane == FLOOR_DEPTH_PLANE)
			sunk_turfs++
	kc_log("[holes.len] holes, [sunk_turfs] sunken on the depth plane")
	// Blood made down in the pit: does Entered() run for something made in place?
	var/entered_before = GLOB.depth_entered
	var/obj/effect/decal/cleanable/blood/B = new(holes[1])
	kc_log("blood made in a hole: Entered() ran [GLOB.depth_entered - entered_before] times, its plane [B.plane] (depth plane [FLOOR_DEPTH_PLANE])")
	var/list/kinds = list()
	for(var/turf/T in holes)
		for(var/obj/O in T)
			kinds["[O.type] plane [O.plane] invis [O.invisibility]"]++
	for(var/k in kinds)
		kc_log("  in the holes: [k] x[kinds[k]]")
	depth_log_unders("with the holes made")
	for(var/turf/T in range(3, holes[1]))
		for(var/obj/effect/abstract/floor_depth_under/U as anything in T.floor_under)
			kc_log("  under the tile at ([T.x],[T.y]): [U.icon]:[U.icon_state] dir [U.dir] color [U.color] px [U.pixel_x],[U.pixel_y] plane [U.plane]")
		for(var/obj/O in T)
			if(O.level == 1 && O.invisibility == INVISIBILITY_MAXIMUM && T.floor_under)
				kc_log("    hidden there: [O.type] '[O.name]' dir [O.dir]")
	sleep(2 SECONDS)

	if(fexists("data/depth_dir_probe")) // does a copy of a hidden east-west pipe stay east-west? four ways, drawn above the floor
		var/obj/machinery/atmospherics/pipe/simple/pipe
		for(var/obj/machinery/atmospherics/pipe/simple/P in range(6, spot))
			if(P.invisibility == INVISIBILITY_MAXIMUM && (P.dir == EAST || P.dir == WEST))
				pipe = P
				break
		kc_log("probe pipe [pipe] at ([pipe?.x],[pipe?.y]) dir [pipe?.dir] state [pipe?.icon_state]")
		if(pipe)
			var/list/ways = list("underlay", "overlay", "vis_contents", "underlay_redir")
			for(var/i in 1 to ways.len)
				var/turf/T = locate(spot.x - 4 + i, spot.y + 1, spot.z)
				var/mutable_appearance/copy = new(pipe)
				copy.plane = GAME_PLANE
				copy.invisibility = 0
				copy.alpha = 255
				copy.layer = ABOVE_OPEN_TURF_LAYER
				switch(ways[i])
					if("underlay")
						T.underlays += copy
						var/mutable_appearance/back = T.underlays[T.underlays.len]
						kc_log("  [ways[i]] at ([T.x],[T.y]), turf dir [T.dir]: copy dir [copy.dir], stored dir [back.dir]")
					if("overlay")
						T.add_overlay(copy)
						kc_log("  [ways[i]] at ([T.x],[T.y]), turf dir [T.dir]: copy dir [copy.dir]")
					if("vis_contents")
						var/obj/effect/abstract/holder = new(null)
						holder.appearance = copy
						T.vis_contents += holder
						kc_log("  [ways[i]] at ([T.x],[T.y]), turf dir [T.dir]: holder dir [holder.dir]")
					if("underlay_redir")
						copy.dir = pipe.dir
						T.underlays += copy
						kc_log("  [ways[i]] at ([T.x],[T.y]), turf dir [T.dir]: copy dir [copy.dir]")
			sleep(1 SECONDS)
			depth_shot("depth_dir_probe")

	depth_set(C, FALSE)
	depth_shot("depth_0_off")
	depth_set(C, TRUE)
	// Each depth, smoothed and crisp, from where the viewer stands
	var/list/depths = list("shallow" = list(0.9875), "medium" = list(FLOOR_DEPTH_SCALE), "deep" = list(0.958))
	for(var/name in depths)
		var/list/D = depths[name]
		for(var/crisp in 0 to 1)
			depth_use(C, D[1], crisp)
			depth_shot("depth_[name]_[crisp ? "crisp" : "soft"]")
	// The spinning drugs turn the world's plane masters: which of ours have to turn with them for the holes to stay put?
	// a: the depth and mask planes (if render targets carry their plane master's turn); b: the drawing and shadow too
	depth_use(C, FLOOR_DEPTH_SCALE, TRUE)
	var/list/world_pms = list()
	for(var/p in list(FLOOR_PLANE, GAME_PLANE, LIGHTING_PLANE, FLOOR_DEPTH_PLANE, FLOOR_DEPTH_MASK_PLANE))
		world_pms += C.mob.hud_used.plane_masters["[p]"]
	var/list/draw_pms = list(C.mob.hud_used.plane_masters["[FLOOR_DEPTH_DRAW_PLANE]"], C.mob.hud_used.plane_masters["[FLOOR_DEPTH_SHADOW_PLANE]"])
	for(var/obj/screen/plane_master/PM as anything in world_pms)
		PM.transform = matrix(20, MATRIX_ROTATE)
	sleep(5)
	depth_shot("depth_rot_a")
	for(var/obj/screen/plane_master/PM as anything in draw_pms)
		PM.transform = matrix(20, MATRIX_ROTATE)
	sleep(5)
	depth_shot("depth_rot_b")
	for(var/obj/screen/plane_master/PM as anything in world_pms + draw_pms)
		PM.transform = matrix()
	sleep(5)
	// Walking past the pit, a picture a step (data/previews/depth_walk_<depth>_<n>.png), for floor_depth_sheet.py's GIFs
	for(var/i in 1 to 3)
		H.Move(get_step(H, WEST), WEST)
		sleep(4)
	for(var/name in list("medium")) // the game's own setting
		var/list/D = depths[name]
		depth_use(C, D[1], TRUE)
		depth_shot("depth_walk_[name]_0")
		for(var/i in 1 to 8)
			H.Move(get_step(H, EAST), EAST)
			sleep(5)
			depth_shot("depth_walk_[name]_[i]")
		for(var/i in 1 to 8)
			H.Move(get_step(H, WEST), WEST)
			sleep(2)
		sleep(5)
	kc_log("walk ended at ([H.x],[H.y])")
	C.screen -= GLOB.depth_current
	depth_set(C, TRUE)

	// A tile back on the pit: it comes up again, with what was down there
	var/turf/open/floor/plating/P = holes[1]
	var/turf/open/floor/W = P.PlaceOnTop(/turf/open/floor/plasteel, flags = CHANGETURF_INHERIT_AIR)
	floor_depth_flush()
	var/still_down = 0
	for(var/atom/movable/AM in W)
		if(AM.plane == FLOOR_DEPTH_PLANE)
			still_down++
	kc_log("tile back on: turf plane [W.plane] sunken [W.floor_sunken], [still_down] things still on the depth plane, its own under-picture [length(W.floor_under)] (beside 3 holes)")
	depth_log_unders("after the tile went back on")
	// Every tile back on: nothing left showing what's under it
	for(var/turf/open/floor/plating/hole in holes)
		if(hole.floor_sunken)
			hole.PlaceOnTop(/turf/open/floor/plasteel, flags = CHANGETURF_INHERIT_AIR)
	depth_log_unders("with every tile back on")

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
