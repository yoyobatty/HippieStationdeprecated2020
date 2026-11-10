// Prototype machines and machine readouts (2026-11-10). First guesses at numbers throughout: see the notes on each.

// ---------------------------------------------------------------------------------------------
// Blood synthesiser
// ---------------------------------------------------------------------------------------------

/// Grows universal-donor blood into the pack hung on it, out of nothing but power. One unit a machine tick with the part it's
/// built with (a 200 unit pack in about seven minutes), and as many units as the manipulator's tier. It only takes a pack that's
/// empty or already holds synthetic blood, since blood of two types in a pack reads as the first.
/obj/machinery/blood_synth
	name = "blood synthesiser"
	desc = "Grows universal-donor blood into the pack hung on it. Slow, and thirsty for power."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "mixer0b"
	color = "#ffb8b8"
	density = TRUE
	anchored = TRUE
	use_power = IDLE_POWER_USE
	idle_power_usage = 40
	active_power_usage = 1500
	circuit = /obj/item/circuitboard/machine/blood_synth
	/// The pack being filled
	var/obj/item/reagent_containers/blood/pack
	/// Units of blood a machine tick
	var/rate = 1
	/// Said the pack's full, so it says it once
	var/said_full = FALSE

/obj/machinery/blood_synth/Destroy()
	QDEL_NULL(pack)
	return ..()

/obj/machinery/blood_synth/handle_atom_del(atom/A)
	. = ..()
	if(A == pack)
		pack = null
		update_icon()

/obj/machinery/blood_synth/on_deconstruction()
	drop_pack()
	return ..()

/obj/machinery/blood_synth/RefreshParts()
	rate = 0
	for(var/obj/item/stock_parts/manipulator/M in component_parts)
		rate += M.rating
	rate = max(rate, 1)

/obj/machinery/blood_synth/update_icon()
	icon_state = pack ? "mixer1b" : "mixer0b"

/obj/machinery/blood_synth/examine(mob/user)
	. = ..()
	if(pack)
		. += "<span class='notice'>\A [pack] hangs on it, [round(pack.reagents.total_volume / pack.reagents.maximum_volume * 100)]% full.</span>"
	else
		. += "<span class='notice'>There's no blood pack on it.</span>"
	if(in_range(user, src) || isobserver(user))
		. += "<span class='notice'>The status display reads: Growing <b>[rate]</b> unit\s of blood per cycle.</span>"

/// Whether a pack can go on: an empty one, or one with nothing in it but synthetic blood.
/obj/machinery/blood_synth/proc/takes_pack(obj/item/reagent_containers/blood/P)
	if(!P.reagents.total_volume)
		return TRUE
	if(length(P.reagents.reagent_list) != 1)
		return FALSE
	var/datum/reagent/blood/B = P.reagents.reagent_list[1]
	return istype(B) && B.data && B.data["blood_type"] == "U"

/obj/machinery/blood_synth/attackby(obj/item/I, mob/user, params)
	if(istype(I, /obj/item/reagent_containers/blood) && !panel_open)
		if(pack)
			to_chat(user, "<span class='warning'>There's a pack on [src] already.</span>")
			return
		if(!takes_pack(I))
			to_chat(user, "<span class='warning'>[src] wants an empty pack, or one of its own blood.</span>")
			return
		if(!user.transferItemToLoc(I, src))
			return
		pack = I
		said_full = FALSE
		to_chat(user, "<span class='notice'>You hang [I] on [src].</span>")
		update_icon()
		return
	if(!pack && default_deconstruction_screwdriver(user, "mixer0b", "mixer0b", I))
		return
	if(default_deconstruction_crowbar(I))
		return
	return ..()

/obj/machinery/blood_synth/attack_hand(mob/user)
	. = ..()
	if(.)
		return
	if(!pack)
		to_chat(user, "<span class='notice'>There's no blood pack on [src].</span>")
		return
	var/obj/item/reagent_containers/blood/taken = pack
	drop_pack()
	user.put_in_hands(taken)
	to_chat(user, "<span class='notice'>You take [taken] off [src].</span>")

/obj/machinery/blood_synth/proc/drop_pack()
	if(!pack)
		return
	pack.forceMove(drop_location())
	pack = null
	use_power = IDLE_POWER_USE
	update_icon()

/obj/machinery/blood_synth/process()
	if(!pack || panel_open || (stat & (NOPOWER|BROKEN)))
		use_power = IDLE_POWER_USE
		return
	var/room = pack.reagents.maximum_volume - pack.reagents.total_volume
	if(room <= 0)
		use_power = IDLE_POWER_USE
		if(!said_full)
			said_full = TRUE
			playsound(src, 'sound/machines/ping.ogg', 30, TRUE)
			visible_message("<span class='notice'>[src] pings: the pack's full.</span>")
		return
	use_power = ACTIVE_POWER_USE
	pack.reagents.add_reagent(/datum/reagent/blood, min(rate, room), list("donor"=null,"viruses"=null,"blood_DNA"=null,"blood_type"="U","resistances"=null,"trace_chem"=null))

