/obj/item/grenade/chem_grenade
	banned_containers = list() // reverts bluespace beaker's nerf

/obj/item/grenade/chem_grenade/Crossed(atom/movable/AM, oldloc)
	for(var/A in wires.assemblies)
		var/obj/item/I = wires.assemblies[A]
		if(istype(I))
			I.Crossed(AM, oldloc)
	return ..()

/obj/item/grenade/chem_grenade/on_found(mob/finder)
	for(var/A in wires.assemblies)
		var/obj/item/assembly/I = wires.assemblies[A]
		if(istype(I))
			I.on_found(finder)

/obj/item/grenade/chem_grenade/saringas
	name = "Sarin gas grenade"
	desc = "Tiger Cooperative military grade nerve gas. WARNING: Ensure internals are active before use, nerve agents are exceptionally lethal regardless of dosage"
	stage = GRENADE_READY

/obj/item/grenade/chem_grenade/saringas/Initialize()
	. = ..()
	var/obj/item/reagent_containers/glass/beaker/large/B1 = new(src)
	var/obj/item/reagent_containers/glass/beaker/large/B2 = new(src)

	B1.reagents.add_reagent(/datum/reagent/toxin/sarin, 100)
	B2.reagents.add_reagent(/datum/reagent/toxin/sarin, 100)
	B1.reagents.chem_temp = 1000
	B2.reagents.chem_temp = 1000
	beakers += B1
	beakers += B2

/obj/item/grenade/chem_grenade/blackpowder
	name = "black powder grenade"
	desc = "Mixes saltpetre, charcoal and sulfur on detonation, scattering the resulting black powder. Keep it away from heat."
	stage = GRENADE_READY
	var/beaker_type = /obj/item/reagent_containers/glass/beaker/large
	var/reagent_scale = 1

/obj/item/grenade/chem_grenade/blackpowder/Initialize()
	. = ..()
	var/obj/item/reagent_containers/glass/beaker/B1 = new beaker_type(src)
	var/obj/item/reagent_containers/glass/beaker/B2 = new beaker_type(src)

	B1.reagents.add_reagent(/datum/reagent/saltpetre, 50 * reagent_scale)
	B1.reagents.add_reagent(/datum/reagent/medicine/charcoal, 50 * reagent_scale)
	B2.reagents.add_reagent(/datum/reagent/sulfur, 50 * reagent_scale)

	beakers += B1
	beakers += B2

/obj/item/grenade/chem_grenade/hydrofluoric
	name = "hydrofluoric acid grenade"
	desc = "Synthesizes fluorosulfuric acid on detonation. Contents are stored pre-heated. Do not handle without protection."
	stage = GRENADE_READY
	var/beaker_type = /obj/item/reagent_containers/glass/beaker/large
	var/reagent_scale = 1

/obj/item/grenade/chem_grenade/hydrofluoric/Initialize()
	. = ..()
	var/obj/item/reagent_containers/glass/beaker/B1 = new beaker_type(src)
	var/obj/item/reagent_containers/glass/beaker/B2 = new beaker_type(src)

	B1.reagents.add_reagent(/datum/reagent/toxin/acid, 50 * reagent_scale)
	B1.reagents.add_reagent(/datum/reagent/fluorine, 50 * reagent_scale)
	B2.reagents.add_reagent(/datum/reagent/hydrogen, 50 * reagent_scale)
	B2.reagents.add_reagent(/datum/reagent/potassium, 50 * reagent_scale)
	// The acid recipe needs 380K, more than a grenade's own ignition heat provides
	B1.reagents.chem_temp = 400
	B2.reagents.chem_temp = 400

	beakers += B1
	beakers += B2

/obj/item/grenade/chem_grenade/plasmasmoke
	name = "plasma smoke grenade"
	desc = "Releases a thick cloud of plasma-laden smoke. Contents under pressure. Do not directly inhale contents."
	stage = GRENADE_READY
	var/beaker_type = /obj/item/reagent_containers/glass/beaker/large
	var/reagent_scale = 1

