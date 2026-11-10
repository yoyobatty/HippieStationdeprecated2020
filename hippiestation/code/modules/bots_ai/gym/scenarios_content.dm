// Checks of game content that isn't a bot's doing: new chemicals, machines and what one thing does to another. The Bot Gym is where
// there's a world to try them in, so they live here; the bot in each arena only stands by.
//
// Each scenario's try_it() does the thing and returns what was wrong, or null. One that throws part way fails as "couldn't be tried".

/datum/bot_scenario/content
	time_limit = 20 SECONDS
	layout = list(
		"#####",
		"#B.K#",
		"#####")
	var/tried = FALSE
	var/wrong

/datum/bot_scenario/content/issue_goal()
	return

/datum/bot_scenario/content/post_spawn()
	wrong = try_it(first_marker("K"))
	tried = TRUE

/// Does it, on this tile. Returns what was wrong, or null.
/datum/bot_scenario/content/proc/try_it(turf/T)
	return null

/// For the ones that take time: called from check() until it returns something. TRUE for all well, text for what's wrong.
/datum/bot_scenario/content/proc/later()
	return TRUE

/datum/bot_scenario/content/check()
	if(!tried)
		fail_reason = "couldn't be tried: it threw part way, or what it tries isn't in this build"
		return BOT_GYM_FAIL
	if(wrong)
		fail_reason = wrong
		return BOT_GYM_FAIL
	var/now = later()
	if(isnull(now))
		return BOT_GYM_PENDING
	if(now != TRUE)
		fail_reason = now
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// A beaker with these in it, at this heat, mixed. Returns the beaker.
/datum/bot_scenario/content/proc/mix(turf/T, list/what, heat = 300)
	var/obj/item/reagent_containers/glass/beaker/large/B = place("K", new /obj/item/reagent_containers/glass/beaker/large(T))
	for(var/path in what)
		B.reagents.add_reagent(path, what[path])
	B.reagents.chem_temp = heat
	B.reagents.handle_reactions()
	return B

// ---------------------------------------------------------------------------------------------
// The chemicals of prototype_chems.dm
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/content/recipes
	name = "chemistry: haemoplast, vitrium, voltagel and lumen gel come out of their recipes"
	desc = "Each new chemical mixed from what its recipe asks for, at the heat it asks for."

/datum/bot_scenario/content/recipes/try_it(turf/T)
	var/list/missing = list()
	var/obj/item/reagent_containers/B = mix(T, list(/datum/reagent/medicine/salglu_solution = 20, /datum/reagent/iron = 10, /datum/reagent/medicine/epinephrine = 10), 340)
	if(!B.reagents.has_reagent(text2path("/datum/reagent/medicine/haemoplast")))
		missing += "haemoplast"
	B = mix(T, list(/datum/reagent/silicon = 20, /datum/reagent/aluminium = 10, /datum/reagent/toxin/plasma = 10), 520)
	if(!B.reagents.has_reagent(text2path("/datum/reagent/vitrium")))
		missing += "vitrium"
	B = mix(T, list(/datum/reagent/consumable/liquidelectricity = 10, /datum/reagent/copper = 10, /datum/reagent/toxin/acid = 10))
	if(!B.reagents.has_reagent(text2path("/datum/reagent/voltagel")))
		missing += "voltagel"
	B = mix(T, list(/datum/reagent/phosphorus = 10, /datum/reagent/uranium/radium = 10, /datum/reagent/consumable/sugar = 10))
	if(!B.reagents.has_reagent(text2path("/datum/reagent/lumen")))
		missing += "lumen gel"
	return length(missing) ? "no [english_list(missing)] from the recipe" : null

/datum/bot_scenario/content/haemoplast
	name = "chemistry: haemoplast puts blood back that stays"
	desc = "Somebody a third of their blood down, with haemoplast in them. Saline only stands in for blood while it lasts; this is taken up."
	var/mob/living/carbon/human/patient
	var/given_at

/datum/bot_scenario/content/haemoplast/try_it(turf/T)
	patient = stand_in(T, "Pale Patient")
	patient.blood_volume = 350
	patient.reagents.add_reagent(text2path("/datum/reagent/medicine/haemoplast"), 10)
	given_at = world.time
	return patient.reagents.total_volume ? null : "nothing went in"

