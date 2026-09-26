#define BLAST_MISSILE_DAMAGE_CAP 30 // most damage a thrown item can do on impact, however hard it was thrown
#define BLAST_MISSILE_DAMAGE_MULTIPLIER 1.2 // impact damage per point of missile power, per point of item size (plus one)
#define BLAST_CABLE_ARCS_PER_SECOND 10 // limit on cable arc flashes, since a big explosion can hit hundreds of cables at once and each one sets off a chain of lightning

GLOBAL_VAR_INIT(blast_cable_arc_window, 0)
GLOBAL_VAR_INIT(blast_cable_arc_count, 0)

/**
  * Throws something as a blast would. Items thrown this way hit hard on impact, more so the harder the blast and the
  * heavier the item is, so debris and anything else a blast picks up is dangerous. The item goes back to normal once it lands.
  *
  * Arguments:
  * * AM - what to throw
  * * target, range, speed, quickstart - passed straight to throw_at()
  * * missile_power - how hard the blast threw it. About the number of turfs it's thrown is a good guide.
  *
  * Returns whatever throw_at() does, TRUE if it was thrown.
  */
/proc/throw_as_missile(atom/movable/AM, atom/target, range, speed, missile_power, quickstart = TRUE)
	var/datum/callback/landed
	var/old_throwforce
	if(isitem(AM))
		var/obj/item/I = AM
		old_throwforce = I.throwforce
		I.throwforce = clamp(max(old_throwforce, missile_power * (1 + I.w_class) * BLAST_MISSILE_DAMAGE_MULTIPLIER), 0, BLAST_MISSILE_DAMAGE_CAP)
		landed = CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(restore_missile_throwforce), I, old_throwforce)
	. = AM.throw_at(target, range, speed, callback = landed, quickstart = quickstart)
	if(!. && landed)
		restore_missile_throwforce(AM, old_throwforce) // it never left the ground, so the callback won't be called

/proc/restore_missile_throwforce(obj/item/I, old_throwforce)
	if(!QDELETED(I))
		I.throwforce = old_throwforce

/**
  * A blasted SMES, APC or exposed cable dumps whatever electrical energy it was holding as an arc flash. It shocks
  * everyone right next to it, ignites any flammable gas, and throws a bolt of lightning at the nearest person or
  * piece of equipment in range, which jumps on from target to target, weaker each time, using the same lightning
  * as the tesla. The bolts only hurt and stun people, the machines and structures just pass them on. It scales with
  * how much power was really there: a full SMES is a bomb, an APC is a nasty zap and a cable depends on how much
  * power its network had available.
  *
  * Returns TRUE if it arced. Equipment that has just arced won't again for a few seconds, and neither can the
  * same person be shocked again for a second, so a chain of cables next to each other can't stack up.
  */
/proc/arc_flash(obj/O)
	if(QDELETED(O) || TIMER_COOLDOWN_CHECK(O, "arc_flash"))
		return FALSE
	var/damage = 0
	var/radius = 1
	if(istype(O, /obj/machinery/power/smes))
		var/obj/machinery/power/smes/S = O
		damage = clamp(5 + S.charge / 100000, 5, 80)
		radius = 1 + round(S.charge / 2000000)
		S.charge = 0
	else if(istype(O, /obj/machinery/power/apc))
		var/obj/machinery/power/apc/A = O
		var/stored = A.cell ? A.cell.charge : 0
		damage = clamp(5 + stored / 250, 5, 25)
		if(A.cell)
			A.cell.charge *= 0.1
	else if(istype(O, /obj/structure/cable))
		var/obj/structure/cable/C = O
		var/available = C.powernet ? C.powernet.avail : 0
		if(available <= 0)
			return FALSE // a dead cable has nothing to arc
		if(world.time - GLOB.blast_cable_arc_window >= 10)
			GLOB.blast_cable_arc_window = world.time
			GLOB.blast_cable_arc_count = 0
		if(GLOB.blast_cable_arc_count >= BLAST_CABLE_ARCS_PER_SECOND)
			return FALSE
		GLOB.blast_cable_arc_count++
		damage = clamp(5 + sqrt(available) / 30, 5, 40)
	else
		return FALSE
	var/turf/T = get_turf(O)
	if(!T)
		return FALSE
	TIMER_COOLDOWN_START(O, "arc_flash", 30)
	do_sparks(3 + radius * 2, FALSE, O)
	playsound(T, 'sound/magic/lightningshock.ogg', 60, TRUE)
	T.hotspot_expose(1500, 100) // an arc lights any flammable gas it goes off in, and does nothing otherwise
	// Everyone next to it gets shocked directly. Anyone who's been shocked in the last second is left out of the lightning too.
	var/list/shocked = list()
	shocked[O] = TRUE
	var/zap_range = 2 + radius * 2
	for(var/mob/living/L in range(zap_range + 2, T))
		if(TIMER_COOLDOWN_CHECK(L, "arc_flash"))
			shocked[L] = TRUE
	for(var/mob/living/L in range(radius, T))
		if(shocked[L])
			continue
		shocked[L] = TRUE
		L.electrocute_act(damage * (1 - get_dist(L, T) / (radius + 1)), O)
	// Then the lightning. A bolt does about power / 600 damage to a person, and it's out of steam below 1000 power.
	tesla_zap(O, zap_range, damage * 600, TESLA_MOB_DAMAGE | TESLA_MOB_STUN, shocked)
	for(var/thing in shocked)
		if(!isliving(thing))
			continue
		var/mob/living/L = thing
		if(!TIMER_COOLDOWN_CHECK(L, "arc_flash"))
			TIMER_COOLDOWN_START(L, "arc_flash", 10)
	return TRUE

