// Department gear self-test - headless checks of the department gear pass, driving the real code in the real engine.
//
// Boot:     DreamDaemon hippiestation.dmb -params "dept-gear-test=1"
// Results:  data/dept_gear_test/results.txt, one PASS/FAIL line per check, then the world shuts down.
//
// Everything but the pager runs in reserved space, well away from the station: a sealed room with station air for the
// scrubber pack, trays, RPED, cargo console and multitool, and open space for the bombs. The pager runs on the station,
// since telecomms only hears signals sent from its own z-levels. The bombs are real: each tank transfer valve, tank and
// one-tank bomb is predicted by the blast yield calculator, then set off, and the explosion the doppler arrays hear
// (COMSIG_GLOB_EXPLOSION, uncapped ranges) is compared with the prediction.

#define DEPT_GEAR_TEST_DIR "data/dept_gear_test/"

/proc/run_dept_gear_test()
	Master.sleep_offline_after_initializations = FALSE
	world.sleep_offline = FALSE
	sleep(5 SECONDS) // let the first ticks settle
	fdel(DEPT_GEAR_TEST_DIR)
	// Air, object processing and explosions only run once the round is on, so start it (as the bot gym does)
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	log_world("DEPT GEAR TEST: round state [SSticker.current_state], starting")
	var/datum/dept_gear_test/test = new
	test.run_all()
	text2file(jointext(test.lines, "\n"), "[DEPT_GEAR_TEST_DIR]results.txt")
	log_world("DEPT GEAR TEST: done, [test.passed] passed, [test.failed] failed")
	Master.Shutdown()
	qdel(world)

/// A tgui that reads as interactive, so ui_act() can be driven without a client
/datum/tgui/dept_gear_test_stub/New()
	status = UI_INTERACTIVE

/datum/dept_gear_test
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	var/datum/turf_reservation/reservation
	/// The sealed room's floor, bottom-left first
	var/list/turf/open/floor/room = list()
	/// Where the bombs go off: open space, far from the room
	var/turf/blast_site
	/// Explosions heard, newest last: list(x, y, orig_dev, orig_heavy, orig_light, world.time)
	var/list/explosions = list()
	var/datum/tgui/dept_gear_test_stub/stub_ui

/datum/dept_gear_test/proc/check(name, condition, detail)
	if(condition)
		passed++
	else
		failed++
	lines += "[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]"

/datum/dept_gear_test/proc/note(text)
	lines += "     [text]"

/datum/dept_gear_test/proc/run_all()
	lines += "Department gear self-test, BYOND [world.byond_version].[world.byond_build]"
	stub_ui = new
	RegisterSignal(SSdcs, COMSIG_GLOB_EXPLOSION, PROC_REF(on_explosion))
	if(!build_site())
		lines += "FAIL couldn't reserve space for the test"
		failed++
		return
	for(var/test in list(PROC_REF(test_maint_loot), PROC_REF(test_godmode_money), PROC_REF(test_rped), PROC_REF(test_ledger), PROC_REF(test_plant_hud), PROC_REF(test_scrubber_pack), PROC_REF(test_multitool), PROC_REF(test_pager), PROC_REF(test_bombs), PROC_REF(test_screentips), PROC_REF(test_examine_more), PROC_REF(test_orbit_menu), PROC_REF(test_order_amounts), PROC_REF(test_crate_trolley)))
		lines += ""
		lines += "== [replacetext("[test]", "/datum/dept_gear_test/proc/", "")]"
		try
			call(src, test)()
		catch(var/exception/e)
			check("[test] ran without a runtime", FALSE, "[e] at [e.file]:[e.line]")
	lines += ""
	lines += "[passed] passed, [failed] failed"
	UnregisterSignal(SSdcs, COMSIG_GLOB_EXPLOSION)

/datum/dept_gear_test/proc/on_explosion(datum/source, turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, took, orig_dev_range, orig_heavy_range, orig_light_range)
	explosions += list(list(epicenter.x, epicenter.y, orig_dev_range, orig_heavy_range, orig_light_range, world.time))

/// A 12x12 room walled in with station air in the left of a reservation, and open space 40 tiles to its right
/datum/dept_gear_test/proc/build_site()
	reservation = SSmapping.RequestBlockReservation(80, 20)
	if(!reservation)
		return FALSE
	var/x0 = reservation.bottom_left_coords[1] + 2
	var/y0 = reservation.bottom_left_coords[2] + 2
	var/z = reservation.bottom_left_coords[3]
	var/area/test_area = new /area/bot_gym
	for(var/x in x0 to x0 + 13)
		for(var/y in y0 to y0 + 13)
			var/turf/T = locate(x, y, z)
			var/area/old_area = T.loc
			old_area.contents -= T
			test_area.contents += T
			T.change_area(old_area, test_area)
			if(x == x0 || x == x0 + 13 || y == y0 || y == y0 + 13)
				T.ChangeTurf(/turf/closed/indestructible/riveted, flags = CHANGETURF_IGNORE_AIR)
			else
				room += T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	for(var/turf/open/F in room)
		F.air.parse_gas_string(OPENTURF_DEFAULT_ATMOS)
		F.update_visuals()
		SSair.add_to_active(F)
	blast_site = locate(x0 + 55, y0 + 8, z)
	sleep(2 SECONDS)
	return TRUE

/// The room's floor tile at (dx, dy) from its bottom-left corner, 1-based
/datum/dept_gear_test/proc/spot(dx, dy)
	var/turf/first = room[1]
	return locate(first.x + dx - 1, first.y + dy - 1, first.z)

/datum/dept_gear_test/proc/make_human(turf/T, name, job)
	var/mob/living/carbon/human/H = new(T)
	H.real_name = name
	H.name = name
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), ITEM_SLOT_ICLOTHING) // the ID and belt slots need one
	var/obj/item/card/id/card = new(H)
	card.registered_name = name
	card.assignment = job
	card.update_label()
	H.equip_to_slot_or_del(card, ITEM_SLOT_ID)
	return H

// ---------------------------------------------------------------------------------------------

/// Every item path in a (nested) loot table
/datum/dept_gear_test/proc/loot_leaves(list/L)
	. = list()
	for(var/entry in L)
		if(islist(entry))
			. += loot_leaves(entry)
		else if(ispath(entry))
			. += entry