/obj/item/circuitboard/machine/blood_synth
	name = "Blood Synthesiser (Machine Board)"
	build_path = /obj/machinery/blood_synth
	req_components = list(
		/obj/item/stock_parts/manipulator = 1,
		/obj/item/stock_parts/matter_bin = 1,
		/obj/item/stack/sheet/glass = 1)

/datum/design/board/blood_synth
	name = "Machine Design (Blood Synthesiser Board)"
	desc = "The circuit board for a blood synthesiser."
	id = "blood_synth"
	build_path = /obj/item/circuitboard/machine/blood_synth
	category = list ("Medical Machinery")
	departmental_flags = DEPARTMENTAL_FLAG_MEDICAL

/datum/techweb_node/adv_biotech/New()
	. = ..()
	design_ids += "blood_synth"

// ---------------------------------------------------------------------------------------------
// What looking at a machine tells you
// ---------------------------------------------------------------------------------------------

/// A drip says how the one on it is for blood, which is what it's there for.
/obj/machinery/iv_drip/examine(mob/user)
	. = ..()
	if(get_dist(user, src) > 2)
		return
	var/mob/living/carbon/human/H = attached
	if(!istype(H) || (NOBLOOD in H.dna?.species?.species_traits))
		return
	var/blood = round(H.blood_volume / BLOOD_VOLUME_NORMAL * 100)
	if(blood < 85)
		. += "<span class='warning'>[H] looks pale: about [blood]% of their blood.</span>"
	else
		. += "<span class='notice'>[H] has their colour: about [min(blood, 100)]% of their blood.</span>"

/// A field generator says whether it's fastened, whether it's on, and how much it has in it.
/obj/machinery/field/generator/examine(mob/user)
	. = ..()
	switch(state)
		if(0)
			. += "<span class='notice'>It's loose on the floor.</span>"
		if(1)
			. += "<span class='notice'>It's bolted to the floor.</span>"
		if(2)
			. += "<span class='notice'>It's bolted and welded to the floor.</span>"
	var/held = round(power / field_generator_max_power * 100)
	switch(active)
		if(0)
			. += "<span class='notice'>It's off, with [held]% of its power in it.</span>"
		if(1)
			. += "<span class='notice'>It's warming up.</span>"
		if(2)
			. += "<span class='notice'>It's on, holding [length(fields)] tile\s of field, with [held]% of its power in it.</span>"
			if(held < 20)
				. += "<span class='warning'>It's close to going out.</span>"

/// An emitter says whether it's fastened, firing and locked.
/obj/machinery/power/emitter/examine(mob/user)
	. = ..()
	switch(state)
		if(0)
			. += "<span class='notice'>It's loose on the floor.</span>"
		if(1)
			. += "<span class='notice'>It's bolted to the floor.</span>"
		if(2)
			. += "<span class='notice'>It's bolted and welded to the floor.</span>"
	if(!active)
		. += "<span class='notice'>It's off.</span>"
	else if(powered)
		. += "<span class='notice'>It's on and firing.</span>"
	else
		. += "<span class='warning'>It's on, with no power to fire.</span>"
	if(locked)
		. += "<span class='notice'>Its controls are locked.</span>"

/// A power storage unit's meter can be read off its front.
/obj/machinery/power/smes/examine(user)
	. = ..()
	if(!in_range(user, src) && !isobserver(user))
		return
	. += "<span class='notice'>The meter reads <b>[round(charge / max(capacity, 1) * 100)]%</b>. It's [inputting ? "taking power in" : (input_attempt ? "set to charge, with nothing coming in" : "not charging")], and [outputting ? "giving power out" : (output_attempt ? "set to give power out, with none to give" : "not giving power out")].</span>"

/// Any part of the gravity generator says how far charged it is.
/obj/machinery/gravity_generator/examine(mob/user)
	. = ..()
	var/obj/machinery/gravity_generator/main/the_main = src
	if(!istype(the_main))
		var/obj/machinery/gravity_generator/part/a_part = src
		the_main = istype(a_part) ? a_part.main_part : null
	if(!the_main)
		return
	if(the_main.stat & BROKEN)
		. += "<span class='warning'>It's broken.</span>"
		return
	. += "<span class='notice'>It's [the_main.on ? "on" : "off"], charged to [the_main.charge_count]%.</span>"
