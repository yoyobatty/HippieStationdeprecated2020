// Bot Gym scenarios for the chem lab (goals/chem_lab.dm). The bot works real machines with real reagents: what it comes out with is what the
// game's own reactions made of it, so a recipe that doesn't work on paper fails here.

/datum/bot_scenario/chem_brew
	layout = list(
		"#########",
		"#D.H.P.C#",
		"#.......#",
		"#.B...b.#",
		"#......M#",
		"#########")
	job = "Chemist"
	time_limit = 240 SECONDS
	kit_backpack = list(/obj/item/reagent_containers/glass/beaker/large, /obj/item/reagent_containers/syringe, /obj/item/reagent_containers/syringe, /obj/item/reagent_containers/syringe)
	/// The brew's label.
	var/label
	max_goal_attempts = 1

/datum/bot_scenario/chem_brew/build_tile(turf/T, char)
	switch(char)
		if("D")
			place(char, new /obj/machinery/chem_dispenser(T))
		if("H")
			place(char, new /obj/machinery/chem_heater(T))
		if("P")
			place(char, new /obj/machinery/chem/pressure(T))
		if("C")
			place(char, new /obj/machinery/chem/centrifuge(T))
		if("M")
			place(char, new /obj/machinery/chem_master(T))
		if("b")
			place(char, new /obj/item/storage/box/syringes(T))
		else
			return ..()

/datum/bot_scenario/chem_brew/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_POWERGAMER)
	brain.job_is_chemist_for_gym = TRUE

/datum/bot_scenario/chem_brew/proc/brew()
	for(var/list/B in GLOB.bot_brews)
		if(B["label"] == label)
			return B

/datum/bot_scenario/chem_brew/make_goal()
	var/datum/bot_goal/synthesize_medicine/fixed/G = new
	G.brew = brew()
	return G

/// The goal, with its mind made up.
/datum/bot_goal/synthesize_medicine/fixed
	var/list/brew

/datum/bot_goal/synthesize_medicine/fixed/resolve_target(datum/bot_brain/bot)
	dispenser = bot.find_reachable_chem_dispenser()
	master = bot.find_reachable_chem_master()
	if(!dispenser || !master)
		return
	recipe = brew
	for_self = TRUE
	target = dispenser

/datum/bot_scenario/chem_brew/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/B = brew()
	for(var/obj/item/reagent_containers/C in bot.GetAllContents(/obj/item/reagent_containers))
		if(!(istype(C, /obj/item/reagent_containers/pill) || istype(C, /obj/item/reagent_containers/syringe)))
			continue
		var/datum/reagent/R = C.reagents.get_master_reagent()
		if(R?.type == B["reagent"])
			log_line("made [C] with [C.reagents.get_reagent_amount(R.type)]u of [R.name]")
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chem_brew/tricordrazine
	name = "chem: tricordrazine"
	label = "tricordrazine"

/// Somebody's beaker, full, left in the dispenser: out and set down, its own in, the batch made. It used to dispense into
/// the full one, be refused, give up, and leave its own half-made batch in the machine for the next chemist.
/datum/bot_scenario/chem_brew/left_beaker
	name = "chem: somebody's full beaker left in the dispenser, it takes it out and makes its bicaridine"
	time_limit = 90 SECONDS
	var/obj/item/reagent_containers/glass/beaker/large/left

/datum/bot_scenario/chem_brew/left_beaker/brew()
	return GLOB.bot_medicine_recipes[1] //bicaridine, a pill

/datum/bot_scenario/chem_brew/left_beaker/setup()
	var/obj/machinery/chem_dispenser/D = first_placed("D")
	left = new(D)
	left.reagents.add_reagent(/datum/reagent/water, left.reagents.maximum_volume)
	D.beaker = left
	D.update_icon()

/datum/bot_scenario/chem_brew/left_beaker/check()
	var/obj/machinery/chem_dispenser/D = first_placed("D")
	if(D && D.beaker == left && bot_transcript_said("wouldn't give me"))
		fail_reason = "dispensed into the full beaker somebody left in it"
		return BOT_GYM_FAIL
	return ..()

/// Its own leftover beaker, full, in the bag beside an empty one: the empty one goes in the dispenser for a new batch.
/datum/bot_scenario/chem_brew/own_full_beaker
	name = "chem: a full leftover beaker in its bag beside an empty one, it uses the empty one for its bicaridine"
	time_limit = 90 SECONDS

/datum/bot_scenario/chem_brew/own_full_beaker/brew()
	return GLOB.bot_medicine_recipes[1] //bicaridine, a pill

