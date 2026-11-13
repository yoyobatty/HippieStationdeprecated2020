// A picture of the alt-click tile list on a pile: 600 everyday items of 16 kinds, a few mice and cats. Not part of the game:
//   SHOT_LABEL=after HARNESS=pile_list_shots.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh pileshot
// The picture is data/previews/pile_list_<label>.png. For the code before a change, run it with CHECKOUT=<a worktree at that commit>.

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
			pile_list_shots_run(src)

/proc/pls_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/pile_list_shots_run(client/C)
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
	var/list/kinds = list(/obj/item/crowbar, /obj/item/screwdriver, /obj/item/wrench, /obj/item/paper, /obj/item/pen,
		/obj/item/reagent_containers/food/drinks/soda_cans/cola, /obj/item/clothing/under/color/grey, /obj/item/clothing/shoes/sneakers/black,
		/obj/item/flashlight, /obj/item/storage/box, /obj/item/toy/crayon/red, /obj/item/reagent_containers/glass/beaker,
		/obj/item/bikehorn/rubberducky, /obj/item/trash/chips, /obj/item/wirecutters, /obj/item/weldingtool)
	for(var/i in 1 to 600)
		var/kind = kinds[(i % kinds.len) + 1]
		new kind(pile)
	for(var/i in 1 to 25)
		var/mob_kind = i <= 20 ? /mob/living/simple_animal/mouse : /mob/living/simple_animal/pet/cat // new (a ? b : c) makes the var's type
		var/mob/living/simple_animal/M = new mob_kind(pile)
		M.status_flags |= GODMODE
		M.toggle_ai(AI_OFF)
	var/deadline = world.time + 30 SECONDS
	while(!C.stat_panel?.is_ready() && world.time < deadline)
		sleep(5)
	sleep(30)
	H.AltClickOn(pile)
	sleep(50) // mob pictures come a few a refresh
	pls_shot("pile_list_[world.GetConfig("env", "SHOT_LABEL") || "now"]")
	kc_log("[length(pile.contents)] things on the tile, shot taken")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
