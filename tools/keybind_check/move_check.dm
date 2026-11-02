// How fast a real client actually moves, straight and diagonally. Not part of the game: HARNESS=move_check.dm tools/keybind_check/run.sh
// A human on a big open floor, with movement keys held through the client's own keyDown(): the same path as a keyboard, /client/Move()
// and its delay included. Reports tiles covered, and the straight-line distance that comes to, a second.

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
			move_check_run(src)

/proc/mc_floor()
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(70, 70)
	var/x0 = R.bottom_left_coords[1]
	var/y0 = R.bottom_left_coords[2]
	var/z = R.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0, y0, z), locate(x0 + 69, y0 + 69, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	return locate(x0, y0, z)

/proc/mc_run(client/C, mob/living/carbon/human/H, label, list/keys, turf/from)
	H.forceMove(from)
	for(var/i in 1 to HELD_KEY_BUFFER_LENGTH)
		C.keys_held[i] = null
	sleep(5)
	var/turf/a = get_turf(H)
	var/t0 = world.time
	for(var/k in keys)
		C.keyDown(k)
	sleep(30)
	var/glide = H.glide_size
	sleep(20)
	var/turf/b = get_turf(H)
	var/seconds = (world.time - t0) / 10
	for(var/k in keys)
		C.keyUp(k)
	var/dx = abs(b.x - a.x)
	var/dy = abs(b.y - a.y)
	var/distance = sqrt(dx * dx + dy * dy)
	kc_log("[label]: [dx] across, [dy] up in [seconds]s = [round(distance / seconds, 0.01)] tiles a second, glide [round(glide, 0.01)] px a tick")
	return distance / seconds

/proc/move_check_run(client/C)
	var/turf/corner = mc_floor()
	var/mob/living/carbon/human/H = new(corner)
	H.status_flags |= GODMODE
	H.equipOutfit(/datum/outfit/bot_gym)
	C.mob = H
	sleep(10)
	var/turf/west_side = locate(corner.x + 3, corner.y + 35, corner.z)
	var/turf/corner_start = locate(corner.x + 3, corner.y + 3, corner.z)
	kc_log("BYOND [C.byond_version].[C.byond_build], tick [world.tick_lag] ds, running delay [H.movement_delay()] ds a tile, walk delay [CONFIG_GET(number/movedelay/walk_delay)]")
	var/straight = mc_run(C, H, "run, straight (D)", list("D"), west_side)
	var/diagonal = mc_run(C, H, "run, diagonal (W+D)", list("W", "D"), corner_start)
	var/straight_up = mc_run(C, H, "run, straight (W)", list("W"), locate(corner.x + 35, corner.y + 3, corner.z))
	kc_log("run: diagonal is [round(diagonal / straight * 100)]% of straight speed")
	H.toggle_move_intent()
	var/walk_straight = mc_run(C, H, "walk, straight (D)", list("D"), west_side)
	var/walk_diagonal = mc_run(C, H, "walk, diagonal (W+D)", list("W", "D"), corner_start)
	kc_log("walk: diagonal is [round(walk_diagonal / walk_straight * 100)]% of straight speed ([straight_up ? "checked" : "unchecked"])")
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