/datum/bot_scenario/chem_brew/own_full_beaker/post_spawn()
	..()
	var/obj/item/storage/backpack/bag = bot.back
	var/obj/item/reagent_containers/glass/beaker/large/full = new(bag)
	full.reagents.add_reagent(/datum/reagent/water, full.reagents.maximum_volume)

/datum/bot_scenario/chem_brew/own_full_beaker/check()
	if(bot_transcript_said("the beaker's full"))
		fail_reason = "loaded its full leftover beaker"
		return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/chem_brew/sodiumf
	name = "chem: sodium fluoride, through the heater twice"
	label = "sodium fluoride"

/// A bottle of water in its pocket, as a chemist had who'd bought one for want of a beaker: the game files it under beakers, and
/// between machines the bottle was taken for the brew.
/datum/bot_scenario/chem_brew/sodiumf/water_bottle
	name = "chem: sodium fluoride with a bottle of water in its pocket, the brew stays in its own beaker"

/datum/bot_scenario/chem_brew/sodiumf/water_bottle/post_spawn()
	..()
	bot.equip_to_slot_or_del(new /obj/item/reagent_containers/glass/beaker/waterbottle(bot), ITEM_SLOT_LPOCKET)

/datum/bot_scenario/chem_brew/sodiumf/water_bottle/check()
	if(bot_transcript_said("didn't yield"))
		fail_reason = "took the bottle of water through the machines in place of its brew"
		return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/chem_brew/aluminiumf
	name = "chem: aluminium fluorate, chilled and under pressure"
	label = "aluminium fluorate"

/datum/bot_scenario/chem_brew/chloral
	name = "chem: chloral hydrate in a syringe"
	label = "chloral hydrate"

/datum/bot_scenario/chem_brew/sleep_toxin
	name = "chem: sleep toxin in a syringe"
	label = "sleep toxin"

/datum/bot_scenario/chem_brew/cyanide
	name = "chem: cyanide in a syringe"
	label = "cyanide"

/datum/bot_scenario/chem_brew/sarin
	name = "chem: sarin, every machine in the lab"
	label = "sarin"
	time_limit = 400 SECONDS

/datum/bot_scenario/chem_brew/order
	name = "collab: Botany's mutagen, made and left on Hydroponics' counter"
	label = "unstable mutagen"
	time_limit = 40 SECONDS
	layout = list(
		"#########",
		"#D.....M#",
		"#.......#",
		"#.B...t.#",
		"#########")

/datum/bot_scenario/chem_brew/order/post_spawn()
	..()
	GLOB.bot_chem_orders += list(list("label" = "unstable mutagen", "area" = /area/bot_gym, "by" = "Hydroponics"))

/datum/bot_scenario/chem_brew/order/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turf/counter = get_turf(first_placed("t"))
	var/obj/item/reagent_containers/glass/beaker/B = locate() in counter
	if(B?.reagents.get_reagent_amount(/datum/reagent/toxin/mutagen) >= 5)
		log_line("left [B] with [B.reagents.get_reagent_amount(/datum/reagent/toxin/mutagen)]u of mutagen")
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chem_brew/poppies
	name = "collab: Botany's poppies through the grinder, into pills"
	label = "poppy bicaridine"
	time_limit = 40 SECONDS
	layout = list(
		"#########",
		"#D..G..M#",
		"#.......#",
		"#.B..p..#",
		"#########")

/datum/bot_scenario/chem_brew/poppies/build_tile(turf/T, char)
	switch(char)
		if("G")
			place(char, new /obj/machinery/reagentgrinder(T))
		if("p")
			for(var/i in 1 to 3)
				var/obj/item/seeds/poppy/seed = new
				seed.potency = 100
				var/obj/item/reagent_containers/food/snacks/grown/poppy/P = new(T, seed)
				place(char, P)
		else
			return ..()

/datum/bot_scenario/chem_brew/smoke
	name = "chem: a knockout smoke grenade, built from the parts"
	label = "knockout smoke"
	time_limit = 60 SECONDS
	kit_backpack = list(/obj/item/reagent_containers/glass/beaker/large, /obj/item/reagent_containers/glass/beaker/large, /obj/item/stack/cable_coil, /obj/item/screwdriver)

/datum/bot_scenario/chem_brew/smoke/post_spawn()
	..()
	new /obj/item/grenade/chem_grenade(first_marker("."))

/datum/bot_scenario/chem_brew/smoke/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return brain.bot_ready_grenade() ? BOT_GYM_PASS : BOT_GYM_PENDING

/obj/item/grenade/chem_grenade/bot_knockout_smoke
	stage = GRENADE_READY

