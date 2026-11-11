/mob/living/carbon/check_projectile_dismemberment(obj/item/projectile/P, def_zone)
	if(HAS_TRAIT(src, TRAIT_NODISMEMBER))
		return FALSE
	return ..()

/mob/living/carbon/attackby(obj/item/I, mob/user, params)
	if(lying || user == src)
		if(surgeries.len)
			if(user.a_intent == "help")
				for(var/datum/surgery/S in surgeries)
					if(S.next_step(user, src))
						return 1
	..()

/mob/living/carbon/soundbang_act()
	if(status_flags & GODMODE)
		return
	. = ..()

/mob/living/carbon/flash_act(intensity = 1, override_blindness_check = 0, affect_silicon = 0, visual = 0, type = /obj/screen/fullscreen/flash)
	if(status_flags & GODMODE)
		return
	. = ..()

//to damage the clothes worn by a mob
/mob/living/carbon/damage_clothes(damage_amount, damage_type = BRUTE, damage_flag = 0, def_zone)
	if(status_flags & GODMODE)
		return
	. = ..()

/mob/living/carbon/ex_act(severity, target, origin)
	if(status_flags & GODMODE)
		return
	. = ..()

/mob/living/carbon/acid_act(acidpwr, acid_volume)
	if(status_flags & GODMODE)
		return
	. = ..()

/mob/living/carbon/electrocute_act(shock_damage, source, siemens_coeff = 1, safety = 0, override = 0, tesla_shock = 0, illusion = 0, stun = TRUE)
	if(status_flags & GODMODE)
		return
	. = ..()
	// The carbon version never calls /mob/living's, which is where COMSIG_LIVING_ELECTROCUTE_ACT is sent, so a shock never
	// touched a human's nanites. Sent here once the shock has landed (not for a hallucinated one).
	if(. && !illusion)
		SEND_SIGNAL(src, COMSIG_LIVING_ELECTROCUTE_ACT, .)

// Stamina crit set its flag but left mobility alone, and a hit updates mobility before stamina: someone exhausted kept
// walking about until the next health update.
/mob/living/carbon/enter_stamcrit()
	var/was_stamcrit = stam_paralyzed
	..()
	if(stam_paralyzed && !was_stamcrit)
		update_mobility()

/mob/living/carbon/update_stamina()
	var/was_stamcrit = stam_paralyzed
	..()
	if(was_stamcrit && !stam_paralyzed)
		update_mobility()
