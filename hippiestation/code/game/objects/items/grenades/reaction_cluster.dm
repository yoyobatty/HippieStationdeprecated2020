// Reaction cluster (admin spawn only): one casing that lets go of four chemical bomblets on the tile it went off on. Each splashes
// its own mix and soaks it into the floor as chem piles, five steps out along open floor, 70% as much each step; the glycerol, powder
// and acid bomblets also let out a see-through cloud of their mix that rolls eight steps out and keeps adding it to the piles under
// it for ten seconds. Every pile ends up holding the lot:
//  1 s    glycerol and black powder soak in, and their clouds roll out
//  2 s    ClF3 + phlogiston: everyone near catches fire, the floor burns, a plasma fire starts, and the ClF3 (hypergolic) heats every
//         pile it reaches to 495 K: past black powder's 474 K, short of boiling. Every pile of powder starts sparking (5-10 s each)
//  3.5 s  the acids: glycerol + fluorosulfuric + sulphuric acid make nitroglycerin, which goes off in a ripple out from the middle,
//         and the acid cloud follows the others out, making more wherever it meets glycerol
//  on     every blast heats the cluster piles round it instead of sweeping them away, so the powder in them starts sparking and goes
//         off in turn, out through the cloud
// The acid melts and burns whoever it splashes, and whoever breathes the cloud.
//
// A cluster pile is topped up again and again, and each top-up would set off its own explosion (black powder sleeping 5-10 s inside
// the smoke's process for each): instead a pile holds one pending blast of each kind, which what reacts after adds to, nitroglycerin
// goes off at most every REACTION_QUICK_COOLDOWN from a pile, and no more than REACTION_BLASTS_PER_TICK cluster blasts go off in a
// tick, the rest rolling on to the next (29 in one tick paused a live round, 2026-11-14).

/// Hot enough for black powder and nitroglycerin (474 K), short of boiling (500 K): hotter and the pile's reagents boil off as vapour
#define REACTION_PILE_HEAT 495
/// Cluster pile blasts in one tick at most
#define REACTION_BLASTS_PER_TICK 4
/// Most explosion power one pile blast has
#define REACTION_BLAST_MAX 6
/// Least time between one pile's nitroglycerin blasts
#define REACTION_QUICK_COOLDOWN (2 SECONDS)
/// Clusters that burst on one tile, and on the whole station, in REACTION_CLUSTER_WINDOW at most
#define REACTION_CLUSTERS_PER_TILE 2
#define REACTION_CLUSTERS_MAX 8
#define REACTION_CLUSTER_WINDOW (10 SECONDS)

// Not a clusterbuster subtype: the random clusterbuster in the syndicate uplink kit picks from those
/obj/item/grenade/reaction_cluster
	name = "reaction cluster"
	desc = "Four chemical bomblets in one casing, each harmless enough alone. The label just says DO NOT MIX."
	icon_state = "clusterbang"
	color = "#ffb070"
	var/list/bomblets = list(
		/obj/item/grenade/chem_grenade/reaction_bomblet/glycerol,
		/obj/item/grenade/chem_grenade/reaction_bomblet/powder,
		/obj/item/grenade/chem_grenade/reaction_bomblet/fire,
		/obj/item/grenade/chem_grenade/reaction_bomblet/acid)

/// Cluster bursts in the last REACTION_CLUSTER_WINDOW: turf = world.time of the latest bursts there (a list), and every burst's time
GLOBAL_LIST_EMPTY(reaction_cluster_tiles)
GLOBAL_LIST_EMPTY(reaction_cluster_times)
GLOBAL_VAR_INIT(reaction_cluster_fizzled, 0)

