#define PIPE_RUPTURE_TEMPERATURE (T0C + 900) // a pipe network won't fail just from routine hot plasma; this needs something actually burning inside it
#define PIPE_RUPTURE_PRESSURE (ONE_ATMOSPHERE * 45) // for reference, a full canister is rated to 90 atmospheres; a pipe is built lighter than that
#define PIPE_RUPTURE_VENT_FRACTION 0.6 // how much of the network's air escapes through the breach, the rest stays in what's left of the network
#define PIPE_RUPTURE_COOLDOWN 20 // deciseconds between ruptures on the same network, so one spike doesn't blow out several segments on consecutive ticks

/**
  * A pipe network already reacts its gas exactly like open air does (see /datum/pipeline/process(), which calls air.react()),
  * so plasma and oxygen mixed in a pipe already ignite the normal way once something heats the mix past the plasma fire's own
  * threshold. What was missing is any consequence for the pipe itself: nothing stopped a pipe from quietly holding a raging
  * fire forever no matter how hot or pressurized it got inside. This adds a genuine failure point: once a network's gas gets
  * dangerously hot AND dangerously pressurized, one of its segments gives way, the gas violently vents into the room, and the
  * escaping gas immediately gets a fiery_explosion() of its own, since gas hot enough to blow out a pipe is more than hot
  * enough to keep burning once it's out in the open.
  */
/datum/pipeline
	var/last_rupture = 0

/datum/pipeline/process()
	. = ..()
	if(!air || !members.len || world.time < last_rupture + PIPE_RUPTURE_COOLDOWN)
		return
	if(air.temperature < PIPE_RUPTURE_TEMPERATURE || air.return_pressure() < PIPE_RUPTURE_PRESSURE)
		return
	rupture()

/// Blows out one random segment of the network, vents a share of its air there, and sets it properly alight.
/datum/pipeline/proc/rupture()
	var/obj/machinery/atmospherics/pipe/weak_point = pick(members)
	var/turf/T = get_turf(weak_point)
	if(!T)
		return
	last_rupture = world.time

	var/datum/gas_mixture/vented = air.remove_ratio(PIPE_RUPTURE_VENT_FRACTION)
	var/summary = "[round(vented.temperature)]K, [round(vented.return_pressure())]kPa"
	log_game("A pipe ruptured from internal combustion at [AREACOORD(T)] ([summary]).")
	message_admins("A pipe ruptured from internal combustion at [ADMIN_VERBOSEJMP(T)] ([summary]).")

	T.assume_air(vented)
	SSair.add_to_active(T)
	playsound(T, 'sound/effects/explosion1.ogg', 60, TRUE)
	// Break the segment before the blast: the explosion usually destroys it first, and damaging a deleted pipe runtimes.
	weak_point.take_damage(weak_point.max_integrity, BRUTE, "bomb", FALSE) // the segment itself fails; the network rebuilds around the gap
	fiery_explosion(T, range = 4, power = 2) // the vented gas is already burning-hot; this sets it properly alight and gives it a small blast wave
