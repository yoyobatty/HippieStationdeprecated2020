// Throwing (the user's ask, 2026-11-13: "improving object throwing"). This file is how a throw looks and lands; throw_skill.dm is how
// well somebody throws, and the toss.
//  - Thrown things glide as fast as they fly. Glide was left at a walking pace (8 pixels a tick), so anything thrown at 2 tiles a
//    tenth of a second got halfway to the next tile, jumped the rest, then sat: it stuttered across the room.
//  - A thrown item rises and falls a few pixels, more for a longer throw and more again for a gentle toss, and spins the whole way,
//    not once at the start. It's drawn over people while it's in the air. It ends up as it was, landed or caught.
//  - Something light thrown hard at a wall can rebound a tile, and a throw is heard landing: a tap, a thud or a clatter by its size.
//
// World param throw-realism=off for throws as they were (throw_skill.dm too).

GLOBAL_VAR_INIT(throw_realism, world.params["throw-realism"] != "off")

/// Past this many thrown items starting in a tick (a blast throwing a room's worth), the rest only glide and spin as before
#define THROW_FLIGHTS_PER_TICK 40
/// Pixels a thrown item rises at most, and the rise per tile of the throw
#define THROW_ARC_MAX 12
#define THROW_ARC_PER_TILE 1.5
/// How much higher a toss goes
#define THROW_TOSS_ARC 1.7
/// Deciseconds a thrown item takes to turn over once
#define THROW_SPIN_TIME 2.5
/// Landing sounds a second, all told: a crate of things thrown about shouldn't be a din
#define THROW_LAND_SOUNDS_PER_SECOND 6

/// Things that roll or slide along the floor when they're thrown, rather than fly
GLOBAL_LIST_INIT(throw_rolls, typecacheof(list(/obj/item/bowling, /obj/item/holopuck)))

GLOBAL_VAR_INIT(throw_flight_tick, -1)
GLOBAL_VAR_INIT(throw_flight_count, 0)
GLOBAL_VAR_INIT(throw_land_sound_window, -INFINITY)
GLOBAL_VAR_INIT(throw_land_sound_count, 0)

/datum/thrownthing
	/// A gentle toss: no harm done, and whoever it's for can catch it (throw_skill.dm)
	var/gentle = FALSE
	/// What the thing's glide was before it was thrown, to put back
	var/old_glide
	/// TRUE when start_flight() is drawing this one's arc and spin, with what to put back after
	var/flying = FALSE
	var/matrix/flight_transform
	var/flight_pixel_z
	var/flight_layer

/// Pixels a tick to glide at `speed` tiles a decisecond. Rounded so a glide finishes before the next step: at 3 tiles a decisecond the
/// steps come one tick apart three times in four, and a slower glide would be cut short and jump.
/proc/throw_glide_size(speed)
	var/ticks_a_tile = 1 / max(speed * world.tick_lag, 0.01)
	return world.icon_size / max(round(ticks_a_tile + 0.001), 1)

/// The nearest speed to `speed` that takes a whole number of ticks a tile, so every step comes the same time after the last and the
/// glide meets it exactly (1.5 tiles a decisecond at 40 ticks a second is a step 2, 3, 3, 2... ticks apart)
/proc/throw_even_speed(speed)
	var/ticks_a_tile = max(round(1 / max(speed * world.tick_lag, 0.01), 1), 1)
	return 1 / (ticks_a_tile * world.tick_lag)

/// Sets a thrown thing up to fly: its glide, and for an item its arc and spin. Called from throw_at(). Returns TRUE if it's seen to
/// the spin, FALSE to leave throw_at() its own.
/datum/thrownthing/proc/start_flight(spin)
	var/atom/movable/AM = thrownthing
	// thrown again while it was still flying (a blast catching it mid-air): what to put back is what the first throw kept
	var/datum/thrownthing/before = SSthrowing.processing[AM]
	if(before && before != src && !QDELETED(before))
		old_glide = before.old_glide
		before.old_glide = null
		if(before.flying)
			before.flying = FALSE
			flight_transform = before.flight_transform
			flight_pixel_z = before.flight_pixel_z
			flight_layer = before.flight_layer
	if(isnull(old_glide))
		old_glide = AM.glide_size
	AM.set_glide_size(throw_glide_size(speed))
	if(!isitem(AM) || !isturf(AM.loc) || is_type_in_typecache(AM, GLOB.throw_rolls))
		return restore_flight_look() //nothing flying: just the glide
	if(GLOB.throw_flight_tick != world.time)
		GLOB.throw_flight_tick = world.time
		GLOB.throw_flight_count = 0
	if(++GLOB.throw_flight_count > THROW_FLIGHTS_PER_TICK)
		return restore_flight_look()
	var/tiles = maxrange
	if(target_turf && target_turf.z == AM.z)
		tiles = min(tiles, get_dist(AM, target_turf))
	tiles = max(tiles, 1)
	var/flight_time = max(tiles / speed, world.tick_lag * 2)
	if(isnull(flight_layer))
		flight_transform = AM.transform
		flight_pixel_z = AM.pixel_z
		flight_layer = AM.layer
	flying = TRUE
	AM.layer = ABOVE_MOB_LAYER //in the air: drawn over people
	if(AM.has_gravity(AM.loc))
		var/height = min(2 + tiles * THROW_ARC_PER_TILE, THROW_ARC_MAX)
		if(gentle)
			height *= THROW_TOSS_ARC
		animate(AM, pixel_z = flight_pixel_z + height, time = flight_time / 2, easing = SINE_EASING | EASE_OUT, flags = ANIMATION_PARALLEL)
		animate(pixel_z = flight_pixel_z, time = flight_time / 2, easing = SINE_EASING | EASE_IN)
	if(spin)
		var/turns = clamp(round(flight_time / THROW_SPIN_TIME), 1, 4)
		AM.SpinAnimation(flight_time / turns, turns, pick(TRUE, FALSE))
	return TRUE

