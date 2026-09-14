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
	. = ..() // hippie -- already calls check_hippie_icon() via /atom/Initialize(), no need to call it again here
