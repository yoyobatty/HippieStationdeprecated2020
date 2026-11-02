// A button dragged while zoomed out, in a real client: does the map go back to its size when the zoom ends? Not part of the game:
// HARNESS=zoom_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh <label>
// BYOND grows the map to show whatever is on client.screen, so only the client knows: view says 15x15 while the map's own view-size shows 24x23
// tiles squeezed into the same window. Posted messages never count as a drag, so the drop itself calls the button's own MouseDrop().

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(zc_reads)
GLOBAL_VAR(zc_button)
GLOBAL_VAR(zc_zoom)
GLOBAL_VAR(zc_mob)
GLOBAL_VAR(zc_client)

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
			zoom_check_run(src)

/proc/zc_floor()
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(50, 50)
	var/x0 = R.bottom_left_coords[1]
	var/y0 = R.bottom_left_coords[2]
	var/z = R.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0, y0, z), locate(x0 + 49, y0 + 49, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	return locate(x0 + 25, y0 + 25, z)

/// The real thing the mouse ends up calling at the end of a drag, with the params the client would send
/proc/zc_drop(tile_x, tile_y)
	var/obj/screen/movable/action_button/B = GLOB.zc_button
	usr = GLOB.zc_mob
	B.MouseDrop(null, null, null, null, null, "screen-loc=[tile_x]:20,[tile_y]:20")

/// Asks shot.ps1 for a picture and waits until it has it
/proc/zc_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)

/proc/zc_toggle()
	var/datum/action/A = GLOB.zc_zoom
	A.Trigger()

/proc/zc_stage_action(stage)
	var/client/C = GLOB.zc_client
	var/mob/living/carbon/human/H = GLOB.zc_mob
	var/obj/screen/movable/action_button/B = GLOB.zc_button
	var/datum/action/A = B.linked_action
	switch(stage)
		if("2 zoomed out", "4 back in", "5 zoomed out again", "6 back in again")
			zc_toggle()
		if("3 dragged far, still zoomed")
			zc_drop(24, 23)
		if("7 saved far spot, default view")
			var/id = B.id
			C.prefs.action_buttons_screen_locs["[A.name]_[id]"] = "24:4,23:4"
			A.Remove(H)
			A.Grant(H)
		if("8 zoom ended behind the helmet's back")
			zc_toggle()
			C.change_view(CONFIG_GET(string/default_view))
		if("9 next click zooms out")
			zc_toggle()
			kc_log("[C.view == 12 ? "PASS" : "FAIL"] one click zooms out after something else ended the zoom (view [C.view])")
		if("10 stunned, click does nothing")
			H.Paralyze(100)
			var/was = C.view
			zc_toggle()
			kc_log("[C.view == was ? "PASS" : "FAIL"] the button does nothing while stunned (view [was], then [C.view])")

/proc/zc_report(stage)
	var/client/C = GLOB.zc_client
	var/obj/screen/movable/action_button/B = GLOB.zc_button
	GLOB.zc_reads[stage] = winget(C, "mapwindow.map", "view-size")
	kc_log("[stage]: view [C.view], button at [B.screen_loc], moved [B.moved], map view-size [GLOB.zc_reads[stage]]")

/proc/zoom_check_run(client/C)
	var/turf/home = zc_floor()
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	C.mob = H
	GLOB.zc_client = C
	GLOB.zc_mob = H
	var/obj/item/clothing/suit/space/hardsuit/nano/S = new(home)
	H.equip_to_slot_or_del(S, ITEM_SLOT_OCLOTHING)
	sleep(30)
	for(var/datum/action/item_action/nanosuit/zoom/Z in H.actions)
		GLOB.zc_zoom = Z
	for(var/datum/action/item_action/nanosuit/armor/A in H.actions)
		GLOB.zc_button = A.button
	if(!GLOB.zc_zoom || !GLOB.zc_button)
		kc_log("no zoom or armour button: [length(H.actions)] actions")
		kc_log("done")
		winset(C, null, "command=.quit")
		sleep(5)
		del(world)
		return

	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys")
	sleep(30)
	zc_shot("nano_zoom_start") // shot.ps1 also brings a minimized window back: a map of 0x0 has nothing to measure
	sleep(20)
	kc_log("BYOND [C.byond_version].[C.byond_build], map [winget(C, "mapwindow.map", "size")], view [C.view], auto fit [C.prefs.auto_fit_viewport]")

	var/list/stages = list("1 default view", "2 zoomed out", "3 dragged far, still zoomed", "4 back in", "5 zoomed out again", "6 back in again", \
		"7 saved far spot, default view", "8 zoom ended behind the helmet's back", "9 next click zooms out", "10 stunned, click does nothing")
	for(var/stage in stages)
		zc_stage_action(stage)
		sleep(30)
		zc_report(stage)
		if(stage == stages[3])
			zc_shot("nano_zoom_dragged")
		if(stage == stages[4])
			zc_shot("nano_zoom_back")

	kc_log("---")
	var/first = GLOB.zc_reads[stages[1]]
	if(!length(first) || first == "0x0")
		kc_log("FAIL the map couldn't be measured, so nothing below means anything ([first])")
		first = "no reading"
	kc_log("[GLOB.zc_reads[stages[4]] == first ? "PASS" : "FAIL"] map back to normal after the zoom ended ([GLOB.zc_reads[stages[4]]], was [first])")
	kc_log("[GLOB.zc_reads[stages[6]] == first ? "PASS" : "FAIL"] and after the second zoom ([GLOB.zc_reads[stages[6]]])")
	kc_log("[GLOB.zc_reads[stages[7]] == first ? "PASS" : "FAIL"] a far spot saved in the preferences doesn't stretch it either ([GLOB.zc_reads[stages[7]]])")
	text2file("done", "data/keycheck_shots_done")
	sleep(15)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