/obj/item/grenade/reaction_cluster/prime()
	update_mob()
	var/turf/T = get_turf(src)
	if(!T)
		qdel(src)
		return
	// A pile primed at once (965 on one tile, 2026-11-14: 3,860 bomblets, a 23 s freeze and the game at 28% speed for a minute)
	// bursts only the first few; the rest fizzle
	if(!reaction_cluster_may_burst(T))
		if(!GLOB.reaction_cluster_fizzled++)
			log_game("Reaction clusters fizzled at [AREACOORD(T)]: more than [REACTION_CLUSTERS_PER_TILE] on a tile or [REACTION_CLUSTERS_MAX] on the station within [DisplayTimeText(REACTION_CLUSTER_WINDOW)]")
		qdel(src)
		return
	for(var/path in bomblets)
		var/obj/item/grenade/chem_grenade/reaction_bomblet/B = new path(T)
		B.fingerprintslast = fingerprintslast
		B.arm()
	playsound(T, 'sound/weapons/armbomb.ogg', 75, 1, -3)
	log_game("A reaction cluster burst at [AREACOORD(T)]")
	qdel(src)

/// Whether a cluster may burst on T now, counting it if so
/proc/reaction_cluster_may_burst(turf/T)
	var/since = world.time - REACTION_CLUSTER_WINDOW
	var/list/times = GLOB.reaction_cluster_times
	while(length(times) && times[1] <= since)
		times.Cut(1, 2)
	if(!length(times))
		GLOB.reaction_cluster_tiles.Cut() // nothing recent anywhere
		GLOB.reaction_cluster_fizzled = 0
	if(length(times) >= REACTION_CLUSTERS_MAX)
		return FALSE
	var/list/here = GLOB.reaction_cluster_tiles[T]
	if(here)
		while(length(here) && here[1] <= since)
			here.Cut(1, 2)
		if(length(here) >= REACTION_CLUSTERS_PER_TILE)
			return FALSE
	else
		here = list()
		GLOB.reaction_cluster_tiles[T] = here
	here += world.time
	times += world.time
	return TRUE

/obj/item/grenade/chem_grenade/reaction_bomblet
	name = "reaction bomblet"
	desc = "One quarter of something much worse."
	stage = GRENADE_READY
	affected_area = 3
	resistance_flags = INDESTRUCTIBLE // another bomblet's blast mustn't eat it before it goes
	anchored = TRUE // nor throw it off the tile
	/// What it splashes, path = units
	var/list/mix
	/// What it soaks into the floor, path = units on its own tile, times seed_falloff for each step out
	var/list/seed
	/// How far the soak spreads, in steps along open floor (not through walls or shut doors)
	var/seed_range = 5
	/// How much of the seed and heat is left each step out
	var/seed_falloff = 0.7
	/// Kelvin over room temperature it heats the piles on its own tile by, times seed_falloff each step out; piles never go past
	/// REACTION_PILE_HEAT (0: no heating)
	var/seed_heat = 0
	/// Plasma moles it leaves alight on each tile within two steps, times seed_falloff each step out (0: none)
	var/fire_moles = 0
	/// Seconds from the cluster bursting to this going off, so the mixes land in order
	var/fuse = 2 SECONDS
	/// Ticks the soak takes to reach each step further out, plus up to soak_jitter more on each tile. A soak that sets off a pile on
	/// every tile in the same tick is one long pause (29 nitroglycerin blasts in one tick, 2026-11-14), so it ripples out instead
	var/soak_step = 0
	var/soak_jitter = 0
	/// What its cloud carries, path = units (a smoke holds 250 at most); every tile of the cloud has all of it
	var/list/cloud
	/// How many steps the cloud rolls out (0: no cloud)
	var/cloud_radius = 0

/obj/item/grenade/chem_grenade/reaction_bomblet/Initialize()
	. = ..()
	// two full bluespace beakers, the mix split between them
	for(var/n in 1 to 2)
		var/obj/item/reagent_containers/glass/beaker/bluespace/B = new(src)
		for(var/path in mix)
			B.reagents.add_reagent(path, mix[path] / 2)
		beakers += B

// The casing keeps blasts off its beakers: each beaker of black powder went off whole when a blast reached it (1,598 explosions from
// a pile of clusters, 2026-11-14)
/obj/item/grenade/chem_grenade/reaction_bomblet/contents_explosion(severity, target)
	return

