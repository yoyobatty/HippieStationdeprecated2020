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
