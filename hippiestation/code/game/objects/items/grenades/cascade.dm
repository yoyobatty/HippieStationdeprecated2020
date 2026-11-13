// Cascade grenades (prototypes, admin spawn only). Each one sets off more than itself, further out, so what it does walks out
// over a far wider area than one bomb under the cap could reach. Three ways of spreading:
//  tree    the grenade lobs live charges over the walls all round it; each of those, where it lands, lobs more outward, and so on.
//          A whole chain shares one budget of charges, so it always ends
//  rings   rings rolling outward from the middle, one every few tiles, a third of a second apart
//  single  one thing, done big
// and what each charge, or each point on a ring, does is its payload (/datum/cascade_payload): a blast, a cloud of reagents,
// fire, lightning, a bang, cold, radiation, shrapnel, or any of those at random.
// A lobbed charge is a real item once it lands: it can be picked up and thrown back, and a blast reaching it sets it off early.
//
//  cascade charge   tree of blasts, ~22 tiles
//  firestorm        tree of blasts, each leaving burning plasma that carries on through the air
//  shockwave        rings of blasts out to 20 tiles
//  acid rain        tree of fluorosulphuric acid clouds that eat the doors and windows round them and get past them
//  hellfire         tree of chlorine trifluoride and phlogiston clouds: everything in them burns, floors included
//  storm cell       tree of lightning: teslium clouds, then arcs that jump person to person and blow up machines, and EMPs
//  thunderclap      rings of flashbangs: everyone in sight down and deaf
//  hammer           a thunderclap, then a cascade charge while they're all on the floor
//  deep freeze      rings of nanofrost: the air in them near absolute zero, vents frozen shut, the floor ice
//  dirty cascade    tree of radiation pulses and polonium clouds
//  flechette        tree of blasts that each fire a ring of fragmentation pellets
//  nerve cascade    tree of sarin clouds that get past shut doors
//  fuel-air charge  one huge cloud of pyrovapour, past shut doors too, lit three seconds later: every tile of it goes off, then burns
//  implosion        drags everything within 12 tiles into the middle for four seconds, tearing at doors and windows in the way, then goes off on the pile
//  seeker           tree of blasts whose charges are lobbed at the people nearest, one each
//  pandemonium      tree where every charge is a different one of the above

#define CASCADE_TREE 1
#define CASCADE_RINGS 2
#define CASCADE_SINGLE 3

// A pile of these sets itself off: every blast reaches the grenades still lying there. 2026-11-13, ~430 of them on one tile: each
// started its own chain of 40-100 payloads, thousands of blasts and clouds on the same few tiles, and the clouds' vapour flooded
// the timers. So:
/// at most this many grenades start their chains (or rings) in this long; the rest only go off where they are
#define CASCADE_CHAIN_WINDOW (10 SECONDS)
#define CASCADE_MAX_CHAINS 16
/// at most this many payloads on one tile in this long; a grenade past that adds to one bigger blast there instead (cascade_pile_boom())
#define CASCADE_TURF_WINDOW (5 SECONDS)
#define CASCADE_TURF_HITS 3

/// world.time each recent chain started
GLOBAL_LIST_EMPTY(cascade_chain_starts)
/// turf = payloads on it since cascade_turf_window
GLOBAL_LIST_EMPTY(cascade_turf_hits)
GLOBAL_VAR_INIT(cascade_turf_window, 0)
/// turf = grenades that went off there past the limit, waiting for cascade_pile_boom()
GLOBAL_LIST_EMPTY(cascade_pile_extra)

/// Whether another chain may start now, counting it if so.
/proc/cascade_chain_slot()
	var/list/starts = GLOB.cascade_chain_starts
	while(length(starts) && starts[1] < world.time - CASCADE_CHAIN_WINDOW)
		starts.Cut(1, 2)
	if(length(starts) >= CASCADE_MAX_CHAINS)
		return FALSE
	starts += world.time
	return TRUE

