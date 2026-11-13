// Realistic explosions: how one looks and sounds (see blast_air.dm). Kept subtle.
//  - The flash is at once; the bang and the shake come at the speed of sound. A tile is about 2 m, so 60 tiles off it's a third of a
//    second after the light.
//  - Walls in the way muffle it. Through one the crack comes dulled; through two or more it's the distant rumble, quieter the more
//    there are. Walls are counted along the straight line, as where the air can't get through.
//  - Nothing carries it through vacuum. A bomb touching the station is still felt through the hull, as a thud and a shake, by anyone
//    standing on the station near it.
//  - Close to it, without ear protection, the ears ring and everything sounds dull for a while (blast_dulled_until, playsound_local()).
//  - A flash of light, and dust that hangs in the room it went off in and settles (none in vacuum, where there's no air to hold it).
//
// Piles of bombs: each listener hears explosions this close together as one, and flashes and dust near one another are merged.

/// Deciseconds a tile of distance holds the sound back: 2 m at 343 m/s
#define BLAST_SOUND_DS_PER_TILE 0.06
/// Deciseconds within which one listener hears two explosions as one
#define BLAST_SOUND_MERGE 3
/// The most walls counted between a blast and a listener
#define BLAST_WALLS_MAX 4
/// How long dust hangs, in deciseconds
#define BLAST_DUST_TIME 150
/// The most dust clouds an explosion leaves, and the most at once anywhere
#define BLAST_DUST_CLOUDS 10
#define BLAST_DUST_CLOUDS_MAX 80

/// Until when this mob's hearing is dulled by a blast (world.time)
/mob/var/blast_dulled_until = 0
/// When this mob last heard a blast arrive (world.time), so a pile going off is heard as one
/mob/var/blast_heard_at = -INFINITY

GLOBAL_LIST_EMPTY(blast_flashes)
GLOBAL_VAR_INIT(blast_dust_clouds, 0)

/// The echo settings of a sound heard through walls: `occlusion` in millibels, negative. Low frequencies get through at a quarter of it.
/proc/blast_muffle_echo(occlusion)
	return list(0, 0, -10000, -10000, 0, 0, occlusion, 0.25, 1.5, 1.0, 0, 1.0, 0, 0, 0, 0, 1.0, 7)

/// Whether air can get from turf `a` to turf `b` next to it (diagonally too, by either side)
/proc/blast_air_joins(turf/a, turf/b)
	var/list/a_joins = a.atmos_adjacent_turfs
	if(!a_joins)
		return FALSE
	if(a.x == b.x || a.y == b.y)
		return a_joins[b] ? TRUE : FALSE
	var/turf/side = locate(b.x, a.y, a.z)
	if(side && a_joins[side] && side.atmos_adjacent_turfs && side.atmos_adjacent_turfs[b])
		return TRUE
	side = locate(a.x, b.y, a.z)
	if(side && a_joins[side] && side.atmos_adjacent_turfs && side.atmos_adjacent_turfs[b])
		return TRUE
	return FALSE

/// How many walls (anything air can't get through) are on the straight line between two turfs, up to `most`. A thick wall counts once.
/proc/blast_walls_between(turf/from, turf/dest, most = BLAST_WALLS_MAX)
	var/walls = 0
	var/blocked = FALSE
	var/turf/at = from
	var/steps = 0
	while(at != dest && steps++ < 150)
		var/turf/next = get_step_towards(at, dest)
		if(!next)
			break
		if(blast_air_joins(at, next))
			blocked = FALSE
		else if(!blocked)
			blocked = TRUE
			walls++
			if(walls >= most)
				break
		at = next
	return walls

/// Whether a bomb in vacuum is touching the station, so the hull carries it
/proc/blast_touches_structure(turf/epicenter)
	if(!isspaceturf(epicenter))
		return TRUE
	for(var/turf/T in range(1, epicenter))
		if(!isspaceturf(T))
			return TRUE
	return FALSE

/// How well the air on a turf carries sound to an ear, as playsound_local() works it out
/proc/blast_sound_air(turf/T)
	if(!T || isspaceturf(T))
		return 0
	var/datum/gas_mixture/air = T.return_air()
	if(!air)
		return 0
	var/pressure = air.return_pressure()
	if(pressure >= ONE_ATMOSPHERE)
		return 1
	return max((pressure - SOUND_MINIMUM_PRESSURE) / (ONE_ATMOSPHERE - SOUND_MINIMUM_PRESSURE), 0)

