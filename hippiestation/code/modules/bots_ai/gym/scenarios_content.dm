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

/datum/bot_scenario/content/more_reactions
	name = "chemistry: vitrium fuses a shard and bakes to glass, and voltagel charges what has a cell in it"
	desc = "Five units of vitrium on a shard of glass; ten heated past 800 K; and voltagel splashed on a stun baton that's flat."

/datum/bot_scenario/content/more_reactions/try_it(turf/T)
	var/list/missing = list()
	var/obj/item/shard/shard = place("K", new /obj/item/shard(T))
	var/obj/item/reagent_containers/glass/beaker/B = place("K", new /obj/item/reagent_containers/glass/beaker(T))
	B.reagents.add_reagent(text2path("/datum/reagent/vitrium"), 5)
	B.reagents.reaction(shard, TOUCH)
	var/obj/item/stack/sheet/glass/sheet = locate() in T
	if(!QDELETED(shard) || !sheet)
		missing += "the shard's still a shard"
	if(sheet)
		qdel(sheet)
	B = mix(T, list(text2path("/datum/reagent/vitrium") = 20), 820)
	sheet = locate() in T
	if(!sheet || B.reagents.has_reagent(text2path("/datum/reagent/vitrium")))
		missing += "no glass out of the heated resin"
	if(sheet)
		place("K", sheet)
	var/obj/item/melee/baton/loaded/baton = place("K", new /obj/item/melee/baton/loaded(T))
	var/obj/item/stock_parts/cell/inside = baton.get_cell()
	inside.charge = 0
	B = place("K", new /obj/item/reagent_containers/glass/beaker(T))
	B.reagents.add_reagent(text2path("/datum/reagent/voltagel"), 10)
	B.reagents.reaction(baton, TOUCH)
	if(!inside.charge)
		missing += "the baton's cell is still flat"
	return length(missing) ? english_list(missing) : null

/datum/bot_scenario/content/saline_pen
	name = "items: the saline autoinjector is in the NanoMeds and puts saline into whoever it's used on"
	desc = "A pen of saline for somebody bleeding out: sold by the NanoMed Plus and the wall NanoMed."

/datum/bot_scenario/content/saline_pen/try_it(turf/T)
	var/pen_type = text2path("/obj/item/reagent_containers/hypospray/medipen/saline")
	if(!pen_type)
		return "no such pen"
	var/obj/machinery/vending/medical/plus = place("K", new /obj/machinery/vending/medical(T))
	if(!plus.products[pen_type])
		return "the NanoMed Plus doesn't stock it"
	var/found = FALSE
	for(var/datum/data/vending_product/record in plus.product_records)
		if(record.product_path == pen_type)
			found = TRUE
	if(!found)
		return "the NanoMed Plus lists it and has none"
	qdel(plus)
	var/mob/living/carbon/human/patient = stand_in(T, "Pale Patient")
	var/obj/item/reagent_containers/hypospray/medipen/pen = place("K", new pen_type(bot.loc))
	bot.put_in_hands(pen)
	bot.forceMove(get_step(T, WEST))
	pen.attack(patient, bot)
	return patient.reagents.get_reagent_amount(/datum/reagent/medicine/salglu_solution) >= 10 ? null : "no saline went in"

/datum/bot_scenario/content/drip_beeps
	name = "machines: an IV drip beeps once when its bag has run dry"
	desc = "A drip on somebody with an empty bag hung on it."

/datum/bot_scenario/content/drip_beeps/try_it(turf/T)
	var/obj/machinery/iv_drip/drip = place("K", new /obj/machinery/iv_drip(T))
	var/mob/living/carbon/human/patient = stand_in(T, "Pale Patient")
	drip.beaker = new /obj/item/reagent_containers/blood(drip)
	drip.beaker.reagents.clear_reagents()
	drip.attached = patient
	drip.process()
	if(!drip.vars["said_empty"])
		return "no beep for the empty bag"
	drip.beaker.reagents.add_reagent(/datum/reagent/blood, 20)
	drip.process()
	return drip.vars["said_empty"] ? "still calling the bag empty with blood in it" : null

/datum/bot_scenario/content/tray_chems
	name = "botany: lumen gel makes a plant glow, voltagel makes it hold a charge and vitrium makes it hardier"
	desc = "Five units of each in a tray with a tomato plant in it."