/// Counts a payload on `T`; TRUE if it's had its fill lately.
/proc/cascade_turf_full(turf/T)
	if(world.time - GLOB.cascade_turf_window > CASCADE_TURF_WINDOW)
		GLOB.cascade_turf_hits = list()
		GLOB.cascade_turf_window = world.time
	var/n = GLOB.cascade_turf_hits[T] + 1
	GLOB.cascade_turf_hits[T] = n
	return n > CASCADE_TURF_HITS

/// A grenade went off on a tile that's had its fill: half a second on, the lot go off as one blast, bigger the more there were
/// (30 make a 1/2/6, 75 or more the cap).
/proc/cascade_pile_add(turf/T)
	var/n = GLOB.cascade_pile_extra[T]
	GLOB.cascade_pile_extra[T] = n + 1
	if(!n)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(cascade_pile_boom), T), 5)

/proc/cascade_pile_boom(turf/T)
	var/n = GLOB.cascade_pile_extra[T]
	GLOB.cascade_pile_extra -= T
	if(!n)
		return
	explosion(T, min(GLOB.MAX_EX_DEVESTATION_RANGE, round(n / 25)), min(GLOB.MAX_EX_HEAVY_RANGE, round(n / 10)), min(GLOB.MAX_EX_LIGHT_RANGE, round(n / 5)), \
		flame_range = min(GLOB.MAX_EX_LIGHT_RANGE, round(n / 5)), adminlog = FALSE)

/// One whole chain: what it does, how many charges are still to come, and where it started.
/datum/cascade_chain
	var/turf/origin
	/// charges that may still be set off, the grenade itself not counted
	var/budget = 0
	var/detonations = 0
	/// last set-off fingerprints of the grenade, so every blast in the chain is put down to whoever primed it
	var/fingerprintslast
	var/datum/cascade_payload/payload
	/// REF(mob) = TRUE for everyone a seeker has already sent a charge at
	var/list/targeted

/datum/cascade_chain/New(turf/origin, budget, fingerprintslast, payload_type)
	src.origin = origin
	src.budget = budget
	src.fingerprintslast = fingerprintslast
	payload = new payload_type

/// The payload at `T`, unless the tile's had its fill (a grenade's own there adds to the pile's blast instead).
/datum/cascade_chain/proc/hit(turf/T, generation, quiet, grenade = FALSE)
	if(cascade_turf_full(T))
		if(grenade)
			cascade_pile_add(T)
		return
	detonations++
	payload.hit(T, generation, src, quiet)

/// A ring of payloads `radius` tiles round `center`, about `spacing` tiles apart. Only every fourth one makes a sound or shakes
/// the screen, so a ring is heard where it is without forty sounds at once.
/datum/cascade_chain/proc/ring(turf/center, radius, spacing, generation)
	var/count = min(max(6, CEILING(2 * PI * radius / spacing, 1)), budget)
	if(count <= 0)
		return
	budget -= count
	var/offset = rand(0, 359)
	for(var/i in 1 to count)
		var/angle = offset + i * 360 / count
		var/turf/T = locate(center.x + round(radius * cos(angle)), center.y + round(radius * sin(angle)), center.z)
		if(!T)
			continue
		hit(T, generation, i % 4 != 1)

/// A followup grenade, primed where the first went off.
/proc/cascade_followup(turf/T, grenade_type, fingerprintslast)
	var/obj/item/grenade/cascade/G = new grenade_type(T)
	G.fingerprintslast = fingerprintslast
	G.prime()

// Payloads: what goes off at each charge, or each point on a ring

/datum/cascade_payload
	/// the blast by generation (the grenade itself first), list(devastation, heavy, light, flame); past the end, the last one.
	/// Empty for no blast
	var/list/blasts = list(list(1, 3, 6, 0), list(1, 2, 4, 0), list(0, 2, 4, 0), list(0, 1, 3, 0))
	/// reagents let out as smoke, type = units on every tile it reaches
	var/list/cloud
	var/cloud_radius = 3
	/// the cloud also gets past up to this many shut doors and windows within cloud_radius, a smaller cloud starting beyond each:
	/// smoke spreads only through open air, so a closed door kept a cloud to one room
	var/seep_doors = 0
	/// damage (acid) to the doors, windows and grilles within cloud_radius
	var/corrode = 0