/// Sends each player who can hear it the bang, when it reaches them. Called from explode() in place of its own sounds.
/proc/blast_sounds(turf/epicenter, list/real, list/raw_ranges, max_range, max_distance)
	var/air = real[6]
	var/touching = air <= 0 && blast_touches_structure(epicenter)
	if(air <= 0 && !touching)
		return //a bomb out in space: nothing carries it anywhere
	var/far_dist = raw_ranges[2] * 5 + raw_ranges[1] * 20
	var/near_dist = round(max_range + world.view - 2, 1)
	var/hear_dist = max(near_dist, far_dist)
	var/source_air = touching ? 1 : blast_sound_air(epicenter) //as it is now: by the time the sound arrives the epicenter may be open to space
	var/near_file = get_sfx("explosion")
	var/frequency = get_rand_frequency()
	var/ring_dist = air > 0 ? real[3] : 0
	for(var/mob/M as anything in GLOB.player_list)
		if(!M.client)
			continue
		var/turf/T = get_turf(M)
		if(!T || T.z != epicenter.z)
			continue
		var/dist = get_dist(T, epicenter)
		if(dist > hear_dist)
			continue
		var/delay = dist * BLAST_SOUND_DS_PER_TILE
		if(M.blast_heard_at + BLAST_SOUND_MERGE > world.time + delay)
			continue
		M.blast_heard_at = world.time + delay
		var/walls = touching ? BLAST_WALLS_MAX : blast_walls_between(epicenter, T)
		if(delay < world.tick_lag)
			blast_hear(M, epicenter, dist, walls, dist <= near_dist, far_dist, max_distance, near_file, frequency, source_air, touching, ring_dist)
		else
			addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(blast_hear), M, epicenter, dist, walls, dist <= near_dist, far_dist, max_distance, near_file, frequency, source_air, touching, ring_dist), delay)

/// The bang reaching one player
/proc/blast_hear(mob/M, turf/epicenter, dist, walls, near, far_dist, max_distance, near_file, frequency, source_air, touching, ring_dist)
	if(QDELETED(M) || !M.client)
		return
	var/turf/T = get_turf(M)
	if(!T)
		return
	var/base_shake = max_distance > dist ? sqrt((max_distance - dist) * 0.1) : 0
	var/file = 'sound/effects/explosionfar.ogg'
	var/volume
	var/occlusion = 0
	var/shake_time = 10
	var/shake = 0
	var/hearing
	if(touching) //through the hull: felt by anyone standing on the station, in air or not
		if(isspaceturf(T))
			return
		hearing = 1
		volume = 45 * clamp(1 - dist / max(far_dist, 1), 0.25, 1)
		occlusion = -3000
		shake = clamp(base_shake * 0.35, 0, 3)
	else
		hearing = min(source_air, blast_sound_air(T))
		if(near)
			if(!walls)
				file = near_file
				volume = 100
				shake_time = 25
				shake = clamp(base_shake, 0, 10)
			else if(walls == 1)
				file = near_file
				volume = 80
				occlusion = -1500
				shake_time = 25
				shake = clamp(base_shake * 0.75, 0, 7)
			else
				volume = max(75 - 12 * (walls - 2), 35)
				occlusion = -2500
				shake_time = 15
				shake = clamp(base_shake * 0.5, 0, 5)
		else
			volume = clamp(far_dist, 30, 50) + (dist <= far_dist * 0.5 ? 50 : 0)
			volume *= 1 - 0.12 * walls
			occlusion = -700 * walls
			shake = clamp(base_shake * 0.25, 0, 2.5)
	volume *= hearing
	if(volume >= SOUND_AUDIBLE_VOLUME_MIN)
		var/sound/S = sound(file)
		if(occlusion)
			S.echo = blast_muffle_echo(occlusion)
		M.playsound_local(epicenter, null, volume, TRUE, frequency, falloff = 5, pressure_affected = FALSE, S = S)
	if(!isliving(M))
		return
	if(shake > 0)
		shake_camera(M, shake_time, shake)
	if(ring_dist && dist < ring_dist && walls < 2 && hearing > 0)
		blast_ring_ears(M, 1 - dist / ring_dist)

/// A close blast: the ears ring, and everything sounds dull for a while. `closeness` is 1 at the middle to 0 at the edge.
/proc/blast_ring_ears(mob/living/L, closeness)
	if(HAS_TRAIT(L, TRAIT_DEAF) || !L.can_hear())
		return
	if(L.get_ear_protection() >= 1)
		return
	var/duration = (8 + 25 * closeness) SECONDS
	L.blast_dulled_until = max(L.blast_dulled_until, world.time + duration)
	var/sound/ring = sound('sound/weapons/flash_ring.ogg')
	ring.volume = 20 + 45 * closeness
	SEND_SOUND(L, ring)
	if(closeness > 0.3)
		to_chat(L, "<span class='warning'>Your ears are ringing.</span>")

