// Only a motion camera needs to know who walks past it, so only a motion camera keeps a proximity monitor. tg gave one to every
// camera: 9 invisible movables around each of the station's 264 that every player's map sending had to look through each tick,
// and a Crossed() for every step onto one, which on a plain camera only noted the mob in a list nothing read (process() stops
// at once without the motion upgrade).

/obj/machinery/camera/upgradeMotion()
	..()
	if(isMotion() && !proximity_monitor)
		proximity_monitor = new(src, 1)

/obj/machinery/camera/removeMotion()
	..()
	QDEL_NULL(proximity_monitor)

// A camera's assembly is part of the camera: it goes when the camera does (Destroy()), and not before. A bomb going off on a
// camera's own tile blows up what's inside everything on the tile as well (SSexplosions, for bombs in bags), and that took the
// assembly out of the bomb range's camera at every test. That camera can't be destroyed, so it went on holding an assembly that
// had been deleted: a hard delete for every bomb the scientists set off, 6 in 12 shifts.
/obj/machinery/camera/prevent_content_explosion()
	return TRUE

/obj/machinery/camera/handle_atom_del(atom/A)
	if(A == assembly)
		assembly = null
	return ..()
