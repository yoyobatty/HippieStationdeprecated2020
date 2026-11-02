// Whether a quick tap one way gets its step when the opposite key goes down straight after. Not part of the game:
// HARNESS=tap_check.dm tools/keybind_check/run.sh <label>
// A real client on an open floor, the keys through its own keyDown() and keyUp(), once with the fix off and once with it on.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(tap_fix_off, FALSE)

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
			tap_check_run(src)

/client/tap_is_waiting(movement)
	return GLOB.tap_fix_off ? FALSE : ..()

/proc/tc_floor()
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

/proc/tc_try(client/C, mob/living/carbon/human/H, turf/home, label)
	H.forceMove(home)
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		C.keys_held[i] = null
	sleep(5)
	// A step's delay still running, so what's pressed now has to wait for it
	C.move_delay = world.time + 2
	var/start_x = H.x
	C.keyDown("A")
	C.keyUp("A")
	C.keyDown("D")
	var/furthest_back = 0
	for(var/i in 1 to 16)
		furthest_back = min(furthest_back, H.x - start_x)
		sleep(world.tick_lag)
	var/ended = H.x - start_x
	C.keyUp("D")
	kc_log("[label]: furthest back [furthest_back], ended [ended] tiles along, [furthest_back < 0 ? "the tap took its step" : "THE TAP WAS LOST"]")

/proc/tap_check_run(client/C)
	var/turf/home = tc_floor()
	var/mob/living/carbon/human/H = new(home)
	H.status_flags |= GODMODE
	H.equipOutfit(/datum/outfit/bot_gym)
	C.mob = H
	sleep(10)
	GLOB.tap_fix_off = TRUE
	for(var/i in 1 to 3)
		tc_try(C, H, home, "fix off, try [i]")
	GLOB.tap_fix_off = FALSE
	for(var/i in 1 to 3)
		tc_try(C, H, home, "fix on, try [i]")
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