/datum/dept_gear_test/proc/test_maint_loot()
	var/list/tiers = list()
	for(var/list/tier in GLOB.maintenance_loot)
		tiers += list(tier)
	check("maintenance loot has its five tiers", length(tiers) >= 5, "[length(tiers)] tiers")
	var/list/tier_of = list()
	var/list/tier_names = list("trash", "common", "uncommon", "rare", "oddity")
	for(var/i in 1 to min(5, length(tiers)))
		for(var/path in loot_leaves(tiers[i]))
			tier_of[path] = tier_names[i]
	var/list/counts = list()
	var/bad = 0
	for(var/i in 1 to 10000)
		var/picked = pick_weight_recursive(GLOB.maintenance_loot)
		if(!ispath(picked))
			bad++
			continue
		counts[tier_of[picked] || "?"]++
	note("10,000 rolls: [counts["trash"]] trash, [counts["common"]] common, [counts["uncommon"]] uncommon, [counts["rare"]] rare, [counts["oddity"] || 0] oddity")
	check("every roll gives an item", !bad, "[bad] bad rolls")
	check("the tiers come out near 45/45/9/1 percent", abs(counts["trash"] - 4500) < 400 && abs(counts["common"] - 4500) < 400 && abs(counts["uncommon"] - 900) < 200 && counts["rare"] > 40 && counts["rare"] < 180)

	// Every item in the tables spawns without a runtime
	// Out in open space, well away from the sealed room the air tests use
	var/list/leaves = loot_leaves(GLOB.maintenance_loot)
	var/turf/T = locate(blast_site.x - 15, blast_site.y, blast_site.z)
	var/failed_spawns = 0
	for(var/path in leaves)
		try
			new path(T)
		catch(var/exception/e)
			failed_spawns++
			note("[path] failed to spawn: [e]")
	sleep(1) // some fill themselves a moment later (a matchbox's matches)
	for(var/atom/movable/leftover in T)
		if(!isliving(leftover))
			qdel(leftover)
	check("all [length(leaves)] loot items spawn cleanly", !failed_spawns, "[failed_spawns] failed")
	// Worn gear does what it says
	var/obj/item/stock_parts/cell/worn/cell = new(T)
	check("a worn cell holds less and is never full", cell.maxcharge < initial(cell.maxcharge) && cell.charge < cell.maxcharge, "[cell.charge] of [cell.maxcharge] (new: [initial(cell.maxcharge)])")
	var/mob/living/carbon/human/H = make_human(locate(T.x, T.y + 2, T.z), "Maint Crawler", "Assistant")
	var/obj/item/weldingtool/rusty/welder = new(H)
	welder.sputter_chance = 100
	welder.switched_on(H)
	var/sputtered = !welder.welding
	welder.sputter_chance = 0
	welder.switched_on(H)
	check("a rusty welder sometimes won't light, and has a small tank", sputtered && welder.welding && welder.max_fuel == 10)
	welder.switched_on(H)
	var/obj/item/tank/internals/emergency_oxygen/scuffed/tank = new(T)
	var/start_moles = tank.air_contents.total_moles()
	var/obj/item/storage/toolbox/mechanical/dented/box = new(T)
	var/obj/item/reagent_containers/pill/expired/pill = new(T)
	check("a dented toolbox has a few tools in it", length(box.contents) >= 2 && length(box.contents) <= 4, "[length(box.contents)]")
	check("an expired pill claims a medicine and holds 5u of something", findtext(pill.name, "expired") && pill.reagents.total_volume == 5, "[pill.name]: [pill.reagents.total_volume]u")
	sleep(30 SECONDS)
	var/full_moles = (10 * ONE_ATMOSPHERE) * tank.volume / (R_IDEAL_GAS_EQUATION * T20C) // a new emergency tank
	check("a scuffed tank starts short and leaks", start_moles < full_moles * 0.65 && tank.air_contents.total_moles() < start_moles, "[round(start_moles, 0.001)] -> [round(tank.air_contents.total_moles(), 0.001)] mol")

	// Loot landing on a closed locker goes inside
	var/turf/locker_spot = locate(T.x, T.y - 2, T.z)
	var/obj/structure/closet/locker = new(locker_spot)
	new /obj/effect/spawner/lootdrop/maintenance/three(locker_spot)
	var/loose = 0 // stacks of the same kind merge, so count what was left outside rather than what went in
	for(var/obj/item/I in locker_spot)
		loose++
	check("maint loot that lands on a closed locker goes inside it", length(locker.contents) >= 1 && !loose, "[length(locker.contents)] in the locker, [loose] loose")
	QDEL_LIST(locker.contents)
	for(var/atom/movable/thing in list(cell, welder, tank, box, pill, locker, H))
		qdel(thing)

/datum/dept_gear_test/proc/test_godmode_money()
	var/mob/living/carbon/human/H = make_human(spot(10, 10), "Godmode Tester", "Assistant")
	var/obj/item/card/id/card = H.get_idcard()
	var/datum/bank_account/account = new("Godmode Tester", SSjob.GetJob("Assistant"))
	card.registered_account = account
	account.bank_cards += card
	account.account_balance = 10
	check("without godmode, a $500 charge is refused", !account.has_money(500) && !account.adjust_money(-500) && account.account_balance == 10)
	H.set_admin_godmode(TRUE)
	check("in godmode, any amount is there", account.has_money(1000000))
	check("in godmode, charges go through and cost nothing", account.adjust_money(-500) && account.account_balance == 10, "$[account.account_balance]")
	var/datum/bank_account/shop = new("Shopkeeper", SSjob.GetJob("Assistant"))
	check("in godmode, paying someone still pays them", shop.transfer_money(account, 300) && shop.account_balance == 300 && account.account_balance == 10)
	H.dropItemToGround(card)
	check("drop the card and it's an ordinary account again", !account.has_money(500))
	var/obj/item/card/id/admin/admin_card = new(H)
	var/datum/bank_account/admin_account = admin_card.registered_account
	check("an Admin ID comes with its own account, listed with the crew's", admin_account && (admin_card in admin_account.bank_cards) && (admin_account in SSeconomy.bank_accounts))
	check("which isn't on the payroll", !admin_account?.payday(1) && admin_account?.account_balance == 0)
	H.put_in_hands(admin_card)
	check("and carried by someone in godmode, it pays for anything", admin_account?.adjust_money(-5000) && admin_account?.has_money(1000000))
	qdel(admin_card)
	qdel(admin_account)
	H.set_admin_godmode(FALSE)
	account.bank_cards -= card
	qdel(account)
	qdel(shop)
	qdel(card)
	qdel(H)

