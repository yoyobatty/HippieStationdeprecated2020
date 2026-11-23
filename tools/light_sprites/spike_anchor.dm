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

	// 1: red behind the wall, anchored 32 south (or north near the bottom edge) and pulled back
	var/dir_y = P.y - LSP_ANCHOR >= 1 ? -1 : 1
	var/obj/effect/lsp_test/red = new(locate(P.x + 6, P.y + dir_y * LSP_ANCHOR, P.z))
	red.color = "#ff0000"
	red.pixel_y = -dir_y * LSP_ANCHOR * world.icon_size
	red.transform = matrix(11, 0, 0, 0, 11, 0)
	sleep(2 SECONDS)
	lsp_shot("lsp_anchor_1_far_anchor")
	qdel(red)
	sleep(1 SECONDS)

	// 2: SendMaps, nothing added
	lsp_measure("plain", 15)
	// 3: 3000 far-anchored sprites, 15 tiles across, scattered over the level
	var/list/made = list()
	for(var/i in 1 to 3000)
		var/x = rand(1, world.maxx)
		var/y = rand(1, world.maxy)
		var/ay = y - LSP_ANCHOR >= 1 ? y - LSP_ANCHOR : y + LSP_ANCHOR
		var/obj/effect/lsp_test/S = new(locate(x, ay, P.z))
		S.color = rgb(rand(0, 40), rand(0, 40), rand(0, 40))
		S.pixel_y = (y - ay) * world.icon_size
		S.transform = matrix(15, 0, 0, 0, 15, 0)
		made += S
	sleep(3 SECONDS)
	lsp_measure("3000 far-anchored", 15)
	// 4: the same 3000 on their own turfs (no offset), for comparison
	for(var/obj/effect/lsp_test/S as anything in made)
		var/y = S.y + S.pixel_y / world.icon_size
		S.pixel_y = 0
		S.forceMove(locate(S.x, y, S.z))
	sleep(3 SECONDS)
	lsp_measure("3000 on their own turfs", 15)
	// 5: 300 far-anchored (closer to a station's lamps in view at once is a few dozen; the level has ~1000-3000 in all)
	for(var/i in 1 to 2700)
		qdel(made[i])
	made.Cut(1, 2701)
	for(var/obj/effect/lsp_test/S as anything in made)
		var/ay = S.y - LSP_ANCHOR >= 1 ? S.y - LSP_ANCHOR : S.y + LSP_ANCHOR
		S.pixel_y = (S.y - ay) * world.icon_size
		S.forceMove(locate(S.x, ay, S.z))
	sleep(3 SECONDS)
	lsp_measure("300 far-anchored", 15)
	lsp_log("done")

#undef LSP_ANCHOR
