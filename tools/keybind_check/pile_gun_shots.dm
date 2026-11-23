// The alt-click tile list on energy guns at three charges (3 full, 1 half, 1 empty) and 5 crowbars: alike rows go by overlays
// too, so the guns should be three rows, each drawn with its charge. Not part of the game:
//   SHOT_LABEL=after HARNESS=pile_gun_shots.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh gunshot
// The rows are in data/keycheck_gunshot.txt, the picture is data/previews/pile_guns_<label>.png. For the code before a change,
// run it with CHECKOUT=<a worktree at that commit>.

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
			pile_gun_shots_run(src)

/proc/pls_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/pile_gun_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") // starts shot.ps1
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(20, 20)
	var/x0 = R.bottom_left_coords[1]
	var/y0 = R.bottom_left_coords[2]
	var/z = R.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0, y0, z), locate(x0 + 19, y0 + 19, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	var/turf/home = locate(x0 + 10, y0 + 10, z)
	var/mob/living/carbon/human/H = new(home)
	H.status_flags |= GODMODE
	H.equipOutfit(/datum/outfit/bot_gym)
	C.mob = H
	var/turf/pile = get_step(home, EAST)
	for(var/i in 1 to 5)
		new /obj/item/crowbar(pile)
	for(var/i in 1 to 3)
		new /obj/item/gun/energy/e_gun(pile)
	var/obj/item/gun/energy/e_gun/half = new(pile)
	half.cell.charge = half.cell.maxcharge / 2
	half.update_icon()
	var/obj/item/gun/energy/e_gun/empty = new(pile)
	empty.cell.charge = 0
	empty.update_icon()
	var/deadline = world.time + 30 SECONDS
	while(!C.stat_panel?.is_ready() && world.time < deadline)
		sleep(5)
	sleep(30)
	H.AltClickOn(pile)
	sleep(50) // flattened pictures come a few a refresh
	var/list/sent = json_decode(C.stat_panel.sent_turf)
	for(var/list/row in sent[1])
		kc_log("[row[1]] x[row[4]]")
	pls_shot("pile_guns_[world.GetConfig("env", "SHOT_LABEL") || "now"]")
	kc_log("[length(pile.contents)] things on the tile, shot taken")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