/datum/cascade_payload/proc/hit(turf/T, generation, datum/cascade_chain/chain, quiet)
	if(length(cloud))
		smoke(T, cloud, cloud_radius)
		if(seep_doors || corrode)
			seep(T)
	if(length(blasts))
		var/list/B = blasts[min(generation + 1, length(blasts))]
		explosion(T, B[1], B[2], B[3], flash_range = B[1], adminlog = FALSE, flame_range = B[4], silent = quiet)

/datum/cascade_payload/proc/smoke(turf/T, list/contents, radius)
	var/datum/effect_system/smoke_spread/chem/S = new
	for(var/R in contents)
		S.chemholder.reagents.add_reagent(R, contents[R])
	S.location = T
	S.amount = radius
	S.start()
	qdel(S)

/// The cloud past what holds it in: acid on the doors, windows and grilles round it, and a smaller cloud beyond each of up to
/// seep_doors of them that's still shut.
/datum/cascade_payload/proc/seep(turf/T)
	var/seeped = 0
	for(var/obj/O in range(cloud_radius, T))
		if(!O.density || !(istype(O, /obj/machinery/door) || istype(O, /obj/structure/window) || istype(O, /obj/structure/grille)))
			continue
		if(corrode)
			O.take_damage(corrode, BRUTE, "acid", FALSE)
		if(QDELETED(O) || !O.density || seeped >= seep_doors)
			continue
		seeped++
		for(var/d in GLOB.cardinals)
			var/turf/open/beyond = get_step(O, d)
			if(istype(beyond) && !beyond.density && !(locate(/obj/effect/particle_effect/smoke) in beyond))
				smoke(beyond, cloud, max(1, round(cloud_radius / 2)))

/datum/cascade_payload/firestorm
	blasts = list(list(0, 2, 4, 4), list(0, 1, 3, 3), list(0, 1, 3, 3), list(0, 1, 2, 2))
	/// gas left where each charge goes off, hot enough to light itself
	var/fire_gas = "plasma=30;o2=15;TEMP=1200"

/datum/cascade_payload/firestorm/hit(turf/T, generation, datum/cascade_chain/chain, quiet)
	..()
	T.atmos_spawn_air(fire_gas)
	T.hotspot_expose(1200, 500)

/datum/cascade_payload/wave
	blasts = list(list(1, 3, 5, 0), list(0, 2, 3, 0))

/datum/cascade_payload/acid
	blasts = list(list(0, 1, 3, 0), list(0, 0, 2, 0))
	cloud = list(/datum/reagent/toxin/acid/fluacid = 40, /datum/reagent/toxin/acid = 20)
	cloud_radius = 3
	seep_doors = 2
	corrode = 150

/datum/cascade_payload/hellfire
	blasts = list(list(0, 1, 3, 3), list(0, 0, 2, 2))
	cloud = list(/datum/reagent/clf3 = 25, /datum/reagent/phlogiston = 25)
	cloud_radius = 2

/datum/cascade_payload/storm
	blasts = list(list(0, 0, 2, 0))
	cloud = list(/datum/reagent/teslium = 20)
	cloud_radius = 2
	var/zap_power = 25000
	var/zap_range = 6

/datum/cascade_payload/storm/hit(turf/T, generation, datum/cascade_chain/chain, quiet)
	..()
	do_sparks(5, TRUE, T)
	empulse(T, 1, 3)
	tesla_zap(T, zap_range, zap_power)
	// a second bolt once the teslium's had a moment to get into them
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(tesla_zap), T, zap_range, zap_power), 1 SECONDS)

/datum/cascade_payload/concussion
	blasts = null
	var/bang_range = 6

/datum/cascade_payload/concussion/hit(turf/T, generation, datum/cascade_chain/chain, quiet)
	do_sparks(rand(3, 6), FALSE, T)
	if(!quiet)
		playsound(T, 'sound/weapons/flashbang.ogg', 100, TRUE, 8, 0.9)
	new /obj/effect/dummy/lighting_obj(T, LIGHT_COLOR_WHITE, bang_range + 2, 4, 2)
	for(var/mob/living/M in get_hearers_in_view(bang_range, T))
		if(M.stat == DEAD)
			continue
		var/d = max(1, get_dist(T, M))
		if(M.flash_act(affect_silicon = 1))
			M.Paralyze(max(120 / d, 40))
		M.soundbang_act(1, max(160 / d, 40), rand(0, 5))
		M.adjustStaminaLoss(60 / d)

