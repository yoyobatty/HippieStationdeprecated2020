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

	// Anchored far south; an overlay scaled about the anchor stretches its bounds back over the screen, the light overlay is moved
	// back to the target. One picture shows which get drawn.
	//      name, colour, dx, dy, anchor distance, how the light is moved back, stretcher alpha
	var/list/tests = list(
		list("control: on its tile", "#ff8000", -6, 0, 0, "none", 0),
		list("I stretcher a0, transform, 16", "#ff0000", -6, -5, 16, "transform", 0),
		list("J stretcher a0, pixel_y, 16", "#00ff00", -4, -5, 16, "pixel", 0),
		list("K stretcher a1, transform, 16", "#0000ff", -2, -5, 16, "transform", 1),
		list("M stretcher a0, transform, 32", "#ffff00", -6, 5, 32, "transform", 0),
		list("N stretcher a0, pixel_y, 32", "#ff00ff", -4, 5, 32, "pixel", 0),
		list("O no stretcher, transform, 32", "#00ffff", -2, 5, 32, "transform", -1))
	for(var/list/t in tests)
		var/turf/target = locate(P.x + t[3], P.y + t[4], P.z)
		var/obj/effect/lsp_test/S = new(locate(target.x, target.y - t[5], P.z))
		S.icon = null
		var/back = t[5] * world.icon_size
		if(t[7] >= 0)
			var/mutable_appearance/stretch = mutable_appearance('icons/effects/alphacolors.dmi', "white")
			stretch.alpha = t[7]
			stretch.appearance_flags = RESET_ALPHA | RESET_COLOR
			stretch.transform = matrix(2 * (t[5] + 2), 0, 0, 0, 2 * (t[5] + 2), 0)
			S.add_overlay(stretch)
		var/mutable_appearance/lit = mutable_appearance('icons/effects/alphacolors.dmi', "white")
		lit.color = t[2]
		lit.blend_mode = BLEND_ADD
		lit.appearance_flags = RESET_ALPHA | RESET_COLOR
		if(t[6] == "pixel")
			lit.pixel_y = back
			lit.transform = matrix(1.5, 0, 0, 0, 1.5, 0)
		else
			lit.transform = matrix(1.5, 0, 0, 0, 1.5, back)
		S.add_overlay(lit)
		lsp_log("[t[1]] [t[2]] at [target.x],[target.y], anchor [S.x],[S.y]")
	sleep(3 SECONDS)
	lsp_shot("lsp_anchor_3_stretch")
	lsp_log("done")

#undef LSP_ANCHOR