/obj/item/grenade/chem_grenade/reaction_bomblet/proc/arm()
	active = TRUE
	icon_state = "[initial(icon_state)]_active"
	addtimer(CALLBACK(src, PROC_REF(prime)), fuse)

/obj/item/grenade/chem_grenade/reaction_bomblet/prime()
	if(stage != GRENADE_READY)
		return
	var/turf/T = get_turf(src)
	if(isopenturf(T))
		if(length(seed) || seed_heat || fire_moles)
			soak(T)
		if(cloud_radius && length(cloud))
			release_cloud(T)
	return ..()

/// Adds the seed mix to the chem pile on each tile out to seed_range, so it reacts with whatever another bomblet left there
/obj/item/grenade/chem_grenade/reaction_bomblet/proc/soak(turf/open/start)
	var/list/steps = list()
	steps[start] = 0
	var/list/queue = list(start)
	var/i = 1
	while(i <= queue.len)
		var/turf/open/O = queue[i++]
		var/dist = steps[O]
		if(!is_type_in_typecache(O, GLOB.statechange_turf_blacklist))
			var/scale = seed_falloff ** dist
			var/heat = seed_heat ? min(T20C + seed_heat * scale, REACTION_PILE_HEAT) : 0
			var/delay = (dist * soak_step + rand(0, soak_jitter)) * world.tick_lag
			if(delay)
				addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(reaction_soak_tile), O, seed, scale, heat), delay)
			else
				INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(reaction_soak_tile), O, seed, scale, heat)
			if(fire_moles && dist <= 2)
				O.atmos_spawn_air("plasma=[fire_moles * scale];TEMP=1000")
		if(dist >= seed_range)
			continue
		for(var/turf/open/N in O.GetAtmosAdjacentTurfs())
			if(isnull(steps[N]))
				steps[N] = dist + 1
				queue += N

/obj/item/grenade/chem_grenade/reaction_bomblet/proc/release_cloud(turf/open/T)
	var/obj/effect/particle_effect/smoke/chem/reaction_cluster/S = new(T)
	for(var/path in cloud)
		S.reagents.add_reagent(path, cloud[path])
	S.source = REF(src)
	S.add_atom_colour(mix_color_from_reagents(S.reagents.reagent_list), FIXED_COLOUR_PRIORITY)
	S.amount = cloud_radius
	playsound(T, 'sound/effects/smoke.ogg', 50, 1, -3)
	INVOKE_ASYNC(S, TYPE_PROC_REF(/obj/effect/particle_effect/smoke, spread_smoke))

/// Adds seed (path = units, times scale) to the chem pile on O, making one if there's none; then heats the pile to heat kelvin (0: no
/// heating). With no seed it only heats a pile already there.
/proc/reaction_soak_tile(turf/open/O, list/seed, scale, heat)
	var/obj/effect/decal/cleanable/chempile/P = locate() in O
	if(length(seed))
		if(QDELETED(P) || !P.reagents)
			P = new(O)
		P.blast_heats = TRUE
		for(var/path in seed)
			if(QDELETED(P) || !P.reagents) // went off
				return
			P.reagents.add_reagent(path, seed[path] * scale)
		if(!QDELETED(P))
			P.queue_recolor()
	if(!heat || QDELETED(P) || !P.reagents?.total_volume || P.reagents.chem_temp >= heat)
		return
	P.reagents.chem_temp = heat
	P.reagents.handle_reactions()

// The cloud: see-through, so the piles can be seen going off under it. It rolls through the other bomblets' clouds (plain smoke
// stops where there's smoke already), keeps a cluster pile under each tile of it for what it drops to go into, and fire doesn't set
// off what it carries: only the piles react.
/obj/effect/particle_effect/smoke/chem/reaction_cluster
	opaque = FALSE
	/// The bomblet it came from: it only stops at tiles its own cloud is on
	var/source

