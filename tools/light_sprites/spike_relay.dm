// Spike 2: a sprite anchored far away (off every nearby screen) and pulled back with pixel_y. Is it drawn? And what do
// thousands of them cost SendMaps?   HARNESS=spike_anchor.dm MAP=testbench tools/light_sprites/run.sh anchor

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

GLOBAL_VAR_INIT(lsp_running, FALSE)

/proc/lsp_log(text)
	text2file(text, "data/keycheck.txt")

/proc/lsp_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/client/New()
	. = ..()
	if(. && !GLOB.lsp_running)
		GLOB.lsp_running = TRUE
		spawn(50)
			lsp_spike(src)

/obj/effect/lsp_test
	name = ""
	icon = 'icons/effects/alphacolors.dmi'
	icon_state = "white"
	plane = LIGHTING_PLANE
	layer = LIGHTING_LAYER + 1
	blend_mode = BLEND_ADD
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE

/// SendMaps' figures: name = list(value, calls)
/proc/lsp_sendmaps()
	. = list()
	var/raw = world.Profile(PROFILE_REFRESH, "sendmaps", "json")
	if(!istext(raw) || findtext(raw, "\[") != 1)
		return
	for(var/list/R in json_decode(raw))
		.["[R["name"]]"] = list(R["value"], R["calls"], R["unit"])

/// SendMaps over `seconds`, per tick
/proc/lsp_measure(label, seconds)
	var/list/before = lsp_sendmaps()
	var/t0 = world.time
	sleep(seconds SECONDS)
	var/list/after = lsp_sendmaps()
	var/ticks = (world.time - t0) / world.tick_lag
	lsp_log("[label]: [ticks] ticks")
	for(var/name in after)
		var/list/A = after[name]
		var/list/B = before[name] || list(0, 0)
		var/dv = A[1] - B[1]
		var/dc = A[2] - B[2]
		if(!dv && !dc)
			continue
		lsp_log("  [name]: [A[3] == "s" ? "[round(dv / ticks * 1e6, 0.1)] us" : "[round(dv / ticks, 0.1)]"]/tick, calls [round(dc / ticks, 0.01)]/tick")

#define LSP_ANCHOR 32

/proc/lsp_spike(client/C)
	fdel("data/keycheck_shot")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	text2file("go", "data/keycheck_sendkeys")
	world.Profile(PROFILE_START, "sendmaps")
	var/turf/start = get_turf(pick(SSjob.latejoin_trackers))
	var/turf/P = locate(start.x, start.y, start.z)
	for(var/turf/T in block(locate(P.x - 10, P.y - 8, P.z), locate(P.x + 16, P.y + 8, P.z)))
		T.ChangeTurf(/turf/open/floor/plasteel)
		for(var/atom/movable/A in T)
			if(!ismob(A) && !istype(A, /atom/movable/lighting_object))
				qdel(A)
	for(var/dy in -8 to 8)
		var/turf/W = locate(P.x + 3, P.y + dy, P.z)
		W.ChangeTurf(/turf/closed/wall/r_wall)
	var/mob/living/carbon/human/H = new(P)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(2 SECONDS)
	H.hud_used.show_hud(HUD_STYLE_NOHUD)
	lsp_log("hwmode [winget(C, null, "hwmode")], view [C.view], at [P.x],[P.y],[P.z], world [world.maxx]x[world.maxy]x[world.maxz]")

	// The relay: a holder on the player's own turf, its pixel offset back to the map's corner (1,1); a chunk object in its
	// vis_contents; light sprites in the chunk's, in nullspace, each offset to its world tile from (1,1).
	var/atom/movable/holder = new /obj/effect/lsp_test(P)
	holder.icon = null
	holder.animate_movement = NO_STEPS
	holder.pixel_x = (1 - P.x) * world.icon_size
	holder.pixel_y = (1 - P.y) * world.icon_size
	var/atom/movable/chunk = new /obj/effect/lsp_test(null)
	chunk.icon = null
	holder.vis_contents += chunk
	//      name, colour, dx, dy
	var/list/tests = list(
		list("in view", "#ff8000", -6, 0),
		list("behind the wall (4 east), scaled 7", "#ff0000", 6, 0),
		list("off screen (14 east), scaled 25", "#00ff00", 14, 3),
		list("far south (20), scaled 33", "#0000ff", -4, -20))
	var/list/scales = list(1.5, 7, 25, 33)
	var/i = 0
	for(var/list/t in tests)
		i++
		var/obj/effect/lsp_test/S = new(null)
		S.color = t[2]
		S.alpha = 120
		S.pixel_x = (P.x + t[3] - 1) * world.icon_size
		S.pixel_y = (P.y + t[4] - 1) * world.icon_size
		S.transform = matrix(scales[i], 0, 0, 0, scales[i], 0)
		chunk.vis_contents += S
		lsp_log("[t[1]] [t[2]] at [P.x + t[3]],[P.y + t[4]]")
	sleep(3 SECONDS)
	lsp_shot("lsp_relay_1")
	// The player walks 3 east and 2 north; the holder follows a moment later: nothing should jump
	for(var/step in list(EAST, EAST, NORTH, EAST, NORTH))
		step(H, step)
		sleep(3)
	lsp_shot("lsp_relay_2_moved_holder_left_behind")
	holder.loc = get_turf(H)
	holder.pixel_x = (1 - H.x) * world.icon_size
	holder.pixel_y = (1 - H.y) * world.icon_size
	sleep(1 SECONDS)
	lsp_shot("lsp_relay_3_holder_caught_up")
	lsp_log("done")

#undef LSP_ANCHOR
