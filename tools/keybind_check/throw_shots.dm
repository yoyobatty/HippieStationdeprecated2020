// Throws seen by a real client (hippiestation/code/modules/throwing/): a magenta wrench thrown across the view with throw-realism off,
// then on, then tossed, pictured as fast as the window can be grabbed, to see how smoothly it moves and how it arcs and spins.
// Not part of the game: HARNESS=throw_shots.dm SENDER=throw_capture.ps1 MAP=testbench tools/keybind_check/run.sh throws
// Grabs in data/throw_capture/, read by tools/keybind_check/throw_read.py; notes in data/keycheck.txt.

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
			throw_shots_run(src)

/// Has throw_capture.ps1 grab pictures for `seconds`, and waits till it's done
/proc/throw_capture(phase, seconds, datum/callback/during)
	text2file("[phase],[seconds]", "data/throw_capture_go")
	sleep(4) //it looks for the order every 50 ms
	during.Invoke()
	var/deadline = world.time + (seconds + 10) SECONDS
	while(fexists("data/throw_capture_go") && world.time < deadline)
		sleep(1)

/// A floor with clear floor `reach` tiles east and west of it, lit
/proc/throw_shot_spot(reach)
	for(var/turf/open/floor/T in GLOB.station_turfs)
		var/clear = TRUE
		for(var/dx in -reach to reach)
			var/turf/along = locate(T.x + dx, T.y, T.z)
			if(!istype(along, /turf/open/floor) || along.density || (locate(/obj/structure) in along) || (locate(/obj/machinery) in along) || (locate(/mob) in along))
				clear = FALSE
				break
		if(clear)
			return T

/proc/throw_shot_throw(mob/living/carbon/human/H, turf/from, turf/target, intent)
	var/obj/item/wrench/W = new(from)
	W.color = "#ff00ff"
	H.forceMove(from)
	H.a_intent = intent
	H.put_in_active_hand(W)
	H.throw_item(target)
	GLOB.throw_shot_last = W

GLOBAL_DATUM(throw_shot_last, /obj/item)

/proc/throw_shots_run(client/C)
	fdel("data/throw_capture_go")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts throw_capture.ps1
	var/turf/spot = throw_shot_spot(5)
	if(!spot)
		kc_log("no clear row found")
		kc_log("done")
		text2file("done", "data/keycheck_shots_done")
		winset(C, null, "command=.quit")
		sleep(5)
		del(world)
		return
	// the viewer stands two rows below the throw, in the middle, out of its way
	var/turf/view_from = locate(spot.x, spot.y - 2, spot.z)
	var/mob/living/carbon/human/viewer = new(view_from)
	viewer.status_flags |= GODMODE
	viewer.ckey = C.ckey
	sleep(2 SECONDS)
	viewer.hud_used.show_hud(HUD_STYLE_NOHUD)
	viewer.forceMove(view_from)
	viewer.anchored = TRUE
	var/mob/living/carbon/human/thrower = new(spot)
	thrower.status_flags |= GODMODE
	var/turf/west = locate(spot.x - 5, spot.y, spot.z)
	var/turf/east = locate(spot.x + 5, spot.y, spot.z)
	kc_log("hwmode [winget(C, null, "hwmode")], fps [C.fps], tick_lag [world.tick_lag]; row [spot.x - 5]..[spot.x + 5],[spot.y] in [get_area(spot)], viewer at [view_from.x],[view_from.y]")
	sleep(5 SECONDS) //for throw_capture.ps1 to find the window
	for(var/phase in list("off", "on", "toss"))
		GLOB.throw_realism = phase != "off"
		throw_capture(phase, 2, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(throw_shot_throw), thrower, west, east, phase == "toss" ? INTENT_HELP : INTENT_HARM))
		var/obj/item/W = GLOB.throw_shot_last
		kc_log("[phase]: the wrench came down at [W.x - west.x] tiles, glide [W.glide_size]")
		qdel(W)
		sleep(1 SECONDS)
	GLOB.throw_realism = TRUE
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
