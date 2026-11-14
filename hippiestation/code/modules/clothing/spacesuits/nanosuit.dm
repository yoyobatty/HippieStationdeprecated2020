#define NANO_ARMOR "armor"
#define NANO_CLOAK "cloak"
#define NANO_SPEED "speed"
#define NANO_STRENGTH "strength"
#define NANO_NONE "none"
#define NANO_JUMP_USE 30
#define NANO_CHARGE_DELAY 15
#define NANO_EMP_CHARGE_DELAY 45

#define POWER_PUNCH "QQQ"
#define FINISH_HIM "SSS"
#define HEAD_EXPLOSION "SSSS"
#define MARTIALART_NANOSUIT "nanosuit strength"

//Crytek Nanosuit made by YoYoBatty
/obj/item/clothing/under/syndicate/combat/nano
	name = "nanosuit lining"
	desc = "Foreign body resistant lining built below the nanosuit. Provides internal protection. Property of CryNet Systems."
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF
	item_flags = DROPDEL

/obj/item/clothing/under/syndicate/combat/nano/equipped(mob/user, slot)
	..()
	if(slot == ITEM_SLOT_ICLOTHING)
		ADD_TRAIT(src, TRAIT_NODROP, CLOTHING_TRAIT)

/obj/item/clothing/mask/gas/nano_mask
	name = "nanosuit gas mask"
	desc = "Operator mask. Property of CryNet Systems." //More accurate
	icon_state = "syndicate"
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF
	item_flags = DROPDEL

/obj/item/clothing/mask/gas/nano_mask/equipped(mob/user, slot)
	..()
	if(slot == ITEM_SLOT_MASK)
		ADD_TRAIT(src, TRAIT_NODROP, CLOTHING_TRAIT)

/datum/action/item_action/nanojump
	name = "Activate Strength Jump"
	desc = "Activates the Nanosuit's super jumping ability to allows the user to cross 2 wide gaps."
	icon_icon = 'icons/mob/actions/actions_items.dmi'
	button_icon_state = "jetboot"

/obj/item/clothing/shoes/combat/coldres/nanojump
	name = "nanosuit boots"
	desc = "Boots part of a nanosuit. Slip resistant. Property of CryNet Systems."
	clothing_flags = NOSLIP
	gas_transfer_coefficient = 0.01
	permeability_coefficient = 0.01
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF
	var/jumpdistance = 3 //-1 from to see the actual distance, e.g 3 goes over 2 tiles
	var/jumpspeed = 1
	actions_types = list(/datum/action/item_action/nanojump)
	item_flags = DROPDEL

