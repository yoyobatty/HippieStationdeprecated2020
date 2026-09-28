#define FLICKER_MAX_TOGGLES 30

/obj/machinery/light/take_damage(damage_amount, damage_type = BRUTE, damage_flag = 0, sound_effect = 1)
	. = ..()
	if(. && !QDELETED(src))
		if(prob(damage_amount * 10))
			flicker(damage_amount*rand(1,3))

/obj/machinery/light/flicker(amount = rand(10, 20))
	set waitfor = FALSE
	if(flickering || !on || status != LIGHT_OK)
		return FALSE
	flickering = TRUE
	amount = min(amount, FLICKER_MAX_TOGGLES)
	var/old_colour = bulb_colour
	var/old_switchcount = switchcount //flickering is cosmetic, don't let it wear out the bulb
	visible_message("<span class='warning'>[src] begins flickering!</span>","<span class='italics'>You hear an electrical sparking.</span>")
	for(var/i in 1 to amount)
		if(QDELETED(src) || status != LIGHT_OK || !has_power())
			break
		on = !on
		if(!on && prob(18))//only spark when off so it doesn't occur too much
			do_sparks(1, FALSE, src)
		else if(prob(40))
			bulb_colour = LIGHT_COLOR_BROWN
			playsound(src, pick('sound/effects/sparks1.ogg', 'sound/effects/sparks2.ogg', 'sound/effects/sparks3.ogg', 'sound/effects/sparks4.ogg', 'sound/effects/light_flicker.ogg'), 60, TRUE)
		else
			bulb_colour = old_colour
		update(FALSE)
		sleep(rand(2, 6))
	if(QDELETED(src))
		return
	bulb_colour = old_colour
	switchcount = old_switchcount
	on = (status == LIGHT_OK && has_power())
	update(FALSE)
	flickering = FALSE
	return TRUE

#undef FLICKER_MAX_TOGGLES
