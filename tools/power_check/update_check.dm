// Whether what should change when something's washed, loses power or breaks really does. Not part of the game: tools/power_check/run.sh <label>
// Headless, on the real station. One bloody human in a real shower, every slot looked at. Then every APC on the station off and on again
// with every machine looked at each time. Then one of each machine broken, and the power off and on once more.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/uc_log(text)
	text2file(text, "data/update_check.txt")

/world/New()
	. = ..()
	spawn(0)
		update_check_run()

/proc/uc_floor()
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(12, 12)
	var/x0 = R.bottom_left_coords[1]
	var/y0 = R.bottom_left_coords[2]
	var/z = R.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0, y0, z), locate(x0 + 11, y0 + 11, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	return locate(x0 + 6, y0 + 6, z)

// ---- blood

/// The blood drawn on the worn sprites. It's what other people see, and it's built apart from the item's own icon.
/proc/uc_worn_blood(mob/living/carbon/human/H)
	. = list()
	for(var/i in 1 to TOTAL_LAYERS)
		var/thing = H.overlays_standing[i]
		if(!thing)
			continue
		var/list/standing = islist(thing) ? thing : list(thing)
		for(var/part in standing)
			var/mutable_appearance/MA = part
			for(var/entry in MA.overlays)
				var/image/E = entry
				if(E.icon == 'icons/effects/blood.dmi')
					. += E.icon_state

/proc/uc_item_state(obj/item/I)
	return "[HAS_BLOOD_DNA(I) ? "dna" : "no dna"], [I.GetComponent(/datum/component/decal/blood) ? "decal" : "no decal"], [length(I.overlays)] overlays"

/proc/uc_dress(mob/living/carbon/human/H, with_gloves, welding_mask)
	var/list/gear = list(
		/obj/item/clothing/under/color/grey = ITEM_SLOT_ICLOTHING,
		/obj/item/clothing/suit/hazardvest = ITEM_SLOT_OCLOTHING,
		/obj/item/clothing/shoes/sneakers/black = ITEM_SLOT_FEET,
		/obj/item/flashlight = ITEM_SLOT_SUITSTORE)
	if(welding_mask)
		gear[/obj/item/clothing/head/welding] = ITEM_SLOT_HEAD
	else
		gear[/obj/item/clothing/head/hardhat] = ITEM_SLOT_HEAD
		gear[/obj/item/clothing/mask/breath] = ITEM_SLOT_MASK
	gear += list(
		/obj/item/clothing/glasses/meson = ITEM_SLOT_EYES,
		/obj/item/radio/headset = ITEM_SLOT_EARS,
		/obj/item/clothing/neck/tie/blue = ITEM_SLOT_NECK,
		/obj/item/storage/belt/utility = ITEM_SLOT_BELT,
		/obj/item/storage/backpack = ITEM_SLOT_BACK,
		/obj/item/card/id = ITEM_SLOT_ID,
		/obj/item/pen = ITEM_SLOT_LPOCKET,
		/obj/item/flashlight/pen = ITEM_SLOT_RPOCKET)
	if(with_gloves)
		gear[/obj/item/clothing/gloves/color/yellow] = ITEM_SLOT_GLOVES
	. = list()
	for(var/path in gear)
		var/obj/item/I = new path(H)
		if(H.equip_to_slot_or_del(I, gear[path]))
			. += I
	var/obj/item/wrench/W = new(H)
	H.put_in_hands(W)
	. += W
	var/obj/item/screwdriver/S = new(H)
	H.put_in_hands(S)
	. += S
	var/obj/item/wirecutters/on_belt = new(H.belt)
	. += on_belt

/// Top row what the inventory showed going in, bottom row coming out, four times size
/proc/uc_preview(list/before, list/after)
	var/icon/sheet = icon('icons/effects/effects.dmi', "nothing")
	sheet.Scale(32 * length(before), 64)
	for(var/i in 1 to length(before))
		sheet.Blend(before[i], ICON_OVERLAY, 1 + (i - 1) * 32, 33)
		sheet.Blend(after[i], ICON_OVERLAY, 1 + (i - 1) * 32, 1)
	sheet.Scale(sheet.Width() * 4, sheet.Height() * 4)
	fdel("data/previews/shower_inventory.png")
	fcopy(fcopy_rsc(sheet), "data/previews/shower_inventory.png")

/proc/uc_blood(label, turf/spot, prints, with_gloves, welding_mask, preview)
	var/mob/living/carbon/human/H = new(spot)
	H.status_flags |= GODMODE
	var/list/worn = uc_dress(H, with_gloves, welding_mask)
	var/obj/item/in_bag = new /obj/item/crowbar(H.back)
	sleep(2 SECONDS)
	var/list/dna = list("ABCDEF" = "O+")
	var/list/clean_overlays = list()
	for(var/obj/item/I in worn)
		clean_overlays[I] = length(I.overlays)
		if(prints)
			I.add_fingerprint(H)
		I.add_blood_DNA(dna)
		I.add_atom_colour("#ff0000", WASHABLE_COLOUR_PRIORITY)
	in_bag.add_blood_DNA(dna)
	H.add_blood_DNA(dna)
	var/mutable_appearance/pie = mutable_appearance('icons/effects/creampie.dmi', "creampie_human")
	H.add_overlay(pie)
	H.creamed = TRUE
	var/body_overlays = length(H.overlays)
	if(H.shoes)
		var/obj/item/clothing/shoes/boots = H.shoes
		boots.bloody_shoes[BLOOD_STATE_HUMAN] = 50
		boots.blood_state = BLOOD_STATE_HUMAN
	H.update_inv_shoes()
	sleep(1 SECONDS)
	uc_log("== [label]")
	uc_log("worn sprites before: [jointext(uc_worn_blood(H), ", ")] | bloody hands [H.bloody_hands]")
	var/list/pictured = list(H.wear_id, H.l_store, H.r_store, H.s_store)
	var/list/pictures_before = list()
	if(preview)
		for(var/obj/item/I in pictured)
			pictures_before += getFlatIcon(I)
	var/obj/machinery/shower/S = new(spot)
	S.interact(H)
	sleep(4 SECONDS)
	S.interact(H)
	sleep(1 SECONDS)
	if(preview)
		var/list/pictures_after = list()
		for(var/obj/item/I in pictured)
			pictures_after += getFlatIcon(I)
		uc_preview(pictures_before, pictures_after)
	var/still = 0
	for(var/obj/item/I in worn)
		var/bloody = HAS_BLOOD_DNA(I) || I.GetComponent(/datum/component/decal/blood) || length(I.overlays) > clean_overlays[I]
		if(bloody)
			still++
		uc_log("[bloody ? "STILL BLOODY" : "clean       "] [I.name] ([H.get_slot_by_item_name(I)]): [uc_item_state(I)], colour [I.color || "none"], was [clean_overlays[I]] overlays when new")
	uc_log("in a closed bag, on purpose: [in_bag.name]: [uc_item_state(in_bag)]")
	var/list/left = uc_worn_blood(H)
	uc_log("[length(left) ? "STILL BLOODY" : "clean       "] worn sprites after: [jointext(left, ", ")] | bloody hands [H.bloody_hands]")
	uc_log("cream: [H.creamed ? "STILL ON" : "gone"], body overlays [body_overlays] -> [length(H.overlays)]")
	uc_log("[still] of [length(worn)] items still bloody, [length(left)] worn sprites still bloody")
	qdel(S)
	qdel(H)
	sleep(1 SECONDS)

/mob/living/carbon/human/proc/get_slot_by_item_name(obj/item/I)
	if(I in held_items)
		return "hand"
	return "worn"

// ---- power

/proc/uc_machines()
	var/list/powered_areas = list()
	for(var/obj/machinery/power/apc/A as anything in GLOB.apcs_list)
		if(A.area && is_station_level(A.z))
			powered_areas[A.area] = TRUE
	. = list()
	for(var/obj/machinery/M in GLOB.machines)
		if(M.z && powered_areas[get_area(M)] && !istype(M, /obj/machinery/power/apc))
			. += M

/proc/uc_look(obj/machinery/M)
	return list("state" = M.icon_state, "overlays" = length(M.overlays), "vis" = length(M.vis_contents), "light" = M.light_power ? M.light_range : 0, "stat" = M.stat, "running" = (M.datum_flags & DF_ISPROCESSING) ? 1 : 0)

/// Whether what it's drawing exists: an icon_state that isn't in the file is an invisible machine.
/proc/uc_sprite_missing(atom/A)
	var/static/list/known = list()
	if(!A.icon || !A.icon_state)
		return FALSE
	var/key = "[A.icon]"
	if(!known[key])
		known[key] = icon_states(A.icon)
	return !(A.icon_state in known[key])

/// A sprite in its file that looks like the unpowered version of what it's showing
/proc/uc_off_sprite(atom/A)
	if(!A.icon || !A.icon_state)
		return null
	var/list/states = icon_states(A.icon)
	for(var/suffix in list("-off", "_off", "off", "-nopower", "_nopower", "-unpowered", "_unpowered", "-p", "_p"))
		if("[A.icon_state][suffix]" in states)
			return "[A.icon_state][suffix]"

/proc/uc_blackout(off)
	for(var/obj/machinery/power/apc/A as anything in GLOB.apcs_list)
		if(A.area && is_station_level(A.z))
			A.operating = !off
			A.update()
			A.update_icon()

/proc/uc_note(list/notes, kind, obj/machinery/M, detail)
	var/key = "[kind]: [M.type]"
	var/list/entry = notes[key]
	if(!entry)
		entry = list(0, detail)
		notes[key] = entry
	entry[1] += 1

/proc/uc_print(list/notes, list/totals)
	var/list/keys = sortList(notes.Copy())
	for(var/key in keys)
		var/list/entry = notes[key]
		var/type_name = copytext(key, findtext(key, ": ") + 2)
		uc_log("[key] ([entry[1]] of [totals[type_name]]): [entry[2]]")

/proc/uc_differs(list/a, list/b)
	return a["state"] != b["state"] || a["overlays"] != b["overlays"] || a["vis"] != b["vis"] || a["light"] != b["light"]

/proc/uc_show(list/look)
	return "[look["state"]] +[look["overlays"]] vis[look["vis"]] light[look["light"]]"

/proc/uc_power_sweep()
	var/list/machines = uc_machines()
	var/list/totals = list()
	var/list/before = list()
	for(var/obj/machinery/M as anything in machines)
		totals["[M.type]"] += 1
		before[M] = uc_look(M)
	uc_log("== power sweep: [length(machines)] machines of [length(totals)] types")
	uc_blackout(TRUE)
	sleep(7 SECONDS)
	var/list/notes = list()
	var/list/dark = list()
	for(var/obj/machinery/M as anything in machines)
		if(QDELETED(M))
			continue
		var/list/now = uc_look(M)
		dark[M] = now
		if(M.stat & BROKEN)
			continue
		if(M.use_power && !istype(M, /obj/machinery/light) && !(M.stat & NOPOWER))
			uc_note(notes, "SAYS POWERED IN A BLACKOUT", M, uc_show(now))
		if(now["light"] && M.use_power && !istype(M, /obj/machinery/light))
			uc_note(notes, "STILL LIT IN A BLACKOUT", M, uc_show(now))
		if(uc_sprite_missing(M))
			uc_note(notes, "INVISIBLE IN A BLACKOUT", M, uc_show(now))
		if(M.use_power && !uc_differs(before[M], now))
			var/off = uc_off_sprite(M)
			if(off)
				uc_note(notes, "LOOKS THE SAME WITHOUT POWER (it has an off sprite)", M, "[uc_show(now)], unused [off]")
	uc_blackout(FALSE)
	sleep(9 SECONDS)
	for(var/obj/machinery/M as anything in machines)
		if(QDELETED(M) || (M.stat & BROKEN))
			continue
		var/list/now = uc_look(M)
		var/list/was = before[M]
		if(M.stat & NOPOWER && !(was["stat"] & NOPOWER))
			uc_note(notes, "STILL NO POWER AFTER RESTORE", M, uc_show(now))
		if(uc_differs(was, now))
			uc_note(notes, "LOOKS DIFFERENT AFTER RESTORE", M, "[uc_show(was)] -> [uc_show(now)]")
		if(was["running"] && !now["running"])
			uc_note(notes, "STOPPED RUNNING AFTER RESTORE", M, uc_show(now))
	uc_print(notes, totals)

/proc/uc_has_broken_sprite(obj/machinery/M)
	if(!M.icon)
		return FALSE
	for(var/state in icon_states(M.icon))
		if(findtext(state, "broken") || findtext(state, "-b") == length(state) - 1 || findtext(state, "_b") == length(state) - 1)
			return TRUE
	return FALSE

/proc/uc_broken_sweep()
	var/list/one_of_each = list()
	for(var/obj/machinery/M as anything in uc_machines())
		if(!one_of_each["[M.type]"] && M.max_integrity && M.integrity_failure)
			one_of_each["[M.type]"] = M
	uc_log("== broken sweep: [length(one_of_each)] types that can break")
	var/list/before = list()
	for(var/key in one_of_each)
		var/obj/machinery/M = one_of_each[key]
		before[M] = uc_look(M)
		M.obj_break("melee")
	sleep(3 SECONDS)
	var/list/notes = list()
	var/list/totals = list()
	for(var/key in one_of_each)
		var/obj/machinery/M = one_of_each[key]
		totals[key] = 1
		if(QDELETED(M))
			continue
		var/list/now = uc_look(M)
		if(!(M.stat & BROKEN))
			uc_note(notes, "did not break", M, uc_show(now))
			continue
		if(uc_sprite_missing(M))
			uc_note(notes, "INVISIBLE WHEN BROKEN", M, uc_show(now))
		if(now["light"])
			uc_note(notes, "BROKEN BUT LIT", M, uc_show(now))
		if(!uc_differs(before[M], now))
			uc_note(notes, uc_has_broken_sprite(M) ? "LOOKS THE SAME BROKEN (it has a broken sprite)" : "looks the same broken", M, uc_show(now))
	uc_blackout(TRUE)
	sleep(5 SECONDS)
	uc_blackout(FALSE)
	sleep(5 SECONDS)
	for(var/key in one_of_each)
		var/obj/machinery/M = one_of_each[key]
		if(!QDELETED(M) && (M.stat & BROKEN) && M.light_range && M.light_power)
			uc_note(notes, "LIT AGAIN AFTER THE POWER CAME BACK WHILE BROKEN", M, uc_show(uc_look(M)))
	uc_print(notes, totals)

// ---- one at a time, what the sweeps can't reach

/proc/uc_apc_named(wanted)
	for(var/obj/machinery/power/apc/A as anything in GLOB.apcs_list)
		if(A.name == wanted && is_station_level(A.z))
			return A

/proc/uc_area_power(area/A)
	return "light [A.power_light] equip [A.power_equip] environ [A.power_environ]"

/proc/uc_recharger()
	var/obj/machinery/recharger/R
	for(var/obj/machinery/recharger/candidate in GLOB.machines)
		if(is_station_level(candidate.z) && !candidate.charging)
			R = candidate
			break
	if(!R)
		uc_log("recharger: none found")
		return
	var/area/room = get_area(R)
	var/obj/machinery/power/apc/A = room.get_apc()
	var/obj/item/gun/energy/laser/gun = new(R)
	gun.cell.use(gun.cell.charge)
	R.setCharging(gun)
	sleep(5 SECONDS)
	uc_log("recharger: empty gun in it, charge [gun.cell.charge], running [(R.datum_flags & DF_ISPROCESSING) ? "yes" : "no"]")
	A.operating = FALSE
	A.update()
	sleep(5 SECONDS)
	var/charge = gun.cell.charge
	uc_log("recharger: power off, charge [charge], running [(R.datum_flags & DF_ISPROCESSING) ? "yes" : "no"]")
	A.operating = TRUE
	A.update()
	sleep(8 SECONDS)
	uc_log("recharger: power back, charge [gun.cell.charge] (was [charge]), running [(R.datum_flags & DF_ISPROCESSING) ? "yes" : "no"], [gun.cell.charge > charge ? "charging again" : "STOPPED FOR GOOD"]")

/proc/uc_repair(turf/spot)
	var/obj/machinery/newscaster/N
	for(var/obj/machinery/newscaster/candidate in GLOB.machines)
		if(is_station_level(candidate.z) && !(candidate.stat & BROKEN))
			N = candidate
			break
	if(!N)
		uc_log("repair: no newscaster found")
		return
	var/area/room = get_area(N)
	var/obj/machinery/power/apc/A = room.get_apc()
	A.operating = FALSE
	A.update()
	sleep(2)
	N.obj_break("melee")
	A.operating = TRUE
	A.update()
	sleep(2)
	uc_log("repair: broke in the dark, room's power back, its own power flag [(N.stat & NOPOWER) ? "still says none" : "fine"]")
	var/mob/living/carbon/human/H = new(get_turf(N))
	H.status_flags |= GODMODE
	var/obj/item/weldingtool/largetank/W = new(H)
	H.put_in_hands(W)
	W.attack_self(H)
	N.attackby(W, H)
	sleep(5)
	uc_log("repair: welded, broken [(N.stat & BROKEN) ? "STILL" : "no"], its own power flag [(N.stat & NOPOWER) ? "STILL SAYS NONE" : "fine"]")
	qdel(H)

/proc/uc_emp()
	var/obj/machinery/power/apc/A = uc_apc_named("Law Office APC")
	if(!A)
		uc_log("emp: no Law Office APC")
		return
	A.emp_act(EMP_HEAVY)
	uc_log("emp: hit, lighting [A.lighting] equipment [A.equipment] environ [A.environ], [uc_area_power(A.area)]")
	A.reset("emp")
	sleep(4 SECONDS)
	uc_log("emp: worn off, lighting [A.lighting] equipment [A.equipment] environ [A.environ], [uc_area_power(A.area)], [A.area.power_light ? "lights back" : "LIGHTS LEFT OFF"]")

/proc/uc_electronics()
	var/obj/machinery/power/apc/A = uc_apc_named("EVA Storage APC")
	if(!A)
		uc_log("electronics: no EVA Storage APC")
		return
	var/mob/living/carbon/human/H = new(get_turf(A))
	H.status_flags |= GODMODE
	var/obj/item/screwdriver/S = new(H)
	H.put_in_hands(S)
	var/obj/item/stock_parts/cell/C = A.cell
	A.opened = 1
	A.cell = null
	A.screwdriver_act(H, S)
	uc_log("electronics: unfastened, MAINT [(A.stat & MAINT) ? "yes" : "no"], [uc_area_power(A.area)], [A.area.power_equip ? "ROOM STILL POWERED" : "room off"]")
	A.screwdriver_act(H, S)
	A.cell = C
	A.opened = 0
	sleep(4 SECONDS)
	uc_log("electronics: fastened again, [uc_area_power(A.area)]")
	qdel(H)

/proc/uc_blackout_event()
	var/obj/machinery/power/apc/broken = uc_apc_named("Brig APC")
	var/obj/machinery/power/apc/working = uc_apc_named("Law Office APC")
	if(!broken || !working)
		uc_log("blackout event: APCs not found")
		return
	broken.operating = TRUE
	broken.stat &= ~BROKEN
	broken.obj_integrity = broken.max_integrity
	broken.update()
	power_failure()
	sleep(2 SECONDS)
	broken.obj_break("melee")
	sleep(1 SECONDS)
	power_restore()
	sleep(4 SECONDS)
	uc_log("blackout event: broken APC's room [uc_area_power(broken.area)], [broken.area.power_equip ? "POWERED ANYWAY" : "stays dark"]")
	uc_log("blackout event: working APC's room [uc_area_power(working.area)], [working.area.power_equip ? "back" : "NOT BACK"]")

/proc/uc_research()
	var/obj/machinery/rnd/server/S
	for(var/obj/machinery/rnd/server/candidate in SSresearch.servers)
		if(is_station_level(candidate.z))
			S = candidate
			break
	if(!S)
		uc_log("research: no server found")
		return
	var/area/room = get_area(S)
	var/obj/machinery/power/apc/A = room.get_apc()
	uc_log("research: powered, working [S.working ? "yes" : "no"], sprite [S.icon_state]")
	A.operating = FALSE
	A.update()
	sleep(2)
	uc_log("research: power off, working [S.working ? "STILL YES" : "no"], sprite [S.icon_state]")
	A.operating = TRUE
	A.update()
	sleep(2)
	uc_log("research: power back, working [S.working ? "yes" : "STILL NO"], sprite [S.icon_state]")

/proc/uc_states(thing)
	. = list()
	var/list/parts = islist(thing) ? thing : list(thing)
	for(var/part in parts)
		var/mutable_appearance/MA = part
		if(MA)
			. += MA.icon_state

/proc/uc_redraws(turf/spot)
	var/mob/living/carbon/human/H = new(spot)
	H.status_flags |= GODMODE
	var/obj/item/clothing/suit/armor/reactive/armour = new(H)
	H.equip_to_slot_or_del(armour, ITEM_SLOT_OCLOTHING)
	var/obj/item/match/M = new(H)
	H.put_in_hands(M)
	M.matchignite()
	H.update_inv_hands()
	sleep(2)
	var/list/worn = uc_states(H.overlays_standing[SUIT_LAYER])
	var/list/held = uc_states(H.overlays_standing[HANDS_LAYER])
	armour.ui_action_click(H, null)
	M.matchburnout()
	sleep(2)
	var/list/worn_after = uc_states(H.overlays_standing[SUIT_LAYER])
	var/list/held_after = uc_states(H.overlays_standing[HANDS_LAYER])
	uc_log("worn toggle: sprite [jointext(worn, ",")] -> [jointext(worn_after, ",")], item now [armour.icon_state], [(armour.icon_state in worn_after) ? "redrawn" : "STALE"]")
	uc_log("burnt-out match in hand: [jointext(held, ",")] -> [jointext(held_after, ",")], [("cigoff" in held_after) ? "redrawn" : "STALE"]")
	qdel(H)

/proc/uc_dominator(turf/spot)
	var/obj/machinery/dominator/D = new(spot)
	var/was = D.light_range
	D.obj_break("melee")
	uc_log("dominator: broken, sprite [D.icon_state], light [was] -> [D.light_range], countdown [D.countdown?.started ? "STILL RUNNING" : "stopped"]")
	qdel(D)

/proc/update_check_run()
	UNTIL(SSticker.initialized) // it reads data/mode.txt when it starts up
	GLOB.master_mode = "extended" // data/mode.txt is whatever the last real round left there, and most modes won't start with nobody playing
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(15 SECONDS)
	uc_log("round state [SSticker.current_state], [length(GLOB.apcs_list)] APCs")
	var/turf/spot = uc_floor()
	uc_redraws(spot)
	uc_blood("first blood on clean items, gloves on", spot, FALSE, TRUE, FALSE, TRUE)
	uc_blood("blood on items that already have fingerprints, gloves on", spot, TRUE, TRUE)
	uc_blood("bare hands", spot, TRUE, FALSE)
	uc_blood("welding mask over the eyes: the shoes were skipped", spot, TRUE, TRUE, TRUE)
	uc_power_sweep()
	uc_research()
	uc_recharger()
	uc_repair(spot)
	uc_emp()
	uc_electronics()
	uc_blackout_event()
	uc_dominator(spot)
	uc_broken_sweep()
	uc_log("done")
	sleep(5)
	del(world)
