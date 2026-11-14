/*

This file is for code regarding areas. Do not add new areas here. Rather, add new areas to the file in which they would go normally.
Hint: This is usually Space_Station_13_areas.dm.

*/

/area
	ambientsounds = list('sound/ambience/ambigen1.ogg','sound/ambience/ambigen3.ogg',\
									'sound/ambience/ambigen4.ogg','sound/ambience/ambigen5.ogg',\
									'sound/ambience/ambigen6.ogg','sound/ambience/ambigen7.ogg',\
									'sound/ambience/ambigen8.ogg','sound/ambience/ambigen9.ogg',\
									'sound/ambience/ambigen10.ogg','sound/ambience/ambigen11.ogg',\
									'sound/ambience/ambigen12.ogg','sound/ambience/ambigen14.ogg',\
									'hippiestation/sound/ambience/ambiencegenlawnmower.ogg','hippiestation/sound/ambience/ambiencegenscivir.ogg',
									)

/area/hippie
	name = "Unknown"
	icon = 'hippiestation/icons/turf/areas.dmi'

/area/space
	ambientsounds = list('hippiestation/sound/ambience/ambispace.ogg','hippiestation/sound/ambience/space_stutter.ogg','hippiestation/sound/ambience/space_ambience.ogg')
/// tg's, but a machine not yet initialized is left out: nothing on it is set up to update yet (a canister has no air), and its
/// LateInitialize() works out its power anyway. The lobby build initializes Lavaland over many ticks, and an APC that's done
/// fires its update() timer while the rest of its area still waits (runtime in canister update_icon(), 2026-11-14).
/area/power_change()
	for(var/obj/machinery/M in src)
		if(M.flags_1 & INITIALIZED_1)
			M.power_change()
	update_icon()