/obj/item/clothing/shoes/combat/coldres/nanojump/ui_action_click(mob/user, action)
	if(!isliving(user))
		return
	var/turf/open/floor/T = get_turf(src)
	var/obj/structure/S = locate() in get_turf(user.loc)
	var/mob/living/carbon/human/H = user
	var/distance = jumpdistance
	if(istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
		var/obj/item/clothing/suit/space/hardsuit/nano/NS = H.wear_suit
		distance *= NS.upgrademulti
		if(NS.mode == NANO_STRENGTH)
			if(istype(T) || istype(S))
				if(NS.cell.charge >= NANO_JUMP_USE)
					NS.cut_nano_energy(NANO_JUMP_USE, NANO_CHARGE_DELAY)
				else
					to_chat(user, "<span class='warning'>Not enough charge.</span>")
					return
			else
				to_chat(user, "<span class='warning'>You must be on a proper floor or stable structure.</span>")
				return
		else
			to_chat(user, "<span class='warning'>Only available in strength mode.</span>")
			return
	else
		to_chat(user, "<span class='warning'>You must be wearing a nanosuit.</span>")
		return

	var/atom/target = get_edge_target_turf(user, user.dir) //gets the user's direction
	if(user.throw_at(target, distance, jumpspeed, spin = FALSE, diagonals_first = TRUE))
		playsound(src, 'sound/effects/stealthoff.ogg', 50, TRUE)
		user.visible_message("<span class='warning'>[user] jumps forward into the air!</span>")
	else
		to_chat(user, "<span class='warning'>Something prevents you from dashing forward!</span>")


/obj/item/clothing/shoes/combat/coldres/nanojump/equipped(mob/user, slot)
	..()
	if(slot == ITEM_SLOT_FEET)
		ADD_TRAIT(src, TRAIT_NODROP, CLOTHING_TRAIT)

/obj/item/clothing/gloves/combat/nano
	name = "nano gloves"
	desc = "These tactical gloves are built into a nanosuit and are fireproof and shock resistant. Property of CryNet Systems."
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF
	gas_transfer_coefficient = 0.01
	permeability_coefficient = 0.01
	item_flags = DROPDEL

/obj/item/clothing/gloves/combat/nano/equipped(mob/user, slot)
	..()
	if(slot == ITEM_SLOT_GLOVES)
		ADD_TRAIT(src, TRAIT_NODROP, CLOTHING_TRAIT)

/obj/item/radio/headset/syndicate/alt/nano
	name = "\proper the nanosuit's bowman headset"
	desc = "Operator communication headset. Property of CryNet Systems. Alt-click to toggle interface."
	icon_state = "syndie_headset"
	item_state = "syndie_headset"
	subspace_transmission = FALSE
	subspace_switchable = TRUE
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF
	item_flags = DROPDEL

/obj/item/radio/headset/syndicate/alt/nano/equipped(mob/user, slot)
	..()
	if(slot == ITEM_SLOT_EARS)
		ADD_TRAIT(src, TRAIT_NODROP, CLOTHING_TRAIT)

/obj/item/radio/headset/syndicate/alt/nano/AltClick()
	var/mob/M = usr
	if(usr.canUseTopic(src))
		attack_self(M)
	..()

/obj/item/radio/headset/syndicate/alt/nano/MouseDrop(obj/over_object, src_location, over_location)
	var/mob/M = usr
	if((!istype(over_object, /obj/screen)) && usr.canUseTopic(src))
		return attack_self(M)
	return ..()

/obj/item/radio/headset/syndicate/alt/nano/emp_act()
	return

/obj/item/clothing/glasses/nano_goggles
	name = "nanosuit goggles"
	desc = "Goggles built for a nanosuit. Property of CryNet Systems."
	alternate_worn_icon = 'hippiestation/icons/mob/nanosuit.dmi'
	icon = 'hippiestation/icons/obj/nanosuit.dmi'
	icon_state = "nvgmesonnano"
	item_state = "nvgmesonnano"
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF
	glass_colour_type = /datum/client_colour/glass_colour/nightvision
	actions_types = list(/datum/action/item_action/nanosuit/goggletoggle)
	vision_correction = TRUE //We must let our wearer have good eyesight
	var/on = FALSE
	item_flags = DROPDEL

/datum/client_colour/glass_colour/nightvision
	colour = "#45723f"

/obj/item/clothing/glasses/nano_goggles/equipped(mob/user, slot)
	..()
	if(slot == ITEM_SLOT_EYES)
		ADD_TRAIT(src, TRAIT_NODROP, CLOTHING_TRAIT)

/obj/item/clothing/glasses/nano_goggles/ui_action_click(mob/user, action)
	if(istype(action, /datum/action/item_action/nanosuit/goggletoggle))
		nvgmode(user)
		return TRUE
	return FALSE


/obj/item/clothing/glasses/nano_goggles/proc/nvgmode(mob/user, var/forced = FALSE)
	var/mob/living/carbon/human/H = user
	if(H.glasses != src)
		return
	if(!ishuman(user))
		return
	on = !on
	to_chat(user, "<span class='[forced ? "warning":"notice"]'>[forced ? "The goggles turn":"You turn the goggles"] [on ? "on":"off"][forced ? "!":"."]</span>")
	if(on)
		darkness_view = 8
		lighting_alpha = LIGHTING_PLANE_ALPHA_MOSTLY_INVISIBLE
	else
		darkness_view = 2
		lighting_alpha = null
	H.update_sight()
	for(var/X in actions)
		var/datum/action/A = X
		A.UpdateButtonIcon()

/obj/item/clothing/glasses/nano_goggles/emp_act(severity)
	..()
	if(prob(33/severity))
		nvgmode(loc,TRUE)

/obj/item/clothing/suit/space/hardsuit/nano
	alternate_worn_icon = 'hippiestation/icons/mob/nanosuit.dmi'
	icon = 'hippiestation/icons/obj/nanosuit.dmi'
	icon_state = "nanosuit"
	item_state = "nanosuit"
	name = "nanosuit"
	desc = "Some sort of alien future suit. It looks very robust. Property of CryNet Systems."
	armor = list("melee" = 40, "bullet" = 40, "laser" = 40, "energy" = 45, "bomb" = 70, "bio" = 100, "rad" = 70, "fire" = 100, "acid" = 100)
	allowed = list(/obj/item/tank/internals)
	heat_protection = CHEST|GROIN|LEGS|FEET|ARMS|HANDS					//Uncomment to enable firesuit protection
	max_heat_protection_temperature = FIRE_IMMUNITY_MAX_TEMP_PROTECT
	helmettype = /obj/item/clothing/head/helmet/space/hardsuit/nano
	slowdown = 0.25
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF
	actions_types = list(/datum/action/item_action/nanosuit/armor, /datum/action/item_action/nanosuit/cloak, /datum/action/item_action/nanosuit/speed, /datum/action/item_action/nanosuit/strength)
	permeability_coefficient = 0.01
	var/mob/living/carbon/human/Wearer = null
	var/criticalpower = FALSE
	var/mode = NANO_NONE
	var/datum/martial_art/nanosuit/style = new
	var/shutdown = TRUE
	var/current_charges = 3
	var/max_charges = 3 //How many charges total the shielding has
	var/temp_cooldown = 0
	var/restore_delay = 120
	var/defrosted = FALSE
	var/detecting = FALSE
	var/help_verb = /mob/living/carbon/human/proc/Nanosuit_help
	var/outfit = /datum/outfit/nanosuit
	jetpack = /obj/item/tank/jetpack/suit
	var/recharge_cooldown = 0 //if this number is greater than 0, we can't recharge
	var/med_cooldown = 0
	var/medical_delay = 3 MINUTES //how long a spent medical charge takes to come back
	var/next_medical_charge = 0
	var/cloak_use_rate = 1.2 //cloaked energy consume rate
	var/speed_use_rate = 2.0 //speed energy consume rate
	var/crit_energy = 20 //critical energy level
	var/regen_rate = 4 //rate at which we regen
	//all of these only while the suit's running: see update_toughness()
	var/stun_mult = 0.25 //how much of a stun lands
	var/armor_stun_mult = 0.1 //the same in armor mode
	var/stamina_mult = 0.5 //how much of a stamina hit lands
	var/stun_grace = 3 SECONDS //how long after a stun ends before another can land
	var/stamina_block = 2 SECONDS //the most a stamina hit can hold back stamina regen, instead of the usual 10
	var/worn_stun_mult = 1 //what's on the wearer's physiology right now
	var/worn_stamina_mult = 1
	var/next_stun = 0
	var/speed_burst_delay = 30 SECONDS //going into speed mode clears some stamina, this often
	var/next_speed_burst = 0
	var/msg_time_react = 0
	var/trauma_threshold = 30
	var/obj/item/stock_parts/cell/nano/cell //What type of power cell this uses
	block_chance = 0
	//variables for cloak pausing when shooting a suppressed gun
	var/stealth_cloak_out = 1 //transition time out of cloak
	var/stealth_cloak_in = 2 //transition time back into cloak
	rad_flags = RAD_PROTECT_CONTENTS|RAD_NO_CONTAMINATE
	rad_insulation = RAD_NO_INSULATION
	var/healthon = FALSE
	var/atmoson = FALSE
	var/radon = FALSE
	var/cellon = FALSE
	var/hacked = FALSE
	var/boot_count = 0 //how many times it's booted: a boot overtaken by a newer one stops (bootSequence())
	//var/upgraded = FALSE
	var/upgrademulti = 1.0 //Upgrade multiplier

/obj/item/clothing/suit/space/hardsuit/nano/Initialize()
	. = ..()
	cell = new(src)
	START_PROCESSING(SSfastprocess, src)

/obj/item/clothing/suit/space/hardsuit/nano/get_cell()
	return cell

/obj/item/clothing/suit/space/hardsuit/nano/Destroy()
	STOP_PROCESSING(SSfastprocess, src)
	disengage() //a wearer killed in strength mode would keep a deleted martial art on their mind otherwise
	if(style)
		QDEL_NULL(style)
	if(cell)
		QDEL_NULL(cell)
	return ..()

/obj/item/clothing/suit/space/hardsuit/nano/prevent_content_explosion()
	return TRUE

/obj/item/clothing/suit/space/hardsuit/nano/contents_explosion()
	return

/obj/item/clothing/suit/space/hardsuit/nano/examine(mob/user)
	. = ..()
	if(mode != NANO_NONE)
		. += "The suit appears to be in [mode] mode."
	else
		. += "The suit appears to be offline."
	. += "The interface seems to be [hacked ? "scrambled" : "untouched"]."

/obj/item/clothing/suit/space/hardsuit/nano/process()
	..()
	if(!Wearer)
		return
	if(cellon)
		Wearer.hud_used?.nano_energy?.show(round(cell.percent()), cell.charge < crit_energy)
	if(shutdown)
		return
	if(!cell)
		return
	if(Wearer.stam_regen_start_time > world.time + stamina_block)
		Wearer.stam_regen_start_time = world.time + stamina_block
	if(current_charges < max_charges && world.time >= next_medical_charge)
		addmedicalcharge()
		next_medical_charge = world.time + medical_delay
		helmet.display_visor_message("Medical systems recharged: [current_charges] of [max_charges].")
	if(prob(20) && Wearer.health < HEALTH_THRESHOLD_CRIT + 15 && hacked) //Automatic healing when hacked
		if(world.time > med_cooldown)
			med_cooldown = world.time + 200
			addtimer(CALLBACK(src, PROC_REF(heal_nano), Wearer), 30)

	if(Wearer.bodytemperature < BODYTEMP_COLD_DAMAGE_LIMIT)
		if(world.time > temp_cooldown)
			helmet.display_visor_message("Activating suit defrosting protocols.")
			Wearer.reagents.add_reagent(/datum/reagent/medicine/leporazine, 3)
			temp_cooldown = world.time + restore_delay

	var/energy = cell.charge //store current energy here
	if(mode == NANO_CLOAK) //are we in cloak, not moving?
		energy -= (cloak_use_rate / 10 / upgrademulti) //take away the cloak discharge rate at 1/10th since we're not moving
	if((energy < cell.maxcharge) && mode != NANO_CLOAK && !recharge_cooldown) //if our energy is less than 100, we're not in cloak and don't have a recharge delay timer
		var/energy2 = regen_rate //store our regen rate here
		energy2+=energy //add our current energy to it
		energy=min(cell.maxcharge, energy2) //our energy now equals the energy we had + 0.75 for everytime it iterates through, so it increases by 0.75 every tick until it goes to 100
	if(recharge_cooldown) //do we have a recharge delay set?
		recharge_cooldown-- //reduce it
	if(msg_time_react)
		msg_time_react--
	if(cell.charge != energy)
		cut_nano_energy(cell.charge - energy) //now set our current energy to the variable we modified

/obj/item/clothing/suit/space/hardsuit/nano/proc/cut_nano_energy(var/amount, var/delay = 0)
	if(delay > recharge_cooldown)
		recharge_cooldown = delay
	cell.charge = max(0, (cell.charge - amount))
	if(cell.charge < crit_energy && !criticalpower) //energy is less than critical energy level(20) and not in crit power
		helmet.display_visor_message("Energy Critical!") //now we are
		criticalpower = TRUE
	else if(cell.charge > crit_energy) //did our energy go higher than the crit level
		criticalpower = FALSE //turn it off
	if(!cell.charge) //did we lose energy?
		if(mode == NANO_CLOAK) //are we in cloak?
			recharge_cooldown = NANO_CHARGE_DELAY //then wait 3 seconds to recharge again
		if(mode != NANO_ARMOR && mode != NANO_NONE) //we're not in cloak
			toggle_mode(NANO_ARMOR, TRUE) //go into it, forced

/obj/item/clothing/suit/space/hardsuit/nano/proc/addmedicalcharge(amount = 1)
	if(current_charges < max_charges)
		current_charges = min(max_charges, current_charges + amount)

/obj/item/clothing/suit/space/hardsuit/nano/proc/onmove()
	if(mode == NANO_CLOAK)
		cut_nano_energy(cloak_use_rate / upgrademulti, NANO_CHARGE_DELAY)
	else if(mode == NANO_SPEED)
		cut_nano_energy(speed_use_rate / upgrademulti, NANO_CHARGE_DELAY)

/obj/item/clothing/suit/space/hardsuit/nano/hit_reaction(mob/living/carbon/human/user, atom/movable/hitby, attack_text = "the attack", final_block_chance = 0, damage = 0, attack_type = MELEE_ATTACK)
	var/obj/item/projectile/P = hitby
	if(mode == NANO_ARMOR && cell && cell.charge)
		if(prob(final_block_chance))
			user.visible_message("<span class='danger'>[user]'s shields deflect [attack_text] draining their energy!</span>")
			if(damage)
				if(attack_type == PROJECTILE_ATTACK && P.damage_type == STAMINA)
					cut_nano_energy(20/upgrademulti, NANO_CHARGE_DELAY)//stamina damage, aka disabler beams
				else
					cut_nano_energy((5 + damage)/upgrademulti, NANO_CHARGE_DELAY)//laser guns, anything lethal drains 5 + the damage dealt
			if(istype(P, /obj/item/projectile/energy/electrode))//if electrode aka taser
				cut_nano_energy(35/upgrademulti, NANO_CHARGE_DELAY)
			return TRUE
		user.visible_message("<span class='warning'>[user]'s shields fail to deflect [attack_text].</span>")
		final_block_chance = 0 //that was the roll, ..() doesn't get another one. What got through still gets the medical systems below
	if(damage && attack_type == PROJECTILE_ATTACK && P.damage_type != STAMINA && prob(50))
		var/datum/effect_system/spark_spread/s = new
		s.set_up(1, 1, src)
		s.start()
	kill_cloak()
	if(prob(damage*1.5) && user.health < HEALTH_THRESHOLD_CRIT + 50)
		heal_nano(user)
	for(var/X in Wearer.bodyparts)
		var/obj/item/bodypart/BP = X
		if(!msg_time_react)
			if(BP.body_zone == BODY_ZONE_L_LEG || BP.body_zone == BODY_ZONE_R_LEG || BP.body_zone == BODY_ZONE_L_ARM || BP.body_zone == BODY_ZONE_R_ARM)
				if(BP.brute_dam > trauma_threshold)
					helmet.display_visor_message("Extensive blunt force detected in [BP.name]!")
					msg_time_react = 200
				else if(BP.burn_dam > trauma_threshold)
					helmet.display_visor_message("Heat shield failure detected in [BP.name]!")
					msg_time_react = 200
			if(BP.body_zone == BODY_ZONE_HEAD)
				if(BP.brute_dam > trauma_threshold)
					helmet.display_visor_message("Cranial trauma detected!")
					msg_time_react = 300
				else if(BP.burn_dam > trauma_threshold)
					helmet.display_visor_message("Facial burns detected!")
					msg_time_react = 300
			if(BP.body_zone == BODY_ZONE_CHEST)
				if(BP.brute_dam > trauma_threshold)
					helmet.display_visor_message("Thoracic trauma detected!")
					msg_time_react = 300
				else if(BP.burn_dam > trauma_threshold)
					helmet.display_visor_message("Thoracic burns detected!")
					msg_time_react = 300

	if(attack_type == LEAP_ATTACK)
		final_block_chance = 75
	SEND_SIGNAL(src, COMSIG_ITEM_HIT_REACT, args)
	return ..()

/obj/item/clothing/suit/space/hardsuit/nano/proc/heal_nano(mob/living/carbon/human/user)
	if(!current_charges || QDELETED(user))
		return
	helmet.display_visor_message("Engaging emergency medical protocols.")
	user.reagents.add_reagent(/datum/reagent/medicine/syndicate_nanites, 1)
	if(current_charges == max_charges) //the clock starts with the first one spent
		next_medical_charge = world.time + medical_delay
	current_charges--

/obj/item/clothing/suit/space/hardsuit/nano/ui_action_click(mob/user, action)
	if(istype(action, /datum/action/item_action/nanosuit/armor))
		toggle_mode(NANO_ARMOR)
		return TRUE
	if(istype(action, /datum/action/item_action/nanosuit/cloak))
		toggle_mode(NANO_CLOAK)
		return TRUE
	if(istype(action, /datum/action/item_action/nanosuit/speed))
		toggle_mode(NANO_SPEED)
		return TRUE
	if(istype(action, /datum/action/item_action/nanosuit/strength))
		toggle_mode(NANO_STRENGTH)
		return TRUE
	return FALSE

/obj/item/clothing/suit/space/hardsuit/nano/proc/toggle_mode(var/suitmode, var/forced = FALSE)
	if(!Wearer)
		return
	if(!shutdown && (forced || (cell?.charge && mode != suitmode)))
		mode = suitmode
		var/datum/component/footstep/FS = Wearer.GetComponent(/datum/component/footstep) //a mob being deleted has none
		switch(suitmode)
			if(NANO_ARMOR)
				helmet.display_visor_message("Maximum Armor!")
				FS?.volume = 1.5
				block_chance = hacked ? 65 : 50 //65% block emagged, 50% normal
				slowdown = initial(slowdown)
				armor = armor.setRating(melee = 60, bullet = 60, laser = 60, energy = 45, bomb = 90, rad = 90)
				helmet.armor = helmet.armor.setRating(melee = 60, bullet = 60, laser = 60, energy = 45, bomb = 90, rad = 90)
				Wearer.filters = list()
				animate(Wearer, alpha = 255, time = 5)
				Wearer.remove_movespeed_modifier(NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_IGNORESLOWDOWN, NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_PUSHIMMUNE, NANO_STRENGTH)
				REMOVE_TRAIT(Wearer, TRAIT_TACRELOAD, NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_LIGHT_STEP, NANO_SPEED)
				style.remove(Wearer)

			if(NANO_CLOAK)
				helmet.display_visor_message("Cloak Engaged!")
				if(prob(hacked? 15: 2))
					var/datum/effect_system/spark_spread/spark = new
					spark.set_up(1, 1, src)
					spark.start()
				FS?.volume = hacked ? 0.25 : 0.75 //upgrade module
				visible_message("<span class='warning'>[Wearer] suddenly disappears!</span>", vision_distance = 3)
				block_chance = initial(block_chance)
				slowdown = 0.15 //cloaking makes us move slightly faster
				armor = armor.setRating(melee = 40, bullet = 40, laser = 40, energy = 45, bomb = 70, rad = 70)
				helmet.armor = helmet.armor.setRating(melee = 40, bullet = 40, laser = 40, energy = 45, bomb = 70, rad = 70)
				Wearer.filters = filter(type="blur",size=1)
				animate(Wearer, alpha = 40, time = 5/upgrademulti)
				Wearer.remove_movespeed_modifier(NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_IGNORESLOWDOWN, NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_PUSHIMMUNE, NANO_STRENGTH)
				REMOVE_TRAIT(Wearer, TRAIT_TACRELOAD, NANO_SPEED)
				ADD_TRAIT(Wearer, TRAIT_LIGHT_STEP, NANO_SPEED)
				style.remove(Wearer)

			if(NANO_SPEED)
				helmet.display_visor_message("Maximum Speed!")
				FS?.volume = 1.0
				block_chance = initial(block_chance)
				slowdown = initial(slowdown)
				armor = armor.setRating(melee = 25, bullet = 25, laser = 25, energy = 45, bomb = 70, rad = 70)
				helmet.armor = helmet.armor.setRating(melee = 25, bullet = 25, laser = 25, energy = 45, bomb = 70, rad = 70)
				if(world.time >= next_speed_burst) //it's free, so switching in and out mustn't be a way to farm it
					next_speed_burst = world.time + speed_burst_delay
					Wearer.adjustOxyLoss(-5, 0)
					Wearer.adjustStaminaLoss(-20)
				Wearer.filters = filter(type="outline", size=0.1, color=rgb(255,255,224))
				animate(Wearer, alpha = 255, time = 5)
				REMOVE_TRAIT(Wearer, TRAIT_PUSHIMMUNE, NANO_STRENGTH)
				ADD_TRAIT(Wearer, TRAIT_TACRELOAD, NANO_SPEED)
				Wearer.add_movespeed_modifier(NANO_SPEED, update=TRUE, priority=100, multiplicative_slowdown = hacked ? -1 : -0.25, override = TRUE, blacklisted_movetypes=(FLYING|FLOATING))
				ADD_TRAIT(Wearer, TRAIT_IGNORESLOWDOWN, NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_LIGHT_STEP, NANO_SPEED)
				style.remove(Wearer)

			if(NANO_STRENGTH)
				helmet.display_visor_message("Maximum Strength!")
				FS?.volume = 1.0
				block_chance = initial(block_chance)
				style.teach(Wearer,TRUE)
				slowdown = initial(slowdown)
				armor = armor.setRating(melee = 40, bullet = 40, laser = 40, energy = 45, bomb = 70, rad = 70)
				helmet.armor = helmet.armor.setRating(melee = 40, bullet = 40, laser = 40, energy = 45, bomb = 70, rad = 70)
				Wearer.filters = filter(type="outline", size=0.1, color=rgb(255,0,0))
				animate(Wearer, alpha = 255, time = 5)
				ADD_TRAIT(Wearer, TRAIT_PUSHIMMUNE, NANO_STRENGTH)
				Wearer.remove_movespeed_modifier(NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_IGNORESLOWDOWN, NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_TACRELOAD, NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_LIGHT_STEP, NANO_SPEED)

			if(NANO_NONE)
				block_chance = initial(block_chance)
				FS?.volume = 1.0
				style.remove(Wearer)
				slowdown = initial(slowdown)
				armor = armor.setRating(melee = 40, bullet = 40, laser = 40, energy = 45, bomb = 70, rad = 70)
				helmet.armor = helmet.armor.setRating(melee = 40, bullet = 40, laser = 40, energy = 45, bomb = 70, rad = 70)
				Wearer.filters = list()
				animate(Wearer, alpha = 255, time = 5)
				REMOVE_TRAIT(Wearer, TRAIT_PUSHIMMUNE, NANO_STRENGTH)
				Wearer.remove_movespeed_modifier(NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_IGNORESLOWDOWN, NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_TACRELOAD, NANO_SPEED)
				REMOVE_TRAIT(Wearer, TRAIT_LIGHT_STEP, NANO_SPEED)

	for(var/X in actions)
		var/datum/action/A = X
		if(istype(A, /datum/action/item_action/nanosuit))
			var/datum/action/item_action/nanosuit/N = A
			N.button.filters = (N.suit_mode == mode) ? filter(type="outline", size=2, color="#aaff00") : null //bg_tech_blue_on looks the same as bg_tech_blue
		A.UpdateButtonIcon()
	Wearer.update_inv_wear_suit()
	Wearer.update_action_buttons_icon()
	update_icon()
	update_toughness()

/// What a running suit does for its wearer against stuns. A suit that's down does nothing, and that's an EMP's whole point.
/obj/item/clothing/suit/space/hardsuit/nano/proc/update_toughness()
	var/datum/physiology/body = Wearer?.physiology
	if(!body) //gone before the suit when a mob's deleted
		return
	var/stun = shutdown ? 1 : (mode == NANO_ARMOR ? armor_stun_mult : stun_mult)
	var/stamina = shutdown ? 1 : stamina_mult
	body.stun_mod *= stun / worn_stun_mult //multiplied, as other things that change these are
	body.stamina_mod *= stamina / worn_stamina_mult
	worn_stun_mult = stun
	worn_stamina_mult = stamina
	if(shutdown)
		REMOVE_TRAIT(Wearer, TRAIT_IMPACTPROOF, "Nanosuit")
	else
		ADD_TRAIT(Wearer, TRAIT_IMPACTPROOF, "Nanosuit")

/// One stun after another is what keeps someone down for good however short they are, so each one leaves a gap before the next can land.
/obj/item/clothing/suit/space/hardsuit/nano/proc/on_stunned(datum/source, amount, updating, ignore_canstun)
	SIGNAL_HANDLER
	if(shutdown || ignore_canstun || amount <= 0)
		return
	if(world.time < next_stun)
		return COMPONENT_NO_STUN
	next_stun = world.time + amount + stun_grace

/// Everything goes off at once, full stuns included.
/obj/item/clothing/suit/space/hardsuit/nano/proc/power_down()
	toggle_mode(NANO_NONE, TRUE)
	shutdown = TRUE
	update_toughness()

/obj/item/clothing/suit/space/hardsuit/nano/ex_act(severity, target)
	. = ..()
	toggle_mode(NANO_ARMOR)

/obj/item/clothing/suit/space/hardsuit/nano/emp_act(severity)
	..()
	if(!severity || shutdown )
		return
	cut_nano_energy(cell.charge/severity, NANO_EMP_CHARGE_DELAY)
	if((mode == NANO_ARMOR && !cell.charge) || (mode != NANO_ARMOR))
		if(prob(5/severity))
			emp_assault()
		else if(prob(10/severity))
			Wearer.confused += 10
	update_icon()

/obj/item/clothing/suit/space/hardsuit/nano/proc/emp_assault()
	set waitfor = FALSE //it's called from emp_act(), and the rest of the pulse has things to do
	if(!Wearer)
		return //Not sure how this could happen.
	SSblackbox.record_feedback("tally", "nanosuit_emp_shutdown", 1, type)
	Wearer.confused += 50
	helmet.display_visor_message("EMP Assault! Systems impaired.")
	sleep(40)
	if(!Wearer)
		return
	power_down() //first, so the stun below lands in full
	Wearer.apply_effects(paralyze = 300, stun = 300, jitter = 120)
	addtimer(CALLBACK(src, PROC_REF(emp_assaulttwo)), 25)


/obj/item/clothing/suit/space/hardsuit/nano/proc/emp_assaulttwo()
	sleep(35)
	if(!Wearer)
		return
	helmet.display_visor_message("Warning, EMP shutdown, all systems impaired!")
	sleep(25)
	helmet.display_visor_message("Switching to: core function mode.")
	sleep(25)
	helmet.display_visor_message("Life support priority. Warning!")
	addtimer(CALLBACK(src, PROC_REF(emp_assaultthree)), 35)


/obj/item/clothing/suit/space/hardsuit/nano/proc/emp_assaultthree()
	if(!Wearer)
		return
	helmet.display_visor_message("CMOS reset sequence begin, standby...")
	sleep(20)
	playsound(src, 'sound/machines/beep.ogg', 50, FALSE)
	helmet.display_visor_message("4672482//-82544111.0//WRXT _YWD")
	sleep(5)
	helmet.display_visor_message("KPO- -86801780.768//1228.")
	sleep(5)
	helmet.display_visor_message("LMU/894411.-//0113122")
	sleep(5)
	helmet.display_visor_message("QRE 8667152...")
	sleep(5)
	helmet.display_visor_message("XAS -123455")
	sleep(5)
	helmet.display_visor_message("WF // .897")
	sleep(20)
	helmet.display_visor_message("DIAG//123")
	sleep(10)
	helmet.display_visor_message("MED//8189")
	sleep(10)
	helmet.display_visor_message("LOADING//...")
	sleep(30)
	helmet.display_visor_message("Cardiac dysrhythmia treatment in progress, standby...")
	playsound(src, 'sound/machines/defib_charge.ogg', 75, FALSE)
	sleep(25)
	if(!Wearer)
		return
	playsound(src, 'sound/machines/defib_zap.ogg', 50, FALSE)
	Wearer.apply_effects(stun = -100, paralyze = -100, stamina = -55)
	Wearer.adjustOxyLoss(-55)
	sleep(3)
	playsound(src, 'sound/machines/defib_success.ogg', 75, FALSE)
	helmet.display_visor_message("Cleared to proceed.")
	shutdown = FALSE
	toggle_mode(NANO_ARMOR, TRUE) //the pulse emptied the cell and it doesn't charge while shut down, so this has to be forced

/obj/item/clothing/suit/space/hardsuit/nano/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/stock_parts/cell))
		var/obj/item/stock_parts/cell/C = W
		if(C && C.charge >= 10000)
			if(current_charges < max_charges)
				if(do_after(user, 30, target = src))
					to_chat(user, "<span class='notice'>You recharge [src]'s medical systems with [C].</span>")
					addmedicalcharge()
					C.use(10000)
					C.chargerate /= 10
					C.chargerate = max(0.1, C.chargerate)
					to_chat(user, "<span class='notice'>In doing so, [C]'s ability to charge has been weakened.</span>")
					C.update_icon()
					return
			else if(current_charges >= max_charges)
				helmet.display_visor_message("Medical systems fully charged.")
				return
		else
			helmet.display_visor_message("Insufficient power source.")
			return

	return ..()

