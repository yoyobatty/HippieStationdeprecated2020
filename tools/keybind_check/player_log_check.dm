// Whether the player log (bots_ai/player_log.dm) follows a real client around. Not part of the game:
// HARNESS=player_log_check.dm SENDER=mouseclick.ps1 tools/keybind_check/run.sh <label>
// Real clicks and keys through the client, a walk, a look at somebody nearby, items, a machine, then out to a ghost and back. What it wrote
// is in the newest data/logs round folder.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(plc_probed, FALSE)

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
			player_log_check_run(src)

/client/MouseDown(object, location, control, params)
	if(!GLOB.plc_probed)
		GLOB.plc_probed = TRUE
		text2file("ok", "data/keycheck_probe_ok")
	return ..()

/obj/screen/plc_button
	name = "test button"
	icon = 'icons/turf/floors.dmi'
	icon_state = "floor"
	screen_loc = "CENTER+3,CENTER+3"
	mouse_opacity = MOUSE_OPACITY_OPAQUE

/proc/plc_floor()
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(30, 30)
	var/x0 = R.bottom_left_coords[1]
	var/y0 = R.bottom_left_coords[2]
	var/z = R.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0, y0, z), locate(x0 + 29, y0 + 29, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	return locate(x0 + 15, y0 + 15, z)

/proc/plc_pixel(wide, high, tile, dx, dy)
	return list(round(wide / 2 + dx * tile), round(high / 2 - dy * tile))

/proc/plc_click(list/steps, list/at)
	steps += "move [at[1]] [at[2]]"
	steps += "wait 80"
	steps += "down left [at[1]] [at[2]]"
	steps += "wait 80"
	steps += "up left [at[1]] [at[2]]"
	steps += "wait 300"

/proc/player_log_check_run(client/C)
	var/turf/home = plc_floor()
	CONFIG_SET(string/player_log_ckey, C.ckey)
	var/mob/living/carbon/human/H = new(home)
	H.status_flags |= GODMODE
	H.equipOutfit(/datum/outfit/bot_gym)
	var/mob/living/carbon/human/neighbour = new(locate(home.x - 2, home.y + 1, home.z))
	neighbour.status_flags |= GODMODE
	var/obj/structure/closet/box = new(locate(home.x + 1, home.y, home.z))
	var/obj/screen/plc_button/button = new
	C.mob = H
	C.screen += button
	sleep(20)

	var/list/map_size = splittext(winget(C, "mapwindow.map", "size"), "x")
	var/wide = text2num(map_size[1])
	var/high = text2num(map_size[2])
	var/zoom = text2num(winget(C, "mapwindow.map", "zoom"))
	var/list/view_size = getviewsize(C.view)
	var/tile = zoom ? world.icon_size * zoom : min(wide / view_size[1], high / view_size[2])
	var/list/steps = list("map [wide] [high]", "probe [round(wide / 2)] [round(high / 2 - 3 * tile)]")
	plc_click(steps, plc_pixel(wide, high, tile, 0, 3)) //the floor
	plc_click(steps, plc_pixel(wide, high, tile, 1, 0)) //the closet
	plc_click(steps, plc_pixel(wide, high, tile, -2, 1)) //somebody
	plc_click(steps, plc_pixel(wide, high, tile, 3, 3)) //the HUD
	steps += list("keydown 88", "wait 90", "keyup 88", "wait 300") //X, a tap: swaps hands
	steps += list("keydown 87", "wait 900", "keyup 87", "wait 400") //W, held: a walk north
	steps += list("keydown 83", "wait 60", "keyup 83", "wait 500") //S, the quickest tap a person does
	text2file(jointext(steps, "\n"), "data/keycheck_mouse_steps")
	text2file("go", "data/keycheck_sendkeys")
	var/deadline = world.time + 2 MINUTES
	while(!fexists("data/keycheck_keys_sent") && world.time < deadline)
		sleep(5)

	// Held against something, then moved by something else, then the server letting go of a key whose release never came
	var/obj/structure/closet/in_the_way = new(locate(H.x, H.y - 1, H.z))
	C.keyDown("S")
	sleep(25)
	C.keyUp("S")
	qdel(in_the_way)
	H.forceMove(locate(H.x + 2, H.y, H.z))
	sleep(10)
	C.reset_held_keys()

	var/obj/item/wrench/W = new(H.loc)
	kc_log("picked up: [H.put_in_hands(W)]")
	kc_log("dropped: [H.dropItemToGround(W)]")
	var/obj/item/clothing/glasses/sunglasses/shades = new(H.loc)
	kc_log("equipped: [H.equip_to_slot_if_possible(shades, ITEM_SLOT_EYES, FALSE, TRUE, TRUE)]")

	var/obj/machinery/vending/cola/V = new(H.loc)
	var/datum/tgui/ui = new(H, V, "main", "vending", "test", 450, 600, null, GLOB.always_state)
	usr = H
	ui.Topic("", list("action" = "test_action", "src" = "test", "item" = "test_item"))
	sleep(20)

	var/mob/dead/observer/ghost = new(H.loc)
	C.mob = ghost
	sleep(20)
	C.mob = H
	sleep(20)
	C.mob = ghost
	sleep(5)
	qdel(H)
	sleep(5)
	kc_log("body after the body's deleted: [GLOB.player_log.body ? "still held" : "let go"]")
	kc_log("log file: [GLOB.player_log.log_file]")
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