/// Regular explosions set off the arc flash too, the closer to the middle the likelier.
/proc/arc_flash_from_explosion(obj/O, severity)
	var/chance = 25
	if(severity == EXPLODE_DEVASTATE)
		chance = 100
	else if(severity == EXPLODE_HEAVY)
		chance = 60
	if(prob(chance))
		arc_flash(O)

/obj/machinery/power/smes/ex_act(severity, target)
	arc_flash_from_explosion(src, severity) // before anything happens to it, while it still has its charge
	return ..()

/obj/machinery/power/apc/ex_act(severity, target)
	arc_flash_from_explosion(src, severity)
	return ..()

/obj/structure/cable/ex_act(severity, target)
	arc_flash_from_explosion(src, severity)
	return ..()

/**
  * The actual structure-wrecking blast wave: damages structures and machines (discharging any power equipment first) and throws
  * loose things and people away from an origin point. This is the same effect a fiery explosion's blast wave uses on everything
  * it touches (see /datum/fiery_explosion/proc/blast in effects_fiery_explosion.dm, now a thin wrapper around this), pulled out
  * as its own global proc so anything else, like a weapon, can call it directly on a single target without needing a whole
  * fiery explosion around it.
  *
  * Arguments:
  * * AM - what to blast. Structures and machines take damage and may discharge; loose items and mobs are thrown.
  * * local_power - how hard, on the same scale as fiery_explosion()'s power: 1 is a shove, 3 breaks windows and wrecks
  *   machines, 5+ devastates structures outright.
  * * origin - the point everything is thrown away from.
  * * arced - optional list to track which equipment has already discharged, so repeated calls (like ringing an explosion
  *   outward) don't re-arc the same piece over and over. Omit it for a one-off call like a single weapon hit.
  */
/proc/blast_atom(atom/movable/AM, local_power, turf/origin, list/arced)
	var/turf/T = AM.loc
	if(istype(T) && T.intact && AM.level == 1) // hidden under the floor, like pipes and cables
		return
	if(istype(AM, /obj/structure) || istype(AM, /obj/machinery))
		var/chance = local_power * 20
		var/severity_power = local_power
		if(istype(AM, /obj/structure/window) || istype(AM, /obj/structure/grille) || istype(AM, /obj/machinery/door/window))
			// glass and grilles are fragile: much likelier to be hit, and hit a tier harder than other structures
			chance = local_power * 45
			severity_power += 2
		else if(istype(AM, /obj/machinery))
			// machines are mostly metal, so they shrug off the blast better than other structures
			chance = local_power * 10
			severity_power -= 1
		if(prob(clamp(chance, 0, 100)))
			// Straight damage rather than ex_act(), since ex_act() just deletes anything at the top severity (and doors
			// bump the severity up a tier). Destroying things through damage leaves shards, frames and assemblies behind.
			var/damage = rand(10, 90)
			if(severity_power >= 4)
				damage = rand(300, 600)
			else if(severity_power >= 2)
				damage = rand(100, 250)
			if(!arced || !arced[AM]) // discharge before the damage, while the equipment still has its charge and its powernet
				if(arc_flash(AM) && arced)
					arced[AM] = TRUE
			blast_damage_obj(AM, damage, local_power, origin)
		return
	blast_launch(AM, local_power, origin)

/// Damages a structure or machine, and throws whatever that knocks loose or spills out (shards, parts, a locker's
/// contents) as debris, away from the origin.
/proc/blast_damage_obj(obj/O, damage, local_power, turf/origin)
	var/turf/T = O.loc
	var/list/before = istype(T) ? T.contents.Copy() : null
	O.take_damage(damage, BRUTE, "bomb", FALSE)
	if(before)
		for(var/thing in T.contents - before)
			blast_launch(thing, local_power, origin)

/// Throws a loose item or a mob away from the origin. Items thrown this way hit hard, so
/// debris and anything else the blast picks up can hurt on impact, more the heavier the item is.
/proc/blast_launch(atom/movable/AM, local_power, turf/origin)
	if(QDELETED(AM) || AM.anchored || !(isitem(AM) || isliving(AM)))
		return
	var/throw_distance = round(local_power * 2)
	var/direction = get_dir(origin, AM)
	if(throw_distance < 1)
		return
	if(!direction)
		direction = pick(GLOB.alldirs)
	if(isliving(AM))
		var/mob/living/L = AM
		L.Knockdown(min(local_power * 10, 60))
	throw_as_missile(AM, get_edge_target_turf(AM, direction), throw_distance, 3, local_power)
