// Worn gear: maintenance finds that work, mostly. Each is an ordinary item with a flaw a careful player learns to live
// with or replace - a slow tool, a leaky tank, a cell that won't hold a full charge. Tinted a little rusty, and examine
// says what's wrong with it. They're in the maintenance loot tables (hippiestation/code/_globalvars/lists/maintenance_loot.dm).

#define WORN_GEAR_TINT "#c9b79c"

// Rusty and bent hand tools: they do the job, slower
/obj/item/wrench/rusty
	name = "rusty wrench"
	desc = "A wrench that's spent too long in a damp maintenance tunnel. The jaw sticks."
	color = WORN_GEAR_TINT
	toolspeed = 1.5

/obj/item/crowbar/rusty
	name = "rusty crowbar"
	desc = "It's pitted with rust, but a crowbar's a crowbar."
	color = WORN_GEAR_TINT
	toolspeed = 1.5

/obj/item/screwdriver/bent
	name = "bent screwdriver"
	desc = "The shaft's bent a few degrees. Screws take some coaxing."
	color = WORN_GEAR_TINT
	toolspeed = 1.5

/obj/item/wirecutters/dull
	name = "dull wirecutters"
	desc = "Blunt jaws that chew through a wire rather than cut it."
	color = WORN_GEAR_TINT
	toolspeed = 1.5

/obj/item/wrench/rusty/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It's slow going with this one.</span>"

/obj/item/crowbar/rusty/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It's slow going with this one.</span>"

/obj/item/screwdriver/bent/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It's slow going with this one.</span>"

/obj/item/wirecutters/dull/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It's slow going with this one.</span>"

// Cracked multitool: now and then the probe slips onto the wrong wire (see the "pulse" action in /datum/wires/ui_act())
/obj/item/multitool/cracked
	name = "cracked multitool"
	desc = "A multitool with a cracked casing and a loose probe tip."
	color = WORN_GEAR_TINT
	/// Chance a pulse lands on a random wire instead of the one picked
	var/slip_chance = 25

/obj/item/multitool/cracked/examine(mob/user)
	. = ..()
	. += "<span class='warning'>The probe tip wobbles. It won't always pulse the wire you aim for.</span>"

// Rusty welding tool: a smaller tank, and it doesn't always light
/obj/item/weldingtool/rusty
	name = "rusty welding tool"
	desc = "An old welding tool with a corroded igniter and a dented fuel tank."
	color = WORN_GEAR_TINT
	max_fuel = 10
	/// Chance it sputters out instead of lighting
	var/sputter_chance = 30

/obj/item/weldingtool/rusty/switched_on(mob/user)
	if(!welding && status && get_fuel() >= 1 && prob(sputter_chance))
		to_chat(user, "<span class='warning'>[src] sputters and dies. Try again.</span>")
		playsound(src, 'sound/machines/click.ogg', 30, TRUE)
		return
	return ..()

/obj/item/weldingtool/rusty/examine(mob/user)
	. = ..()
	. += "<span class='warning'>The igniter's corroded - it takes a few tries to light.</span>"

// Worn power cell: it won't hold its full charge any more, and it's never found full
/obj/item/stock_parts/cell/worn
	name = "worn power cell"
	color = WORN_GEAR_TINT

/obj/item/stock_parts/cell/worn/Initialize(mapload, override_maxcharge)
	. = ..(mapload, override_maxcharge || round(initial(maxcharge) * rand(50, 85) / 100))
	charge = round(maxcharge * rand(10, 60) / 100)
	update_icon()

/obj/item/stock_parts/cell/worn/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It's been charged and drained a lot of times. It won't hold what it used to.</span>"

// Scuffed emergency oxygen tank: half full, with a slow leak
/obj/item/tank/internals/emergency_oxygen/scuffed
	name = "scuffed emergency oxygen tank"
	desc = "A small oxygen tank covered in scratches. The valve hisses faintly."
	color = WORN_GEAR_TINT

