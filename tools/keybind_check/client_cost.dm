// What one real client costs the server, and how long a key press takes to reach its screen, at 20, 30 and 40 ticks a second.
// Not part of the game: HARNESS=client_cost.dm SENDER=press_probe.ps1 tools/keybind_check/run.sh <label>
// A human in the bar on the real map: standing alone, running across the station, then standing in a crowd of 20 walking humans.
// press_probe.ps1 posts real keys to the window and watches one tile in the corner of the map change colour, both ways a key can act:
// a hotkey does its work as the key arrives, a step waits for SSinput. The lobby is held throughout, so whole server figures
// leave out everything a running round does; map sending is the figure to read.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(press_pending, FALSE)
GLOBAL_DATUM(press_plate, /atom/movable/screen/press_plate)

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
			client_cost_run(src)

/atom/movable/screen/press_plate
	icon = 'icons/effects/alphacolors.dmi'
	icon_state = "white"
	screen_loc = "1,1"
	plane = ABOVE_HUD_PLANE
	layer = ABOVE_HUD_LAYER
	color = "#000000"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	var/lit = FALSE

/atom/movable/screen/press_plate/proc/flip()
	lit = !lit
	color = lit ? "#ffffff" : "#000000"

/client/keyDown(_key as text)
	set instant = TRUE
	set hidden = TRUE
	if(_key == "F9")
		GLOB.press_plate.flip()
		return
	if(_key == "F8")
		GLOB.press_pending = TRUE
		return
	return ..()

/client/keyUp(_key as text)
	set instant = TRUE
	set hidden = TRUE
	if(_key == "F9" || _key == "F8")
		return
	return ..()

/datum/controller/subsystem/input/fire()
	. = ..()
	if(GLOB.press_pending)
		GLOB.press_pending = FALSE
		GLOB.press_plate.flip()

/proc/cc_mean(list/values)
	var/total = 0
	for(var/value in values)
		total += value
	return total / max(length(values), 1)

/proc/cc_sample(label, seconds)
	var/list/map = list()
	var/list/load = list()
	for(var/i in 1 to round(seconds * world.fps))
		sleep(world.tick_lag)
		map += world.map_cpu
		load += world.cpu
	var/map_mean = cc_mean(map)
	sortTim(map, GLOBAL_PROC_REF(cmp_numeric_asc))
	kc_log("[world.fps] ticks, [label]: map sending [round(map_mean, 0.01)]% of a tick = [round(map_mean * world.tick_lag, 0.01)] ms a tick, worst 1% [round(map[CEILING(length(map) * 0.99, 1)], 0.01)]%, whole server [round(cc_mean(load), 0.1)]%")

/// Runs along a row of the station at running speed, through whatever's in the way.
/proc/cc_run_across(mob/M, seconds)
	var/end = world.time + seconds * 10
	var/stride = 1
	while(world.time < end)
		var/turf/next = locate(M.x + stride, M.y, M.z)
		if(!next || next.x < 30 || next.x > world.maxx - 30)
			stride = -stride
			continue
		M.forceMove(next)
		sleep(1)

/proc/cc_gather(list/crowd, turf/middle)
	var/list/spots = list()
	for(var/turf/open/floor/T in view(6, middle))
		if(!is_blocked_turf(T))
			spots += T
	for(var/mob/M as anything in crowd)
		M.forceMove(pick(spots))
		walk_rand(M, 3)

/proc/cc_disperse(list/crowd)
	for(var/mob/M as anything in crowd)
		walk(M, 0)
		M.forceMove(locate(5, 5, M.z))

/proc/client_cost_run(client/C)
	SSticker.timeLeft = -1 // held in the lobby
	fdel("data/press_find")
	fdel("data/press_found")
	fdel("data/press_go")
	fdel("data/press_done")
	var/list/bar = get_area_turfs(/area/crew_quarters/bar)
	var/turf/middle = pick(bar)
	while(!isopenturf(middle) || is_blocked_turf(middle))
		middle = pick(bar)
	var/mob/living/carbon/human/H = new(middle)
	H.status_flags |= GODMODE
	H.equipOutfit(/datum/outfit/bot_gym)
	C.mob = H
	GLOB.press_plate = new
	C.screen += GLOB.press_plate
	var/list/crowd = list()
	for(var/i in 1 to 20)
		var/mob/living/carbon/human/extra = new(locate(5, 5, H.z))
		extra.status_flags |= GODMODE
		extra.equipOutfit(/datum/outfit/bot_gym)
		crowd += extra
	sleep(30)
	kc_log("BYOND [C.byond_version].[C.byond_build], [SSmapping.config?.map_name], view [C.view], client fps [C.fps], hardware drawing [winget(C, null, "hwmode")], in [get_area_name(H)]")
	text2file("find", "data/press_find") // before anything's walking about, or it finds them instead of the plate
	text2file("go", "data/keycheck_sendkeys")
	var/found_by = world.time + 600
	while(!fexists("data/press_found") && world.time < found_by)
		sleep(5)
	for(var/rate in list(20, 30, 40))
		world.fps = rate
		H.forceMove(middle)
		sleep(30)
		cc_sample("standing alone", 10)
		spawn(0)
			cc_run_across(H, 15)
		cc_sample("running across the station", 15)
		sleep(5)
		H.forceMove(middle)
		cc_gather(crowd, middle)
		sleep(20)
		cc_sample("in a crowd of 20", 10)
		text2file("[rate]", "data/press_go")
		var/deadline = world.time + 2400
		while(!fexists("data/press_done") && world.time < deadline)
			sleep(5)
		if(!fexists("data/press_done"))
			kc_log("[rate] ticks: the probe never finished")
		fdel("data/press_done")
		cc_disperse(crowd)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
