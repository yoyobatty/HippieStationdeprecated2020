/turf
	var/elevation = 10
	var/pinned = null

/turf/Destroy()
	if (pinned)
		var/mob/living/carbon/human/H = pinned

		if (istype(H))
			H.anchored = FALSE
			H.pinned_to = null
			H.do_pindown(src, 0)
			H.update_mobility()

			for (var/obj/item/stack/rods/R in H.contents)
				if (R.pinned)
					R.pinned = null
		pinned = null
	return ..()

/turf/Initialize()
	. = ..() // hippie -- base /turf/Initialize(mapload) never calls ..() up to /atom/Initialize(), so this is the only place turfs get their hippie icon applied - do not remove
	if(icon_hippie)
		check_hippie_icon()
