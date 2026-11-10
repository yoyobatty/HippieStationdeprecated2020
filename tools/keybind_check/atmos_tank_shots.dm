// Pictures of the gas tank consoles with a real client, old window and new (hippiestation/code/game/machinery/computer/atmos_control.dm).
// Not part of the game.
//   after:  echo after > data/atmos_shots_label; HARNESS=atmos_tank_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh atmos
//   before: git show HEAD:tgui-next/packages/tgui/public/tgui.bundle.js > data/previews/atmos_old/tgui.bundle.js (and .css), then
//           echo before > data/atmos_shots_label; EXCLUDE='hippiestation\code\game\machinery\computer\atmos_control.dm'
//           HARNESS=atmos_tank_shots_before.dm SENDER=shot.ps1 tools/keybind_check/run.sh atmos
// Pictures in data/previews/popup_atmos_<label>_*.png.

GLOBAL_VAR_INIT(atmos_shots_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/at_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.atmos_shots_running)
		GLOB.atmos_shots_running = TRUE
		spawn(50)
			atmos_shots_run(src)

/proc/at_shot(name)
	fdel("data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// Opens a console's window next to it, waits for the page, places it and takes its picture
/proc/at_window(client/C, mob/living/carbon/human/H, obj/machinery/console, name)
	for(var/turf/open/T in orange(1, console))
		if(!T.density && !(locate(/obj/machinery) in T))
			H.forceMove(T)
			break
	usr = H
	console.ui_interact(H)
	var/datum/tgui/ui
	var/deadline = world.time + 15 SECONDS
	while(world.time < deadline)
		for(var/datum/tgui/open as anything in H.open_uis)
			if(open.src_object == console && open.initialized)
				ui = open
		if(ui)
			break
		sleep(2)
	at_log("[ui ? "PASS" : "FAIL"] [console.name]'s window opens")
	if(!ui)
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(4 SECONDS) // the old console waits on radio replies
	at_shot(name)
	SStgui.close_uis(console)
	sleep(1 SECONDS)

/proc/atmos_shots_run(client/C)
	var/label = trim(file2text("data/atmos_shots_label")) || "now"
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") // starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/obj/machinery/computer/atmos_control/tank/oxygen_tank/tank = locate() in GLOB.atmos_air_controllers
	var/obj/machinery/computer/atmos_control/monitor
	for(var/obj/machinery/computer/atmos_control/candidate in GLOB.atmos_air_controllers)
		if(!istype(candidate, /obj/machinery/computer/atmos_control/tank) && is_station_level(candidate.z))
			monitor = candidate
			break
	var/mob/living/carbon/human/H = new(get_turf(tank))
	H.mind_initialize()
	H.ckey = C.ckey
	H.status_flags |= GODMODE
	sleep(2 SECONDS)
	at_log("atmos tank consoles, [label] build")
	at_window(C, H, tank, "popup_atmos_[label]_1_oxygen")
	if(monitor)
		at_window(C, H, monitor, "popup_atmos_[label]_2_monitor")
	// the tank's injector breaks
	var/obj/machinery/atmospherics/components/unary/outlet_injector/atmos/oxygen_input/injector = locate() in GLOB.machines
	injector?.deconstruct(FALSE)
	at_window(C, H, tank, "popup_atmos_[label]_3_injector_broken")
	// and then its sensor
	var/obj/machinery/air_sensor/atmos/oxygen_tank/sensor = locate() in GLOB.machines
	qdel(sensor)
	at_window(C, H, tank, "popup_atmos_[label]_4_sensor_gone")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	at_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