/datum/bot_scenario/content/tray_chems/try_it(turf/T)
	var/obj/machinery/hydroponics/constructable/tray = place("K", new /obj/machinery/hydroponics/constructable(T))
	tray.myseed = new /obj/item/seeds/tomato(tray)
	var/hardy = tray.myseed.endurance
	var/obj/item/reagent_containers/glass/beaker/B = place("K", new /obj/item/reagent_containers/glass/beaker(T))
	B.reagents.add_reagent(text2path("/datum/reagent/lumen"), 5)
	B.reagents.add_reagent(text2path("/datum/reagent/voltagel"), 5)
	B.reagents.add_reagent(text2path("/datum/reagent/vitrium"), 5)
	tray.applyChemicals(B.reagents, bot)
	var/list/missing = list()
	if(!tray.myseed.get_gene(/datum/plant_gene/trait/glow))
		missing += "no glow"
	if(!tray.myseed.get_gene(/datum/plant_gene/trait/cell_charge))
		missing += "no charge"
	if(tray.myseed.endurance <= hardy)
		missing += "no hardier"
	tray.applyChemicals(B.reagents, bot)
	var/glows = 0
	for(var/datum/plant_gene/trait/glow/G in tray.myseed.genes)
		glows++
	if(glows > 1)
		missing += "a second dose gave it the glow twice"
	return length(missing) ? english_list(missing) : null

/datum/bot_scenario/content/lumen_on_people
	name = "chemistry: lumen gel splashed on somebody makes them glow"
	desc = "Ten units over a bystander."

/datum/bot_scenario/content/lumen_on_people/try_it(turf/T)
	var/mob/living/carbon/human/patient = stand_in(T, "Glowing Patient")
	var/obj/item/reagent_containers/glass/beaker/B = place("K", new /obj/item/reagent_containers/glass/beaker(T))
	B.reagents.add_reagent(text2path("/datum/reagent/lumen"), 10)
	B.reagents.reaction(patient, TOUCH)
	return (locate(/obj/effect/dummy/lighting_obj/moblight) in patient) ? null : "no light on them"

/datum/bot_scenario/content/batch_four
	name = "chemistry: voltagel sparks in water, lumen gel refuels a glowstick, vitrium takes up the glass on a floor"
	desc = "Ten units of voltagel into water; lumen gel on a spent glowstick; vitrium splashed on a floor with a shard on it."

/datum/bot_scenario/content/batch_four/try_it(turf/T)
	var/list/missing = list()
	var/obj/item/reagent_containers/B = mix(T, list(text2path("/datum/reagent/voltagel") = 10, /datum/reagent/water = 10))
	if(B.reagents.has_reagent(text2path("/datum/reagent/voltagel")) || B.reagents.has_reagent(/datum/reagent/water))
		missing += "the gel and the water are still sat there together"
	var/obj/item/flashlight/glowstick/stick = place("K", new /obj/item/flashlight/glowstick(T))
	stick.fuel = 0
	B = place("K", new /obj/item/reagent_containers/glass/beaker(T))
	B.reagents.add_reagent(text2path("/datum/reagent/lumen"), 10)
	B.reagents.reaction(stick, TOUCH)
	if(stick.fuel < 300)
		missing += "the glowstick's still spent"
	for(var/obj/effect/decal/cleanable/greenglow/puddle in T)
		qdel(puddle)
	place("K", new /obj/item/shard(T))
	B = place("K", new /obj/item/reagent_containers/glass/beaker(T))
	B.reagents.add_reagent(text2path("/datum/reagent/vitrium"), 10)
	B.reagents.reaction(T, TOUCH)
	if(locate(/obj/item/shard) in T)
		missing += "the shard's still on the floor"
	var/obj/item/stack/sheet/glass/sheet = locate() in T
	if(sheet)
		place("K", sheet)
	return length(missing) ? english_list(missing) : null

/datum/bot_scenario/content/optable_readout
	name = "machines: an operating table says who's on it and when they're short of blood"
	desc = "Somebody on the table with two thirds of their blood."

/datum/bot_scenario/content/optable_readout/try_it(turf/T)
	var/obj/structure/table/optable/table = place("K", new /obj/structure/table/optable(T))
	var/mob/living/carbon/human/patient = stand_in(T, "Pale Patient")
	patient.blood_volume = 370
	var/list/told = table.examine(bot)
	var/all_of_it = jointext(told, " ")
	if(!findtext(all_of_it, "is on it"))
		return "nothing about who's on it"
	return findtext(all_of_it, "pale") ? null : "nothing about their blood"