/datum/dept_gear_test/proc/test_rped()
	var/mob/living/carbon/human/H = make_human(spot(2, 2), "RPED Tester", "Scientist")
	var/obj/machinery/autolathe/lathe = new(spot(3, 2))
	var/obj/item/storage/part_replacer/rped = new(H)
	H.put_in_hands(rped)
	for(var/i in 1 to 3)
		new /obj/item/stock_parts/matter_bin/bluespace(rped)
	new /obj/item/stock_parts/manipulator/femto(rped)
	var/closed = lathe.display_parts(H)
	note(replacetext(closed, "\n", "\n     "))
	check("parts are listed with their tier", findtext(closed, "tier 1") && findtext(closed, "Average part tier"))
	check("panel closed: says how many it could upgrade", findtext(closed, "could upgrade") && findtext(closed, "open the maintenance panel"), lathe.rped_upgrade_count(rped))
	var/list/rped_lines = rped.examine(H)
	check("RPED examine sums up its parts by tier", findtext(jointext(rped_lines, " "), "4&times; tier 4"), jointext(rped_lines, " | "))
	lathe.panel_open = TRUE
	lathe.exchange_parts(H, rped)
	var/lowest = INFINITY
	for(var/obj/item/stock_parts/P in lathe.component_parts)
		lowest = min(lowest, P.rating)
	check("RPED swapped every part up to tier 4", lowest == 4, "lowest tier now [lowest]")
	var/summary = lathe.part_tier_summary(H)
	note(summary)
	check("after the swap: average tier 4, nothing better left", findtext(summary, ">4<") && findtext(summary, "has nothing better"))
	qdel(lathe)
	qdel(H)

/datum/dept_gear_test/proc/test_ledger()
	var/datum/supply_pack/pack
	for(var/path in SSshuttle.supply_packs)
		var/datum/supply_pack/P = SSshuttle.supply_packs[path]
		if(!P.hidden && !P.contraband && !P.special && !P.DropPodOnly && P.cost <= 2000)
			pack = P
			break
	var/mob/living/carbon/human/H = make_human(spot(2, 4), "Ledger Tester", "Quartermaster")
	var/obj/machinery/computer/cargo/console = new(spot(3, 4))
	var/before = length(SSshuttle.shoppinglist)
	var/old_usr = usr
	usr = H
	console.ui_act("add", list("id" = "[pack.type]"), stub_ui)
	usr = old_usr
	var/datum/supply_order/order = length(SSshuttle.shoppinglist) > before ? SSshuttle.shoppinglist[length(SSshuttle.shoppinglist)] : null
	check("a full console's order goes on the shuttle", order)
	if(!order)
		return
	check("it's signed for by whoever ordered it", order.approved_by == "Ledger Tester (Quartermaster)", order.approved_by)
	var/datum/bank_account/cargo = SSeconomy.get_dep_account(ACCOUNT_CAR)
	cargo.adjust_money(pack.cost * 2) // make sure it can pay
	var/balance = cargo.account_balance
	SSshuttle.supply.buy()
	var/list/entry = cargo_order_ledger(1)[1]
	note(json_encode(entry))
	check("shipping it puts it in the ledger", entry["id"] == order.id)
	check("the ledger has who paid, what it cost and when", entry["paid_by"] == "Cargo budget" && entry["cost"] == pack.cost && entry["shipped_at"], "charged [balance - cargo.account_balance] of [pack.cost]")
	var/list/data = console.ui_data()
	check("the console's History tab gets the ledger", length(data["history"]) >= 1)
	qdel(console)
	qdel(H)

/datum/dept_gear_test/proc/test_plant_hud()
	var/datum/atom_hud/data/botany/hud = GLOB.huds[DATA_HUD_BOTANY]
	var/obj/machinery/hydroponics/constructable/tray = new(spot(6, 2))
	var/image/water = tray.hud_list?[PLANT_WATER_HUD]
	check("a new tray is on the botanical HUD", (tray in hud.hudatoms) && water && "[water.icon]" == "hippiestation/icons/mob/plant_hud.dmi", water ? "[water.icon] / [water.icon_state]" : "no image")
	check("empty tray: water and nutrient bars, nothing else", water?.icon_state == "water10" && tray.hud_list[PLANT_NUTRI_HUD].icon_state == "nutri10" && tray.hud_list[PLANT_HEALTH_HUD].icon_state == "", "[water?.icon_state] [tray.hud_list[PLANT_NUTRI_HUD].icon_state]")
	tray.myseed = new /obj/item/seeds/tomato(tray)
	tray.plant_health = tray.myseed.endurance
	tray.age = 1
	tray.adjustWater(-60)
	tray.update_icon()
	check("planted: full health, the water bar drops", tray.hud_list[PLANT_HEALTH_HUD].icon_state == "health10_good" && water.icon_state == "water4", "[tray.hud_list[PLANT_HEALTH_HUD].icon_state] [water.icon_state] [tray.hud_list[PLANT_GROWTH_HUD].icon_state]")
	var/endurance = tray.myseed.endurance
	tray.plant_health = endurance / 2 + 1
	tray.update_icon()
	var/just_above = tray.hud_list[PLANT_HEALTH_HUD].icon_state
	tray.plant_health = endurance / 2
	tray.update_icon()
	var/at_half = tray.hud_list[PLANT_HEALTH_HUD].icon_state
	check("the health bar turns red exactly where the tray's low-health light comes on", !findtext(just_above, "_low") && findtext(at_half, "_low"), "[just_above] at [endurance / 2 + 1], [at_half] at [endurance / 2] of [endurance]")
	tray.plant_health = endurance
	tray.harvest = 1
	tray.update_icon()
	check("ready to harvest: a full growth bar, and no badge (the tray has its own light)", tray.hud_list[PLANT_GROWTH_HUD].icon_state == "growth10" && !tray.hud_list[PLANT_ALERT_HUD].icon_state && length(tray.hud_list) == 5)
	tray.pestlevel = 6
	tray.toxic = 25
	tray.update_icon()
	check("pests hurting it outrank toxins building up", tray.hud_list[PLANT_ALERT_HUD].icon_state == "pests2", tray.hud_list[PLANT_ALERT_HUD].icon_state)
	tray.pestlevel = 0
	tray.update_icon()
	check("then the toxins show", tray.hud_list[PLANT_ALERT_HUD].icon_state == "toxic1", tray.hud_list[PLANT_ALERT_HUD].icon_state)
	tray.dead = 1
	tray.harvest = 0
	tray.update_icon()
	check("dead: no health or growth bar (the withered plant says it)", tray.hud_list[PLANT_HEALTH_HUD].icon_state == "" && tray.hud_list[PLANT_GROWTH_HUD].icon_state == "")
	var/mob/living/carbon/human/H = make_human(spot(6, 3), "Botanist Tester", "Botanist")
	var/obj/item/clothing/glasses/hud/botany/glasses = new(H)
	H.equip_to_slot_or_del(glasses, ITEM_SLOT_EYES)
	check("wearing the glasses shows the HUD", H in hud.hudusers)
	H.dropItemToGround(glasses)
	check("taking them off hides it", !(H in hud.hudusers))
	qdel(tray)
	check("a destroyed tray leaves the HUD", !(tray in hud.hudatoms))
	qdel(H)
	qdel(glasses)

/datum/dept_gear_test/proc/room_moles(gas)
	for(var/turf/open/F in room)
		. += F.air.moles[gas]