/datum/action/item_action/nanosuit
	check_flags = AB_CHECK_STUN|AB_CHECK_CONSCIOUS
	icon_icon = 'icons/mob/actions.dmi'
	background_icon_state = "bg_tech_blue"
	var/suit_mode //the mode this button lights up for

/datum/action/item_action/nanosuit/goggletoggle
	name = "Night Vision"
	icon_icon = 'hippiestation/icons/mob/actions/actions_nanosuit.dmi'
	button_icon_state = "toggle_goggle"

/datum/action/item_action/nanosuit/armor
	name = "Armor Mode"
	suit_mode = NANO_ARMOR
	icon_icon = 'hippiestation/icons/mob/actions/actions_nanosuit.dmi'
	button_icon_state = "armor_mode"

/datum/action/item_action/nanosuit/cloak
	name = "Cloak Mode"
	suit_mode = NANO_CLOAK
	icon_icon = 'hippiestation/icons/mob/actions/actions_nanosuit.dmi'
	button_icon_state = "cloak_mode"

/datum/action/item_action/nanosuit/speed
	name = "Speed Mode"
	suit_mode = NANO_SPEED
	icon_icon = 'hippiestation/icons/mob/actions/actions_nanosuit.dmi'
	button_icon_state = "speed_mode"

/datum/action/item_action/nanosuit/strength
	name = "Strength Mode"
	suit_mode = NANO_STRENGTH
	icon_icon = 'hippiestation/icons/mob/actions/actions_nanosuit.dmi'
	button_icon_state = "strength_mode"


