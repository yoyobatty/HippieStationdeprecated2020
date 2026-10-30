// Idle atmos machines: vents, scrubbers, tank sensors and shut canisters with nothing to do stop being run every
// atmos tick.
//
// A vent in a full room or a scrubber over clean air spends every tick finding out it has nothing to do. Instead its
// process_atmos() returns ATMOS_IDLE, and SSair skips it until its turf's air changes, its settings change
// (atmos_wake()), or ATMOS_IDLE_RECHECK ticks go by. The last one is a backstop for anything that changes a machine
// without waking it, like an admin editing its vars.
//
// A turf's air counts as changed when the tile engine changes it or anything calls add_to_active() on it, which is
// what code that changes a turf's air already does. Only while the tile engine runs turfs: LINDA doesn't keep track.

/atom
	/// SSair's times_fired when this turf's air last changed (see idle_machines.dm). Only turfs set it; it's on /atom so
	/// a machine that ends up inside something, like a canister in a mech, reads 0.
	var/air_changed_at = 0

/obj/machinery
	/// SSair's times_fired when process_atmos() last said there was nothing to do, or 0 if it runs every tick
	var/atmos_idle_since = 0

/// Has SSair run process_atmos() again from the next atmos tick, for when the machine's settings change
/obj/machinery/proc/atmos_wake()
	atmos_idle_since = 0
