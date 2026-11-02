// When a mouse action really happens in a real client: on the press, or on the release. Not part of the game:
// HARNESS=mouse_check.dm SENDER=mouseclick.ps1 tools/keybind_check/run.sh <label>
// Real button messages go to the map window (mouseclick.ps1). The long holds leave no doubt which of the two an action follows. The short
// ones are a person's click, standing still, walking, running and on something that moves, to count how many clicks get through.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(mc_running, TRUE)
GLOBAL_VAR_INIT(mc_phase, "probe")
GLOBAL_VAR_INIT(mc_press_time, 0)
GLOBAL_VAR_INIT(mc_probed, FALSE)
GLOBAL_LIST_EMPTY(mc_counts)
GLOBAL_VAR(mc_mob)
GLOBAL_VAR(mc_home)
GLOBAL_VAR(mc_target)
GLOBAL_VAR(mc_target_home)

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
			mouse_check_run(src)

/client/MouseDown(object, location, control, params)
	if(!GLOB.mc_probed)
		GLOB.mc_probed = TRUE
		text2file("ok", "data/keycheck_probe_ok")
	mc_event("press", object, params)
	if(mc_group() == "target")
		var/atom/movable/target = GLOB.mc_target
		target.forceMove(get_step(target, NORTH))
	return ..()

/client/MouseUp(object, location, control, params)
	mc_event("release", object, params)
	return ..()

/client/MouseDrop(src_object, over_object, src_location, over_location, src_control, over_control, params)
	mc_event("drag", src_object, params)
	return ..()

/client/Click(object, location, control, params)
	mc_event("click", object, params)
	return ..()

/mob/ClickOn(atom/A, params)
	mc_event("action", A, params)
	return ..()

/obj/screen/mc_button
	name = "test button"
	icon = 'icons/turf/floors.dmi'
	icon_state = "floor"
	screen_loc = "CENTER+3,CENTER+3"
	mouse_opacity = MOUSE_OPACITY_OPAQUE

/proc/mc_group()
	var/space = findtext(GLOB.mc_phase, " ")
	return space ? copytext(GLOB.mc_phase, 1, space) : GLOB.mc_phase

/proc/mc_where(object)
	var/mob/H = GLOB.mc_mob
	if(!H || !istype(object, /atom))
		return "[object]"
	var/atom/A = object
	var/turf/T = get_turf(A)
	return T ? "[A.type] at [T.x - H.x],[T.y - H.y]" : "[A.type] on the HUD"

/proc/mc_event(kind, object, params)
	var/group = mc_group()
	var/list/counts = GLOB.mc_counts[group]
	if(!counts)
		counts = list()
		GLOB.mc_counts[group] = counts
	counts[kind] += 1
	if(kind == "press")
		GLOB.mc_press_time = world.time
	var/list/mods = params2list(params)
	var/button = mods["left"] ? "left" : (mods["right"] ? "right" : (mods["middle"] ? "middle" : "no button"))
	kc_log("[GLOB.mc_phase]: +[(world.time - GLOB.mc_press_time) / 10]s [kind] ([button]) on [mc_where(object)]")

