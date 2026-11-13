// Reagent heat check (tools/chem_heat_check/run_chem_heat_check.sh): heating by volume, drift towards the air, the chem tank, headless on
// Runtime Station. Lines to data/chem_heat_check.txt, PASS/FAIL each, with the numbers.
/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("chem-heat-check" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_chem_heat_check))
	return ..()

GLOBAL_LIST_EMPTY(chem_heat_lines)
GLOBAL_VAR_INIT(chem_heat_fails, 0)

/proc/chem_heat_note(ok, text)
	GLOB.chem_heat_lines += "[ok ? "PASS" : "FAIL"] [text]"
	if(!ok)
		GLOB.chem_heat_fails++

/proc/chem_heat_beaker(turf/T, amount, temp, reagent = /datum/reagent/water)
	var/obj/item/reagent_containers/glass/beaker/bluespace/B = new(T) // 300 units
	B.reagents.add_reagent(reagent, amount, reagtemp = temp)
	return B

/// Moves R as if minutes had passed since it last drifted, and returns its temperature
/proc/chem_heat_drift(datum/reagents/R, minutes)
	R.drift_last = world.time - minutes MINUTES
	R.drift_next = 0
	R.process()
	return R.chem_temp

/proc/run_chem_heat_check()
	sleep(5 SECONDS)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	var/turf/open/floor/spot
	for(var/turf/open/floor/F in GLOB.station_turfs)
		if(F.density || !F.air || abs(F.air.return_pressure() - ONE_ATMOSPHERE) > 5 || locate(/obj) in F)
			continue
		spot = F
		break
	var/ambient = spot.air.return_temperature()
	GLOB.chem_heat_lines += "spot [AREACOORD(spot)]: [round(ambient, 0.01)] K, [round(spot.air.return_pressure(), 0.1)] kPa"

	// 1 A hot tool's heat by volume: expose_temperature(3800), a lit welder, once each
	var/list/heats = list()
	for(var/amount in list(5, 10, 50, 100, 300))
		var/obj/item/reagent_containers/glass/beaker/bluespace/B = chem_heat_beaker(spot, amount, 300)
		B.reagents.expose_temperature(3800)
		heats["[amount]"] = B.reagents.chem_temp
		qdel(B)
	var/obj/structure/reagent_dispensers/chemical/tank = new(spot)
	tank.reagents.add_reagent(/datum/reagent/water, 1000, reagtemp = 300)
	tank.reagents.expose_temperature(3800)
	heats["1000 (tank)"] = tank.reagents.chem_temp
	var/list/heat_text = list()
	for(var/k in heats)
		heat_text += "[k]u [heats[k]] K"
	chem_heat_note(heats["50"] == 370 && heats["100"] < heats["50"] && heats["10"] > heats["50"] && heats["1000 (tank)"] < heats["100"], "welder once on water at 300 K: [jointext(heat_text, ", ")] (was +70 K for any amount)")

	// 2 The chem tank: a lit lighter, by volume
	var/mob/living/carbon/human/H = new(spot)
	var/obj/item/lighter/L = new(spot)
	L.lit = TRUE
	tank.reagents.chem_temp = 300
	tank.attackby(L, H)
	var/after_full = tank.reagents.chem_temp
	tank.reagents.remove_all(900)
	tank.reagents.chem_temp = 300
	tank.attackby(L, H)
	var/after_100 = tank.reagents.chem_temp
	chem_heat_note(after_full > 300 && after_100 > after_full, "lighter on the chem tank: 1000u 300 -> [after_full] K, 100u 300 -> [after_100] K (was +15 K)")

	// 3 The fill gauge: its icon, and the quarter it shows
	var/list/gauge = list()
	for(var/amount in list(100, 250, 251, 500, 750, 751, 1000))
		tank.reagents.clear_reagents()
		tank.reagents.add_reagent(/datum/reagent/water, amount, reagtemp = 300)
		tank.update_icon()
		var/shown = "none"
		for(var/O in tank.overlays)
			if(findtext("[O:icon_state]", "tankfilling"))
				shown = "[O:icon_state][O:icon ? "" : " (NO ICON)"]"
		gauge += "[amount]u [shown]"
	var/gauge_text = jointext(gauge, ", ")
	chem_heat_note(!findtext(gauge_text, "NO ICON") && findtext(gauge_text, "250u tankfilling1") && findtext(gauge_text, "251u tankfilling2") && findtext(gauge_text, "751u tankfilling4"), "fill gauge: [gauge_text]")

	// 4 Science goggles read the tank (not see-through) and its temperature; without them, only the amount
	var/list/plain = tank.examine(H)
	H.equip_to_slot_or_del(new /obj/item/clothing/glasses/science(H), ITEM_SLOT_EYES)
	var/list/goggled = tank.examine(H)
	var/plain_text = jointext(plain, " | ")
	var/goggled_text = jointext(goggled, " | ")
	chem_heat_note(!findtext(plain_text, "Temperature") && findtext(goggled_text, "units of Water") && findtext(goggled_text, "Temperature: "), "examine without goggles: [plain_text]")
	GLOB.chem_heat_lines += "     with goggles: [goggled_text]"

	// 5 Wrenching it down
	var/obj/item/wrench/W = new(spot)
	H.put_in_active_hand(W)
	INVOKE_ASYNC(tank, TYPE_PROC_REF(/atom, wrench_act), H, W)
	sleep(4 SECONDS)
	var/bolted = tank.anchored
	INVOKE_ASYNC(tank, TYPE_PROC_REF(/atom, wrench_act), H, W)
	sleep(4 SECONDS)
	chem_heat_note(bolted && !tank.anchored, "wrench: bolted [bolted ? "yes" : "no"], then unbolted [tank.anchored ? "no" : "yes"]")

	// 6 Drift: hot beakers on the floor start drifting by themselves (handle_reactions) and cool by size
	var/list/drift = list()
	var/drift_ok = TRUE
	for(var/amount in list(5, 50, 300))
		var/obj/item/reagent_containers/glass/beaker/bluespace/B = chem_heat_beaker(spot, amount, 500)
		var/started = (B.reagents.datum_flags & DF_ISPROCESSING) ? TRUE : FALSE
		var/t1 = chem_heat_drift(B.reagents, 1)
		var/t10 = chem_heat_drift(B.reagents, 9)
		drift += "[amount]u 500 -> [round(t1, 0.1)] K after 1 min, [round(t10, 0.1)] K after 10[started ? "" : " (NOT STARTED)"]"
		drift_ok = drift_ok && started && t1 < 500 && t10 < t1 && t10 > ambient
		qdel(B)
	tank.reagents.clear_reagents()
	tank.reagents.add_reagent(/datum/reagent/water, 1000, reagtemp = 500)
	var/tank1 = chem_heat_drift(tank.reagents, 1)
	var/tank10 = chem_heat_drift(tank.reagents, 9)
	drift += "tank 1000u 500 -> [round(tank1, 0.1)] K after 1 min, [round(tank10, 0.1)] K after 10"
	chem_heat_note(drift_ok && tank10 > ambient && tank1 < 500, "drift in room air: [jointext(drift, "; ")]")
	var/obj/item/reagent_containers/glass/beaker/bluespace/cold = chem_heat_beaker(spot, 50, 200)
	var/cold10 = chem_heat_drift(cold.reagents, 10)
	chem_heat_note(cold10 > 200 && cold10 < ambient, "a chilled beaker warms: 50u 200 -> [round(cold10, 0.1)] K after 10 min")
	var/datum/reagent/ice = cold.reagents.reagent_list[1]
	var/frozen_state = ice.reagent_state
	cold.reagents.chem_temp = 280
	chem_heat_drift(cold.reagents, 1)
	chem_heat_note(frozen_state == SOLID && ice.reagent_state == LIQUID, "water frozen at 200 K ([frozen_state == SOLID ? "solid" : "not solid"]) melts as it drifts past 273 K ([ice.reagent_state == LIQUID ? "liquid" : "not liquid"])")
	cold.reagents.chem_temp = ambient + 0.3
	cold.reagents.drift_next = 0
	var/stop = cold.reagents.process()
	chem_heat_note(stop == PROCESS_KILL, "within [REAGENT_DRIFT_STOP] K of the air it stops drifting")
	qdel(cold)

	// 7 Kept from the air: in a chem heater, a grenade, a fridge; not in a bag on a mob
	var/obj/machinery/chem_heater/heater = new(spot)
	var/obj/item/reagent_containers/glass/beaker/bluespace/in_heater = chem_heat_beaker(spot, 50, 500)
	in_heater.forceMove(heater)
	var/obj/item/grenade/chem_grenade/G = new(spot)
	var/obj/item/reagent_containers/glass/beaker/bluespace/in_grenade = chem_heat_beaker(spot, 50, 500)
	in_grenade.forceMove(G)
	var/obj/item/storage/backpack/pack = new(spot)
	H.equip_to_slot_or_del(pack, ITEM_SLOT_BACK)
	var/obj/item/reagent_containers/glass/beaker/bluespace/in_pack = chem_heat_beaker(spot, 50, 500)
	in_pack.forceMove(pack)
	var/heater_t = chem_heat_drift(in_heater.reagents, 10)
	var/grenade_t = chem_heat_drift(in_grenade.reagents, 10)
	var/pack_t = chem_heat_drift(in_pack.reagents, 10)
	chem_heat_note(heater_t == 500 && grenade_t == 500 && pack_t < 500, "kept: in a chem heater [round(heater_t, 0.1)] K, in a grenade [round(grenade_t, 0.1)] K; a backpack on a mob [round(pack_t, 0.1)] K, after 10 min")

	// 7b A chemical heater drives a chem tank driven beside it, holds it there against the air, and leaves a loose one alone
	var/turf/open/floor/heater_spot
	var/turf/open/floor/tank_spot
	var/turf/open/floor/loose_spot
	for(var/turf/open/floor/F in GLOB.station_turfs)
		var/turf/open/floor/E = get_step(F, EAST)
		var/turf/open/floor/E2 = get_step(E, EAST)
		var/turf/open/floor/E3 = get_step(E2, EAST)
		if(!istype(E) || !istype(E2) || !istype(E3) || F.density || E.density || E2.density || E3.density || (locate(/obj) in F) || (locate(/obj) in E) || (locate(/obj) in E2) || (locate(/obj) in E3))
			continue
		heater_spot = E
		tank_spot = F
		loose_spot = E2
		break
	var/obj/machinery/chem_heater/drive = new(heater_spot)
	drive.on = TRUE
	drive.target_temperature = 500
	var/obj/structure/reagent_dispensers/chemical/driven = new(tank_spot)
	driven.anchored = TRUE
	driven.reagents.add_reagent(/datum/reagent/water, 1000, reagtemp = 300)
	var/obj/structure/reagent_dispensers/chemical/loose = new(loose_spot)
	loose.reagents.add_reagent(/datum/reagent/water, 1000, reagtemp = 300)
	var/list/ticks = list()
	var/reached = 0
	for(var/i in 1 to 300) // SSmachines every 2 s: 10 minutes
		drive.process()
		if(i in list(15, 45, 90, 150))
			ticks += "[i * 2] s [round(driven.reagents.chem_temp, 0.1)] K"
		if(!reached && driven.reagents.chem_temp >= 475)
			reached = i * 2
	var/list/ui = drive.ui_data(H)
	var/held = chem_heat_drift(driven.reagents, 10)
	chem_heat_note(reached && loose.reagents.chem_temp == 300 && held >= 475 && ui["isTankLinked"] && ui["tankTemp"] >= 475, "heater (stock laser) to 500 K, a full tank driven beside it: [jointext(ticks, ", ")], 95% at [reached] s; held there against the air: [round(held, 0.1)] K; a loose tank beside it [loose.reagents.chem_temp] K; window shows the tank [ui["isTankLinked"] ? "yes" : "NO"]")
	drive.on = FALSE
	var/drifts_again = chem_heat_drift(driven.reagents, 0)
	driven.reagents.drift_held_until = 0
	drifts_again = chem_heat_drift(driven.reagents, 10)
	chem_heat_note(drifts_again < held, "heater off, the tank drifts again: [round(held, 0.1)] -> [round(drifts_again, 0.1)] K after 10 min")
	qdel(drive)
	qdel(driven)
	qdel(loose)

	// 8 A hot room heats a beaker till it reacts: oil -> ash at 480 K, by drifting
	var/turf/open/floor/hot = get_step(spot, NORTH)
	if(!istype(hot) || !hot.air)
		hot = spot
	var/old_temp = hot.air.return_temperature()
	hot.air.temperature = 900
	var/obj/item/reagent_containers/glass/beaker/bluespace/oil = chem_heat_beaker(hot, 30, 400, /datum/reagent/oil)
	var/had_ash = oil.reagents.has_reagent(/datum/reagent/ash)
	var/oil_t = chem_heat_drift(oil.reagents, 10)
	var/has_ash = oil.reagents.has_reagent(/datum/reagent/ash)
	hot.air.temperature = old_temp
	chem_heat_note(!had_ash && has_ash && oil_t > 480, "30u oil at 400 K in 900 K air: [round(oil_t, 0.1)] K after 10 min, [has_ash ? "turned to ash" : "NO ASH"]")
	qdel(oil)

	// 9 Space: thin air, slow
	var/turf/open/space/void
	for(var/turf/open/space/S in block(locate(1, 1, spot.z), locate(world.maxx, world.maxy, spot.z)))
		void = S
		break
	if(void)
		var/obj/item/reagent_containers/glass/beaker/bluespace/out = chem_heat_beaker(void, 50, 500)
		var/out_t = chem_heat_drift(out.reagents, 10)
		GLOB.chem_heat_lines += "     in space ([void.air ? "[round(void.air.return_temperature(), 0.1)] K air" : "no air"]): 50u 500 -> [round(out_t, 0.1)] K after 10 min"
		qdel(out)

	// 10 Gone: a drifting beaker deleted leaves SSprocessing
	var/obj/item/reagent_containers/glass/beaker/bluespace/gone = chem_heat_beaker(spot, 50, 500)
	var/datum/reagents/gone_reagents = gone.reagents
	var/was_in = (gone_reagents in SSprocessing.processing)
	qdel(gone)
	chem_heat_note(was_in && !(gone_reagents in SSprocessing.processing), "a deleted drifting beaker leaves SSprocessing ([was_in ? "was in" : "WASN'T IN"])")
	gone_reagents = null

	// 11 A pile: 500 hot beakers on one tile, each drift step timed, and SSprocessing's cost while they drift
	var/list/pile = list()
	for(var/i in 1 to 500)
		pile += chem_heat_beaker(spot, 50, 450)
	var/mark = TICK_USAGE_REAL
	for(var/obj/item/reagent_containers/glass/beaker/bluespace/B as anything in pile)
		B.reagents.drift_last = world.time - 1 SECONDS
		B.reagents.drift_next = 0
		B.reagents.process()
	var/pile_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark)
	var/cost_before = SSprocessing.cost
	sleep(10 SECONDS)
	var/drifting = 0
	for(var/obj/item/reagent_containers/glass/beaker/bluespace/B as anything in pile)
		if(B.reagents.datum_flags & DF_ISPROCESSING)
			drifting++
	chem_heat_note(pile_ms < 25 && drifting == 500, "500 hot beakers on one tile: one drift step each [round(pile_ms, 0.01)] ms ([round(pile_ms * 1000 / 500, 0.1)] us each), [drifting] drifting, SSprocessing [round(cost_before, 0.01)] -> [round(SSprocessing.cost, 0.01)] ms a run, [length(SSprocessing.processing)] processing")
	QDEL_LIST(pile)

	GLOB.chem_heat_lines += "[GLOB.chem_heat_fails ? "[GLOB.chem_heat_fails] FAILED" : "ALL PASS"]"
	fdel("data/chem_heat_check.txt")
	text2file(jointext(GLOB.chem_heat_lines, "\n"), "data/chem_heat_check.txt")