/obj/item/clothing/head/helmet/space/hardsuit/nano
	name = "nanosuit helmet"
	desc = "The cherry on top. Property of CryNet Systems."
	alternate_worn_icon = 'hippiestation/icons/mob/nanosuit.dmi'
	icon = 'hippiestation/icons/obj/nanosuit.dmi'
	icon_state = "nanohelmet"
	item_state = "nanohelmet"
	item_color = "nano"
	siemens_coefficient = 0.0
	gas_transfer_coefficient = 0.01
	permeability_coefficient = 0.01
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF //No longer shall our kind be foiled by lone chemists with spray bottles!
	armor = list("melee" = 40, "bullet" = 40, "laser" = 40, "energy" = 45, "bomb" = 70, "bio" = 100, "rad" = 70, "fire" = 100, "acid" = 100)
	heat_protection = HEAD
	max_heat_protection_temperature = FIRE_IMMUNITY_MAX_TEMP_PROTECT
	var/zoom_range = 12
	var/zoom = FALSE
	var/explosion_detection_dist = 21
	scan_reagents = TRUE
	actions_types = list(/datum/action/item_action/nanosuit/zoom)
	rad_flags = RAD_PROTECT_CONTENTS | RAD_NO_CONTAMINATE
	rad_insulation = RAD_NO_INSULATION

/obj/item/clothing/head/helmet/space/hardsuit/nano/Initialize()
	. = ..()
	RegisterSignal(SSdcs, COMSIG_GLOB_EXPLOSION, PROC_REF(sense_explosion))

/obj/item/clothing/head/helmet/space/hardsuit/nano/proc/sense_explosion(datum/source, turf/epicenter, devastation_range, heavy_impact_range,
		light_impact_range, took, orig_dev_range, orig_heavy_range, orig_light_range)
	SIGNAL_HANDLER
	var/turf/T = get_turf(src)
	if(T.z != epicenter.z)
		return
	if(get_dist(epicenter, T) > explosion_detection_dist)
		return
	display_visor_message("Explosion detected! Epicenter: [devastation_range], Outer: [heavy_impact_range], Shock: [light_impact_range]")


/obj/item/clothing/head/helmet/space/hardsuit/nano/ui_action_click(mob/user, action)
	if(istype(action, /datum/action/item_action/nanosuit/zoom))
		toggle_zoom(user)
		return TRUE
	if(istype(action, /datum/action/item_action/toggle_geiger))
		return ..()
	return FALSE

/obj/item/clothing/head/helmet/space/hardsuit/nano/equipped(mob/living/carbon/human/user, slot)
	..()
	if(slot == ITEM_SLOT_HEAD)
		ADD_TRAIT(src, TRAIT_NODROP, CLOTHING_TRAIT)
		var/datum/atom_hud/medsensor = GLOB.huds[DATA_HUD_MEDICAL_ADVANCED]
		medsensor.add_hud_to(user)

/obj/item/clothing/head/helmet/space/hardsuit/nano/dropped(mob/living/carbon/human/user)
	..()
	if(user.head == src)
		var/datum/atom_hud/medsensor = GLOB.huds[DATA_HUD_MEDICAL_ADVANCED]
		medsensor.remove_hud_from(user)
		if(zoom)
			toggle_zoom(user, TRUE)

/obj/item/clothing/head/helmet/space/hardsuit/nano/proc/toggle_zoom(mob/living/user, force_off = FALSE)
	if(!user || !user.client)
		zoom = FALSE //a client coming back gets the default view from Login()
		return
	if(user.client.view != zoom_range) //a ghost and back, a mech: the view's been put back without us
		zoom = FALSE
	if(zoom || force_off)
		user.client.change_view(CONFIG_GET(string/default_view))
		to_chat(user, "<span class='boldnotice'>Disabled helmet zoom...</span>")
		zoom = FALSE
		return FALSE
	else
		user.client.change_view(zoom_range)
		to_chat(user, "<span class='boldnotice'>Enabled helmet zoom!</span>")
		zoom = TRUE
		return TRUE