/datum/dept_gear_test/proc/test_scrubber_pack()
	var/turf/open/floor/T = spot(9, 6)
	T.air.assert_gas(/datum/gas/plasma)
	T.air.moles[/datum/gas/plasma] += 40
	T.air_update_turf(FALSE, FALSE)
	var/start_plasma = room_moles(/datum/gas/plasma)
	var/obj/item/scrubber_pack/pack = new(T)
	pack.toggle_power(null)
	var/list/progress = list()
	for(var/i in 1 to 6)
		sleep(10 SECONDS)
		progress += "[i * 10]s: [round(pack.air_contents.moles[/datum/gas/plasma], 0.1)]"
	var/caught = pack.air_contents.moles[/datum/gas/plasma]
	var/left = room_moles(/datum/gas/plasma)
	note("caught over a minute, standing still in a 144-tile room: [jointext(progress, ", ")] mol (depends on how fast the gas spreads before its first tick)")
	check("switched on, it catches plasma from the room", caught > 0.5, "caught [round(caught, 0.1)] of [round(start_plasma, 0.1)] mol; [round(left, 0.1)] left in the room")
	// One scrub, deterministically: it filters volume_rate litres of the tile's air, so it takes that share of the tile's plasma
	var/datum/gas_mixture/sample = new(CELL_VOLUME)
	sample.temperature = T20C
	sample.assert_gas(/datum/gas/plasma)
	sample.moles[/datum/gas/plasma] = 10
	var/obj/item/scrubber_pack/probe = new(T)
	probe.scrub(sample)
	var/expected = 10 * min(1, probe.volume_rate / CELL_VOLUME)
	check("one scrub takes its share of a tile's plasma", abs(probe.air_contents.moles[/datum/gas/plasma] - expected) < 0.01, "[round(probe.air_contents.moles[/datum/gas/plasma], 0.01)] of an expected [expected] mol")
	qdel(probe)
	check("and none goes missing", abs(caught + left - start_plasma) < 0.5, "[round(caught + left, 0.01)] vs [round(start_plasma, 0.01)]")
	check("it keeps the room's oxygen", !pack.air_contents.moles[/datum/gas/oxygen])
	var/mob/living/carbon/human/H = make_human(spot(8, 6), "Atmos Tester", "Atmospheric Technician")
	var/obj/machinery/portable_atmospherics/canister/canister = new(spot(8, 7))
	var/canister_before = canister.air_contents.moles[/datum/gas/plasma]
	pack.toggle_power(null)
	H.put_in_hands(pack)
	pack.afterattack(canister, H, TRUE)
	var/moved = canister.air_contents.moles[/datum/gas/plasma] - canister_before
	check("used on a canister, it empties into it", pack.air_contents.total_moles() < 0.01 && abs(moved - caught) < 0.5, "[round(moved, 0.1)] of [round(caught, 0.1)] mol moved")
	pack.air_contents.assert_gas(/datum/gas/plasma)
	pack.air_contents.moles[/datum/gas/plasma] = 150
	var/obj/item/tank/internals/plasma/empty/tank = new(spot(8, 5))
	pack.afterattack(tank, H, TRUE)
	check("used on a gas tank, it fills it only to a safe pressure", tank.air_contents.return_pressure() <= TANK_LEAK_PRESSURE && tank.air_contents.return_pressure() > TANK_LEAK_PRESSURE * 0.8 && pack.air_contents.moles[/datum/gas/plasma] > 1, "tank at [round(tank.air_contents.return_pressure())] kPa, [round(pack.air_contents.moles[/datum/gas/plasma])] mol left in the pack")
	pack.air_contents.moles[/datum/gas/plasma] = 5000
	pack.on = TRUE
	pack.process()
	check("a full tank switches it off", !pack.on, "[round(pack.air_contents.return_pressure())] kPa")
	var/turf/open/here = get_turf(H)
	var/before = here.air.moles[/datum/gas/plasma]
	qdel(pack)
	check("destroyed, it spills what it caught", here.air.moles[/datum/gas/plasma] - before > 4000)
	here.air.moles[/datum/gas/plasma] = 0
	for(var/turf/open/F in room)
		F.air.parse_gas_string(OPENTURF_DEFAULT_ATMOS)
	qdel(canister)
	qdel(tank)
	qdel(H)

/datum/dept_gear_test/proc/test_multitool()
	var/mob/living/carbon/human/H = make_human(spot(2, 9), "CE Tester", "Chief Engineer")
	var/obj/item/multitool/master/tool = new(H)
	H.put_in_hands(tool)
	var/obj/machinery/door/airlock/door = new(spot(4, 9))
	var/obj/machinery/door/airlock/other = new(spot(4, 11))
	var/obj/item/multitool/plain = new(spot(2, 10))
	check("examining a multitool works", islist(tool.examine(H)) && islist(plain.examine(H)))
	qdel(plain)
	tool.linking = TRUE
	tool.melee_attack_chain(H, door)
	check("a closed panel can't take a probe", !length(tool.get_links()))
	door.panel_open = TRUE
	tool.linking = TRUE
	tool.melee_attack_chain(H, door)
	check("an open one can", door in tool.get_links())
	check("anyone looking in sees the probe", findtext(jointext(door.examine(H), " "), "link probe"))
	var/bolts = door.wires.get_color_of_wire(WIRE_BOLTS)
	var/old_usr = usr
	usr = H
	tool.ui_act("select_link", list("ref" = REF(door)), stub_ui)
	tool.ui_act("pulse", list("wire" = bolts), stub_ui)
	check("pulsing its bolt wire from the screen drops the bolts", door.locked)
	var/list/data = tool.ui_data(H)
	check("the screen lists the link and its wires", length(data["links"]) == 1 && length(data["selected"]["wires"]) == length(door.wires.colors))
	door.locked = FALSE
	H.forceMove(locate(door.x + 20, door.y, door.z))
	tool.ui_act("pulse", list("wire" = bolts), stub_ui)
	check("from 20 tiles away it's out of range", !door.locked)
	H.forceMove(spot(2, 9))
	door.panel_open = FALSE
	tool.ui_act("pulse", list("wire" = bolts), stub_ui)
	check("with the panel shut again it can't reach", !door.locked)
	usr = old_usr
	tool.buffer = door
	tool.select_slot(2)
	check("a second buffer slot starts empty", isnull(tool.buffer))
	tool.buffer = other
	tool.select_slot(1)
	var/first = tool.buffer
	tool.select_slot(2)
	check("each slot keeps its own buffer", first == door && tool.buffer == other)
	qdel(door)
	check("a destroyed machine drops its probe", !length(tool.get_links()) && !length(tool.links))
	qdel(other)
	qdel(tool)
	qdel(H)

