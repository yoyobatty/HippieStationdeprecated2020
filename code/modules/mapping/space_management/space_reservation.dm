
//Yes, they can only be rectangular.
//Yes, I'm sorry.
/datum/turf_reservation
	var/list/reserved_turfs = list()
	var/width = 0
	var/height = 0
	var/bottom_left_coords[3]
	var/top_right_coords[3]
	var/wipe_reservation_on_release = TRUE
	var/turf_type = /turf/open/space

/datum/turf_reservation/transit
	turf_type = /turf/open/space/transit

/datum/turf_reservation/proc/Release()
	var/v = reserved_turfs.Copy()
	for(var/i in reserved_turfs)
		reserved_turfs -= i
		SSmapping.used_turfs -= i
	SSmapping.reserve_turfs(v)

/datum/turf_reservation/proc/Reserve(width, height, zlevel)
	if(width > world.maxx || height > world.maxy || width < 1 || height < 1)
		return FALSE
	var/list/avail = SSmapping.unused_turfs["[zlevel]"]
	var/turf/BL
	var/turf/TR
	var/list/turf/final = list()
	var/passing = FALSE
	// hippie start -- from the end of the list: what's claimed is then near its end, where -= below starts looking (it removes the last
	// copy), rather than at its start, up to 65,000 turfs into the search for each (2026-11-09: 27 us a turf, a third of what a Bot
	// Gym's arenas cost to build). By index, not a copy of the list: CHECK_TICK can sleep while another reservation takes turfs out.
	for(var/index in length(avail) to 1 step -1)
		CHECK_TICK
		if(index > length(avail))
			continue
		BL = avail[index]
	// hippie end
		if(!(BL.flags_1 & UNUSED_RESERVATION_TURF_1))
			continue
		if(BL.x + width > world.maxx || BL.y + height > world.maxy)
			continue
		TR = locate(BL.x + width - 1, BL.y + height - 1, BL.z)
		if(!(TR.flags_1 & UNUSED_RESERVATION_TURF_1))
			continue
		final = block(BL, TR)
		if(!final)
			continue
		passing = TRUE
		for(var/I in final)
			var/turf/checking = I
			if(!(checking.flags_1 & UNUSED_RESERVATION_TURF_1))
				passing = FALSE
				break
		if(!passing)
			continue
		break
	if(!passing || !istype(BL) || !istype(TR))
		return FALSE
	bottom_left_coords = list(BL.x, BL.y, BL.z)
	top_right_coords = list(TR.x, TR.y, TR.z)
	for(var/i in final)
		var/turf/T = i
		reserved_turfs |= T
		T.flags_1 &= ~UNUSED_RESERVATION_TURF_1
		SSmapping.unused_turfs["[T.z]"] -= T
		SSmapping.used_turfs[T] = src
	// hippie -- all claimed above, so changing them can wait for the next tick: SSshuttle can't pause by itself, and ~700 turfs in one go was a 47 ms hitch per shuttle trip
	for(var/i in final)
		var/turf/T = i
		T.ChangeTurf(turf_type, turf_type)
		CHECK_TICK
	src.width = width
	src.height = height
	return TRUE

/datum/turf_reservation/New()
	LAZYADD(SSmapping.turf_reservations, src)

/datum/turf_reservation/Destroy()
	Release()
	LAZYREMOVE(SSmapping.turf_reservations, src)
	return ..()
