// Player-reported bugs (the upstream issue numbers are in the names). None of this has anything to do with the bots: the gym's
// just the quickest way to stand something up in a running round and see what it does.

/datum/bot_scenario/griefed/bug
	layout = list(
		"#########",
		"#.......#",
		"#..BC...#",
		"#.......#",
		"#########")
	time_limit = 10 SECONDS
	/// BOT_GYM_PASS or BOT_GYM_FAIL, from grief().
	var/verdict

/datum/bot_scenario/griefed/bug/check()
	return isnull(verdict) ? BOT_GYM_PENDING : verdict

/datum/bot_scenario/griefed/bug/proc/expect(result, what)
	log_line("[what]: [result ? "yes" : "no"]")
	verdict = result ? BOT_GYM_PASS : BOT_GYM_FAIL

/datum/bot_scenario/griefed/bug/bluespace_floor
	name = "bug 12221: walking onto bluespace dust floor doesn't teleport you round and round until the server dies"

/datum/bot_scenario/griefed/bug/bluespace_floor/grief()
	var/turf/middle = get_step(griefer, EAST)
	for(var/turf/open/floor/T in RANGE_TURFS(2, middle))
		var/turf/open/floor/mineral/reagent/R = T.ChangeTurf(/turf/open/floor/mineral/reagent)
		R.reagent_type = new /datum/reagent/bluespace
	griefer.forceMove(middle)
	expect(!QDELETED(griefer), "came through it")

/datum/bot_scenario/griefed/bug/nan
	name = "bug 11324: one reagent gone NaN doesn't take the whole mob's reagents with it"

/datum/bot_scenario/griefed/bug/nan/grief()
	griefer.reagents.add_reagent(/datum/reagent/water, 10)
	griefer.reagents.add_reagent(/datum/reagent/consumable/sugar, 10)
	var/datum/reagent/R = griefer.reagents.reagent_list[1]
	var/huge = 1e30 * 1e30
	R.volume = huge - huge
	griefer.reagents.update_total()
	expect(griefer.reagents.total_volume == 10, "the other one still counts: [griefer.reagents.total_volume], [length(griefer.reagents.reagent_list)] reagents, nan [R.volume]")

/datum/bot_scenario/griefed/bug/chem_master
	name = "bug 11858: both reagents called Translucent mixture come out of the Chem Master"

/datum/bot_scenario/griefed/bug/chem_master/grief()
	var/obj/machinery/chem_master/M = new(get_step(griefer, EAST))
	var/obj/item/reagent_containers/glass/beaker/large/B = new(M)
	M.beaker = B
	B.reagents.add_reagent(/datum/reagent/impvolt, 5)
	B.reagents.add_reagent(/datum/reagent/toxin/sarin_a, 5)
	var/list/shown = M.ui_data(griefer)["beakerContents"]
	var/datum/tgui/dept_gear_test_stub/window = new
	for(var/list/line as anything in shown)
		M.ui_act("transfer", list("id" = line["id"], "amount" = "5", "to" = "buffer"), window)
	expect(M.reagents.total_volume == 10 && !B.reagents.total_volume, "both went across, [M.reagents.total_volume] in the buffer")

/datum/bot_scenario/griefed/bug/abductor
	griefer_job = "Abductor Scientist"
	name = "bug 12034: an abductor scientist can read a gland"

/datum/bot_scenario/griefed/bug/abductor/grief()
	var/obj/item/organ/heart/gland/G = new /obj/item/organ/heart/gland/heals(griefer.loc)
	var/untrained = length(G.examine(griefer))
	griefer.mind.add_antag_datum(/datum/antagonist/abductor/scientist/gym)
	expect(length(G.examine(griefer)) > untrained, "learned something from it")

/// A scientist with none of the setup: no team, no ship to go to.
/datum/antagonist/abductor/scientist/gym/on_gain()
	ADD_TRAIT(owner, TRAIT_ABDUCTOR_SCIENTIST_TRAINING, ABDUCTOR_ANTAGONIST)

/datum/antagonist/abductor/scientist/gym/on_removal()
	REMOVE_TRAIT(owner, TRAIT_ABDUCTOR_SCIENTIST_TRAINING, ABDUCTOR_ANTAGONIST)

/datum/bot_scenario/griefed/bug/contract
	name = "bug 8763: an unused apprentice contract refunds what it cost"

/datum/bot_scenario/griefed/bug/contract/grief()
	var/obj/item/spellbook/book = new(griefer.loc)
	var/obj/item/antag_spawner/contract/C = new(griefer.loc)
	griefer.put_in_active_hand(C)
	book.uses = 0
	var/cost = 0
	for(var/datum/spellbook_entry/item/contract/entry in book.entries)
		cost = entry.cost
	book.attackby(C, griefer)
	expect(cost && book.uses == cost, "got back the [cost] it cost, has [book.uses]")

/datum/bot_scenario/griefed/bug/nanite_defib
	griefer_job = "Assistant"
	name = "bug 12026: nanite defibrillation brings back somebody damage killed"
	time_limit = 20 SECONDS

/datum/bot_scenario/griefed/bug/nanite_defib/grief()
	griefer.AddComponent(/datum/component/nanites, 200)
	var/datum/component/nanites/N = griefer.GetComponent(/datum/component/nanites)
	var/datum/nanite_program/defib/P = new
	N.add_program(null, P)
	griefer.apply_damage(120, BRUTE, BODY_ZONE_CHEST)
	griefer.adjustOxyLoss(100)
	griefer.updatehealth()
	griefer.death()
	log_line("dead at health [griefer.health], stat [griefer.stat]")
	P.on_trigger()

/datum/bot_scenario/griefed/bug/nanite_defib/check()
	if(griefer.stat != DEAD && griefer.timeofdeath)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/bug/cane_gun
	griefer_job = "Assistant"
	griefer_name = "Pimp"
	name = "bug 12819: the cane gun runs out"
	var/obj/item/gun/ballistic/shotgun/canegun/cane

/datum/bot_scenario/griefed/bug/cane_gun/grief()
	cane = new(griefer.loc)
	griefer.put_in_active_hand(cane)
	QDEL_LIST(cane.magazine.stored_ammo)
	if(cane.chambered)
		QDEL_NULL(cane.chambered)
	var/obj/item/ammo_casing/shotgun/beanbag/shell = new(cane.magazine)
	cane.magazine.stored_ammo += shell
	cane.chamber_round()
	var/turf/wall = locate(griefer.x, griefer.y + 2, griefer.z)
	for(var/i in 1 to 3)
		log_line("shot [i]: chambered [cane.chambered], left in it [cane.magazine.ammo_count()]")
		if(cane.can_shoot())
			cane.process_fire(wall, griefer, FALSE)
	log_line("after: chambered [cane.chambered], live [cane.chambered?.BB], left in it [cane.magazine.ammo_count()], can shoot [cane.can_shoot()]")
	expect(!cane.chambered?.BB, "nothing left to fire")