/datum/dept_gear_test/proc/test_pager()
	var/turf/T
	for(var/area/hallway/A in GLOB.sortedAreas)
		if(!is_station_level(A.z))
			continue
		for(var/turf/open/floor/F in A)
			if(!F.density && !is_blocked_turf(F))
				T = F
				break
		if(T)
			break
	check("found a spot on the station", T)
	if(!T)
		return
	for(var/obj/machinery/telecomms/message_server/server in GLOB.telecomms_list)
		server.calibrating = 0 // it takes 15 minutes from roundstart otherwise
	var/mob/living/carbon/human/boss = make_human(T, "Pager Chief", "Chief Engineer")
	var/mob/living/carbon/human/engineer = make_human(T, "Pager Engineer", "Station Engineer")
	var/mob/living/carbon/human/doctor = make_human(T, "Pager Doctor", "Medical Doctor")
	var/obj/item/pda/engineer_pda = new(engineer)
	engineer_pda.owner = "Pager Engineer"
	engineer_pda.ownjob = "Station Engineer"
	engineer.equip_to_slot_or_del(engineer_pda, ITEM_SLOT_BELT)
	var/obj/item/pda/doctor_pda = new(doctor)
	doctor_pda.owner = "Pager Doctor"
	doctor_pda.ownjob = "Medical Doctor"
	doctor.equip_to_slot_or_del(doctor_pda, ITEM_SLOT_BELT)
	var/obj/item/dept_pager/engineering/pager = new(boss)
	boss.put_in_hands(pager)
	pager.send_page(boss, "Everyone to the SM")
	check("the page goes out", pager.page_id == 1 && ("Pager Engineer (Station Engineer)" in pager.last_recipients), "[pager.page_id], [english_list(pager.last_recipients)]")
	check("the engineer's PDA gets it", findtext(engineer_pda.tnote, "PAGE to Engineering from Pager Chief (Chief Engineer)") && findtext(engineer_pda.tnote, "Everyone to the SM"))
	check("the doctor's doesn't", !findtext(doctor_pda.tnote, "Everyone to the SM"))
	var/old_usr = usr
	usr = engineer
	pager.Topic("", list("ack" = "1", "pda" = REF(engineer_pda)))
	pager.Topic("", list("ack" = "1", "pda" = REF(engineer_pda)))
	usr = doctor
	pager.Topic("", list("ack" = "1", "pda" = REF(engineer_pda))) // not carrying that PDA
	usr = old_usr
	check("the engineer acknowledges it, once; the doctor can't for them", length(pager.acknowledged) == 1, english_list(pager.acknowledged))
	pager.send_page(boss, "Again")
	check("it has to recharge between pages", pager.page_id == 1)
	for(var/mob/M in list(boss, engineer, doctor))
		qdel(M)

// ---------------------------------------------------------------------------------------------
// Bombs: predict, then set it off and compare with what the explosion actually was

/datum/dept_gear_test/proc/make_tank(gas, moles, temperature, turf/where)
	var/obj/item/tank/internals/plasma/empty/tank = new(where)
	if(gas)
		tank.air_contents.assert_gas(gas)
		tank.air_contents.moles[gas] = moles
	tank.air_contents.temperature = temperature
	return tank

/// Waits for an explosion after `since`, up to timeout
/datum/dept_gear_test/proc/wait_for_explosion(since, timeout)
	var/deadline = world.time + timeout
	while(world.time < deadline)
		for(var/list/boom in explosions)
			if(boom[6] >= since)
				return boom
		sleep(5)

/datum/dept_gear_test/proc/compare_blast(name, list/predicted, list/boom, opened_at)
	if(!boom)
		check("[name]: it went off", FALSE, "no explosion heard")
		return
	var/list/actual = list(boom[3], boom[4], boom[5])
	var/list/expected = list(predicted["dev"], predicted["heavy"], predicted["light"])
	check("[name]: yield matches the prediction", actual[1] == expected[1] && actual[2] == expected[2] && actual[3] == expected[3], "predicted [jointext(expected, "/")], got [jointext(actual, "/")]")
	var/seconds = (boom[6] - opened_at) / 10
	check("[name]: it went off when predicted", seconds <= predicted["tick"] * 2 + 1 && seconds >= (predicted["tick"] - 1) * 2 - 1, "predicted within [predicted["tick"] * 2] s, took [seconds] s")

/datum/dept_gear_test/proc/test_bombs()
	var/obj/item/blast_calculator/calc = new(blast_site)
	var/list/cases = list(
		list("hot plasma into oxygen", /datum/gas/plasma, 25, 1000, /datum/gas/oxygen, 50, T20C),
		list("big plasma mix", /datum/gas/plasma, 60, 1500, /datum/gas/oxygen, 120, 400),
		list("cold dud", /datum/gas/plasma, 5, T20C, /datum/gas/oxygen, 5, T20C))
	for(var/list/C in cases)
		var/obj/item/transfer_valve/valve = new(blast_site)
		valve.tank_one = make_tank(C[2], C[3], C[4], valve)
		valve.tank_two = make_tank(C[5], C[6], C[7], valve)
		var/report = calc.blast_report(valve)
		note("[C[1]]: [replacetext(report, "\n", " | ")]")
		var/datum/gas_mixture/mix = copy_tank_mix(valve.tank_two.air_contents)
		mix.volume += valve.tank_one.air_contents.volume
		mix.merge(copy_tank_mix(valve.tank_one.air_contents).remove_ratio(1))
		var/list/predicted = predict_tank_blast(mix, valve.tank_two.integrity)
		var/opened_at = world.time
		valve.toggle_valve()
		if(predicted["result"] == "explodes")
			compare_blast(C[1], predicted, wait_for_explosion(opened_at, predicted["tick"] * 20 + 60), opened_at)
		else
			var/list/boom = wait_for_explosion(opened_at, 20 SECONDS)
			check("[C[1]]: predicted no blast, and none came", !boom, predicted["result"])
			qdel(valve)
		sleep(3 SECONDS)
		calc.forceMove(blast_site) // the blast may have thrown it

	// A tank just past rupture pressure with nothing reacting: it should strain three ticks, then burst without exploding
	var/obj/item/tank/strained = make_tank(/datum/gas/nitrogen, 0, T20C, blast_site)
	strained.air_contents.moles[/datum/gas/nitrogen] = (TANK_RUPTURE_PRESSURE + 50) * strained.air_contents.volume / (R_IDEAL_GAS_EQUATION * T20C)
	var/list/strain = predict_tank_blast(strained.air_contents, strained.integrity)
	note("strained tank: [calc.describe_prediction(strain, "from now")]")
	var/started = world.time
	var/list/boom = wait_for_explosion(started, strain["tick"] * 20 + 60)
	check("overpressured tank: predicted a rupture, it ruptured without a blast", strain["result"] == "ruptures" && QDELETED(strained) && !boom, "[strain["result"]] at tick [strain["tick"]]; [QDELETED(strained) ? "burst" : "still there"]")

	// A welded one-tank bomb: setting it off heats the tank 10 K (hippie's /obj/item/tank/ignite()), the tank does the rest.
	// Just under the plasma fire's ignition point, so it's inert until set off.
	var/obj/item/onetankbomb/bomb = new(blast_site)
	bomb.bombtank = make_tank(/datum/gas/plasma, 20, FIRE_MINIMUM_TEMPERATURE_TO_EXIST - 5, bomb)
	bomb.bombtank.air_contents.assert_gas(/datum/gas/oxygen)
	bomb.bombtank.air_contents.moles[/datum/gas/oxygen] = 30
	bomb.status = TRUE
	var/one_tank = calc.blast_report(bomb)
	note("one-tank bomb: [replacetext(one_tank, "\n", " | ")]")
	var/datum/gas_mixture/triggered = copy_tank_mix(bomb.bombtank.air_contents)
	triggered.temperature += 10
	var/list/predicted = predict_tank_blast(triggered, bomb.bombtank.integrity)
	var/list/idle = predict_tank_blast(bomb.bombtank.air_contents, bomb.bombtank.integrity)
	check("one-tank bomb: inert until it's set off", idle["result"] == "stable" && !findtext(one_tank, "Left alone"), "left alone: [idle["result"]], set off: [predicted["result"]] at tick [predicted["tick"]]")
	var/obj/item/tank/bomb_tank = bomb.bombtank
	started = world.time
	bomb_tank.ignite()
	switch(predicted["result"])
		if("explodes")
			compare_blast("one-tank bomb", predicted, wait_for_explosion(started, predicted["tick"] * 20 + 60), started)
		if("ruptures")
			boom = wait_for_explosion(started, predicted["tick"] * 20 + 60)
			check("one-tank bomb: predicted a rupture after [predicted["tick"] * 2] s, it ruptured without a blast", QDELETED(bomb_tank) && !boom, QDELETED(bomb_tank) ? "burst" : "still there")
		else
			boom = wait_for_explosion(started, 20 SECONDS)
			check("one-tank bomb: predicted it would sit there, it did", !QDELETED(bomb_tank) && !boom)
	qdel(calc)

