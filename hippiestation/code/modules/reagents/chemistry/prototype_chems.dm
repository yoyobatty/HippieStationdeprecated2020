// New chemicals of 2026-11-10, each with something to do it to. Reagent, recipe and what it does to a thing are kept together here.
//
//  - Haemoplast: blood that stays. Saline only stands in for blood while it's in the body; this the body keeps.
//  - Vitrium: sets hard on glass. Splashed on a window it mends it, and ten units make it a quarter tougher, once.
//  - Voltagel: holds a charge. Splashed on a power cell it gives it up.
//  - Lumen gel: glows. Splashed on the floor it lights the room for a few minutes.
//
// And two things for the commonest death in Medbay, losing blood: a sleeper stocks saline and gives it to somebody too far gone
// for the rest of what it has, and a defibrillator says so when it's brought back somebody with too little blood to live on.

// ---------------------------------------------------------------------------------------------
// Haemoplast
// ---------------------------------------------------------------------------------------------

/datum/reagent/medicine/haemoplast
	name = "Haemoplast"
	description = "A synthetic blood substitute. Saline stands in for lost blood only while it lasts; this the body takes up as its own. Too much at once and the blood runs thick."
	reagent_state = LIQUID
	color = "#B03A48"
	taste_description = "copper"
	metabolization_rate = 0.5 * REAGENTS_METABOLISM
	overdose_threshold = 40

/datum/reagent/medicine/haemoplast/on_mob_life(mob/living/carbon/M)
	var/mob/living/carbon/human/H = M
	if(istype(H) && !(NOBLOOD in H.dna?.species?.species_traits) && H.blood_volume < BLOOD_VOLUME_NORMAL)
		H.blood_volume = min(H.blood_volume + 6, BLOOD_VOLUME_NORMAL)
	..()

/datum/reagent/medicine/haemoplast/overdose_process(mob/living/M)
	M.adjustOxyLoss(1.5 * REM, 0)
	M.adjustStaminaLoss(2 * REM, 0)
	if(prob(10))
		to_chat(M, "<span class='warning'>Your heart labours. Your blood feels thick.</span>")
	..()
	. = 1

/datum/chemical_reaction/haemoplast
	name = "Haemoplast"
	id = "haemoplast"
	results = list(/datum/reagent/medicine/haemoplast = 3)
	required_reagents = list(/datum/reagent/medicine/salglu_solution = 2, /datum/reagent/iron = 1, /datum/reagent/medicine/epinephrine = 1)
	required_temp = 330
	mix_message = "The solution thickens and turns a deep red."

// ---------------------------------------------------------------------------------------------
// Vitrium
// ---------------------------------------------------------------------------------------------

/obj/structure/window
	/// Hardened with vitrium already: it only takes once.
	var/vitrified = FALSE

/datum/reagent/vitrium
	name = "Vitrium"
	description = "A silicate resin that sets hard on glass. It fills the cracks in a window, and enough of it leaves the pane tougher than it was."
	reagent_state = LIQUID
	color = "#BFE9F2"
	taste_description = "sand"

/datum/reagent/vitrium/reaction_obj(obj/O, volume)
	// A shard of glass: five units fuse it back into a sheet
	var/obj/item/shard/shard = O
	if(istype(shard) && volume >= 5)
		var/sheet = istype(shard, /obj/item/shard/plasma) ? /obj/item/stack/sheet/plasmaglass : /obj/item/stack/sheet/glass
		new sheet(shard.drop_location())
		shard.visible_message("<span class='notice'>The resin draws [shard] together into a clean sheet.</span>")
		qdel(shard)
		return
	var/obj/structure/window/W = O
	if(!istype(W) || volume < 1)
		return ..()
	var/mended = W.obj_integrity < W.max_integrity
	if(volume >= 10 && !W.vitrified)
		W.vitrified = TRUE
		W.max_integrity = round(W.max_integrity * 1.25)
		W.visible_message("<span class='notice'>The resin sets across [W], leaving it clearer and harder.</span>")
	else if(mended)
		W.visible_message("<span class='notice'>The resin runs into the cracks in [W] and sets.</span>")
	W.obj_integrity = min(W.max_integrity, W.obj_integrity + volume * 10)
	W.update_nearby_icons()

/datum/chemical_reaction/vitrium
	name = "Vitrium"
	id = "vitrium"
	results = list(/datum/reagent/vitrium = 3)
	required_reagents = list(/datum/reagent/silicon = 2, /datum/reagent/aluminium = 1, /datum/reagent/toxin/plasma = 1)
	required_temp = 500
	mix_message = "The mixture goes glassy and clear."

/// Baked hotter, it's glass: a sheet for every ten units.
/datum/chemical_reaction/vitrium_glass
	name = "Vitrium glass"
	id = "vitrium_glass"
	required_reagents = list(/datum/reagent/vitrium = 10)
	required_temp = 800
	mix_message = "The resin sets solid in the heat."

/datum/chemical_reaction/vitrium_glass/on_reaction(datum/reagents/holder, created_volume)
	var/turf/T = get_turf(holder.my_atom)
	if(T && created_volume >= 1)
		new /obj/item/stack/sheet/glass(T, round(created_volume))

// ---------------------------------------------------------------------------------------------
// Voltagel
// ---------------------------------------------------------------------------------------------