/obj/effect/particle_effect/smoke/chem/reaction_cluster/process()
	var/turf/open/T = get_turf(src)
	if(istype(T) && !is_type_in_typecache(T, GLOB.statechange_turf_blacklist))
		var/obj/effect/decal/cleanable/chempile/P = locate() in T
		if(QDELETED(P))
			P = new(T)
		P.blast_heats = TRUE
	return ..()

/obj/effect/particle_effect/smoke/chem/reaction_cluster/fire_act(exposed_temperature, exposed_volume)
	return

/obj/effect/particle_effect/smoke/chem/reaction_cluster/spread_smoke()
	var/turf/t_loc = get_turf(src)
	if(!t_loc)
		return
	var/list/newsmokes = list()
	for(var/turf/T in t_loc.GetAtmosAdjacentTurfs())
		var/covered = FALSE
		for(var/obj/effect/particle_effect/smoke/chem/reaction_cluster/other in T)
			if(other.source == source)
				covered = TRUE
				break
		if(covered)
			continue
		for(var/mob/living/L in T)
			smoke_mob(L)
		var/obj/effect/particle_effect/smoke/chem/reaction_cluster/S = new type(T)
		reagents.copy_to(S, reagents.total_volume)
		S.source = source
		S.setDir(pick(GLOB.cardinals))
		S.amount = amount - 1
		S.add_atom_colour(color, FIXED_COLOUR_PRIORITY)
		S.lifetime = lifetime
		if(S.amount > 0)
			newsmokes += S
	for(var/obj/effect/particle_effect/smoke/chem/reaction_cluster/S as anything in newsmokes)
		addtimer(CALLBACK(S, TYPE_PROC_REF(/obj/effect/particle_effect/smoke, spread_smoke)), 1)

/obj/effect/decal/cleanable/chempile
	/// A reaction cluster's: a blast heats it rather than sweeping it away, so what's in it goes off in turn (otherwise the first blast
	/// clears every pile round it and the rest of the mix never reacts), and its explosions are queued (queue_blast())
	var/blast_heats = FALSE
	/// Explosion power waiting to go off: quick (nitroglycerin and the like) and slow (black powder, sparking first)
	var/quick_power = 0
	var/slow_power = 0
	var/quick_queued = FALSE
	var/slow_queued = FALSE
	/// world.time before which this pile's next quick blast can't go
	var/quick_next = 0

/obj/effect/decal/cleanable/chempile/ex_act(severity, target)
	if(!blast_heats)
		return ..()
	// Kept even empty: it may have a blast queued
	if(!reagents?.total_volume || reagents.chem_temp >= 474) // hot already, so whatever reacts to heat is reacting: once is enough
		return
	reagents.chem_temp = REACTION_PILE_HEAT
	INVOKE_ASYNC(reagents, TYPE_PROC_REF(/datum/reagents, handle_reactions)) // this is inside the blast

/// Adds power (plus modifier, if nothing of that kind is queued yet) to this pile's pending blast, queuing it if it isn't
/obj/effect/decal/cleanable/chempile/proc/queue_blast(power, modifier, slow)
	if(slow)
		slow_power += power + (slow_queued ? 0 : modifier)
		if(slow_queued)
			return
		slow_queued = TRUE
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(reaction_pile_blast), src, get_turf(src), TRUE), rand(50, 100))
		return
	quick_power += power + (quick_queued ? 0 : modifier)
	if(quick_queued || quick_power < 1)
		return
	quick_queued = TRUE
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(reaction_pile_blast), src, get_turf(src), FALSE), max(rand(1, 4) * world.tick_lag, quick_next - world.time))

GLOBAL_VAR_INIT(reaction_blast_time, 0)
GLOBAL_VAR_INIT(reaction_blasts_now, 0)