/datum/cascade_payload/cryo
	blasts = list(list(0, 0, 2, 0))
	var/chill_radius = 3

/datum/cascade_payload/cryo/hit(turf/T, generation, datum/cascade_chain/chain, quiet)
	..()
	var/datum/effect_system/smoke_spread/freezing/S = new
	S.set_up(2, T, chill_radius)
	S.start()
	qdel(S)
	for(var/turf/open/floor/F in RANGE_TURFS(chill_radius, T))
		F.MakeSlippery(TURF_WET_PERMAFROST, 2 MINUTES)
	for(var/mob/living/L in range(chill_radius, T))
		L.adjust_bodytemperature(-180)

/datum/cascade_payload/rad
	blasts = list(list(0, 1, 3, 0), list(0, 1, 2, 0))
	cloud = list(/datum/reagent/toxin/polonium = 15, /datum/reagent/uranium/radium = 15)
	cloud_radius = 2
	var/pulse = 1500

/datum/cascade_payload/rad/hit(turf/T, generation, datum/cascade_chain/chain, quiet)
	..()
	radiation_pulse(T, pulse)

/datum/cascade_payload/shrapnel
	blasts = list(list(0, 1, 3, 0), list(0, 1, 2, 0))
	var/pellets = 8
	var/pellet_type = /obj/item/projectile/bullet/pellet/frag
	var/pellet_range = 8

/datum/cascade_payload/shrapnel/hit(turf/T, generation, datum/cascade_chain/chain, quiet)
	..()
	var/offset = rand(0, 359)
	for(var/i in 1 to pellets)
		var/obj/item/projectile/P = new pellet_type(T)
		P.range = pellet_range
		P.fire(offset + i * 360 / pellets)

/datum/cascade_payload/nerve
	blasts = list(list(0, 0, 1, 0))
	cloud = list(/datum/reagent/toxin/sarin = 30)
	cloud_radius = 4
	seep_doors = 3

/datum/cascade_payload/vapour
	blasts = null
	cloud = list(/datum/reagent/pyrovapour = 30)
	cloud_radius = 12
	seep_doors = 8
	var/ignite_delay = 3 SECONDS

/datum/cascade_payload/vapour/hit(turf/T, generation, datum/cascade_chain/chain, quiet)
	..()
	addtimer(CALLBACK(src, PROC_REF(ignite), T), ignite_delay)

/datum/cascade_payload/vapour/proc/ignite(turf/T)
	do_sparks(8, TRUE, T)
	for(var/obj/effect/particle_effect/smoke/chem/S in range(1, T))
		if(S.reagents?.has_reagent(/datum/reagent/pyrovapour))
			S.detonate_vapour()
			return
	T.hotspot_expose(1500, 500)

/// Every charge a different payload.
/datum/cascade_payload/chaos
	blasts = null
	var/list/pool

/datum/cascade_payload/chaos/hit(turf/T, generation, datum/cascade_chain/chain, quiet)
	if(!pool)
		pool = list()
		for(var/path in list(/datum/cascade_payload, /datum/cascade_payload/firestorm, /datum/cascade_payload/acid, /datum/cascade_payload/hellfire, \
			/datum/cascade_payload/storm, /datum/cascade_payload/concussion, /datum/cascade_payload/cryo, /datum/cascade_payload/rad, \
			/datum/cascade_payload/shrapnel, /datum/cascade_payload/nerve))
			pool += new path
	var/datum/cascade_payload/P = pick(pool)
	P.hit(T, generation, chain, quiet)

// The grenades