/obj/item/grenade/chem_grenade/plasmasmoke/Initialize()
	. = ..()
	var/obj/item/reagent_containers/glass/beaker/B1 = new beaker_type(src)
	var/obj/item/reagent_containers/glass/beaker/B2 = new beaker_type(src)

	B1.reagents.add_reagent(/datum/reagent/toxin/plasma, 60 * reagent_scale)
	B1.reagents.add_reagent(/datum/reagent/potassium, 40 * reagent_scale)
	B2.reagents.add_reagent(/datum/reagent/phosphorus, 40 * reagent_scale)
	B2.reagents.add_reagent(/datum/reagent/consumable/sugar, 40 * reagent_scale)

	beakers += B1
	beakers += B2

/obj/item/grenade/chem_grenade/pyro/volatile
	name = "volatile pyro grenade"
	desc = "Black powder, fluorosulfuric acid and plasma, all carried out in a smoke cloud, then set alight. Whoever built this wanted everyone to have a bad day."
	stage = GRENADE_READY
	// Kept low on purpose: at the stock pyro 500K the black powder (474K) blows up inside the grenade
	// before any smoke gets out. The fire is delivered by the fiery explosion in prime() instead.
	ignition_temp = 100
	var/beaker_type = /obj/item/reagent_containers/glass/beaker/large
	var/reagent_scale = 1
	var/ignite_range = 6 // how far the fiery explosion travels, roughly the smoke radius for the standard version
	var/ignite_delay = 60 // gives the smoke time to spread and leave chem piles behind

/obj/item/grenade/chem_grenade/pyro/volatile/Initialize()
	. = ..()
	var/obj/item/reagent_containers/glass/beaker/B1 = new beaker_type(src)
	var/obj/item/reagent_containers/glass/beaker/B2 = new beaker_type(src)

	// Same setup as the teargas grenade: potassium, phosphorus and sugar react into the smoke
	// (25 of each), which carries the finished payload out. Keeping the payload as finished reagents
	// means the smoke reaction is the only one that can fire, whatever order the reagents react in.
	B1.reagents.add_reagent(/datum/reagent/potassium, 25 * reagent_scale)
	B1.reagents.add_reagent(/datum/reagent/blackpowder, 40 * reagent_scale)
	B1.reagents.add_reagent(/datum/reagent/toxin/plasma, 30 * reagent_scale)
	B2.reagents.add_reagent(/datum/reagent/phosphorus, 25 * reagent_scale)
	B2.reagents.add_reagent(/datum/reagent/consumable/sugar, 25 * reagent_scale)
	B2.reagents.add_reagent(/datum/reagent/toxin/acid/fluacid, 40 * reagent_scale)

	beakers += B1
	beakers += B2

/obj/item/grenade/chem_grenade/pyro/volatile/prime()
	if(stage != GRENADE_READY)
		return
	var/turf/epicenter = get_turf(src)
	..()
	// The grenade only deletes itself if it actually splashed something
	if(epicenter && QDELETED(src))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(fiery_explosion), epicenter, ignite_range, 3), ignite_delay)

// Bluespace variants: the same mixes in bluespace beakers, at triple the amounts
/obj/item/grenade/chem_grenade/blackpowder/bluespace
	name = "bluespace black powder grenade"
	beaker_type = /obj/item/reagent_containers/glass/beaker/bluespace
	reagent_scale = 3

/obj/item/grenade/chem_grenade/hydrofluoric/bluespace
	name = "bluespace hydrofluoric acid grenade"
	beaker_type = /obj/item/reagent_containers/glass/beaker/bluespace
	reagent_scale = 3

/obj/item/grenade/chem_grenade/plasmasmoke/bluespace
	name = "bluespace plasma smoke grenade"
	beaker_type = /obj/item/reagent_containers/glass/beaker/bluespace
	reagent_scale = 3

/obj/item/grenade/chem_grenade/pyro/volatile/bluespace
	name = "bluespace volatile pyro grenade"
	beaker_type = /obj/item/reagent_containers/glass/beaker/bluespace
	reagent_scale = 3
	ignite_range = 10