// ---------------------------------------------------------------------------------------------
// UI and text QOL: screentips (the decisions; drawing them needs a client), examine-more, the orbit menu

/// What a screentip would say for user hovering over target
/datum/dept_gear_test/proc/tip(atom/target, mob/living/user, key = SCREENTIP_LMB)
	var/list/context = list()
	target.gather_screentip_context(context, user)
	return context[key]

/datum/dept_gear_test/proc/hold(mob/living/carbon/human/H, obj/item/I)
	for(var/obj/item/held in H.held_items)
		qdel(held)
	if(I)
		H.put_in_active_hand(I)

/datum/dept_gear_test/proc/test_screentips()
	var/list/made = list()
	var/mob/living/carbon/human/H = make_human(spot(6, 10), "Tip Tester", "Station Engineer")
	var/mob/living/carbon/human/friend = make_human(spot(6, 9), "Tip Friend", "Assistant")
	made += list(H, friend)
	var/obj/item/wrench/floor_wrench = new(spot(7, 10))
	made += floor_wrench
	check("an item on the floor, empty hand: Pick up", tip(floor_wrench, H) == "Pick up", tip(floor_wrench, H))

	var/obj/machinery/door/airlock/door = new(spot(6, 11))
	made += door
	check("airlock, empty hand: Open", tip(door, H) == "Open", tip(door, H))
	hold(H, new /obj/item/screwdriver)
	check("airlock, screwdriver: Open panel", tip(door, H) == "Open panel", tip(door, H))
	hold(H, new /obj/item/crowbar)
	check("powered airlock, crowbar: no tip (the motors resist)", isnull(tip(door, H)), tip(door, H))
	door.stat |= NOPOWER
	check("unpowered airlock, crowbar: Pry open", tip(door, H) == "Pry open", tip(door, H))
	door.stat &= ~NOPOWER
	hold(H, new /obj/item/weldingtool)
	check("airlock, welder on help intent, undamaged: no tip", isnull(tip(door, H)), tip(door, H))
	H.a_intent = INTENT_DISARM
	check("airlock, welder off help intent: Weld shut", tip(door, H) == "Weld shut", tip(door, H))
	door.bolt()
	hold(H, null)
	check("bolted airlock, empty hand: no tip", isnull(tip(door, H)), tip(door, H))
	H.a_intent = INTENT_HELP

	var/obj/structure/closet/closet = new(spot(5, 11))
	var/obj/structure/closet/secure_closet/locker = new(spot(5, 10))
	made += list(closet, locker)
	check("closet, empty hand: Open", tip(closet, H) == "Open", tip(closet, H))
	check("locked locker: Alt-LMB Unlock", tip(locker, H, SCREENTIP_ALT_LMB) == "Unlock", tip(locker, H, SCREENTIP_ALT_LMB))
	hold(H, new /obj/item/weldingtool)
	check("closet, welder: Weld shut", tip(closet, H) == "Weld shut", tip(closet, H))

	var/obj/structure/table/table = new(spot(7, 11))
	made += table
	hold(H, new /obj/item/wrench)
	check("table, wrench: Deconstruct", tip(table, H) == "Deconstruct", tip(table, H))
	hold(H, new /obj/item/paper)
	check("table, paper: Place", tip(table, H) == "Place", tip(table, H))

	var/turf/wall_spot = spot(8, 12)
	var/turf/closed/wall/r_wall/rwall = wall_spot.ChangeTurf(/turf/closed/wall/r_wall)
	hold(H, new /obj/item/wirecutters)
	check("reinforced wall, wirecutters: Cut outer grille", tip(rwall, H) == "Cut outer grille", tip(rwall, H))
	rwall.d_state = COVER
	hold(H, new /obj/item/weldingtool)
	check("reinforced wall, cover stage, welder: Slice metal cover", tip(rwall, H) == "Slice metal cover", tip(rwall, H))
	hold(H, new /obj/item/crowbar)
	check("plasteel floor, crowbar: Pry up tile", tip(spot(4, 12), H) == "Pry up tile", tip(spot(4, 12), H))

	hold(H, null)
	check("a person, help intent: Hug", tip(friend, H) == "Hug", tip(friend, H))
	H.a_intent = INTENT_HARM
	check("a person, harm intent: Punch", tip(friend, H) == "Punch", tip(friend, H))
	H.a_intent = INTENT_GRAB
	check("a person, grab intent: Grab", tip(friend, H) == "Grab", tip(friend, H))
	H.a_intent = INTENT_HELP
	check("yourself: no tip", isnull(tip(H, H)), tip(H, H))

	var/obj/machinery/portable_atmospherics/canister/air/can = new(spot(9, 12))
	var/obj/machinery/hydroponics/constructable/tray = new(spot(10, 12))
	var/obj/item/storage/backpack/pack = new(spot(11, 12))
	made += list(can, tray, pack)
	hold(H, new /obj/item/tank/internals/emergency_oxygen)
	check("canister, tank: Insert tank", tip(can, H) == "Insert tank", tip(can, H))
	check("backpack, tank: Put in", tip(pack, H) == "Put in", tip(pack, H))
	hold(H, new /obj/item/seeds/tomato)
	check("empty tray, seeds: Plant", tip(tray, H) == "Plant", tip(tray, H))

	hold(H, null)
	for(var/atom/A in made)
		qdel(A)
	wall_spot.ChangeTurf(/turf/open/floor/plasteel)