/obj/item/grenade/cascade
	name = "cascade charge"
	desc = "A prototype cluster charge. Each charge it lobs out lobs out more. Do not be anywhere."
	icon_state = "redfrag"
	resistance_flags = FIRE_PROOF //goes off by its own fuse or a blast, not by burning
	var/pattern = CASCADE_TREE
	var/payload_type = /datum/cascade_payload
	var/datum/cascade_chain/chain
	/// 0 for the grenade itself, 1 for the charges it lobs, and so on
	var/generation = 0
	var/detonated = FALSE
	/// a blast reached it and it's going off (ex_act()): it waits on one timer however many more reach it. Each blast used to
	/// add another, and in a pile one grenade could be holding hundreds
	var/blasted = FALSE
	/// whether a blast sets it off. A lobbed charge only arms when it lands: otherwise the blast that threw it catches it in the
	/// air, a few tiles out, and the whole chain goes off in the middle
	var/armed = TRUE
	/// how many charges (or points on rings) a whole chain may set off, the grenade included
	var/budget = 40
	/// tree: how many charges each generation lobs, list[1] the grenade itself, list[2] each of its charges...; past the end, none
	var/list/fan_out = list(6, 3, 2)
	var/fling_min = 4
	var/fling_max = 7
	/// tree: how far either way of straight out a charge goes, in degrees (the grenade itself lobs all round)
	var/fling_spread = 60
	/// tree: charges are lobbed at the living nearest, one each, before anywhere else
	var/seek = FALSE
	var/seek_range = 9
	/// deciseconds from landing to going off
	var/fuse_min = 5
	var/fuse_max = 10
	var/fragment_state = "clusterbang_segment"
	var/fragment_color = "#ff5030"
	/// rings: tiles between rings, and between points on a ring
	var/ring_step = 4
	var/rings = 5
	/// rings: deciseconds between rings
	var/ring_delay = 3
	/// another grenade primed where this one went off, this long after
	var/followup_type
	var/followup_delay = 2.5 SECONDS

/obj/item/grenade/cascade/Destroy()
	chain = null
	return ..()

/obj/item/grenade/cascade/examine(mob/user)
	. = ..()
	if(generation)
		. += "<span class='warning'>It's ticking.</span>"

/obj/item/grenade/cascade/prime()
	if(detonated)
		return
	detonated = TRUE
	update_mob()
	var/turf/T = get_turf(src)
	if(T)
		if(!chain)
			chain = new(T, budget - 1, fingerprintslast, payload_type)
			var/full = cascade_chain_slot()
			log_game("[name] went off at [AREACOORD(T)][blasted ? " in another blast" : ""][full ? "" : " (too many chains going: no charges)"]. Last touched by [fingerprintslast || "nobody"].")
			if(!blasted) // one that went off in a pile's blasts isn't news on its own; the admins heard about the first
				message_admins("[name] went off at [ADMIN_VERBOSEJMP(T)]. Last touched by [fingerprintslast || "nobody"].")
			start_chain(T, full)
		else
			chain.hit(T, generation, FALSE)
			spread_tree(T)
	qdel(src)

/// The grenade's own payload, then (if `full`) its charges or rings and any followup.
/obj/item/grenade/cascade/proc/start_chain(turf/T, full)
	chain.hit(T, 0, FALSE, TRUE)
	if(!full)
		return
	switch(pattern)
		if(CASCADE_TREE)
			spread_tree(T)
		if(CASCADE_RINGS)
			for(var/k in 1 to rings)
				addtimer(CALLBACK(chain, TYPE_PROC_REF(/datum/cascade_chain, ring), T, k * ring_step, ring_step, k), k * ring_delay)
	if(followup_type)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(cascade_followup), T, followup_type, fingerprintslast), followup_delay)

/// A blast reaching a live charge sets it off a moment later, rather than destroying it.
/obj/item/grenade/cascade/ex_act(severity, target)
	if(detonated || !armed || blasted)
		return
	blasted = TRUE
	if(!active)
		active = TRUE
		icon_state = "[icon_state]_active"
	addtimer(CALLBACK(src, PROC_REF(prime)), rand(1, 3))