/datum/action/item_action/nanosuit/zoom
	name = "Helmet Zoom"
	icon_icon = 'icons/mob/actions.dmi'
	background_icon_state = "bg_tech_blue"
	icon_icon = 'icons/mob/actions/actions_items.dmi'
	button_icon_state = "sniper_zoom"

/obj/item/clothing/head/helmet/space/hardsuit/nano/ComponentInitialize()
	. = ..()
	AddComponent(/datum/component/rad_insulation, RAD_NO_INSULATION, TRUE, TRUE)

/obj/item/clothing/suit/space/hardsuit/nano/equipped(mob/user, slot)
	if(ishuman(user) && slot == ITEM_SLOT_OCLOTHING)
		Wearer = user
		var/turf/T = get_turf(src)
		var/area/A = get_area(src)
		ADD_TRAIT(src, TRAIT_NODROP, CLOTHING_TRAIT)
		Wearer.unequip_all_items()
		Wearer.equipOutfit(outfit)
		ADD_TRAIT(Wearer, TRAIT_NODISMEMBER, "Nanosuit")
		RegisterSignal(Wearer, list(COMSIG_MOB_ITEM_ATTACK,COMSIG_MOB_THROW,COMSIG_MOB_ATTACK_HAND), PROC_REF(kill_cloak),TRUE)
		RegisterSignal(Wearer, COMSIG_MOB_ITEM_AFTERATTACK, PROC_REF(on_item_afterattack),TRUE)
		RegisterSignal(Wearer, list(COMSIG_LIVING_STATUS_STUN,COMSIG_LIVING_STATUS_KNOCKDOWN,COMSIG_LIVING_STATUS_IMMOBILIZE,COMSIG_LIVING_STATUS_PARALYZE,COMSIG_LIVING_STATUS_UNCONSCIOUS), PROC_REF(on_stunned),TRUE)
		if(is_station_level(T.z))
			priority_announce("[user] has engaged [src] at [A.map_name]!","Message from The Syndicate!", sound = 'hippiestation/sound/misc/nanosuitengage.ogg')
			bot_nanosuit_announced(user) //bots_ai/goals/robust.dm
		log_game("[user] has engaged [src]")
		if(help_verb)
			Wearer.verbs += help_verb
		INVOKE_ASYNC(src, PROC_REF(bootSequence))
	..()

/obj/item/clothing/suit/space/hardsuit/nano/dropped(mob/user)
	if(user == Wearer)
		disengage()
	..()

/// Takes back everything the suit did to its wearer. It can't be taken off, but it can still come off: a monkey sting, an admin, deletion.
/obj/item/clothing/suit/space/hardsuit/nano/proc/disengage()
	if(!Wearer)
		return
	power_down()
	if(hacked)
		var/datum/atom_hud/secsensor = GLOB.huds[DATA_HUD_SECURITY_ADVANCED]
		var/datum/atom_hud/diagsensor = GLOB.huds[DATA_HUD_DIAGNOSTIC_BASIC ]
		secsensor.remove_hud_from(Wearer)
		diagsensor.remove_hud_from(Wearer)
	if(help_verb)
		Wearer.verbs -= help_verb
	REMOVE_TRAIT(Wearer, TRAIT_NODISMEMBER, "Nanosuit")
	UnregisterSignal(Wearer, list(COMSIG_MOB_ITEM_ATTACK,COMSIG_MOB_ITEM_AFTERATTACK,COMSIG_MOB_THROW,COMSIG_MOB_ATTACK_HAND,COMSIG_LIVING_STATUS_STUN,COMSIG_LIVING_STATUS_KNOCKDOWN,COMSIG_LIVING_STATUS_IMMOBILIZE,COMSIG_LIVING_STATUS_PARALYZE,COMSIG_LIVING_STATUS_UNCONSCIOUS))
	REMOVE_TRAIT(src, TRAIT_NODROP, CLOTHING_TRAIT)
	Wearer.hud_used?.nano_energy?.clear()
	healthon = FALSE
	atmoson = FALSE
	radon = FALSE
	cellon = FALSE
	var/mob/living/carbon/human/H = Wearer
	Wearer = null
	if(QDELETED(H))
		return
	var/static/list/parts = typecacheof(list(/obj/item/clothing/under/syndicate/combat/nano, /obj/item/clothing/mask/gas/nano_mask, /obj/item/clothing/shoes/combat/coldres/nanojump, /obj/item/clothing/gloves/combat/nano, /obj/item/radio/headset/syndicate/alt/nano, /obj/item/clothing/glasses/nano_goggles))
	for(var/obj/item/I in H.get_equipped_items())
		if(is_type_in_typecache(I, parts))
			H.dropItemToGround(I, TRUE) //they can't be taken off by hand, and they delete themselves
	for(var/obj/item/implant/explosive/disintegrate/I in H.implants)
		qdel(I)

/// Waits out a step of the boot. FALSE once the boot's over: the suit's come off or gone, or it's been put back on and is booting again.
/obj/item/clothing/suit/space/hardsuit/nano/proc/boot_wait(time, boot)
	sleep(time)
	return boot == boot_count && Wearer && helmet && !QDELETED(src)

/// Coming on, the suit's systems report in one by one, and it's running about 13 seconds later. Every step looks first whether the boot is
/// still on: the suit can come off or go meanwhile (killed mid-boot, the wearer is dusted by their implant, the suit and helmet with them:
/// round-07.14.23), and put back on, it boots again from the start.
/obj/item/clothing/suit/space/hardsuit/nano/proc/bootSequence()
	var/boot = ++boot_count
	helmet.display_visor_message("Crynet - UEFI v1.32 Syndicate Systems")
	if(!boot_wait(10, boot))
		return
	helmet.display_visor_message("P.O.S.T. Commencing...")
	if(!boot_wait(30, boot))
		return
	playsound(src, 'sound/machines/beep.ogg', 50, FALSE)
	helmet.display_visor_message("Memory test: 6144MB OK(Installed Memory: 6144MB)")
	if(!boot_wait(10, boot))
		return
	helmet.display_visor_message("Onboard equipment test: OK")
	if(!boot_wait(10, boot))
		return
	helmet.display_visor_message("Telecommunications systems: OK")
	if(!boot_wait(10, boot))
		return
	helmet.display_visor_message("Checking environment sensors, standby...")
	if(!boot_wait(20, boot))
		return
	healthon = TRUE
	helmet.display_visor_message("Life signs systems: OK")
	if(!boot_wait(5, boot))
		return
	atmoson = TRUE
	helmet.display_visor_message("Atmospheric sensors: OK")
	if(!boot_wait(5, boot))
		return
	cellon = TRUE
	helmet.display_visor_message("Power sensor: OK")
	if(!boot_wait(5, boot))
		return
	radon = TRUE
	helmet.display_visor_message("Geiger counter: OK")
	if(!boot_wait(5, boot))
		return
	helmet.display_visor_message("Loading default configuration, standby...")
	if(!boot_wait(25, boot))
		return
	helmet.display_visor_message("Successful. Have a safe and secure day.")
	if(hacked) //put back on: coming off took its HUDs with it
		upgrade()
		return
	shutdown = FALSE
	toggle_mode(NANO_ARMOR)

/obj/item/clothing/suit/space/hardsuit/nano/emag_act(mob/user)
	if(shutdown)
		to_chat(user, "<span class='warning'>Error: Interfaces offline</span>")
		return
	if(!hacked)
		var/choice = tgui_alert(user, "Warning: This will DESTROY your emag, are you sure you want to continue?", "Warning", list("Yes, continue", "No, abort"))
		if(hacked || choice == "No, abort")
			return
		else
			var/obj/item/card/emag/card = locate() in user
			if(card)
				hacked = TRUE
				qdel(card)
				to_chat(user, "<span class='warning'>The emag is absorbed into the nanosuit!</span>")
				INVOKE_ASYNC(src, PROC_REF(emagSequence))
			else
				to_chat(user, "<span class='danger'>An error has occured, please try again.</span>")
				return
	else
		to_chat(user, "<span class='notice'>[src] has already been emagged.</span>")
		return

/obj/item/clothing/suit/space/hardsuit/nano/proc/emagSequence()
	power_down()
	sleep(15)
	helmet.display_visor_message("Unknown interference detected!")
	sleep(20)
	helmet.display_visor_message("Rebooting systems...")
	sleep(50)
	helmet.display_visor_message("Upgrades unlocked. Have a nice day.")
	if(Wearer)
		upgrade()

/obj/item/clothing/suit/space/hardsuit/nano/proc/upgrade()
	shutdown = FALSE
	toggle_mode(NANO_ARMOR, TRUE)
	upgrademulti = 1.5
	var/datum/atom_hud/secsensor = GLOB.huds[DATA_HUD_SECURITY_ADVANCED]
	var/datum/atom_hud/diagsensor = GLOB.huds[DATA_HUD_DIAGNOSTIC_BASIC ]
	secsensor.add_hud_to(Wearer)
	diagsensor.add_hud_to(Wearer)

/datum/outfit/nanosuit
	name = "Nanosuit"
	uniform = /obj/item/clothing/under/syndicate/combat/nano
	glasses = /obj/item/clothing/glasses/nano_goggles
	mask = /obj/item/clothing/mask/gas/nano_mask
	ears = /obj/item/radio/headset/syndicate/alt/nano
	shoes = /obj/item/clothing/shoes/combat/coldres/nanojump
	gloves = /obj/item/clothing/gloves/combat/nano
	implants = list(/obj/item/implant/explosive/disintegrate)
	suit_store = /obj/item/tank/internals/emergency_oxygen/recharge
	internals_slot = ITEM_SLOT_SUITSTORE