/datum/dept_gear_test/proc/test_examine_more()
	var/mob/living/carbon/human/H = make_human(spot(3, 10), "Close Looker", "Assistant")
	var/obj/item/gun/energy/laser/laser = new(spot(3, 11))
	var/obj/item/gun/energy/laser/bluetag/tag = new(spot(3, 11))
	var/obj/item/gun/ballistic/rifle/boltaction/mosin = new(spot(3, 11))
	check("a laser gun has lore on a closer look", findtext(jointext(laser.examine_more(H), ""), "Type 5 Heat Delivery System"))
	check("its normal examine hints there's more", findtext(jointext(H.examine_or_look_closer(laser), ""), "Examine it again"))
	check("a laser tag gun has no lore, and no hint", !length(tag.examine_more(H)) && !findtext(jointext(H.examine_or_look_closer(tag), ""), "Examine it again"))
	var/mosin_lore = jointext(mosin.examine_more(H), "")
	check("the Mosin's lore uses this station's name for it", findtext(mosin_lore, "Mosin Nagant") && !findtext(mosin_lore, "Sakhno"))

	var/obj/item/card/id/card = new(spot(3, 11))
	var/id_examine = jointext(card.examine(H), "")
	check("an ID without an account says so, without the how-to", findtext(id_examine, "no registered account") && !findtext(id_examine, "Alt-Click"), id_examine)
	check("the how-to is on a closer look", findtext(jointext(card.examine_more(H), ""), "Alt-Click to add one"))

	var/obj/machinery/autolathe/lathe = new(spot(4, 11))
	check("a closed machine shows no parts", !findtext(jointext(lathe.examine_more(H), ""), "following parts"))
	lathe.panel_open = TRUE
	var/parts = jointext(lathe.examine_more(H), "")
	check("with its panel open, a closer look lists its parts and tiers", findtext(parts, "following parts") && findtext(parts, "tier 1"), parts)
	check("one line per kind of part", !findtext(parts, "</span><span"))

	var/obj/item/scrubber_pack/pack = new(spot(3, 11))
	check("department gear explains itself on a closer look", findtext(jointext(pack.examine_more(H), ""), "Use it in hand"))
	for(var/atom/A in list(H, laser, tag, mosin, card, lathe, pack))
		qdel(A)

/datum/dept_gear_test/proc/test_orbit_menu()
	var/mob/living/carbon/human/H = make_human(spot(9, 10), "Orbit Target", "Assistant")
	H.mind_initialize()
	var/mob/dead/observer/ghost = new(spot(9, 11))
	var/datum/orbit_menu/menu = new(ghost)
	var/list/data = menu.ui_data(ghost)
	var/found = FALSE
	for(var/list/entry in data["alive"])
		if(entry["ref"] == REF(H))
			found = TRUE
	check("the living show under Alive", found)
	check("no antagonist section for players", !length(data["antagonists"]))
	var/ghost_listed = FALSE
	for(var/list/entry in data["ghosts"])
		if(entry["ref"] == REF(ghost))
			ghost_listed = TRUE
	check("you aren't listed", !ghost_listed)
	usr = ghost
	menu.ui_act("orbit", list("ref" = REF(H)), stub_ui)
	check("picking someone orbits them", ghost.orbiting?.parent == H)
	var/obj/item/wrench/not_a_poi = new(spot(9, 12))
	menu.ui_act("orbit", list("ref" = REF(not_a_poi)), stub_ui)
	check("things the menu never offered can't be orbited through it", ghost.orbiting?.parent == H)
	for(var/datum/D in list(menu, ghost, H, not_a_poi))
		qdel(D)

/datum/dept_gear_test/proc/count_on(turf/T, path)
	. = 0
	for(var/atom/movable/A in T)
		if(istype(A, path))
			.++

