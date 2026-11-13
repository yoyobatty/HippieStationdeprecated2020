/turf/open/floor/mineral/reagent
	name = "reagent floor"
	icon_state = "titanium_white"
	floor_tile = /obj/item/stack/tile/mineral/reagent
	icons = list("titanium_white","titanium_dam1")
	var/datum/reagent/reagent_type
	var/obj/effect/particle_effect/fakeholder

/turf/open/floor/mineral/reagent/temperature_expose(datum/gas_mixture/air, exposed_temperature, exposed_volume)
	if(exposed_temperature && !fakeholder)
		fakeholder = new(get_turf(src))
		fakeholder.create_reagents(50)
		fakeholder.reagents.add_reagent(reagent_type.type, 50, reagtemp = exposed_temperature)
		fakeholder.reagents.handle_reactions()
		QDEL_IN(fakeholder, 150)

	else if(exposed_temperature && fakeholder && !QDELETED(fakeholder))
		fakeholder.reagents.chem_temp = exposed_temperature
		fakeholder.reagents.handle_reactions()

	if(exposed_temperature > 3000)
		for(var/mob/M in viewers(3, src))
			to_chat(M, ("<span class='warning'>[icon2html(src, viewers(src))] The [src] boils away in the extreme heat!</span>"))
		vapourise()
	..()

/turf/open/floor/mineral/reagent/proc/vapourise()
	if(reagent_type && !QDELETED(src))
		release_reagent_vapour(get_turf(src), reagent_type.type, 20000, TRUE, "[src] of [reagent_type] was vaporized in [AREACOORD(src)]")
		ScrapeAway(flags = CHANGETURF_INHERIT_AIR)


// A reaction can move what it touches: bluespace dust teleports you, onto the next tile of the same floor, and that was the server gone.
// So one at a time, station wide, whatever a reaction sets off in the meantime goes without.
/turf/open/floor/mineral/reagent/proc/reagent_act(atom/A)
	var/static/reacting = FALSE
	if(reacting)
		return
	reacting = TRUE
	try
		apply_reagent(A)
	catch(var/exception/e)
		reacting = FALSE
		throw e
	reacting = FALSE

/turf/open/floor/mineral/reagent/proc/apply_reagent(atom/A)
	if(reagent_type)
		reagent_type.reaction_turf(src, TOUCH, 3)
		if(prob(90))
			if(isliving(A))
				reagent_type.reaction_mob(A, TOUCH, 3)
			else if(isturf(A))
				reagent_type.reaction_turf(A, TOUCH, 3)
			else if(isobj(A))
				reagent_type.reaction_obj(A, TOUCH, 3)
		else if(reagent_type)
			for(var/atom/AM in view(1, src))
				if(isliving(AM))
					reagent_type.reaction_mob(AM, TOUCH, 3)
				else if(isturf(AM))
					reagent_type.reaction_turf(AM, TOUCH, 3)
				else if(isobj(AM))
					reagent_type.reaction_obj(AM, TOUCH, 3)


/turf/open/floor/mineral/reagent/attack_hand(mob/user)
	reagent_act(user)
	..()

/turf/open/floor/mineral/reagent/attack_paw(mob/user)
	reagent_act(user)
	..()

/turf/open/floor/mineral/reagent/Entered(atom/AM)
	.=..()
	if(!. && !iseffect(AM)) //sparks from the last reaction aren't to set off the next
		reagent_act(AM)

/turf/open/floor/mineral/reagent/attackby(obj/item/I, mob/user, params)
	var/hotness = I.is_hot()
	if(hotness)
		temperature_expose(exposed_temperature = hotness)
		to_chat(user, "<span class='warning'>You heat [src] with [I]!</span>")
		message_admins("[src] of [reagent_type] was heated by [ADMIN_LOOKUPFLW(user)] with [I] in [ADMIN_VERBOSEJMP(src)]")
		log_game("[src] of [reagent_type] was heated by [ADMIN_LOOKUPFLW(user)] with [I] in [AREACOORD(src)]")
	..()

/turf/open/floor/mineral/reagent/ex_act()
	if(fakeholder && fakeholder.reagents && !QDELETED(fakeholder))
		for(var/datum/reagent/R in fakeholder.reagents.reagent_list)
			R.on_ex_act()
	else
		fakeholder = new(get_turf(src))
		fakeholder.create_reagents(30)
		fakeholder.reagents.add_reagent(reagent_type.type, 50)
		for(var/datum/reagent/R in fakeholder.reagents.reagent_list)
			R.on_ex_act()
		fakeholder.reagents.handle_reactions()
		QDEL_IN(fakeholder, 150)
	..()

/turf/open/floor/mineral/reagent/remove_tile(mob/user, silent = FALSE, make_tile = TRUE)
	if(broken || burnt)
		broken = FALSE
		burnt = FALSE
		if(user && !silent)
			to_chat(user, "<span class='notice'>You remove the broken plating.</span>")
	else
		if(user && !silent)
			to_chat(user, "<span class='notice'>You remove the floor tile.</span>")
		if(floor_tile && make_tile)
			var/obj/item/stack/tile/mineral/reagent/F = new floor_tile(src)
			// hippie -- the same reagent as reagent_type, made directly: this made every reagent type in turn (up to ~1000) until one matched
			var/datum/reagent/RR = new reagent_type.type
			F.reagent_type = RR
			F.name ="[reagent_type] floor tiles"
			F.singular_name = "[reagent_type] floor tile"
			F.desc = "floor tiles made of [reagent_type]"
			F.add_atom_colour(reagent_type.color, FIXED_COLOUR_PRIORITY)
	return make_plating()

/turf/open/floor/mineral/reagent/Destroy()
	if(fakeholder)
		QDEL_NULL(fakeholder)
	return ..()