/// The flash and the dust. Called from explode().
/proc/blast_sights(turf/epicenter, list/real, list/raw_ranges)
	var/size = max(raw_ranges[1], raw_ranges[2], raw_ranges[3])
	if(size < 1)
		return
	var/air = real[6]
	// the flash: the products glow in vacuum too, though they're gone quicker
	var/flash_range = clamp(2 + size * (air > 0 ? 0.6 : 0.4), 3, 9)
	var/merged = FALSE
	for(var/obj/effect/temp_visual/blast_flash/F as anything in GLOB.blast_flashes)
		if(F.z == epicenter.z && get_dist(F, epicenter) <= 4)
			merged = TRUE
			break
	if(!merged)
		new /obj/effect/temp_visual/blast_flash(epicenter, flash_range)
	// the dust, in the room it went off in, round the middle
	var/list/room = real[9]
	if(air <= 0 || !length(room))
		return
	var/radius = clamp(max(real[1], real[2]) + 1, 1, 6)
	var/list/near = list()
	for(var/turf/open/T as anything in room)
		if(isspaceturf(T))
			continue
		var/d = get_dist(T, epicenter)
		if(d > radius)
			break //nearest first, so the rest are further
		near += T
	if(!length(near))
		return
	var/clouds = min(BLAST_DUST_CLOUDS, BLAST_DUST_CLOUDS_MAX - GLOB.blast_dust_clouds, length(near))
	if(clouds <= 0)
		return
	var/stride = length(near) / clouds
	for(var/i in 0 to clouds - 1)
		var/turf/T = near[round(i * stride) + 1]
		if(locate(/obj/effect/particle_fx/blast_dust) in T)
			continue
		new /obj/effect/particle_fx/blast_dust(T)

/obj/effect/temp_visual/blast_flash
	icon = null
	icon_state = null
	randomdir = FALSE
	duration = 7

/obj/effect/temp_visual/blast_flash/Initialize(mapload, flash_range = 4)
	. = ..()
	GLOB.blast_flashes += src
	set_light(flash_range, 3, "#ffdcaa")
	addtimer(CALLBACK(src, PROC_REF(dim), flash_range * 0.65, 1.6), 2)
	addtimer(CALLBACK(src, PROC_REF(dim), flash_range * 0.35, 0.7), 4)

/obj/effect/temp_visual/blast_flash/proc/dim(flash_range, power)
	set_light(flash_range, power)

/obj/effect/temp_visual/blast_flash/Destroy()
	GLOB.blast_flashes -= src
	return ..()

/// Dust from a blast hanging in the air and settling. Its particles are its own, so it can stop making them once they're out.
/obj/effect/particle_fx/blast_dust
	burst_time = BLAST_DUST_TIME

/obj/effect/particle_fx/blast_dust/Initialize(mapload)
	. = ..()
	GLOB.blast_dust_clouds++
	particles = new /particles/blast_dust
	addtimer(CALLBACK(src, PROC_REF(stop)), 2)
	QDEL_IN(src, burst_time)

/obj/effect/particle_fx/blast_dust/proc/stop()
	if(particles)
		particles.spawning = 0

/obj/effect/particle_fx/blast_dust/Destroy()
	GLOB.blast_dust_clouds--
	particles = null
	return ..()

/particles/blast_dust
	icon = 'hippiestation/icons/effects/particle_fx.dmi'
	icon_state = "puff"
	width = 224
	height = 224
	count = 9
	spawning = 9
	lifespan = generator("num", 80, 140)
	fadein = 8
	fade = 60
	position = generator("circle", 0, 14)
	velocity = generator("circle", 0.1, 0.45)
	drift = generator("vector", list(-0.015, -0.015), list(0.015, 0.015))
	friction = 0.03
	color = "#a49d9268"
	scale = generator("vector", list(0.9, 0.9), list(1.4, 1.4))
	grow = 0.006

#undef BLAST_SOUND_DS_PER_TILE
#undef BLAST_SOUND_MERGE
#undef BLAST_WALLS_MAX
#undef BLAST_DUST_TIME
#undef BLAST_DUST_CLOUDS
#undef BLAST_DUST_CLOUDS_MAX