/datum/dept_gear_test/proc/test_order_amounts()
	var/old_usr = usr
	var/mob/living/carbon/human/H = make_human(spot(2, 8), "Bulk Buyer", "Assistant")
	var/obj/item/card/id/card = H.get_idcard()
	var/datum/bank_account/account = new("Bulk Buyer", SSjob.GetJob("Assistant"))
	card.registered_account = account
	account.bank_cards += card
	usr = H

	// a vending machine: three at once, then more than the money covers
	var/turf/vend_spot = spot(3, 8)
	var/obj/machinery/vending/cola/vendor = new(vend_spot)
	vendor.onstation = TRUE
	var/datum/data/vending_product/R = vendor.product_records[1]
	var/price = R.custom_price || vendor.default_price
	var/stock = R.amount
	account.account_balance = price * 10
	vendor.ui_act("vend", list("ref" = REF(R), "amount" = "3"), stub_ui)
	check("vending 3 at once hands out 3", count_on(vend_spot, R.product_path) == 3 && R.amount == stock - 3, "[count_on(vend_spot, R.product_path)] on the floor, stock [stock] -> [R.amount]")
	check("and charges for 3", account.account_balance == price * 7, "$[account.account_balance], price $[price]")
	account.account_balance = price * 2 + 1
	vendor.ui_act("vend", list("ref" = REF(R), "amount" = "5"), stub_ui)
	check("asking for more than you can pay for gets what you can pay for", count_on(vend_spot, R.product_path) == 5 && account.account_balance == 1, "[count_on(vend_spot, R.product_path)] on the floor, $[account.account_balance] left")
	vendor.ui_act("vend", list("ref" = REF(R), "amount" = "1000"), stub_ui)
	check("and a silly amount can't overdraw or overvend", account.account_balance == 1 && count_on(vend_spot, R.product_path) == 5)

	// a custom vendor: the owner gets paid the item's own price
	var/turf/custom_spot = spot(4, 8)
	var/obj/machinery/vending/custom/stall = new(custom_spot)
	var/datum/bank_account/owner = new("Stall Owner", SSjob.GetJob("Assistant"))
	stall.private_a = owner
	var/crayon_name
	for(var/i in 1 to 3)
		var/obj/item/toy/crayon/red/crayon = new(stall)
		crayon.custom_price = 7
		stall.vending_machine_input[crayon.name] = i
		crayon_name = crayon.name
		stall.loaded_items++
	account.account_balance = 100
	stall.ui_act("dispense", list("item" = crayon_name, "amount" = "2"), stub_ui)
	check("a custom vendor dispenses 2 at once", count_on(custom_spot, /obj/item/toy/crayon/red) == 2, "[count_on(custom_spot, /obj/item/toy/crayon/red)]")
	check("and pays its owner the item's price, not the machine's", owner.account_balance == 14 && account.account_balance == 86, "owner $[owner.account_balance], buyer $[account.account_balance]")

	// cargo: three of a pack, one requisition form
	var/datum/supply_pack/pack
	for(var/path in SSshuttle.supply_packs)
		var/datum/supply_pack/P = SSshuttle.supply_packs[path]
		if(!P.hidden && !P.contraband && !P.special && !P.DropPodOnly && P.cost <= 2000)
			pack = P
			break
	var/turf/console_spot = spot(5, 8)
	var/obj/machinery/computer/cargo/console = new(console_spot)
	var/before = length(SSshuttle.shoppinglist)
	console.ui_act("add", list("id" = "[pack.type]", "amount" = "3"), stub_ui)
	check("ordering 3 puts 3 orders on the shuttle", length(SSshuttle.shoppinglist) == before + 3, "[length(SSshuttle.shoppinglist) - before]")
	var/forms = 0
	var/form_name
	for(var/obj/item/paper/P in console_spot)
		forms++
		form_name = P.name
	check("with one requisition form covering them", forms == 1 && findtext(form_name, "3x"), "[forms] forms: [form_name]")
	SSshuttle.shoppinglist.Cut(before + 1)

	// express: three pods asked for, budget for one
	var/obj/machinery/computer/cargo/express/express = new(spot(6, 8))
	var/datum/bank_account/cargo = SSeconomy.get_dep_account(ACCOUNT_CAR)
	var/old_budget = cargo.account_balance
	cargo.account_balance = round(pack.cost * 1.5)
	express.ui_act("add", list("id" = "[pack.type]", "amount" = "3"), stub_ui)
	check("an express order stops when the budget runs out", cargo.account_balance == round(pack.cost * 1.5) - pack.cost, "budget [round(pack.cost * 1.5)] -> [cargo.account_balance], pack [pack.cost]")
	cargo.account_balance = old_budget

	usr = old_usr
	for(var/datum/D in list(vendor, stall, console, express, H))
		qdel(D)
	for(var/atom/movable/A in vend_spot)
		qdel(A)
	for(var/atom/movable/A in custom_spot)
		qdel(A)
	for(var/obj/item/paper/P in console_spot)
		qdel(P)

/datum/dept_gear_test/proc/test_crate_trolley()
	var/mob/living/carbon/human/H = make_human(spot(8, 5), "Trolley Pusher", "Cargo Technician")
	var/obj/structure/crate_trolley/trolley = new(spot(8, 6))
	var/list/made = list(H, trolley)
	var/recipe_found = FALSE
	for(var/datum/stack_recipe/R in GLOB.metal_recipes)
		if(R.result_type == /obj/structure/crate_trolley)
			recipe_found = (R.req_amount == 5)
	check("a crate trolley is built from 5 metal sheets", recipe_found)

	var/list/crates = list()
	for(var/i in 1 to 5)
		var/obj/structure/closet/crate/crate = new(spot(7 + (i % 3), 4))
		crates += crate
		made += crate
	for(var/i in 1 to 4)
		var/obj/structure/closet/crate/crate = crates[i]
		crate.forceMove(spot(9, 5)) // beside both the pusher and the trolley
		trolley.try_load(crate, H)
	check("four crates load onto it", length(trolley.crates) == 4 && crates[1] in trolley, "[length(trolley.crates)] aboard")
	COMPILE_OVERLAYS(trolley)
	check("and stack up on its sprite, with the handle on top", length(trolley.overlays) == 5, "[length(trolley.overlays)] overlays")
	var/obj/structure/closet/crate/fifth = crates[5]
	fifth.forceMove(spot(9, 5))
	check("a fifth doesn't fit", !trolley.try_load(fifth, H) && isturf(fifth.loc))
	var/obj/structure/closet/crate/open_crate = new(spot(9, 5))
	made += open_crate
	open_crate.open()
	var/obj/structure/closet/crate/stowaway_crate = new(spot(9, 5))
	made += stowaway_crate
	var/mob/living/carbon/monkey/stowaway = new(stowaway_crate)
	made += stowaway
	var/obj/structure/closet/crate/bottom = trolley.crates[1]
	trolley.crates -= bottom // make room to test the refusals
	check("an open crate won't load", !trolley.can_load(open_crate, H, TRUE))
	check("nor one with someone inside", !trolley.can_load(stowaway_crate, H, TRUE))
	trolley.crates.Insert(1, bottom)

	H.start_pulling(trolley)
	var/list/slowdown = LAZYACCESS(H.movespeed_modification, "crate_trolley")
	check("pulling it loaded slows you down", H.pulling == trolley && slowdown, "pulling [H.pulling]")
	trolley.attack_hand(H)
	var/obj/structure/closet/crate/set_down = crates[4]
	check("clicking it sets the top crate down beside it", length(trolley.crates) == 3 && isturf(set_down.loc) && get_dist(set_down, trolley) == 1 && set_down.loc != H.loc, "[length(trolley.crates)] aboard, top crate at [set_down.loc]")
	trolley.AltClick(H)
	var/unloaded_ok = TRUE
	for(var/i in 1 to 3)
		var/obj/structure/closet/crate/crate = crates[i]
		if(!isturf(crate.loc) || crate.loc == H.loc || crate.loc == trolley.loc)
			unloaded_ok = FALSE
	check("alt-click unloads the lot onto the tiles around it", !length(trolley.crates) && unloaded_ok)
	check("and empty, it's no slower to pull", !LAZYACCESS(H.movespeed_modification, "crate_trolley"))
	H.stop_pulling()

	var/list/context = list()
	var/obj/item/wrench/wrench = new
	H.put_in_active_hand(wrench)
	made += wrench
	trolley.add_context(trolley, context, wrench, H)
	check("empty, a wrench's screentip says it comes apart", context[SCREENTIP_LMB] == "Take apart")

	fifth.forceMove(spot(9, 5))
	trolley.try_load(fifth, H)
	var/turf/trolley_turf = get_turf(trolley)
	qdel(trolley)
	check("if it's destroyed, its crates are left behind", fifth.loc == trolley_turf && !QDELETED(fifth))
	for(var/datum/D in made)
		qdel(D)

#undef DEPT_GEAR_TEST_DIR
