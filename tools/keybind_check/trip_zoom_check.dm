// Does a trip's picture sit over the real screen at every map zoom? A player on a fixed zoom saw it drawn twice the size and off to
// one side. Not part of the game: HARNESS=trip_zoom_check.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh tripzoom
// Pictures data/previews/zoom_*.png: at zoom 0 (stretch), 1 and 2, the trip at no strength (it should match the plain screen).

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
			trip_zoom_run(src)

/proc/zoom_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/trip_zoom_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys")
	var/turf/spot
	for(var/turf/open/floor/F in world)
		if(is_station_level(F.z) && F.get_lumcount() > 0.5 && !(locate(/obj/structure) in F))
			spot = F
			break
	var/mob/living/carbon/human/H = new(spot)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(4 SECONDS)
	kc_log("map zoom [winget(C, "mapwindow.map", "zoom")] zoom-mode [winget(C, "mapwindow.map", "zoom-mode")] size [winget(C, "mapwindow.map", "size")] icon-size [winget(C, "mapwindow.map", "icon-size")]")
	for(var/zoom in list(2, 0, 1))
		winset(C, "mapwindow.map", "zoom=[zoom]")
		sleep(2 SECONDS)
		zoom_shot("zoom_[zoom]_plain")
		var/datum/trip_vision/V = new(H)
		H.trip_vision = V
		V.start()
		V.geometry_until = world.time + 10 MINUTES
		V.colour_until = world.time + 10 MINUTES
		V.kaleido_until = world.time + 10 MINUTES
		V.fade_until = world.time + 10 MINUTES // no sway or grade loops: the picture held still and plain
		for(var/i in 1 to 9)
			V.update(0, FALSE, 0)
			sleep(2 SECONDS)
		animate(V.fractal_pms[1], alpha = 0, time = 0)
		animate(V.fractal_pms[2], alpha = 0, time = 0)
		sleep(1 SECONDS)
		var/matrix/T = V.view_pm.transform
		kc_log("zoom [zoom]: view transform [T.a],[T.b],[T.c],[T.d],[T.e],[T.f] screen [length(C.screen)] pixel [C.pixel_x],[C.pixel_y]")
		zoom_shot("zoom_[zoom]_trip")
		V.split(3, 60)
		sleep(15)
		zoom_shot("zoom_[zoom]_split")
		sleep(7 SECONDS)
		V.kaleido_until = 0
		V.set_kaleido(255, 1)
		V.kaleido_until = world.time + 10 MINUTES
		sleep(2 SECONDS)
		zoom_shot("zoom_[zoom]_kaleido")
		V.kaleido_until = 0
		V.set_kaleido(0, 1)
		V.kaleido_until = world.time + 10 MINUTES
		sleep(2 SECONDS)
		qdel(V)
		sleep(2 SECONDS)
	winset(C, "mapwindow.map", "zoom=0")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
