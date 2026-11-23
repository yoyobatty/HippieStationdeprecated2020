// Spike: does BYOND draw a big sprite whose own turf the player can't see, where its picture reaches tiles they can see?
// HARNESS=spike_visibility.dm MAP=testbench tools/light_sprites/run.sh spike

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

/proc/lsp_spike(client/C)
	fdel("data/keycheck_shot")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	text2file("go", "data/keycheck_sendkeys")
	// A clear stretch: a floor with floors for 12 tiles each way, made so
	var/turf/start = get_turf(pick(SSjob.latejoin_trackers))
	var/turf/P = locate(start.x, start.y, start.z)
	for(var/turf/T in block(locate(P.x - 10, P.y - 8, P.z), locate(P.x + 16, P.y + 8, P.z)))
		T.ChangeTurf(/turf/open/floor/plasteel)
		for(var/atom/movable/A in T)
			if(!ismob(A) && !istype(A, /atom/movable/lighting_object))
				qdel(A)
	// A wall three tiles east, top to bottom of the screen
	for(var/dy in -8 to 8)
		var/turf/W = locate(P.x + 3, P.y + dy, P.z)
		W.ChangeTurf(/turf/closed/wall/r_wall)
	var/mob/living/carbon/human/H = new(P)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(2 SECONDS)
	H.hud_used.show_hud(HUD_STYLE_NOHUD)
	lsp_log("hwmode [winget(C, null, "hwmode")], view [C.view], at [P.x],[P.y],[P.z]")
	sleep(2 SECONDS)
	lsp_shot("lsp_spike_0_plain")

	// 1: red, its turf behind the wall (6 east), scaled to 11 tiles: reaches the two columns in front of the wall
	var/obj/effect/lsp_test/red = new(locate(P.x + 6, P.y, P.z))
	red.color = "#ff0000"
	red.transform = matrix(11, 0, 0, 0, 11, 0)
	// control: green, on a tile the player can see, scaled to 3
	var/obj/effect/lsp_test/green = new(locate(P.x - 4, P.y - 3, P.z))
	green.color = "#00ff00"
	green.transform = matrix(3, 0, 0, 0, 3, 0)
	sleep(2 SECONDS)
	lsp_log("1: red behind the wall seen by the player: [(red in view(H))], its turf [(get_turf(red) in view(H))]")
	lsp_shot("lsp_spike_1_behind_wall")

	// 2: the same with TILE_BOUND: should vanish if it's the visual bounds that let it through
	red.appearance_flags |= TILE_BOUND
	sleep(2 SECONDS)
	lsp_shot("lsp_spike_2_tile_bound")
	red.appearance_flags &= ~TILE_BOUND

	// 3: off the screen: turf 14 east (beyond the wall too), scaled to 25 so it reaches back to the player's side
	red.forceMove(locate(P.x + 14, P.y, P.z))
	red.transform = matrix(25, 0, 0, 0, 25, 0)
	sleep(2 SECONDS)
	lsp_shot("lsp_spike_3_offscreen")

	// 4: a big icon instead of a transform: the screen-sized transparent sheet with the red as its overlay
	red.transform = null
	red.icon = 'icons/effects/alphacolors.dmi'
	red.icon_state = "white"
	red.color = null
	var/mutable_appearance/inner = mutable_appearance('icons/effects/alphacolors.dmi', "white")
	inner.color = "#0000ff"
	inner.transform = matrix(25, 0, 0, 0, 25, 0)
	inner.blend_mode = BLEND_ADD
	inner.appearance_flags = RESET_ALPHA | RESET_COLOR
	red.alpha = 0
	red.add_overlay(inner)
	sleep(2 SECONDS)
	lsp_shot("lsp_spike_4_overlay_scaled")
	lsp_log("done")
