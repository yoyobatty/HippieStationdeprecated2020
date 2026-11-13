/obj/structure/reagent_dispensers
	var/mutable_appearance/reagent_icon
	var/use_reagent_icon = FALSE

/obj/structure/reagent_dispensers/Initialize()
	. = ..()
	generate_reagent_icon()

/obj/structure/reagent_dispensers/Destroy()
	QDEL_NULL(reagent_icon)
	return ..()

/obj/structure/reagent_dispensers/on_reagent_change()
	update_icon()

/obj/structure/reagent_dispensers/attack_hand()
	..()
	update_icon()

/obj/structure/reagent_dispensers/update_icon()
	if(!use_reagent_icon)
		return
	cut_overlays()
	if(reagent_icon && reagents && reagents.total_volume)
		// a quarter full or less, half, three quarters, full
		reagent_icon.icon_state = "tankfilling[clamp(CEILING(reagents.total_volume / tank_volume * 4, 1), 1, 4)]"
		reagent_icon.color = mix_color_from_reagents(reagents.reagent_list)
		add_overlay(reagent_icon)

/obj/structure/reagent_dispensers/chemical
	name = "chem tank"
	desc = "It can hold a large amount of chemicals. Use a screwdriver to open and close its lid, and a wrench to bolt it down. Bolted beside a chemical heater, the heater heats or cools it."
	icon_state = "chem"
	tank_volume = 1000
	use_reagent_icon = TRUE
	reagent_id = null

/obj/structure/reagent_dispensers/proc/generate_reagent_icon()
	if(!use_reagent_icon)
		return
	reagent_icon = mutable_appearance(icon, "tankfilling1") // the fill gauge states are in the tank's own sheet
	update_icon()

/obj/structure/reagent_dispensers/attackby(obj/item/W, mob/user, params)
	..()
	update_icon()

/obj/structure/reagent_dispensers/chemical/screwdriver_act(mob/living/user, obj/item/I)
	if(reagents.flags & DRAINABLE)
		ENABLE_BITFIELD(reagents.flags, OPENCONTAINER)
		DISABLE_BITFIELD(reagents.flags, DRAINABLE)
		to_chat(user, "<span class='notice'>You unfasten the tank's cap.</span>")
	else if(reagents.flags & OPENCONTAINER)
		DISABLE_BITFIELD(reagents.flags, OPENCONTAINER)
		ENABLE_BITFIELD(reagents.flags, DRAINABLE)
		to_chat(user, "<span class='notice'>You fasten the tank's cap.</span>")
	update_icon()
	playsound(src.loc, 'sound/machines/click.ogg', 20, 1)
	return TRUE

/obj/structure/reagent_dispensers/chemical/wrench_act(mob/living/user, obj/item/I)
	default_unfasten_wrench(user, I)
	return TRUE

/obj/structure/reagent_dispensers/chemical/attackby(obj/item/W, mob/user, params)
	var/hotness = W.is_hot()
	if(hotness && reagents)
		if(reagents.total_volume && reagents.chem_temp < hotness) //can't be heated to be hotter than the source
			reagents.expose_temperature(hotness) // by how much is in it: a full tank takes a while (reagent_heat.dm)
			to_chat(user, "<span class='notice'>You heat [src] with [W].</span>")
		else
			to_chat(user, "<span class='warning'>[W] cannot heat anything inside [src]!</span>")
		return FALSE
	..()

/obj/structure/reagent_dispensers/chemical/examine(mob/user)
	. = ..()
	if(reagents.flags & DRAINABLE)
		. += "Its lid is closed."
	else if(reagents.flags & OPENCONTAINER)
		. += "Its lid is open."
	if(anchored)
		. += "It's bolted to the floor."

/obj/structure/reagent_dispensers/chemical/update_icon()
	..()
	if(reagents?.flags & DRAINABLE)
		add_overlay("chemlid")

/obj/structure/reagent_dispensers/watertank
	use_reagent_icon = TRUE

/obj/structure/reagent_dispensers/watertank/high
	use_reagent_icon = FALSE

/obj/structure/reagent_dispensers/fueltank
	use_reagent_icon = TRUE

/// A fuel tank goes off by the fuel left in it: full as it always did (1 heavy, 5 light, 5 flame), half full 4 and 4, a tenth 2 and 2;
/// under FUEL_TANK_BLAST_MIN it only ruptures. It went off full size empty.
/obj/structure/reagent_dispensers/fueltank/boom()
	if(QDELETED(src))
		return
	var/fuel = reagents ? reagents.get_reagent_amount(/datum/reagent/fuel) : 0
	if(fuel < FUEL_TANK_BLAST_MIN)
		visible_message("<span class='danger'>\The [src] ruptures!</span>")
		chem_splash(loc, 5, list(reagents))
		qdel(src)
		return
	var/size = (fuel / tank_volume) ** (1/3)
	explosion(get_turf(src), 0, fuel >= tank_volume / 2 ? 1 : 0, round(5 * size, 1), flame_range = round(5 * size, 1))
	qdel(src)

/obj/structure/reagent_dispensers/water_cooler/honk
	name = "honk-cooler"
	desc = "A machine that dispenses the clown's thick juice. HONK!"
	icon_state = "honk_cooler"
	reagent_id = /datum/reagent/consumable/banana

/obj/structure/reagent_dispensers/cooking_oil
	icon = 'icons/obj/objects.dmi'
