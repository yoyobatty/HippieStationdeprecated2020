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

	// Anchored far off. The object is drawn at full alpha but adds nothing: a transparent icon state, or black added. Its own
	// transform stretches its bounds about the anchor; the light overlay undoes that and moves back to the target.
	//      name, colour, dx, dy, anchor dx, anchor dy, main look
	var/list/tests = list(
		list("control: on its tile", "#ff8000", -6, 0, 0, 0, "transparent"),
		list("V transparent, 16 south", "#ff0000", -6, -5, 0, -16, "transparent"),
		list("W transparent, 32 south", "#00ff00", -4, -5, 0, -32, "transparent"),
		list("X black added, 16 south", "#0000ff", -2, -5, 0, -16, "black"),
		list("Y black added, 32 south", "#ffff00", -6, 5, 0, -32, "black"),
		list("Z transparent, 24 east", "#ff00ff", -4, 5, 24, 0, "transparent"),
		list("AA black added, 24 east", "#00ffff", -2, 5, 24, 0, "black"))
	for(var/list/t in tests)
		var/turf/target = locate(P.x + t[3], P.y + t[4], P.z)
		var/obj/effect/lsp_test/S = new(locate(target.x + t[5], target.y + t[6], P.z))
		if(t[7] == "transparent")
			S.icon = 'icons/effects/lighting_object.dmi'
			S.icon_state = "transparent"
		else
			S.color = "#000000"
		var/far = max(abs(t[5]), abs(t[6]))
		var/stretch_by = 2 * (far + 2)
		S.transform = matrix(stretch_by, 0, 0, 0, stretch_by, 0)
		var/mutable_appearance/lit = mutable_appearance('icons/effects/alphacolors.dmi', "white")
		lit.color = t[2]
		lit.blend_mode = BLEND_ADD
		lit.appearance_flags = RESET_ALPHA | RESET_COLOR | RESET_TRANSFORM
		lit.transform = matrix(1.5, 0, -t[5] * world.icon_size, 0, 1.5, -t[6] * world.icon_size)
		S.add_overlay(lit)
		lsp_log("[t[1]] [t[2]] at [target.x],[target.y], anchor [S.x],[S.y]")
	sleep(3 SECONDS)
	lsp_shot("lsp_anchor_5_visible_main")
	lsp_log("done")

#undef LSP_ANCHOR