/datum/bot_scenario/content/haemoplast/later()
	if(patient.blood_volume >= 380)
		return TRUE
	return world.time > given_at + 15 SECONDS ? "blood at [round(patient.blood_volume)] fifteen seconds on, from 350" : null

/datum/bot_scenario/content/vitrium
	name = "chemistry: vitrium mends a cracked window and leaves it tougher, once"
	desc = "Ten units splashed on a window knocked down to a fifth of its strength, then ten more."

/datum/bot_scenario/content/vitrium/try_it(turf/T)
	var/obj/structure/window/W = place("K", new /obj/structure/window(T, WEST))
	var/was = W.max_integrity
	W.obj_integrity = was * 0.2
	var/obj/item/reagent_containers/glass/beaker/B = place("K", new /obj/item/reagent_containers/glass/beaker(T))
	B.reagents.add_reagent(text2path("/datum/reagent/vitrium"), 10)
	B.reagents.reaction(W, TOUCH)
	if(W.obj_integrity <= was * 0.2)
		return "the window's no better for it"
	if(W.max_integrity <= was)
		return "the window's no tougher for it"
	var/tougher = W.max_integrity
	B.reagents.reaction(W, TOUCH)
	return W.max_integrity > tougher ? "a second coat made it tougher again" : null

/datum/bot_scenario/content/voltagel
	name = "chemistry: voltagel splashed on a flat power cell charges it"
	desc = "A cell with nothing in it and ten units of the gel."

/datum/bot_scenario/content/voltagel/try_it(turf/T)
	var/obj/item/stock_parts/cell/high/C = place("K", new /obj/item/stock_parts/cell/high(T))
	C.charge = 0
	var/obj/item/reagent_containers/glass/beaker/B = place("K", new /obj/item/reagent_containers/glass/beaker(T))
	B.reagents.add_reagent(text2path("/datum/reagent/voltagel"), 10)
	B.reagents.reaction(C, TOUCH)
	return C.charge > 0 ? null : "the cell's still flat"

/datum/bot_scenario/content/lumen
	name = "chemistry: lumen gel splashed on the floor leaves a puddle that glows"
	desc = "Ten units on a floor tile."

/datum/bot_scenario/content/lumen/try_it(turf/T)
	var/obj/item/reagent_containers/glass/beaker/B = place("K", new /obj/item/reagent_containers/glass/beaker(T))
	B.reagents.add_reagent(text2path("/datum/reagent/lumen"), 10)
	B.reagents.reaction(T, TOUCH)
	var/obj/effect/decal/cleanable/greenglow/puddle = locate() in T
	if(!puddle)
		return "no puddle"
	place("K", puddle)
	return puddle.light_range >= 3 ? null : "the puddle doesn't light anything"

// ---------------------------------------------------------------------------------------------
// Machines
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/content/sleeper_saline
	name = "machines: a sleeper stocks saline and gives it to somebody too far gone for the rest"
	desc = "Somebody at forty under, short of blood, in a sleeper. Below twenty-five under it gave epinephrine and nothing else, and what they were dying of was blood."

/datum/bot_scenario/content/sleeper_saline/try_it(turf/T)
	var/obj/machinery/sleeper/S = place("K", new /obj/machinery/sleeper(T))
	if(!(/datum/reagent/medicine/salglu_solution in S.available_chems))
		return "no saline on its list"
	var/mob/living/carbon/human/patient = stand_in(T, "Pale Patient")
	patient.blood_volume = 300
	patient.adjustOxyLoss(140)
	patient.updatehealth()
	S.close_machine(patient)
	if(S.occupant != patient)
		return "the patient didn't go in"
	if(S.chem_allowed(/datum/reagent/medicine/bicaridine))
		return "it gives bicaridine at forty under: nothing tried"
	if(!S.inject_chem(/datum/reagent/medicine/salglu_solution))
		return "it won't give saline at forty under"
	return patient.reagents.has_reagent(/datum/reagent/medicine/salglu_solution) ? null : "the saline didn't go in"
