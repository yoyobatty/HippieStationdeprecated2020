// What the nanosuit shows on the HUD, as a real client draws it, and its quick menu key through an old save. Not part of the game:
// HARNESS=nano_hud_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh <label>
// Pictures land in data/previews/. One boot, so before and after are the same room: the before picture just hides what's new.

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
			nano_hud_run(src)

/proc/nh_check(name, ok, detail)
	kc_log("[ok ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " ([detail])"]")

/// Asks shot.ps1 for a picture and waits until it has it
/proc/nh_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/nh_lit(obj/item/clothing/suit/space/hardsuit/nano/S)
	. = list()
	for(var/datum/action/item_action/nanosuit/N in S.actions)
		if(length(N.button.filters))
			. += N.name

/proc/nh_mode(obj/item/clothing/suit/space/hardsuit/nano/S, mode, charge)
	S.toggle_mode(mode, TRUE)
	S.cell.charge = charge
	S.recharge_cooldown = 3000

/proc/nh_menus()
	return length(GLOB.radial_menus)

/proc/nano_hud_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE // the suit's process() doesn't run in the lobby
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	kc_log("round state [SSticker.current_state]")
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers)) // a lit room
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	C.mob = H
	var/obj/item/clothing/suit/space/hardsuit/nano/S = new(home)
	H.equip_to_slot_or_del(S, ITEM_SLOT_OCLOTHING)
	var/deadline = world.time + 40 SECONDS
	while(S.shutdown && world.time < deadline)
		sleep(2)
	text2file("go", "data/keycheck_sendkeys")
	sleep(30)
	kc_log("BYOND [C.byond_version].[C.byond_build], view [C.view], hwmode [winget(C, null, "hwmode")], map [winget(C, "mapwindow.map", "size")], actions [length(H.actions)]")

	var/obj/screen/nanosuit_energy/display = H.hud_used.nano_energy
	nh_check("the readout exists on a human's HUD", display, "[display?.screen_loc]")
	nh_check("it's on the screen", display in C.screen)

	// what it looked like
	nh_mode(S, "armor", 100)
	S.cellon = FALSE
	display.clear()
	for(var/datum/action/item_action/nanosuit/N in S.actions)
		N.button.filters = null
	sleep(10)
	nh_shot("nano_hud_before")

	S.cellon = TRUE
	var/list/stages = list(list("armor", 100, "nano_hud_armor"), list("cloak", 63, "nano_hud_cloak"), list("speed", 15, "nano_hud_speed"), list("strength", 8, "nano_hud_strength"))
	for(var/list/stage in stages)
		nh_mode(S, stage[1], stage[2])
		sleep(10)
		var/list/lit = nh_lit(S)
		nh_check("[stage[1]] at [stage[2]]: one button lit, the readout follows", length(lit) == 1 && display.shown == round(S.cell.percent()), "[jointext(lit, ", ")], reads [display.shown]")
		nh_shot(stage[3])

	// the F12 HUD toggle
	var/old_style = H.hud_used.hud_version
	H.hud_used.show_hud(HUD_STYLE_NOHUD)
	sleep(5)
	nh_check("F12 hides the readout with the rest of the HUD", !(display in C.screen))
	H.hud_used.show_hud(old_style)
	sleep(5)
	nh_check("and brings it back", display in C.screen)

	// the key, through what an old save looks like
	nh_mode(S, "armor", 100)
	C.prefs.hotkeys = TRUE
	C.prefs.key_bindings = list("W" = list("North"), "R" = list("toggle_throw_mode"))
	C.keyDown("C")
	C.keyUp("C")
	sleep(5)
	nh_check("before its update an old save has nothing on C, so C did nothing without one", !nh_menus(), "[nh_menus()] menus")
	C.prefs.update_preferences(26, null)
	nh_check("the update binds it to C", "nanosuit_menu" in C.prefs.key_bindings["C"], "[jointext(C.prefs.key_bindings["C"], ", ")]")
	nh_check("the keys they had are left alone", ("North" in C.prefs.key_bindings["W"]) && ("toggle_throw_mode" in C.prefs.key_bindings["R"]))
	C.prefs.update_preferences(26, null)
	nh_check("running it twice doesn't bind it twice", length(C.prefs.key_bindings["C"]) == 1, "[length(C.prefs.key_bindings["C"])]")
	C.keyDown("C")
	C.keyUp("C")
	sleep(10)
	nh_check("C opens the menu", nh_menus() == 1, "[nh_menus()] menus")
	nh_shot("nano_hud_menu")
	for(var/id in GLOB.radial_menus)
		var/datum/radial_menu/menu = GLOB.radial_menus[id]
		menu.finished = TRUE
	sleep(5)

	C.prefs.key_bindings["C"] -= "nanosuit_menu"
	C.prefs.key_bindings -= "C"
	C.prefs.update_preferences(27, null)
	nh_check("once it's updated, a key that was cleared stays clear", !C.prefs.key_bindings["C"])
	C.prefs.key_bindings["G"] = list("nanosuit_menu")
	C.keyDown("G")
	C.keyUp("G")
	sleep(10)
	nh_check("moved to G, G opens the menu", nh_menus() == 1, "[nh_menus()] menus")
	for(var/id in GLOB.radial_menus)
		var/datum/radial_menu/menu = GLOB.radial_menus[id]
		menu.finished = TRUE
	sleep(5)

	S.current_charges = 3
	display.clear()
	H.dropItemToGround(S, TRUE)
	sleep(5)
	nh_check("the readout leaves with the suit", display.invisibility, "invisibility [display.invisibility]")

	text2file("done", "data/keycheck_shots_done")
	sleep(15)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
