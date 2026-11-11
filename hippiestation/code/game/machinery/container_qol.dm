// Containers in machines, the same everywhere (overnight 2026-11-10, the user's "would a player find this awkward?" pass). The chem
// dispenser, ChemMaster and heater already take a new beaker in place of the one inside (it goes to your hand) and give it back on
// Alt-click. The cryo cell, biogenerator and grinder made you open the window and press Eject first, and the cryo cell and
// biogenerator just said one was already loaded.

/// Into the hand that's free, or onto the floor in front of the machine.
/obj/machinery/proc/hand_back(obj/item/I, mob/living/user)
	I.forceMove(drop_location())
	if(user && Adjacent(user) && !issiliconoradminghost(user))
		user.put_in_hands(I)

// Cryo cell

/obj/machinery/atmospherics/components/unary/cryo_cell/attackby(obj/item/I, mob/user, params)
	if(istype(I, /obj/item/reagent_containers/glass) && beaker && user.transferItemToLoc(I, src))
		var/obj/item/old = beaker
		beaker = I
		hand_back(old, user)
		user.visible_message("<span class='notice'>[user] swaps the beaker in [src].</span>", "<span class='notice'>You swap [old] for [I].</span>")
		log_game("[key_name(user)] swapped [old] for [I] in cryo containing [pretty_string_from_reagent_list(I.reagents.reagent_list)]")
		return TRUE
	return ..()

/obj/machinery/atmospherics/components/unary/cryo_cell/AltClick(mob/living/user)
	if(!istype(user) || !user.canUseTopic(src, BE_CLOSE, FALSE, NO_TK) || !beaker || (user.ventcrawler && Adjacent(user)))
		return ..() //a ventcrawler's Alt-click is the way into the pipes
	var/obj/item/old = beaker
	beaker = null
	hand_back(old, user)
	to_chat(user, "<span class='notice'>You take [old] out of [src].</span>")
	update_icon()

// Biogenerator

/obj/machinery/biogenerator/attackby(obj/item/O, mob/user, params)
	if(istype(O, /obj/item/reagent_containers/glass) && beaker && !panel_open && user.a_intent != INTENT_HARM && user.transferItemToLoc(O, src))
		var/obj/item/old = beaker
		beaker = O
		hand_back(old, user)
		to_chat(user, "<span class='notice'>You swap [old] for [O].</span>")
		update_icon()
		return TRUE
	return ..()

/obj/machinery/biogenerator/AltClick(mob/living/user)
	if(!istype(user) || !user.canUseTopic(src, BE_CLOSE, FALSE, NO_TK) || !beaker || processing)
		return ..()
	var/obj/item/old = beaker
	beaker = null
	hand_back(old, user)
	to_chat(user, "<span class='notice'>You take [old] out of [src].</span>")
	update_icon()

// All-In-One Grinder: it swaps already (replace_beaker()); Alt-click gives the beaker back.

/obj/machinery/reagentgrinder/AltClick(mob/living/user)
	if(!istype(user) || !user.canUseTopic(src, BE_CLOSE, FALSE, NO_TK) || !beaker || operating)
		return ..()
	replace_beaker(user)
	to_chat(user, "<span class='notice'>You take the beaker out of [src].</span>")
