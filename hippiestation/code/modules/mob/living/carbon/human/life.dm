/mob/living/carbon/human/handle_status_effects()
	..()
	checklisp()
	if(pinned_to && !pinning_rod_in()) // the rod's out, however it came out
		unpin_from_wall()
	
/mob/living/carbon/human/handle_hygiene()
 	return
