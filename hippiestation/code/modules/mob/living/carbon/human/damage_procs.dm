/mob/living/carbon/human/adjustStaminaLoss(amount, updating_health = TRUE, forced = FALSE)
	..()
	update_stamina_hud()

// The stamina bar only changed in adjustStaminaLoss(), but most stamina comes and goes another way: hits (batons,
// disablers, punches) go into the limb's receive_damage() and regen heals the limbs directly. Both end in
// updatehealth() -> update_stat() -> here, so the bar follows them now, and the health it's drawn from.
/mob/living/carbon/human/update_health_hud()
	. = ..()
	update_stamina_hud()

/mob/living/carbon/human/proc/update_stamina_hud()
	if(client && hud_used?.staminas)
		hud_used.staminas.icon_state = staminahudamount()