/// The energy every mode runs on, a number and a bar to catch the eye mid-fight
/obj/screen/nanosuit_energy
	name = "suit energy"
	screen_loc = "WEST,CENTER-2:15" //under the chemical and blood displays, which someone in a suit can have too
	invisibility = INVISIBILITY_ABSTRACT
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	maptext_width = 32
	maptext_height = 32
	maptext_y = 15 //it sits on the bottom of its box, and the bar has that
	var/shown

/obj/screen/nanosuit_energy/proc/show(percent, low)
	invisibility = 0
	if(shown == percent)
		return
	shown = percent
	var/colour = low ? "#ff5050" : "#66ccff"
	maptext = "<div style=\"text-align: center; font-family: 'Verdana'; font-size: 7pt; color: [colour]; -dm-text-outline: 1px #000000;\"><b>[percent]</b></div>"
	cut_overlays()
	add_overlay(bar(1, 5, 30, 10, "#000000"))
	add_overlay(bar(3, 7, 26 * percent / 100, 6, colour))

/// A flat block, this many pixels from the tile's bottom left corner
/obj/screen/nanosuit_energy/proc/bar(left, bottom, width, height, colour)
	var/mutable_appearance/block = mutable_appearance('icons/effects/alphacolors.dmi', "white")
	block.color = colour
	var/matrix/M = matrix()
	M.Scale(width / world.icon_size, height / world.icon_size)
	M.Translate(left + width / 2 - world.icon_size / 2, bottom + height / 2 - world.icon_size / 2)
	block.transform = M
	return block

/obj/screen/nanosuit_energy/proc/clear()
	invisibility = INVISIBILITY_ABSTRACT

/datum/hud
	var/obj/screen/nanosuit_energy/nano_energy

/datum/hud/human/New(mob/living/carbon/human/owner, ui_style = 'icons/mob/screen_midnight.dmi')
	. = ..()
	nano_energy = new()
	infodisplay += nano_energy

/datum/hud/Destroy()
	. = ..()
	nano_energy = null

