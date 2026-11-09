/turf
	var/elevation = 10
	var/pinned = null
	/// The last get_hearers_in_view() that could see this tile. A stamp beats a list of them: this runs for every word anyone says.
	var/hearing_stamp = 0

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