/obj/item/grenade/chem_grenade/bot_knockout_smoke/Initialize()
	. = ..()
	var/obj/item/reagent_containers/glass/beaker/large/one = new(src)
	var/obj/item/reagent_containers/glass/beaker/large/two = new(src)
	one.reagents.add_reagent(/datum/reagent/toxin/chloralhydrate, 20)
	one.reagents.add_reagent(/datum/reagent/potassium, 20)
	one.reagents.add_reagent(/datum/reagent/consumable/sugar, 20)
	two.reagents.add_reagent(/datum/reagent/phosphorus, 20)
	beakers += one
	beakers += two

/datum/bot_scenario/griefed/throws_smoke
	name = "chem: knockout smoke on somebody armed, from a safe distance"
	desc = "Somebody with a fire axe across the room and a grenade in the bag. Smoke doesn't care who it's on: it's thrown from a distance, and it stops them."
	layout = list(
		"###########",
		"#B.....C..#",
		"###########")
	time_limit = 30 SECONDS
	kit_backpack = list(/obj/item/grenade/chem_grenade/bot_knockout_smoke)

/datum/bot_scenario/griefed/throws_smoke/post_spawn()
	..()
	brain.nerve = 0.9
	var/obj/item/twohanded/fireaxe/axe = griefer_holds(/obj/item/twohanded/fireaxe)
	axe.wield(griefer)

/datum/bot_scenario/griefed/throws_smoke/grief()
	brain.on_attacked(griefer, "attacked", null)

/datum/bot_scenario/griefed/throws_smoke/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return griefer.reagents.has_reagent(/datum/reagent/toxin/chloralhydrate) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/needles_them
	name = "chem: a knockout syringe in somebody it's fighting"
	desc = "A chemist with chloral hydrate on it, set on by somebody. It sticks them with it."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	kit_backpack = list(/obj/item/reagent_containers/syringe/lethal/choral)

/datum/bot_scenario/griefed/needles_them/post_spawn()
	..()
	brain.nerve = 0.9

/datum/bot_scenario/griefed/needles_them/grief()
	griefer_hand(INTENT_HARM)

/datum/bot_scenario/griefed/needles_them/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return griefer.reagents.has_reagent(/datum/reagent/toxin/chloralhydrate) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/keeps_it_clean
	name = "chem: a lethal stays in the bag against a greytider with a toolbox"
	desc = "The bag has cyanide and chloral in it. Somebody who's only got a toolbox isn't a case for lethal force: chloral it is."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	kit_backpack = list(/obj/item/reagent_containers/syringe/lethal/choral, /obj/item/reagent_containers/syringe/bot_cyanide)

/obj/item/reagent_containers/syringe/bot_cyanide
	list_reagents = list(/datum/reagent/toxin/cyanide = 15)

/datum/bot_scenario/griefed/keeps_it_clean/post_spawn()
	..()
	brain.nerve = 0.9
	brain.set_playstyle(BOT_STYLE_PARANOID)
	griefer_holds(/obj/item/storage/toolbox/mechanical)

/datum/bot_scenario/griefed/keeps_it_clean/grief()
	griefer_hand(INTENT_HARM)

/datum/bot_scenario/griefed/keeps_it_clean/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(griefer.reagents.has_reagent(/datum/reagent/toxin/cyanide))
		fail_reason = "cyanide, for a toolbox"
		return BOT_GYM_FAIL
	return griefer.reagents.has_reagent(/datum/reagent/toxin/chloralhydrate) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Hippie's superboom, the saboteur's way (goals/sabotage_grenades.dm): three beakers, every machine, and a pill of it at the end
/datum/bot_scenario/chem_brew/superboom
	name = "chem: superboom in three beakers, every machine in the lab, into a pill"
	time_limit = 500 SECONDS
	kit_backpack = list(/obj/item/reagent_containers/glass/beaker/large, /obj/item/reagent_containers/glass/beaker/large, /obj/item/reagent_containers/glass/beaker/large)

/datum/bot_scenario/chem_brew/superboom/brew()
	var/finder = text2path("/proc/bot_sabotage_brew") // the fix's: a build without it has no such brew
	return finder ? call(finder)(/datum/reagent/superboom) : null

/datum/bot_scenario/chem_brew/superboom/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/reagent_containers/pill/P in bot.GetAllContents(/obj/item/reagent_containers/pill))
		var/amount = P.reagents.get_reagent_amount(/datum/reagent/superboom)
		if(amount >= 8)
			log_line("made [P] with [round(amount, 0.1)]u of superboom")
			return BOT_GYM_PASS
	return BOT_GYM_PENDING