/// A throw that won't fly (a ball rolling, or past the tick's share) after one that did, caught mid-air: the first one's look put
/// back. Returns FALSE, for throw_at() to spin it as before.
/datum/thrownthing/proc/restore_flight_look()
	if(isnull(flight_layer))
		return FALSE
	var/atom/movable/AM = thrownthing
	animate(AM, transform = flight_transform, pixel_z = flight_pixel_z, time = 0)
	if(AM.layer == ABOVE_MOB_LAYER)
		AM.layer = flight_layer
	flight_layer = null
	return FALSE

/// The throw's over: put its glide back, settle an item that flew, and give it a landing. Called from finalize().
/datum/thrownthing/proc/end_flight(hit, atom/hit_target)
	var/atom/movable/AM = thrownthing
	if(QDELETED(AM))
		return
	if(!isnull(old_glide))
		AM.set_glide_size(old_glide)
	if(!flying)
		return
	var/on_floor = isturf(AM.loc)
	//one animation, not parallel: it ends the arc and the spin wherever they'd got to
	animate(AM, transform = flight_transform, pixel_z = flight_pixel_z, time = on_floor ? 1 : 0, easing = SINE_EASING)
	if(AM.layer == ABOVE_MOB_LAYER) //caught, it's had its layer set in the hand
		AM.layer = flight_layer
	if(!on_floor || !GLOB.throw_realism)
		return
	var/obj/item/I = AM
	var/hit_hard = hit && hit_target && !ismob(hit_target) && (isclosedturf(hit_target) || (isobj(hit_target) && hit_target.density))
	if(hit_hard && !gentle && I.w_class <= WEIGHT_CLASS_NORMAL && speed >= 1.5 && AM.has_gravity(AM.loc) && prob(50))
		rebound()
	if(ismob(thrower) && !(hit_target && ismob(hit_target)))
		landing_sound(hit_hard)

/// Off the wall a tile, the way it came
/datum/thrownthing/proc/rebound()
	var/atom/movable/AM = thrownthing
	var/turf/back = get_step(AM, turn(init_dir, 180))
	if(!back || back.density)
		return
	AM.set_glide_size(world.icon_size / 3)
	if(!AM.Move(back, get_dir(AM, back)))
		return
	animate(AM, pixel_z = flight_pixel_z + 3, time = 1, easing = SINE_EASING | EASE_OUT)
	animate(pixel_z = flight_pixel_z, time = 1, easing = SINE_EASING | EASE_IN)
	AM.set_glide_size(old_glide)

/// A tap, a thud or a clatter as it comes down, by its size: off a wall, or onto the floor for anything bigger than small
/datum/thrownthing/proc/landing_sound(hit_hard)
	var/obj/item/I = thrownthing
	var/soundin
	var/volume
	if(hit_hard)
		switch(I.w_class)
			if(0 to WEIGHT_CLASS_SMALL)
				soundin = 'sound/weapons/throwtap.ogg'
				volume = 25
			if(WEIGHT_CLASS_NORMAL)
				soundin = 'sound/weapons/genhit.ogg'
				volume = 30
			else
				soundin = 'sound/weapons/genhit3.ogg'
				volume = 40
	else
		switch(I.w_class)
			if(0 to WEIGHT_CLASS_TINY)
				return
			if(WEIGHT_CLASS_SMALL)
				soundin = 'sound/weapons/throwtap.ogg'
				volume = 15
			if(WEIGHT_CLASS_NORMAL)
				soundin = 'sound/weapons/genhit1.ogg'
				volume = 20
			else
				soundin = 'sound/weapons/genhit2.ogg'
				volume = 30
	if(gentle)
		volume *= 0.5
	if(world.time >= GLOB.throw_land_sound_window + 1 SECONDS)
		GLOB.throw_land_sound_window = world.time
		GLOB.throw_land_sound_count = 0
	if(++GLOB.throw_land_sound_count > THROW_LAND_SOUNDS_PER_SECOND)
		return
	playsound(I, soundin, volume, TRUE, -2)

#undef THROW_FLIGHTS_PER_TICK
#undef THROW_ARC_MAX
#undef THROW_ARC_PER_TILE
#undef THROW_TOSS_ARC
#undef THROW_SPIN_TIME
#undef THROW_LAND_SOUNDS_PER_SECOND