/// Lobs this generation's charges: all round from the grenade, outward (away from where the chain began) from the charges.
/obj/item/grenade/cascade/proc/spread_tree(turf/T)
	if(generation >= length(fan_out))
		return
	var/count = min(fan_out[generation + 1], chain.budget)
	if(count <= 0)
		return
	chain.budget -= count
	var/list/targets = seek ? seek_targets(T, count) : list()
	var/all_round = !generation || T == chain.origin
	var/base = all_round ? rand(0, 359) : arctan(T.x - chain.origin.x, T.y - chain.origin.y)
	for(var/i in 1 to count)
		var/turf/target
		if(i <= length(targets))
			target = targets[i]
		else
			var/angle
			if(all_round)
				angle = base + i * 360 / count + rand(-15, 15)
			else
				angle = base - fling_spread + (i - 0.5) * (2 * fling_spread) / count + rand(-10, 10)
			var/dist = rand(fling_min, fling_max)
			target = locate(clamp(T.x + round(dist * cos(angle)), 1, world.maxx), clamp(T.y + round(dist * sin(angle)), 1, world.maxy), T.z)
		if(!target)
			continue
		var/obj/item/grenade/cascade/F = new type(T)
		F.become_charge(src)
		var/flight = F.lob(T, target)
		addtimer(CALLBACK(F, PROC_REF(prime)), flight + rand(fuse_min, fuse_max))

/// The turfs of up to `count` living people near `T` no charge of this chain has gone for yet, nearest first.
/obj/item/grenade/cascade/proc/seek_targets(turf/T, count)
	. = list()
	var/list/found = list()
	for(var/mob/living/L in range(seek_range, T))
		if(L.stat == DEAD || LAZYACCESS(chain.targeted, REF(L)))
			continue
		found[L] = get_dist(T, L)
	sortTim(found, GLOBAL_PROC_REF(cmp_numeric_asc), TRUE)
	for(var/mob/living/L as anything in found)
		if(length(.) >= count)
			break
		LAZYSET(chain.targeted, REF(L), TRUE)
		. += get_turf(L)

/// Arcs through the air from `start` to `landing`, over anything in between, and arms on landing. Returns the flight time.
/obj/item/grenade/cascade/proc/lob(turf/start, turf/landing)
	armed = FALSE
	forceMove(landing)
	var/dist = get_dist(start, landing)
	var/flight = max(3, dist)
	pixel_x = (start.x - landing.x) * world.icon_size
	pixel_y = (start.y - landing.y) * world.icon_size
	animate(src, pixel_x = 0, pixel_y = 0, time = flight)
	animate(src, pixel_z = 12 + dist * 4, time = flight / 2, easing = SINE_EASING | EASE_OUT, flags = ANIMATION_PARALLEL)
	animate(pixel_z = 0, time = flight / 2, easing = SINE_EASING | EASE_IN)
	addtimer(CALLBACK(src, PROC_REF(arm)), flight)
	return flight

/obj/item/grenade/cascade/proc/arm()
	armed = TRUE

/obj/item/grenade/cascade/proc/become_charge(obj/item/grenade/cascade/parent)
	chain = parent.chain
	generation = parent.generation + 1
	fingerprintslast = chain.fingerprintslast
	name = "[initial(name)] fragment"
	desc = "A live charge, lobbed out of something worse."
	w_class = WEIGHT_CLASS_TINY
	active = TRUE
	icon_state = "[fragment_state]_active"
	color = fragment_color

/obj/item/grenade/cascade/firestorm
	name = "firestorm charge"
	desc = "A prototype cluster charge. Every charge it lobs out leaves burning plasma where it goes off."
	icon_state = "frag"
	color = "#ffa040"
	payload_type = /datum/cascade_payload/firestorm
	fragment_color = "#ffa020"

/obj/item/grenade/cascade/wave
	name = "shockwave charge"
	desc = "A prototype charge that sets off rings of blasts rolling outward from where it lands."
	icon_state = "large_grenade"
	color = "#80a0ff"
	pattern = CASCADE_RINGS
	payload_type = /datum/cascade_payload/wave
	budget = 100

/obj/item/grenade/cascade/acid
	name = "acid rain charge"
	desc = "A prototype cluster charge. Every charge it lobs out bursts into a cloud of fluorosulphuric acid."
	icon_state = "chemg"
	color = "#90ff40"
	payload_type = /datum/cascade_payload/acid
	fragment_color = "#90ff40"