/obj/item/tank/internals/emergency_oxygen/scuffed/populate_gas()
	air_contents.assert_gas(/datum/gas/oxygen)
	air_contents.moles[/datum/gas/oxygen] = (rand(3, 6) * ONE_ATMOSPHERE) * volume / (R_IDEAL_GAS_EQUATION * T20C)

/obj/item/tank/internals/emergency_oxygen/scuffed/process()
	. = ..()
	if(QDELETED(src) || air_contents.total_moles() < 0.01)
		return
	var/turf/T = get_turf(src)
	if(!T)
		return
	T.assume_air(air_contents.remove_ratio(0.005)) // a steady hiss: about half gone in five minutes
	T.air_update_turf(FALSE, FALSE)
	if(prob(3))
		playsound(src, 'sound/effects/spray.ogg', 5, TRUE, -4)

/obj/item/tank/internals/emergency_oxygen/scuffed/examine(mob/user)
	. = ..()
	. += "<span class='warning'>The valve seal is worn - it's slowly leaking.</span>"

// Flickering flashlight: a loose contact cuts it out for a moment now and then
/obj/item/flashlight/flickering
	name = "flickering flashlight"
	desc = "A hand-held emergency light with a loose battery contact."
	color = WORN_GEAR_TINT

/obj/item/flashlight/flickering/attack_self(mob/user)
	. = ..()
	if(on)
		START_PROCESSING(SSobj, src)

/obj/item/flashlight/flickering/process()
	if(!on)
		return PROCESS_KILL
	if(prob(8))
		set_light(0)
		icon_state = initial(icon_state)
		addtimer(CALLBACK(src, PROC_REF(end_flicker)), rand(3, 15))

/obj/item/flashlight/flickering/proc/end_flicker()
	if(on)
		update_brightness()

/obj/item/flashlight/flickering/Destroy()
	STOP_PROCESSING(SSobj, src)
	return ..()

/obj/item/flashlight/flickering/examine(mob/user)
	. = ..()
	. += "<span class='notice'>The battery rattles. It cuts out now and then.</span>"

// Expired pills: labelled as a real medicine, but who knows what's left in them
/obj/item/reagent_containers/pill/expired
	name = "expired pill"
	desc = "A pill found loose in maintenance. The label's faded, but the expiry date is long gone."
	rename_with_volume = FALSE

/obj/item/reagent_containers/pill/expired/Initialize()
	. = ..()
	var/static/list/medicines = list(
		/datum/reagent/medicine/bicaridine = "Bicaridine",
		/datum/reagent/medicine/kelotane = "Kelotane",
		/datum/reagent/medicine/antitoxin = "Anti-Toxin",
		/datum/reagent/medicine/tricordrazine = "Tricordrazine",
		/datum/reagent/medicine/charcoal = "Charcoal")
	var/medicine = pick(medicines)
	name = "expired [medicines[medicine]] pill"
	switch(rand(1, 10))
		if(1 to 5) // it's lost whatever it had
			reagents.add_reagent(/datum/reagent/consumable/sugar, 5)
		if(6 to 8) // still works, a little
			reagents.add_reagent(medicine, 5)
		else // gone off
			reagents.add_reagent(/datum/reagent/toxin, 5)

// Dented toolbox: a few tools rattling around loose, some of them worse for wear
/obj/item/storage/toolbox/mechanical/dented
	name = "dented toolbox"
	desc = "A toolbox that's been kicked around maintenance for a while. Something rattles inside."
	color = WORN_GEAR_TINT

/obj/item/storage/toolbox/mechanical/dented/PopulateContents()
	var/list/tools = list(
		/obj/item/screwdriver, /obj/item/screwdriver/bent,
		/obj/item/wrench, /obj/item/wrench/rusty,
		/obj/item/crowbar, /obj/item/crowbar/rusty,
		/obj/item/wirecutters, /obj/item/wirecutters/dull,
		/obj/item/weldingtool/rusty, /obj/item/analyzer, /obj/item/multitool/cracked)
	for(var/i in 1 to rand(2, 4))
		var/path = pick_n_take(tools)
		new path(src)

#undef WORN_GEAR_TINT