/mob/living/carbon/human/get_stat_panel_extra_tabs()
	. = ..()
	if(istype(wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
		var/obj/item/clothing/suit/space/hardsuit/nano/NS = wear_suit
		var/datum/gas_mixture/environment = loc?.return_air()
		if(environment)
			var/pressure = environment.return_pressure()
			var/list/lines = list()
			lines += "Crynet Protocols: [!NS.shutdown?"Engaged":"Disengaged"]"
			lines += "Energy Charge: [NS.cellon?"[round(NS.cell.percent())]%":"offline"]"
			lines += "Medical Charges: [NS.healthon?"[NS.current_charges] of [NS.max_charges]":"offline"]"
			lines += "Mode: [NS.mode]"
			lines += "Overall Status: [NS.healthon?"[health]% healthy":"offline"]"
			lines += "Nutrition Status: [NS.healthon?"[nutrition]":"offline"]"
			lines += "Oxygen Loss: [NS.healthon?"[getOxyLoss()]":"offline"]"
			lines += "Toxin Levels: [NS.healthon?"[getToxLoss()]":"offline"]"
			lines += "Burn Severity: [NS.healthon?"[getFireLoss()]":"offline"]"
			lines += "Brute Trauma: [NS.healthon?"[getBruteLoss()]":"offline"]"
			lines += "Radiation Levels: [NS.radon?"[radiation] rads":"offline"]"
			lines += "Body Temperature: [NS.healthon?"["[bodytemperature-T0C] degrees C ([bodytemperature*1.8-459.67] degrees F)"]":"offline"]"
			lines += "Atmospheric Pressure: [NS.atmoson?"[pressure] kPa":"offline"]"
			lines += "Atmospheric Temperature: [NS.atmoson?"[round(environment.temperature-T0C, 0.01)] C ([round(environment.temperature, 0.01)] K)[environment.temperature > FIRE_IMMUNITY_MAX_TEMP_PROTECT ? " (too hot)" : ""]":"offline"]"
			lines += "Atmospheric Thermal Energy: [NS.atmoson?"[THERMAL_ENERGY(environment)/1000] kJ":"offline"]"
			LAZYSET(., "Crynet Nanosuit", lines)

/mob/living/carbon/human/Move(NewLoc, direct)
	. = ..()
	if(. && !(direct & (direct - 1))) //a diagonal is two of these steps, and it comes through here again once they're done
		if(istype(wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
			var/obj/item/clothing/suit/space/hardsuit/nano/NS = wear_suit
			if(mob_has_gravity() && !stat)
				NS.onmove()

/datum/martial_art/nanosuit
	name = "Nanosuit strength mode"
	block_chance = 75
	deflection_chance = 25
	id = MARTIALART_NANOSUIT

/datum/martial_art/nanosuit/teach(mob/living/carbon/human/H, make_temporary = FALSE)
	. = ..()
	RegisterSignal(H, COMSIG_HUMAN_EARLY_UNARMED_ATTACK, PROC_REF(on_attack_hand))

/datum/martial_art/nanosuit/remove(mob/living/carbon/human/H)
	. = ..()
	UnregisterSignal(H, COMSIG_HUMAN_EARLY_UNARMED_ATTACK)

/datum/martial_art/nanosuit/proc/check_streak(mob/living/carbon/human/A, mob/living/carbon/human/D)
	A.hud_used?.combo_object.update_icon(streak, 60)
	if(findtext(streak, POWER_PUNCH))
		streak = ""
		A.hud_used?.combo_object.update_icon(streak)
		PowerPunch(A,D)
		return TRUE
	if(findtext(streak, FINISH_HIM))
		to_chat(A, "<span class='cult italic'><b><span class='big'>FINISH HIM!!</span></b></span>")
	if(findtext(streak, HEAD_EXPLOSION))
		streak = ""
		A.hud_used?.combo_object.update_icon(streak)
		HeadStomp(A,D)
		return TRUE
	return FALSE

/datum/martial_art/nanosuit/proc/PowerPunch(mob/living/carbon/human/A, mob/living/carbon/human/D)
	if(!D.stat || !D.IsParalyzed())
		D.visible_message("<span class='warning'>[A] power punches [D]!</span>", \
						  	"<span class='userdanger'>[A] hits you with the force of a bus!</span>")
		playsound(get_turf(A), 'sound/effects/hit_punch.ogg', 75, TRUE, -1)
		D.apply_damage(20, BRUTE)
		var/atom/throw_target = get_edge_target_turf(D, A.dir)
		if(!D.anchored)
			D.throw_at(throw_target, rand(1,2), 7, A)
		log_combat(A, D, "nanosuit slammed")
	return TRUE

/datum/martial_art/nanosuit/proc/HeadStomp(mob/living/carbon/human/A, mob/living/carbon/human/D)
	var/obj/item/bodypart/head/head = D.get_bodypart(BODY_ZONE_HEAD)
	if(head)
		head.drop_limb()
		head.drop_organs()
		D.visible_message("<span class='warning'>[A] smashes [D] in the head, splattering their brains!</span>", \
					"<span class='userdanger'>OH SHI-</span>")
		playsound(get_turf(A), 'hippiestation/sound/misc/squishy.ogg', 75, TRUE, -1)
		playsound(get_turf(A), 'sound/magic/disintegrate.ogg', 50, TRUE, -1)
		D.death(FALSE)
		log_combat(A, D, "head stomped")
	if(ishuman(D))
		D.bleed_rate += 10
	D.apply_damage(40, BRUTE)
	A.do_attack_animation(D, ATTACK_EFFECT_KICK)
	return TRUE

/datum/martial_art/nanosuit/grab_act(mob/living/carbon/human/A, mob/living/carbon/D)
	if(A.grab_state >= GRAB_AGGRESSIVE)
		D.grabbedby(A, TRUE)
	else
		A.start_pulling(D, TRUE)
		if(A.pulling)
			D.stop_pulling()
			D.visible_message("<span class='danger'>[A] grapples [D]!</span>", \
								"<span class='userdanger'>[A] grapples you!</span>")
			A.grab_state = GRAB_AGGRESSIVE //Instant aggressive grab
			log_combat(A, D, "grabbed", addition="aggressively")
	return TRUE

/datum/martial_art/nanosuit/harm_act(var/mob/living/carbon/human/A, var/mob/living/carbon/D)
	var/picked_hit_type = pick("punches", "kicks")
	var/bonus_damage = 10
	var/quick = FALSE
	if(D.resting || D.lying)//we can hit ourselves
		bonus_damage += 5
		picked_hit_type = "stomps on"
		if(A.zone_selected == BODY_ZONE_HEAD && D.get_bodypart(BODY_ZONE_HEAD) && (!A.resting || !A.lying))
			D.add_splatter_floor(D.loc)
			D.apply_damage(10, BRAIN)
			bonus_damage += 5
			if(D.health <= 40)
				add_to_streak("S",D)
				if(check_streak(A,D))
					return TRUE
	if(D != A && !D.stat && (!D.IsParalyzed() || !D.IsStun())) //and we can't knock ourselves the fuck out/down!
		if(A.pulling == D && A.grab_state == GRAB_AGGRESSIVE)
			A.stop_pulling() //So we don't spam the combo
			bonus_damage += 5
			D.Paralyze(15)
			D.visible_message("<span class='warning'>[A] knocks [D] the fuck down!", \
							"<span class='userdanger'>[A] knocks you the fuck down!</span>")
			if(prob(75))
				step_away(D,A,15)
		else if(A.pulling == D && A.grab_state > GRAB_AGGRESSIVE)
			var/atom/throw_target = get_edge_target_turf(D, A.dir)
			if(!D.anchored)
				D.throw_at(throw_target, rand(1,2), 7, A)
			bonus_damage += 10
			D.Paralyze(60)
			D.visible_message("<span class='warning'>[A] knocks [D] the fuck out!!", \
							"<span class='userdanger'>[A] knocks you the fuck out!!</span>")
		else if(A.resting && !D.lying) //but we can't legsweep ourselves!
			D.visible_message("<span class='warning'>[A] leg sweeps [D]!", \
								"<span class='userdanger'>[A] leg sweeps you!</span>")
			playsound(get_turf(A), 'sound/effects/hit_kick.ogg', 50, TRUE, -1)
			bonus_damage += 5
			D.Paralyze(60)
			log_combat(A, D, "nanosuit leg swept")
	if(!A.resting || !A.lying)
		if(prob(30))
			quick = TRUE
			A.changeNext_move(CLICK_CD_RAPID)
			.= FALSE
			add_to_streak("Q",D)
			if(check_streak(A,D))
				return TRUE
		else if(prob(35))
			cleeve_attack(A,D)
			return FALSE
	D.visible_message("<span class='danger'>[A] [quick?"quick":""] [picked_hit_type] [D]!</span>", \
					"<span class='userdanger'>[A] [quick?"quick":""] [picked_hit_type] you!</span>")
	if(picked_hit_type == "kicks" || picked_hit_type == "stomps on")
		A.do_attack_animation(D, ATTACK_EFFECT_KICK)
		playsound(get_turf(D), 'sound/effects/hit_kick.ogg', 50, TRUE, -1)
	else
		A.do_attack_animation(D, ATTACK_EFFECT_PUNCH)
		playsound(get_turf(D), 'sound/effects/hit_punch.ogg', 50, TRUE, -1)
	log_combat(A, D, "attacked ([name])")
	if(isalien(D))
		bonus_damage += 30
	D.apply_damage(bonus_damage, BRUTE)
	return TRUE

/datum/martial_art/nanosuit/disarm_act(var/mob/living/carbon/human/A, var/mob/living/carbon/D)
	var/obj/item/I = null
	A.do_attack_animation(D, ATTACK_EFFECT_DISARM)
	if(prob(70) && D != A)
		I = D.get_active_held_item()
		if(I)
			if(D.temporarilyRemoveItemFromInventory(I))
				A.put_in_hands(I)
		D.visible_message("<span class='danger'>[A] has disarmed [D]!</span>", \
							"<span class='userdanger'>[A] has disarmed [D]!</span>")
		playsound(D, 'sound/weapons/thudswoosh.ogg', 50, TRUE, -1)
		D.Paralyze(40)
	else
		D.visible_message("<span class='danger'>[A] attempted to disarm [D]!</span>", \
							"<span class='userdanger'>[A] attempted to disarm [D]!</span>")
		playsound(D, 'sound/weapons/punchmiss.ogg', 25, TRUE, -1)
	log_combat(A, D, "disarmed with nanosuit", "[I ? " removing \the [I]" : ""]")
	return TRUE

/datum/martial_art/nanosuit/proc/cleeve_attack(mob/living/carbon/human/A, mob/living/carbon/D)
	for(D in orange(1, A))
		if(D != A && is_A_facing_B(A,D) && (!D.stat || !D.IsParalyzed()))
			basic_hit(A,D)

/atom/proc/nanosuit_damage() //the damage nanosuits do on punches to this object, is affected by melee armor
	return 25 //just enough to damage an airlock

/atom/proc/attack_nanosuit(mob/living/carbon/human/user)
	SEND_SIGNAL(src, COMSIG_MOB_ATTACK_HAND, user)

/mob/living/simple_animal/nanosuit_damage()
	return 20

/mob/living/attack_nanosuit(mob/living/carbon/human/user)
	..()
	if(HAS_TRAIT(user, TRAIT_PACIFISM))
		to_chat(user, "<span class='warning'>You don't want to hurt [src]!</span>")
		return FALSE
	return TRUE

/mob/living/simple_animal/attack_nanosuit(mob/living/carbon/human/user)
	. = ..()
	if(!.)
		return
	adjustBruteLoss(nanosuit_damage())
	var/hitverb = "punched"
	if(mob_size < MOB_SIZE_LARGE)
		safe_throw_at(get_edge_target_turf(src, get_dir(user, src)), 2, 1, user)
		hitverb = "slammed"
	playsound(loc, "punch", 25, TRUE, -1)
	visible_message("<span class='danger'>[user] has [hitverb] [src]!</span>", \
		"<span class='userdanger'>[user] has [hitverb] [src]!</span>", null, COMBAT_MESSAGE_RANGE)

/obj/item/attack_nanosuit(mob/living/carbon/human/user)
	return FALSE

/obj/effect/attack_nanosuit(mob/living/carbon/human/user)
	return FALSE

/obj/structure/window/attack_nanosuit(mob/living/carbon/human/user)
	if(!can_be_reached(user))
		return
	. = ..()

/obj/structure/grille/attack_nanosuit(mob/living/carbon/human/user)
	if(shock(user, 70))
		return
	. = ..()

/obj/structure/destructible/clockwork/attack_nanosuit(mob/living/carbon/human/user)
	if(is_servant_of_ratvar(user) && immune_to_servant_attacks)
		return FALSE
	return ..()

/obj/attack_nanosuit(mob/living/carbon/human/user)//attacking objects barehand
	..()
	visible_message("<span class='danger'>[user] smashes [src]!</span>", null, null, COMBAT_MESSAGE_RANGE)
	playsound(src, 'sound/effects/bang.ogg', density ? 100 : 50, TRUE)//less ear rape
	take_damage(nanosuit_damage(), BRUTE, "melee", FALSE, get_dir(src, user))
	return TRUE

/mob/living/carbon/human/check_weakness(obj/item/weapon, mob/living/carbon/attacker)
	. = ..()
	if(attacker && ishuman(attacker))
		if(attacker.mind?.has_martialart(MARTIALART_NANOSUIT) && weapon && weapon.damtype == BRUTE)
			. *= 1.25 //deal 25% more damage in strength

/obj/attacked_by(obj/item/I, mob/living/user)
	if(I.force && I.damtype == BRUTE && ishuman(user) && !user.stat && user.mind?.has_martialart(MARTIALART_NANOSUIT))
		visible_message("<span class='danger'>[user] has hit [src] with a strengthened blow from [I]!</span>", null, null, COMBAT_MESSAGE_RANGE)
		take_damage(I.force*1.75, I.damtype, "melee", TRUE, get_dir(src, user))//take 75% more damage with strength on
		return
	return ..()

/obj/item/throw_at(atom/target, range, speed, mob/thrower, spin = TRUE, diagonals_first = FALSE, datum/callback/callback, force, gentle = FALSE, quickstart = TRUE)
	if(thrower && ishuman(thrower))
		var/mob/living/carbon/human/H = thrower
		if(istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
			var/obj/item/clothing/suit/space/hardsuit/nano/NS = H.wear_suit
			if(NS.mode == NANO_STRENGTH)
				. = ..(target, range*1.5, speed*2, thrower, spin, diagonals_first, callback, force, gentle, quickstart = quickstart)
				return
	. = ..()

/datum/martial_art/nanosuit/proc/on_attack_hand(mob/living/carbon/human/owner, atom/target, proximity)
	SIGNAL_HANDLER
	if(!proximity)
		return
	var/datum/martial_art/nanosuit/style = owner.mind?.has_martialart(MARTIALART_NANOSUIT)
	if(iscarbon(target) && !ishuman(target))
		if(owner.a_intent == INTENT_HARM && style?.harm_act(owner, target))
			return COMPONENT_NO_ATTACK_HAND
		return
	if(owner.a_intent == INTENT_HARM && !iscarbon(target))
		if(target.attack_nanosuit(owner))
			log_combat(owner, target, "punched", "nanosuit strength mode")
			owner.do_attack_animation(target, ATTACK_EFFECT_SMASH)
			owner.changeNext_move(CLICK_CD_MELEE)
			return COMPONENT_NO_ATTACK_HAND

/mob/living/simple_animal/attack_hand(mob/living/carbon/human/M)
	. = ..()
	if(M && ishuman(M) && istype(M.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
		var/obj/item/clothing/suit/space/hardsuit/nano/NS = M.wear_suit
		NS.kill_cloak()

/obj/item/clothing/suit/space/hardsuit/nano/proc/kill_cloak()
	SIGNAL_HANDLER
	if(mode == NANO_CLOAK)
		var/obj/item/W = Wearer.get_active_held_item()
		if(istype(W, /obj/item/gun))
			var/obj/item/gun/G = W
			if(G.suppressed && G.can_shoot())
				cut_nano_energy(15)
				Wearer.filters = null
				animate(Wearer, alpha = 255, time = stealth_cloak_out)
				addtimer(CALLBACK(src, PROC_REF(resume_cloak)), 6, TIMER_UNIQUE|TIMER_OVERRIDE)
				return
		cut_nano_energy(cell.charge, NANO_CHARGE_DELAY)

/// Afterattack runs for every click with something in hand. Guns fire from it, but a wrench on a pipe or a flashlight on the floor isn't an attack.
/obj/item/clothing/suit/space/hardsuit/nano/proc/on_item_afterattack(datum/source, atom/target, mob/user, proximity_flag)
	SIGNAL_HANDLER
	if(ismob(target) || (!proximity_flag && istype(Wearer.get_active_held_item(), /obj/item/gun)))
		kill_cloak()

/obj/item/clothing/suit/space/hardsuit/nano/proc/resume_cloak()
	if(cell.charge && mode == NANO_CLOAK)
		Wearer.filters = filter(type="blur",size=1)
		animate(Wearer, alpha = 40, time = stealth_cloak_in)

/obj/item/storage/box/syndie_kit/nanosuit
	name = "\improper Crynet Systems kit"
	desc = "Maximum Death."

/obj/item/storage/box/syndie_kit/nanosuit/PopulateContents()
	new /obj/item/clothing/suit/space/hardsuit/nano(src)

/obj/item/implant/explosive/disintegrate
	name = "disintegration implant"
	desc = "Ashes to ashes."
	icon_state = "explosive"
	actions_types = list(/datum/action/item_action/dusting_implant)
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF

/obj/item/implant/explosive/disintegrate/activate(cause)
	if(!cause || !imp_in || cause == "emp" || active)
		return FALSE
	if(cause == "action_button")
		if(popup) //the warning's already up, and a second click isn't a yes
			return FALSE
		popup = TRUE
		var/response = tgui_alert(imp_in, "Are you sure you want to activate your [name]? This will cause you to disintergrate!", "[name] Confirmation", list("Yes", "No"))
		popup = FALSE
		if(response == "No")
			return FALSE
	active = TRUE //to avoid it triggering multiple times due to dying
	to_chat(imp_in, "<span class='notice'>Your dusting implant activates!</span>")
	imp_in.visible_message("<span class='warning'>[imp_in] burns up in a flash!</span>")
	var/turf/T = get_turf(imp_in)
	message_admins("[ADMIN_LOOKUPFLW(imp_in)] has activated their [name] at [ADMIN_VERBOSEJMP(T)], with cause of [cause].")
	playsound(loc, 'sound/effects/fuse.ogg', 30, FALSE)
	imp_in.dust(TRUE,TRUE)
	qdel(src)

/obj/item/tank/internals/emergency_oxygen/recharge
	name = "self-filling miniature oxygen tank"
	desc = "An oxygen tank that uses bluespace technology to replenish it's oxygen supply."
	volume = 3
	icon_state = "emergency_tst"
	item_flags = DROPDEL
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF

/obj/item/tank/internals/emergency_oxygen/recharge/New()
	..()
	air_contents.assert_gas(/datum/gas/oxygen)
	air_contents.moles[/datum/gas/oxygen] = (10*ONE_ATMOSPHERE)*volume/(R_IDEAL_GAS_EQUATION*T20C)

/obj/item/tank/internals/emergency_oxygen/recharge/process()
	if(ishuman(loc))
		var/moles_val = ONE_ATMOSPHERE*volume/(R_IDEAL_GAS_EQUATION*T20C)
		if(air_contents.moles[/datum/gas/oxygen] < (10*moles_val))
			air_contents.assert_gas(/datum/gas/oxygen)
			air_contents.moles[/datum/gas/oxygen] = clamp(air_contents.total_moles()+moles_val,MOLES_GAS_VISIBLE,(10*moles_val))
			if(!air_contents.total_moles())
				air_contents.moles[/datum/gas/oxygen] = ONE_ATMOSPHERE*volume/(R_IDEAL_GAS_EQUATION*T20C)
		if(air_contents.return_pressure() != initial(distribute_pressure))
			distribute_pressure = initial(distribute_pressure)

/obj/item/tank/internals/emergency_oxygen/recharge/equipped(mob/living/carbon/human/wearer, slot)
	..()
	if(slot == ITEM_SLOT_SUITSTORE)
		ADD_TRAIT(src, TRAIT_NODROP, ABSTRACT_ITEM_TRAIT)
		START_PROCESSING(SSobj, src)

/obj/item/tank/internals/emergency_oxygen/recharge/dropped(mob/living/carbon/human/wearer)
	..()
	STOP_PROCESSING(SSobj, src)

/mob/living/carbon/human/proc/Nanosuit_help()
	set name = "Crytek Product Manual"
	set desc = "You read through the manual..."
	set category = "Nanosuit help"

	to_chat(src, "<b><i>Welcome to CryNet Systems user manual 1.47 rev. 10619. Today we will learn about what your new piece of hardware has to offer.</i></b>")
	to_chat(src, "<b><i>If you are reading this, you've probably alerted the entire sector about the purchase of an illegal syndicate item banned in a radius of 50 megaparsecs!</i></b>")
	to_chat(src, "<b><i>Fortunately, the syndicate equipped this bad boy with high tech sensing equipment, the downside is the whole crew knows you're here.</i></b>")
	to_chat(src, "<b>Sensors</b>: Reagent scanner, bomb radar, medical, user life signs monitor and bluespace communication relay.")
	to_chat(src, "<b>Passive equipment</b>: Binoculars, night vision, anti-slips, shock and heat proof gloves, self-refilling mini o2 tank, body temperature stabilizer and impact reactive medical systems, with a charge back every 3 minutes.")
	to_chat(src, "<b>Press C to toggle quick mode selection. It's a keybind, so it can be changed in your preferences.</b>")
	to_chat(src, "<b>Your energy is on the left of your screen, and the button of the mode you're in is lit.</b>")
	to_chat(src, "<b>Toughness</b>: While the suit's running, stuns last a quarter as long and a tenth in armor mode, and another can't land until 3 seconds after one wears off. Stamina hits count half and you shake them off in seconds. Being thrown into a wall does nothing to you, and anyone you crash into goes down alone. An EMP shutdown takes all of this away.")
	to_chat(src, "<b>Active modes</b>: Armor, strength, speed and cloak.")
	to_chat(src, "<span class='notice'>Armor</span>: Resist damage that would normally kill or seriously injure you. Your heaviest armor, and blocks 50% of attacks at a cost of suit energy drain.\n\
    <span class='notice'>Cloak</span>: Become a ninja. Cloaking technology alters the outer layers to refract light through and around the suit, making the user appear almost completely invisible. Simple tasks such as attacking in any way, being hit or throwing objects cancels cloak.\n\
	<span class='notice'>Speed</span>: Run like a madman. Use conservatively as suit energy drains rather quickly.\n\
	<span class='notice'>Strength</span>: Beat the shit out of objects  or people with your fists. Jump across small gaps and structures. You hit and throw harder with brute objects. You can't be grabbed aggressively or pushed. 25% ranged hits deflection. Toggling throw mode gives you a 75% block chance.\n\
	<span class='notice'>Aggressive grab</span>: Your grabs start aggressive.\n\
	<span class='notice'>Robust push</span>: Your disarms have a 70% chance of knocking an opponent down for 4 seconds.\n\
	<span class='notice'>MMA master</span>: Harm intents deals more damage, occasionally trigger series of fast hits and you can leg sweep while lying down.\n\
	<span class='notice'>Highschool bully</span>: Grab someone and harm intent them to deliver a deadly knock down punch.\n\
	<span class='notice'>Knockout master</span>: Tighten your grip and harm intent to deliver a very deadly knockout punch.\n\
	<span class='notice'>Mike Tyson</span>: Getting 3 successful quick punches sends your victim flying back.\n\
	<span class='notice'>Head stomp special</span>: Target victims head while they're knocked down, stomp until their brain explodes.")
	to_chat(src, "<b><i>User warning: The suit is equipped with an implant which vaporizes the suit and user upon request or death.</i></b>")

/obj/item/stock_parts/cell/nano
	name = "nanosuit self charging battery"
	maxcharge = 100
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | FREEZE_PROOF

/datum/keybinding/human/nanosuit_menu
	hotkey_keys = list("C")
	name = "nanosuit_menu"
	full_name = "Nanosuit quick menu"
	description = "Pick a nanosuit mode from a wheel around you"

/datum/keybinding/human/nanosuit_menu/down(client/user)
	var/mob/living/carbon/human/H = user.mob
	var/obj/item/clothing/suit/space/hardsuit/nano/NS = H.wear_suit
	if(!istype(NS))
		return FALSE
	INVOKE_ASYNC(NS, TYPE_PROC_REF(/obj/item/clothing/suit/space/hardsuit/nano, open_mode_menu), H) //the wheel waits for a click, and the key press mustn't
	return TRUE

/obj/item/clothing/suit/space/hardsuit/nano/proc/check_menu(mob/living/user)
	if(!user)
		return FALSE
	if(user.incapacitated(TRUE, TRUE) || user != Wearer) //the same as the buttons: a locker or cuffs stop neither
		return FALSE
	return TRUE

/obj/item/clothing/suit/space/hardsuit/nano/proc/open_mode_menu(mob/living/user)
	var/list/choices = list(
	"armor" = image(icon = 'hippiestation/icons/mob/actions/actions_nanosuit.dmi', icon_state = "armor_menu"),
	"speed" = image(icon = 'hippiestation/icons/mob/actions/actions_nanosuit.dmi', icon_state = "speed_menu"),
	"cloak" = image(icon = 'hippiestation/icons/mob/actions/actions_nanosuit.dmi', icon_state = "cloak_menu"),
	"strength" = image(icon = 'hippiestation/icons/mob/actions/actions_nanosuit.dmi', icon_state = "strength_menu")
	)
	var/choice = show_radial_menu(user,user, choices, custom_check = CALLBACK(src, PROC_REF(check_menu), user), require_near = TRUE)
	if(!check_menu(user))
		return
	switch(choice)
		if("armor")
			toggle_mode(NANO_ARMOR)
			return
		if("speed")
			toggle_mode(NANO_SPEED)
			return
		if("cloak")
			toggle_mode(NANO_CLOAK)
			return
		if("strength")
			toggle_mode(NANO_STRENGTH)
			return

/datum/radial_menu/extract_image(E)
	var/mutable_appearance/MA = new /mutable_appearance(E)
	if(MA)
		MA.layer = ABOVE_HUD_LAYER
		MA.appearance_flags |= RESET_TRANSFORM | RESET_ALPHA
	return MA
