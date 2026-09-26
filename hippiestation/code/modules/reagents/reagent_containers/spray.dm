/obj/item/reagent_containers/spray/cleaner
	volume = 250
	list_reagents = list(/datum/reagent/space_cleaner = 250)
	amount_per_transfer_from_this = 5
	stream_amount = 10

/**
  * A chem sprayer pre-loaded with fluorosulfuric acid: the same reagent the acid grenade and metal foam use, just
  * delivered as a sustained stream instead of a single splash. Reagent vapor already melts armor, machines, and
  * even walls through the normal acid_act() path (see toxin/acid/reaction_mob/obj/turf and turf/closed/wall/acid_act
  * in walls.dm), so nothing new needed building there - this is just a dedicated, pre-filled delivery tool for it.
  */
/obj/item/reagent_containers/spray/chemsprayer/acidthrower
	name = "acid thrower"
	desc = "A chem sprayer rigged to project a steady stream of fluorosulfuric acid. Eats through armor, machinery and even hull plating."
	icon_state = "chemsprayer" // no dedicated sprite yet, reusing the base chem sprayer's
	item_state = "chemsprayer"
	list_reagents = list(/datum/reagent/toxin/acid/fluacid = 750)
	volume = 750
	amount_per_transfer_from_this = 15
