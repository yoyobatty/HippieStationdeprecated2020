// Heat through walls (process_super_conductivity()) runs every superconduct_every atmos ticks instead of every one, and each run
// stands for that many: every coefficient c it shares heat by becomes 1 - (1 - c)^N (SUPERCONDUCT_COEFF() in
// ~hippie_defines/atmospherics.dm, at the five places LINDA_turf_tile.dm uses one). For two tiles that's exactly what N runs at c
// do, and it never shares past even, so a floor and its air (0.4) can't overshoot the way 4 x 0.4 would. Heat creeps through
// walls in 2 second steps instead of half second ones; in a plasma fire this stage was a quarter of SSair (tools/atmos_ab).
// -params "atmos-superconduct-every=1" runs it every tick as before.

/datum/controller/subsystem/air
	/// Heat through walls runs every this many atmos ticks
	var/superconduct_every = 4

/datum/controller/subsystem/air/Initialize(timeofday)
	var/every = text2num(world.params["atmos-superconduct-every"])
	superconduct_every = every ? clamp(round(every), 1, 10) : 4
	return ..()

/datum/controller/subsystem/air/process_super_conductivity(resumed = FALSE)
	if(!resumed && superconduct_every > 1 && (times_fired % superconduct_every))
		return
	return ..()