/obj/item/grenade/cascade/hellfire
	name = "hellfire charge"
	desc = "A prototype cluster charge. Every charge it lobs out bursts into chlorine trifluoride and phlogiston. It burns through floors."
	icon_state = "pyrog"
	payload_type = /datum/cascade_payload/hellfire
	fragment_color = "#ff4000"

/obj/item/grenade/cascade/storm
	name = "storm cell"
	desc = "A prototype cluster charge. Every charge it lobs out lets go teslium and then lightning."
	icon_state = "emp"
	color = "#ffff60"
	payload_type = /datum/cascade_payload/storm
	fragment_color = "#ffff60"

/obj/item/grenade/cascade/thunderclap
	name = "thunderclap"
	desc = "A prototype flashbang that rolls outward in rings."
	icon_state = "flashbang"
	pattern = CASCADE_RINGS
	payload_type = /datum/cascade_payload/concussion
	budget = 100

/obj/item/grenade/cascade/hammer
	name = "hammer and anvil"
	desc = "A prototype two-stage charge: a thunderclap to put everyone on the floor, then a cascade charge while they're there."
	icon_state = "concussion"
	pattern = CASCADE_RINGS
	payload_type = /datum/cascade_payload/concussion
	budget = 100
	followup_type = /obj/item/grenade/cascade

/obj/item/grenade/cascade/deepfreeze
	name = "deep freeze charge"
	desc = "A prototype charge that rolls rings of nanofrost outward. The air it reaches is nearly absolute zero."
	icon_state = "cryog"
	pattern = CASCADE_RINGS
	payload_type = /datum/cascade_payload/cryo
	budget = 100

/obj/item/grenade/cascade/dirty
	name = "dirty cascade"
	desc = "A prototype cluster charge. Every charge it lobs out is a radiation pulse and a cloud of polonium."
	icon_state = "grenade"
	color = "#a0ff60"
	payload_type = /datum/cascade_payload/rad
	fragment_color = "#60ff40"

/obj/item/grenade/cascade/flechette
	name = "flechette cascade"
	desc = "A prototype cluster charge. Every charge it lobs out fires a ring of fragmentation pellets."
	icon_state = "syndicate"
	payload_type = /datum/cascade_payload/shrapnel
	budget = 25
	fan_out = list(6, 3)
	fragment_color = "#c0c0c0"

/obj/item/grenade/cascade/nerve
	name = "nerve cascade"
	desc = "A prototype cluster charge. Every charge it lobs out is a cloud of sarin."
	icon_state = "chemg"
	color = "#b060ff"
	payload_type = /datum/cascade_payload/nerve
	fragment_color = "#b060ff"

/obj/item/grenade/cascade/fuelair
	name = "fuel-air charge"
	desc = "A prototype charge that fills the place with pyrovapour and lights it."
	icon_state = "large_grenade"
	color = "#c8b070"
	pattern = CASCADE_SINGLE
	payload_type = /datum/cascade_payload/vapour

/obj/item/grenade/cascade/implosion
	name = "implosion charge"
	desc = "A prototype charge that drags everything around it into one place, then goes off there."
	icon_state = "timeg"
	color = "#9060ff"
	pattern = CASCADE_SINGLE
	var/pull_range = 12
	var/pulls = 8
	var/pull_delay = 5
	/// each pull tears at the doors, windows, grilles and anything else fixed and solid this near, so the next pulls get more through
	var/shear_range = 7
	var/shear = 60
	var/list/final_blast = list(3, 5, 9, 5)

/obj/item/grenade/cascade/implosion/start_chain(turf/T, full)
	chain.detonations++
	if(!full) // no pull, just the blast
		if(cascade_turf_full(T))
			cascade_pile_add(T)
		else
			explosion(T, final_blast[1], final_blast[2], final_blast[3], final_blast[1], FALSE, FALSE, final_blast[4])
		return
	playsound(T, 'sound/effects/empulse.ogg', 100, TRUE, 10)
	for(var/i in 0 to pulls - 1)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(cascade_pull), T, pull_range, shear_range, shear), i * pull_delay)
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(explosion), T, final_blast[1], final_blast[2], final_blast[3], final_blast[1], FALSE, FALSE, final_blast[4]), pulls * pull_delay)