/proc/mc_floor()
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(40, 40)
	var/x0 = R.bottom_left_coords[1]
	var/y0 = R.bottom_left_coords[2]
	var/z = R.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0, y0, z), locate(x0 + 39, y0 + 39, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	return locate(x0 + 20, y0 + 20, z)

/// Puts everything back for the next phase, and starts the walk or the run when that's what it's for
/proc/mc_phase_changed(client/C)
	var/mob/living/carbon/human/H = GLOB.mc_mob
	C.keyUp("A")
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		C.keys_held[i] = null
	H.forceMove(GLOB.mc_home)
	var/atom/movable/target = GLOB.mc_target
	target.forceMove(GLOB.mc_target_home)
	var/group = mc_group()
	if(group == "running" || group == "walking")
		if((group == "walking") != (H.m_intent == MOVE_INTENT_WALK))
			H.toggle_move_intent()
		C.keyDown("A")

/proc/mc_phase_loop(client/C)
	set waitfor = FALSE
	while(GLOB.mc_running)
		var/text = fexists("data/keycheck_phase") ? file2text("data/keycheck_phase") : null
		if(text && text != GLOB.mc_phase)
			GLOB.mc_phase = text
			mc_phase_changed(C)
		sleep(world.tick_lag)

/proc/mc_closet_watch(obj/structure/closet/box)
	set waitfor = FALSE
	var/was = box.opened
	while(GLOB.mc_running)
		if(box.opened != was)
			was = box.opened
			kc_log("[GLOB.mc_phase]: +[(world.time - GLOB.mc_press_time) / 10]s the closet [was ? "opened" : "closed"]")
		sleep(world.tick_lag)

/// A press and a release, with a pause each side so the phase has time to get to the server
/proc/mc_click_steps(list/steps, phase, button, list/at, hold, list/let_go_at)
	steps += "phase [phase]"
	steps += "wait 400"
	steps += "move [at[1]] [at[2]]"
	steps += "wait 60"
	steps += "down [button] [at[1]] [at[2]]"
	if(let_go_at)
		steps += "drag [button] [let_go_at[1]] [let_go_at[2]]"
	steps += "wait [hold]"
	steps += "up [button] [(let_go_at || at)[1]] [(let_go_at || at)[2]]"
	steps += "wait 350"

/proc/mouse_check_run(client/C)
	var/turf/home = mc_floor()
	var/mob/living/carbon/human/H = new(home)
	H.status_flags |= GODMODE
	H.equipOutfit(/datum/outfit/bot_gym)
	C.mob = H
	GLOB.mc_mob = H
	GLOB.mc_home = home
	var/obj/structure/closet/box = new(locate(home.x + 1, home.y, home.z))
	var/obj/structure/closet/target = new(locate(home.x + 3, home.y - 3, home.z))
	GLOB.mc_target = target
	GLOB.mc_target_home = get_turf(target)
	var/obj/screen/mc_button/button = new
	C.screen += button
	sleep(20)

	var/list/map_size = splittext(winget(C, "mapwindow.map", "size"), "x")
	var/wide = text2num(map_size[1])
	var/high = text2num(map_size[2])
	var/zoom = text2num(winget(C, "mapwindow.map", "zoom"))
	var/list/view_size = getviewsize(C.view)
	var/tile = zoom ? world.icon_size * zoom : min(wide / view_size[1], high / view_size[2])
	kc_log("BYOND [C.byond_version].[C.byond_build], map [wide]x[high], view [view_size[1]]x[view_size[2]], [tile] px a tile, zoom [zoom]")

	var/list/steps = list("map [wide] [high]", "probe [round(wide / 2)] [round(high / 2 - 3 * tile)]")
	var/list/floor = mc_pixel(wide, high, tile, 0, 3)
	mc_click_steps(steps, "hold-floor left", "left", floor, 1500)
	mc_click_steps(steps, "hold-floor right", "right", floor, 1500)
	mc_click_steps(steps, "hold-floor middle", "middle", floor, 1500)
	mc_click_steps(steps, "hold-closet", "left", mc_pixel(wide, high, tile, 1, 0), 1500)
	mc_click_steps(steps, "hold-hud", "left", mc_pixel(wide, high, tile, 3, 3), 1500)
	for(var/i in 1 to 10)
		mc_click_steps(steps, "still [i]", "left", floor, 90)
	for(var/i in 1 to 5)
		mc_click_steps(steps, "same-tile [i]", "left", floor, 90, list(floor[1] + 4, floor[2]))
	for(var/i in 1 to 5)
		mc_click_steps(steps, "next-tile [i]", "left", floor, 90, mc_pixel(wide, high, tile, 1, 3))
	var/list/on_target = mc_pixel(wide, high, tile, 3, -3)
	for(var/i in 1 to 10)
		mc_click_steps(steps, "target [i]", "left", on_target, 120)
	for(var/i in 1 to 10)
		mc_click_steps(steps, "walking [i]", "left", floor, 90)
	for(var/i in 1 to 10)
		mc_click_steps(steps, "running [i]", "left", floor, 90)
	steps += "phase finished"

	mc_phase_loop(C)
	mc_closet_watch(box)
	text2file(jointext(steps, "\n"), "data/keycheck_mouse_steps")
	text2file("go", "data/keycheck_sendkeys")
	var/deadline = world.time + 4 MINUTES
	while(!fexists("data/keycheck_keys_sent") && world.time < deadline)
		sleep(5)
	sleep(10)
	GLOB.mc_running = FALSE

	kc_log("---")
	for(var/group in GLOB.mc_counts)
		var/list/counts = GLOB.mc_counts[group]
		kc_log("[group]: [counts["press"] + 0] presses, [counts["release"] + 0] releases, [counts["click"] + 0] clicks, [counts["action"] + 0] actions, [counts["drag"] + 0] drags")
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)

/// Where a tile that far from the player is in the map control, in its pixels
/proc/mc_pixel(wide, high, tile, dx, dy)
	return list(round(wide / 2 + dx * tile), round(high / 2 - dy * tile))
