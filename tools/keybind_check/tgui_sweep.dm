// tgui windows with a real client, one after another: each opened the way a player opens it, and judged by whether its page came
// up (the page tells the server it's there: /datum/tgui initialized) within a few seconds. A page that didn't gets a picture.
// Not part of the game: HARNESS=tgui_sweep.dm SENDER=shot.ps1 tools/keybind_check/run.sh <label>
// Verdicts in data/keycheck.txt; pictures of the failures in data/previews/popup_tgui_*.png.

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
			tgui_sweep_run(src)

/proc/ts_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// The things with a tgui window a player sees in a round, the common ones.
GLOBAL_LIST_INIT(ts_types, list("/obj/machinery/vending/cola", "/obj/machinery/chem_dispenser", "/obj/machinery/chem_master", "/obj/machinery/chem_heater", "/obj/machinery/sleeper", "/obj/machinery/atmospherics/components/unary/cryo_cell", "/obj/machinery/smartfridge", "/obj/machinery/autolathe", "/obj/machinery/computer/cargo", "/obj/machinery/computer/cargo/request", "/obj/machinery/computer/crew", "/obj/machinery/computer/communications", "/obj/machinery/computer/scan_consolenew", "/obj/machinery/computer/operating", "/obj/machinery/mineral/ore_redemption", "/obj/machinery/mineral/equipment_vendor", "/obj/machinery/suit_storage_unit/standard_unit", "/obj/machinery/portable_atmospherics/canister/oxygen", "/obj/machinery/portable_atmospherics/pump", "/obj/machinery/portable_atmospherics/scrubber", "/obj/machinery/atmospherics/components/unary/thermomachine/freezer", "/obj/machinery/airalarm", "/obj/machinery/power/apc", "/obj/machinery/power/smes", "/obj/machinery/particle_accelerator/control_box", "/obj/machinery/power/port_gen/pacman", "/obj/machinery/computer/station_alert", "/obj/machinery/computer/atmos_alert", "/obj/machinery/computer/security", "/obj/machinery/computer/med_data", "/obj/machinery/computer/secure_data", "/obj/machinery/computer/card", "/obj/machinery/computer/cloning", "/obj/machinery/computer/rdconsole/core", "/obj/machinery/rnd/production/protolathe/department/science", "/obj/machinery/computer/holodeck", "/obj/machinery/computer/shuttle/mining", "/obj/machinery/computer/emergency_shuttle", "/obj/machinery/door_timer", "/obj/machinery/computer/teleporter", "/obj/machinery/gravity_generator/main/station", "/obj/machinery/disposal/bin", "/obj/machinery/computer/pandemic", "/obj/machinery/chem_dispenser/drinks", "/obj/item/radio", "/obj/item/tank/internals/oxygen", "/obj/item/pda", "/obj/item/assembly/signaler", "/obj/item/electropack", "/obj/item/storage/backpack/duffelbag", "/obj/item/computer_hardware", "/obj/machinery/computer/camera_advanced", "/obj/machinery/nanite_chamber", "/obj/machinery/computer/nanite_chamber_control", "/obj/machinery/computer/nanite_cloud_controller", "/obj/machinery/nanite_program_hub", "/obj/machinery/computer/slime_control", "/obj/machinery/computer/bounty")) //text: a path this fork hasn't got is skipped, not a build error

/proc/tgui_sweep_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/captain) //the most access, the fewest refusals
	H.ckey = C.ckey
	sleep(3 SECONDS)
	kc_log("round state [SSticker.current_state], mob [C.mob]")
	var/passed = 0
	var/failed = 0
	var/none = 0
	for(var/path_text in GLOB.ts_types)
		var/path = text2path(path_text)
		if(!path)
			kc_log("SKIP [path_text]: no such thing here")
			continue
		var/turf/spot = get_step(H, EAST)
		var/atom/movable/A
		try
			A = new path(spot)
		catch(var/exception/e)
			kc_log("SKIP [path]: couldn't make one ([e])")
			continue
		if(isitem(A))
			H.put_in_hands(A)
		var/obj/machinery/M = A
		if(istype(M))
			M.stat &= ~(NOPOWER|BROKEN)
			M.panel_open = FALSE
			M.anchored = TRUE
		try
			if(isitem(A))
				var/obj/item/I = A
				I.attack_self(H)
			else
				A.ui_interact(H)
		catch(var/exception/e2)
			kc_log("FAIL [path]: opening it ran into [e2] at [e2.file]:[e2.line]")
			failed++
			qdel(A)
			continue
		var/datum/tgui/ui
		for(var/i in 1 to 30)
			sleep(2)
			ui = null
			for(var/datum/tgui/open as anything in C.mob.open_uis)
				if(open.src_object == A || open.src_object == A.ui_host())
					ui = open
			if(ui?.initialized)
				break
		if(!ui)
			kc_log("NONE [path]: no tgui window opened (an old window, or it wants more than this to open)")
			none++
		else if(ui.initialized)
			kc_log("PASS [path]: [ui.interface] came up")
			passed++
		else
			kc_log("FAIL [path]: [ui.interface] opened but the page never started")
			failed++
			winset(C, ui.window_id, "pos=1700,300")
			sleep(10)
			ts_shot("popup_tgui_[replacetext("[path]", "/", "_")]")
		SStgui.close_user_uis(H)
		H.drop_all_held_items()
		qdel(A)
		sleep(5)
	kc_log("[passed] came up, [failed] failed, [none] opened no tgui window")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