/// Throws everything loose within `range` of `T` at it, and deals `shear` to whatever's fixed and solid within `shear_range`.
/proc/cascade_pull(turf/T, range, shear_range = 0, shear = 0)
	screen_shockwave(T, range, 6)
	for(var/atom/movable/AM in orange(range, T))
		if(iseffect(AM) || AM.throwing)
			continue
		if(AM.anchored && !ismob(AM))
			if(shear && isobj(AM) && AM.density && get_dist(AM, T) <= shear_range)
				var/obj/O = AM
				O.take_damage(shear, BRUTE, "bomb", FALSE)
			continue
		AM.throw_at(T, get_dist(AM, T), 2)

/obj/item/grenade/cascade/seeker
	name = "seeker cascade"
	desc = "A prototype cluster charge. It lobs its charges at people."
	icon_state = "redfrag"
	color = "#ff80ff"
	seek = TRUE
	fragment_color = "#ff40ff"

/obj/item/grenade/cascade/chaos
	name = "pandemonium charge"
	desc = "A prototype cluster charge. No two of its charges are the same."
	icon_state = "slimebang"
	payload_type = /datum/cascade_payload/chaos
	fragment_state = "slimebang_segment"
	fragment_color = null

// Pyrovapour: a fuel that only hangs in the air. A cloud of it goes off tile by tile from one spark, each tile lighting the next.

/datum/reagent/pyrovapour
	name = "Pyrovapour"
	description = "A fine aerosol fuel. As a cloud it goes off all at once from a single spark; it soaks into anyone standing in it."
	reagent_state = GAS
	color = "#c8b070"
	taste_description = "petrol and pennies"

/datum/reagent/pyrovapour/reaction_mob(mob/living/M, method = TOUCH, reac_volume)
	if(method == TOUCH || method == VAPOR)
		M.adjust_fire_stacks(reac_volume / 2)
		return
	..()

/datum/reagent/pyrovapour/on_mob_life(mob/living/carbon/M)
	M.adjustToxLoss(1, 0)
	if(prob(10))
		M.emote("cough")
	..()
	return TRUE

/obj/effect/particle_effect/smoke/chem
	var/vapour_lit = FALSE

/obj/effect/particle_effect/smoke/chem/fire_act(exposed_temperature, exposed_volume)
	if(reagents?.has_reagent(/datum/reagent/pyrovapour))
		detonate_vapour()
		return
	return ..()

/// This tile of the cloud goes off, and lights the tiles of it next to it a moment later. Every other tile blasts, so a big cloud
/// isn't hundreds of explosions; every tile burns.
/obj/effect/particle_effect/smoke/chem/proc/detonate_vapour()
	if(vapour_lit || QDELETED(src))
		return
	vapour_lit = TRUE
	var/turf/T = get_turf(src)
	reagents?.clear_reagents()
	kill_smoke()
	if(!T)
		return
	if((T.x + T.y) % 2 == 0)
		explosion(T, 0, 1, 2, flash_range = 0, adminlog = FALSE, flame_range = 1, silent = prob(85))
	T.atmos_spawn_air("plasma=4;TEMP=1500") // what didn't go off burns on, and the fire carries past the cloud
	T.hotspot_expose(1500, 500)
	// up to two tiles off, so it jumps a shut door to the cloud that seeped past it; not through a wall
	for(var/obj/effect/particle_effect/smoke/chem/S in range(2, T))
		if(S.vapour_lit || S == src)
			continue
		var/turf/between = get_step(T, get_dir(T, S))
		if(between != get_turf(S) && isclosedturf(between))
			continue
		addtimer(CALLBACK(S, PROC_REF(detonate_vapour)), 1)

#undef CASCADE_TREE
#undef CASCADE_RINGS
#undef CASCADE_SINGLE
#undef CASCADE_CHAIN_WINDOW
#undef CASCADE_MAX_CHAINS
#undef CASCADE_TURF_WINDOW
#undef CASCADE_TURF_HITS