/// A cluster pile's queued blast goes off, where the pile is or was
/proc/reaction_pile_blast(obj/effect/decal/cleanable/chempile/P, turf/T, slow)
	if(GLOB.reaction_blast_time != world.time)
		GLOB.reaction_blast_time = world.time
		GLOB.reaction_blasts_now = 0
	if(GLOB.reaction_blasts_now >= REACTION_BLASTS_PER_TICK)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(reaction_pile_blast), P, T, slow), world.tick_lag)
		return
	GLOB.reaction_blasts_now++
	var/power
	if(slow)
		power = P.slow_power
		P.slow_power = 0
		P.slow_queued = FALSE
	else
		power = P.quick_power
		P.quick_power = 0
		P.quick_queued = FALSE
		P.quick_next = world.time + REACTION_QUICK_COOLDOWN
	if(!QDELETED(P))
		T = get_turf(P) || T
	if(!T || power < 1)
		return
	var/datum/effect_system/reagents_explosion/E = new
	E.set_up(min(power, REACTION_BLAST_MAX), T, 0, 0)
	E.start(FALSE)

// In a cluster pile an explosive reaction queues its blast rather than going off there and then
/datum/chemical_reaction/reagent_explosion/on_reaction(datum/reagents/holder, created_volume, log = TRUE)
	var/obj/effect/decal/cleanable/chempile/P = holder?.my_atom
	if(istype(P) && P.blast_heats)
		P.queue_blast(created_volume / strengthdiv, modifier, FALSE)
		return
	return ..()

/datum/chemical_reaction/reagent_explosion/blackpowder_explosion/on_reaction(datum/reagents/holder, created_volume)
	var/obj/effect/decal/cleanable/chempile/P = holder?.my_atom
	if(istype(P) && P.blast_heats)
		P.queue_blast(created_volume / strengthdiv, modifier, TRUE)
		return
	return ..()

/obj/item/grenade/chem_grenade/reaction_bomblet/glycerol
	name = "glycerol bomblet"
	color = "#e8e0a0"
	mix = list(/datum/reagent/glycerol = 300, /datum/reagent/fuel = 300)
	seed = list(/datum/reagent/glycerol = 12)
	cloud = list(/datum/reagent/glycerol = 250)
	cloud_radius = 8
	fuse = 1 SECONDS

/obj/item/grenade/chem_grenade/reaction_bomblet/powder
	name = "black powder bomblet"
	color = "#606060"
	mix = list(/datum/reagent/blackpowder = 600)
	seed = list(/datum/reagent/blackpowder = 30)
	cloud = list(/datum/reagent/blackpowder = 250)
	cloud_radius = 8
	fuse = 1 SECONDS

/// ClF3 doesn't pile up (it burns straight away): it heats the piles it reaches, and the powder in them starts sparking
/obj/item/grenade/chem_grenade/reaction_bomblet/fire
	name = "ClF3 bomblet"
	color = "#ff6040"
	mix = list(/datum/reagent/clf3 = 300, /datum/reagent/phlogiston = 300)
	seed_heat = 2000
	fire_moles = 12
	fuse = 2 SECONDS

/// Every pile with glycerol in it goes off as nitroglycerin, rippling out from the middle
/obj/item/grenade/chem_grenade/reaction_bomblet/acid
	name = "acid bomblet"
	color = "#80ff60"
	mix = list(/datum/reagent/toxin/acid/fluacid = 400, /datum/reagent/toxin/acid = 200)
	seed = list(/datum/reagent/toxin/acid/fluacid = 12, /datum/reagent/toxin/acid = 12)
	cloud = list(/datum/reagent/toxin/acid/fluacid = 125, /datum/reagent/toxin/acid = 125)
	cloud_radius = 8
	soak_step = 2
	soak_jitter = 3
	fuse = 3.5 SECONDS // after the ClF3 has the powder sparking

#undef REACTION_PILE_HEAT
#undef REACTION_BLASTS_PER_TICK
#undef REACTION_BLAST_MAX
#undef REACTION_QUICK_COOLDOWN
#undef REACTION_CLUSTERS_PER_TILE
#undef REACTION_CLUSTERS_MAX
#undef REACTION_CLUSTER_WINDOW