/datum/reagent/voltagel
	name = "Voltagel"
	description = "A conductive gel that holds a charge and gives it up to the first power cell it touches. Not for drinking."
	reagent_state = LIQUID
	color = "#F2E24A"
	taste_description = "a nine-volt battery"
	/// What a unit of it puts into a cell
	var/charge_per_unit = 250

/datum/reagent/voltagel/reaction_obj(obj/O, volume)
	var/obj/item/stock_parts/cell/C = O
	if(!istype(C))
		C = O.get_cell() //whatever keeps one: a stun baton, an energy gun, an APC
	if(!istype(C) || volume < 1)
		return ..()
	var/given = C.give(min(volume * charge_per_unit, C.maxcharge - C.charge))
	if(given)
		C.update_icon()
		C.visible_message("<span class='notice'>[C] crackles as the gel discharges into it.</span>")
		do_sparks(1, FALSE, C)

/datum/reagent/voltagel/on_mob_life(mob/living/carbon/M)
	M.adjustFireLoss(0.5 * REM, 0)
	M.Jitter(5)
	if(prob(10))
		to_chat(M, "<span class='warning'>Your teeth buzz.</span>")
	..()
	. = 1

/datum/chemical_reaction/voltagel
	name = "Voltagel"
	id = "voltagel"
	results = list(/datum/reagent/voltagel = 3)
	required_reagents = list(/datum/reagent/consumable/liquidelectricity = 1, /datum/reagent/copper = 1, /datum/reagent/toxin/acid = 1)
	mix_message = "The mixture sets to a gel that makes your hair stand up."

// ---------------------------------------------------------------------------------------------
// Lumen gel
// ---------------------------------------------------------------------------------------------

/datum/reagent/lumen
	name = "Lumen Gel"
	description = "A cold-glowing gel. A splash of it on the floor lights a room for a few minutes."
	reagent_state = LIQUID
	color = "#7FFFD4"
	taste_description = "glow sticks"

/datum/reagent/lumen/reaction_turf(turf/T, volume)
	if(!isopenturf(T) || isspaceturf(T) || volume < 5 || (locate(/obj/effect/decal/cleanable/greenglow/lumen) in T))
		return
	new /obj/effect/decal/cleanable/greenglow/lumen(T)

/obj/effect/decal/cleanable/greenglow/lumen
	name = "glowing gel"
	desc = "A puddle of gel giving off a cold light. It fades."
	light_power = 1
	light_range = 4
	light_color = "#7FFFD4"
	color = "#7FFFD4"

/obj/effect/decal/cleanable/greenglow/lumen/Initialize()
	. = ..()
	QDEL_IN(src, 3 MINUTES)

/datum/chemical_reaction/lumen
	name = "Lumen Gel"
	id = "lumen"
	results = list(/datum/reagent/lumen = 3)
	required_reagents = list(/datum/reagent/phosphorus = 1, /datum/reagent/uranium/radium = 1, /datum/reagent/consumable/sugar = 1)
	mix_message = "The mixture begins to glow."

// ---------------------------------------------------------------------------------------------
// Saline in the sleeper
// ---------------------------------------------------------------------------------------------

/obj/machinery/sleeper/Initialize()
	var/list/first = possible_chems[1]
	possible_chems[1] = first | list(/datum/reagent/medicine/salglu_solution)
	return ..()

/// Saline, like epinephrine, for somebody too far gone for the rest: what they're short of is blood.
/obj/machinery/sleeper/chem_allowed(chem)
	. = ..()
	if(. || chem != /datum/reagent/medicine/salglu_solution)
		return
	var/mob/living/mob_occupant = occupant
	return mob_occupant?.reagents && mob_occupant.reagents.get_reagent_amount(chem) + 10 <= 20 * efficiency

// ---------------------------------------------------------------------------------------------
// A saline autoinjector
// ---------------------------------------------------------------------------------------------

/// Fifteen units of saline in a pen: what somebody bleeding out wants while the blood's fetched. The NanoMeds sell them.
/obj/item/reagent_containers/hypospray/medipen/saline
	name = "saline autoinjector"
	desc = "A pen of saline-glucose solution for somebody who's lost a lot of blood. It stands in for blood until the real thing can be got into them."
	icon_state = "lepopen"
	amount_per_transfer_from_this = 15
	volume = 15
	list_reagents = list(/datum/reagent/medicine/salglu_solution = 15)
	custom_price = 30

/obj/machinery/vending/medical/Initialize(mapload)
	products[/obj/item/reagent_containers/hypospray/medipen/saline] = 4
	return ..()

/obj/machinery/vending/wallmed/Initialize(mapload)
	products[/obj/item/reagent_containers/hypospray/medipen/saline] = 2
	return ..()

// ---------------------------------------------------------------------------------------------
// An IV drip says when its bag's run dry
// ---------------------------------------------------------------------------------------------

/obj/machinery/iv_drip
	/// Beeped for the empty bag already
	var/said_empty = FALSE

/obj/machinery/iv_drip/process()
	. = ..()
	if(. == PROCESS_KILL || !attached || !beaker || !mode || beaker.reagents.total_volume) //mode: giving, not taking (iv_drip.dm's IV_INJECTING)
		said_empty = FALSE
		return
	if(!said_empty)
		said_empty = TRUE
		playsound(src, 'sound/machines/twobeep.ogg', 50, 1)
		visible_message("<span class='notice'>[src] beeps: its bag is empty.</span>")