/datum/bot_scenario/content/blood_synth
	name = "machines: a blood synthesiser fills an empty pack with universal blood, and turns down a pack of somebody's own"
	desc = "A pack of A+ offered, then an empty one hung on it and run with the power off, on, and past full."

/datum/bot_scenario/content/blood_synth/try_it(turf/T)
	var/obj/machinery/blood_synth/synth = place("K", new /obj/machinery/blood_synth(T))
	var/list/missing = list()
	bot.forceMove(get_step(T, WEST))
	var/obj/item/reagent_containers/blood/typed = place("K", new /obj/item/reagent_containers/blood/APlus(T))
	synth.attackby(typed, bot)
	if(synth.pack)
		missing += "it took a pack of A+"
		synth.drop_pack()
	var/obj/item/reagent_containers/blood/pack = place("K", new /obj/item/reagent_containers/blood(T))
	synth.attackby(pack, bot)
	if(synth.pack != pack)
		return "the empty pack didn't go on"
	synth.stat |= NOPOWER
	synth.process()
	if(pack.reagents.total_volume)
		missing += "it made blood with no power"
	synth.stat &= ~NOPOWER
	for(var/i in 1 to 30)
		synth.process()
	if(pack.reagents.total_volume != 30)
		missing += "thirty cycles made [pack.reagents.total_volume] units"
	if(pack.blood_type != "U")
		missing += "the blood's of type [pack.blood_type]"
	for(var/i in 1 to 250)
		synth.process()
	if(pack.reagents.total_volume != pack.reagents.maximum_volume)
		missing += "left running it holds [pack.reagents.total_volume] of [pack.reagents.maximum_volume]"
	synth.drop_pack()
	synth.attackby(pack, bot)
	if(synth.pack != pack)
		missing += "it turned down a pack of its own blood"
	synth.attack_hand(bot)
	if(synth.pack || pack.loc == synth)
		missing += "the pack didn't come off by hand"
	var/datum/techweb_node/node = SSresearch.techweb_node_by_id("adv_biotech")
	if(!node || !("blood_synth" in node.design_ids) || !SSresearch.techweb_design_by_id("blood_synth"))
		missing += "its board isn't in research"
	return length(missing) ? english_list(missing) : null

/datum/bot_scenario/content/machine_readouts
	name = "machines: a drip, a field generator, an emitter, a power store and the gravity generator say how they are when looked at"
	desc = "One of each, looked at."

/datum/bot_scenario/content/machine_readouts/try_it(turf/T)
	var/list/missing = list()
	bot.forceMove(T)
	var/obj/machinery/iv_drip/drip = place("K", new /obj/machinery/iv_drip(T))
	var/mob/living/carbon/human/patient = stand_in(T, "Pale Patient")
	patient.blood_volume = 300
	drip.attached = patient
	if(!findtext(jointext(drip.examine(bot), " "), "looks pale"))
		missing += "the drip says nothing of their blood"
	drip.attached = null
	var/obj/machinery/field/generator/gen = place("K", new /obj/machinery/field/generator(T))
	var/said = jointext(gen.examine(bot), " ")
	if(!findtext(said, "loose on the floor") || !findtext(said, "It's off"))
		missing += "the field generator: [said]"
	var/obj/machinery/power/emitter/emitter = place("K", new /obj/machinery/power/emitter(T))
	said = jointext(emitter.examine(bot), " ")
	if(!findtext(said, "loose on the floor") || !findtext(said, "It's off"))
		missing += "the emitter: [said]"
	emitter.active = TRUE
	if(!findtext(jointext(emitter.examine(bot), " "), "no power to fire"))
		missing += "an emitter on with no power doesn't say so"
	emitter.active = FALSE
	var/obj/machinery/power/smes/store = place("K", new /obj/machinery/power/smes(T))
	store.charge = store.capacity / 2
	if(!findtext(jointext(store.examine(bot), " "), "50%"))
		missing += "the power store's meter"
	var/obj/machinery/gravity_generator/main/gravity = place("K", new /obj/machinery/gravity_generator/main(T))
	if(!findtext(jointext(gravity.examine(bot), " "), "charged to 100%"))
		missing += "the gravity generator's charge"
	return length(missing) ? english_list(missing) : null
