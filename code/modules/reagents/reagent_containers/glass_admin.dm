// Adminbus-only gas beakers. Not obtainable through normal gameplay (no vendor/loot table
// references) -- spawn via the admin "Create Item" panel by typepath for atmos testing,
// e.g. supermatter delamination scenarios.

/obj/item/reagent_containers/glass/beaker/large/admin_gas
	name = "administrative gas beaker"
	desc = "A beaker that shouldn't exist outside of testing. Holds up to 1000 units."
	icon_state = "beakerbluespace"
	volume = 1000
	amount_per_transfer_from_this = 100
	possible_transfer_amounts = list(10, 25, 50, 100, 250, 500, 1000)

/obj/item/reagent_containers/glass/beaker/large/admin_gas/plasma
	name = "administrative gas beaker (plasma)"
	list_reagents = list(/datum/reagent/toxin/plasma = 1000)

/obj/item/reagent_containers/glass/beaker/large/admin_gas/carbondioxide
	name = "administrative gas beaker (carbon dioxide)"
	list_reagents = list(/datum/reagent/carbondioxide = 1000)

/obj/item/reagent_containers/glass/beaker/large/admin_gas/nitrous_oxide
	name = "administrative gas beaker (nitrous oxide)"
	list_reagents = list(/datum/reagent/nitrous_oxide = 1000)

/obj/item/reagent_containers/glass/beaker/large/admin_gas/oxygen
	name = "administrative gas beaker (oxygen)"
	list_reagents = list(/datum/reagent/oxygen = 1000)

/obj/item/reagent_containers/glass/beaker/large/admin_gas/nitrogen
	name = "administrative gas beaker (nitrogen)"
	list_reagents = list(/datum/reagent/nitrogen = 1000)
