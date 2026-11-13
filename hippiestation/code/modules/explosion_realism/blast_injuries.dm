// Realistic explosions: what a blast does to people (see blast_air.dm). Injuries last (the user's pick, 2026-11-13).
//  - Eardrums burst: always in the heavy ring, often in the light ring. A burst eardrum leaves you deaf until it's treated
//    (inacusiate), and the health analyser says permanent. Out where only glass breaks, a few seconds of deafness. Ear protection
//    (earmuffs, a bowman headset, a bomb hood) saves them.
//  - Blast lung near the middle: bleeding in the lungs (blast_lung, below). Coughing blood, short of breath, gasping when bad. It
//    heals slowly by itself, faster on salbutamol, perfluorodecalin, cryoxadone, clonexadone or omnizine; new lungs end it.
//    Bomb armour shields the chest from it.
//  - Lying down is much safer: the heavy blast hits you as the light one does, and ears and lungs half as often. Fragments thrown
//    across a room fly over people lying down.
//  - Fragments: a bomb with a casing (grenades, pipe bombs, gas tanks and transfer valves, fuel tanks, canisters) throws metal
//    fragments in every direction, and a glass container throws glass. Each flies a straight line at once and stops in the first
//    person standing in the way (three times in four), or at a wall, window or shut door. They hit hard, embed and need pulling out,
//    and go further in vacuum, where nothing slows them and nothing else carries the blast. Plastic explosive has no casing to throw.

/// The most fragments one explosion throws, and the most a second anywhere (a pile of grenades)
#define BLAST_FRAGMENTS_MAX 40
#define BLAST_FRAGMENTS_PER_SECOND 150

GLOBAL_VAR_INIT(blast_fragment_window, 0)
GLOBAL_VAR_INIT(blast_fragment_count, 0)
/// Fragments thrown, and how many hit someone, all round (for the checks)
GLOBAL_VAR_INIT(blast_fragments_thrown, 0)
GLOBAL_VAR_INIT(blast_fragments_hit, 0)

/// Until when this mob counts as having been lying down when a blast went off (explode() sets it, or clears it for anyone standing)
/mob/living/carbon/var/blast_prone_until = 0

/mob/living/carbon/human/ex_act(severity, target, origin)
	// lying down when it went off, the heavy blast hits you as the light one does
	if(GLOB.explosion_realism && severity == EXPLODE_HEAVY && blast_prone_until >= world.time && !(status_flags & GODMODE))
		severity = EXPLODE_LIGHT
	return ..()

/mob/living/carbon/ex_act(severity, target, origin)
	. = ..()
	if(GLOB.explosion_realism && severity && !QDELETED(src) && !(status_flags & GODMODE))
		blast_injuries(severity)

/// Ears and lungs, by how hard the blast hit
/mob/living/carbon/proc/blast_injuries(severity)
	var/ear_chance = 0
	var/lung_chance = 0
	var/lung_damage = 0
	switch(severity)
		if(EXPLODE_DEVASTATE)
			ear_chance = 100
			lung_chance = 100
			lung_damage = rand(45, 75)
		if(EXPLODE_HEAVY)
			ear_chance = 85
			lung_chance = 60
			lung_damage = rand(25, 50)
		if(EXPLODE_LIGHT)
			ear_chance = 35
			lung_chance = 12
			lung_damage = rand(10, 25)
	if(blast_prone_until >= world.time)
		ear_chance *= 0.5
		lung_chance *= 0.5
	if(prob(ear_chance))
		blast_burst_eardrums()
	var/shield = 1 - clamp(getarmor(BODY_ZONE_CHEST, "bomb"), 0, 100) / 100
	if(prob(lung_chance * shield))
		blast_lung(lung_damage * shield)

/// Bursts the eardrums: deaf until treated
/mob/living/carbon/proc/blast_burst_eardrums()
	if(get_ear_protection() >= 1)
		return
	var/obj/item/organ/ears/E = getorganslot(ORGAN_SLOT_EARS)
	if(!E || E.damage_multiplier <= 0 || E.ear_damage > UNHEALING_EAR_DAMAGE)
		return
	E.ear_damage = max(E.ear_damage, UNHEALING_EAR_DAMAGE + 10)
	E.deaf = max(E.deaf, 30)
	to_chat(src, "<span class='userdanger'>Your ears pop, and everything goes quiet!</span>")

/// Bleeding in the lungs, `amount` more of it
/mob/living/carbon/proc/blast_lung(amount)
	if(amount < 1 || !getorganslot(ORGAN_SLOT_LUNGS) || HAS_TRAIT(src, TRAIT_NOBREATH))
		return
	var/datum/status_effect/blast_lung/B = has_status_effect(/datum/status_effect/blast_lung)
	if(B)
		B.severity = min(B.severity + amount, 100)
		return
	apply_status_effect(/datum/status_effect/blast_lung, amount)

/datum/status_effect/blast_lung
	id = "blast_lung"
	duration = -1
	tick_interval = 20
	alert_type = /obj/screen/alert/status_effect/blast_lung
	/// How bad it is, 0 to 100
	var/severity = 0
	/// The lungs it's in: new ones end it
	var/obj/item/organ/lungs/lungs

/datum/status_effect/blast_lung/on_creation(mob/living/new_owner, amount)
	severity = min(amount, 100)
	return ..()

/datum/status_effect/blast_lung/on_apply()
	if(!iscarbon(owner))
		return FALSE
	var/mob/living/carbon/C = owner
	lungs = C.getorganslot(ORGAN_SLOT_LUNGS)
	if(!lungs)
		return FALSE
	to_chat(owner, "<span class='userdanger'>Your chest burns, and every breath hurts!</span>")
	return TRUE

/datum/status_effect/blast_lung/on_remove()
	lungs = null

/datum/status_effect/blast_lung/tick()
	var/mob/living/carbon/C = owner
	if(C.getorganslot(ORGAN_SLOT_LUNGS) != lungs)
		qdel(src) //new lungs
		return
	var/heal = 0.08
	if(C.reagents)
		if(C.reagents.has_reagent(/datum/reagent/medicine/salbutamol))
			heal += 1.5
		if(C.reagents.has_reagent(/datum/reagent/medicine/perfluorodecalin))
			heal += 1
		if(C.reagents.has_reagent(/datum/reagent/medicine/cryoxadone) || C.reagents.has_reagent(/datum/reagent/medicine/clonexadone))
			heal += 2
		if(C.reagents.has_reagent(/datum/reagent/medicine/omnizine))
			heal += 0.5
	severity -= heal
	if(severity <= 0)
		to_chat(C, "<span class='notice'>Breathing comes easier.</span>")
		qdel(src)
		return
	if(C.stat == DEAD)
		return
	if(prob(severity * 0.5))
		C.visible_message("<span class='danger'>[C] coughs up blood!</span>", "<span class='danger'>You cough up blood!</span>")
		C.emote("cough")
		C.add_splatter_floor(get_turf(C), TRUE)
	C.adjustStaminaLoss(severity * 0.08)
	if(severity >= 40 && prob(severity - 30))
		C.losebreath = max(C.losebreath, 1)

/obj/screen/alert/status_effect/blast_lung
	name = "Blast lung"
	desc = "Bleeding in the lungs. Salbutamol, perfluorodecalin, cryo."
	icon_state = "too_much_oxy"

/// How many fragments an explosion's casing throws, and of what: list(count, type), or null for none
/proc/blast_casing(atom/cause)
	if(!istype(cause) || isturf(cause))
		return null
	if(istype(cause, /obj/item/grenade/plastic))
		return null //no casing to speak of
	if(istype(cause, /obj/item/grenade/syndieminibomb/concussion/frag))
		return list(40, /obj/item/blast_fragment)
	if(istype(cause, /obj/item/grenade/syndieminibomb/concussion))
		return list(10, /obj/item/blast_fragment)
	if(istype(cause, /obj/item/grenade/syndieminibomb))
		return list(24, /obj/item/blast_fragment)
	if(istype(cause, /obj/item/grenade/iedcasing))
		return list(30, /obj/item/blast_fragment)
	if(istype(cause, /obj/item/grenade))
		return list(12, /obj/item/blast_fragment)
	if(istype(cause, /obj/item/transfer_valve))
		return list(16, /obj/item/blast_fragment)
	if(istype(cause, /obj/item/tank))
		return list(12, /obj/item/blast_fragment)
	if(istype(cause, /obj/structure/reagent_dispensers))
		return list(16, /obj/item/blast_fragment)
	if(istype(cause, /obj/machinery/portable_atmospherics/canister))
		return list(20, /obj/item/blast_fragment/large)
	if(istype(cause, /obj/item/reagent_containers/glass) || istype(cause, /obj/item/reagent_containers/food/drinks))
		return list(5, /obj/item/shard)
	return null

/// Throws the casing out as fragments. `cause` is what blew up.
/proc/blast_fragments(turf/epicenter, atom/cause, list/real, list/raw_ranges)
	var/list/casing = blast_casing(cause)
	if(!casing)
		return
	var/size = max(raw_ranges[1], raw_ranges[2], raw_ranges[3])
	if(size <= 0)
		return
	if(world.time >= GLOB.blast_fragment_window + 1 SECONDS)
		GLOB.blast_fragment_window = world.time
		GLOB.blast_fragment_count = 0
	var/count = min(casing[1], BLAST_FRAGMENTS_MAX, BLAST_FRAGMENTS_PER_SECOND - GLOB.blast_fragment_count)
	if(count <= 0)
		return
	GLOB.blast_fragment_count += count
	var/reach = clamp(5 + size, 6, 14)
	if(real[6] <= 0)
		reach = min(reach * 1.6, 20) //nothing slows them
	// at once: the blast knocks everyone down when SSexplosions gets to them, next tick, and fragments then would fly over them all
	blast_throw_fragments(epicenter, casing[2], count, reach, clamp(size, 1, 6))

/// Fragments go a kilometre or two a second, so across a station they're there at once: each flies a straight line out and stops at
/// the first wall, window or shut door (denting or chipping it), or in the first person standing in the way, three times in four. It
/// passes over anyone lying down. Where it stops it drops, or stays in them.
/proc/blast_throw_fragments(turf/epicenter, fragment_type, count, reach, power)
	var/start = rand(0, 359)
	for(var/i in 1 to count)
		var/angle = start + i * (360 / count) + rand(-8, 8)
		var/distance = rand(round(reach * 0.6), reach)
		var/turf/target = locate(clamp(round(epicenter.x + distance * cos(angle)), 1, world.maxx), clamp(round(epicenter.y + distance * sin(angle)), 1, world.maxy), epicenter.z)
		if(!target || target == epicenter)
			continue
		var/turf/landing = epicenter
		var/mob/living/hit
		for(var/turf/T as anything in getline(epicenter, target))
			if(T == epicenter)
				continue
			if(T.density)
				if(iswallturf(T) && prob(30))
					var/turf/closed/wall/W = T
					W.add_dent(WALL_DENT_SHOT)
				break
			var/obj/stopped_by
			for(var/obj/O in T)
				if(O.density && !(O.pass_flags & LETPASSTHROW))
					stopped_by = O
					break
			if(stopped_by)
				if(istype(stopped_by, /obj/structure/window) || istype(stopped_by, /obj/structure/grille))
					stopped_by.take_damage(power * 3, BRUTE, "bullet", FALSE)
				break
			landing = T
			for(var/mob/living/L in T)
				if(L.density && !(L.status_flags & GODMODE) && prob(75))
					hit = L
					break
			if(hit)
				break
		var/obj/item/F = new fragment_type(landing)
		GLOB.blast_fragments_thrown++
		if(hit)
			GLOB.blast_fragments_hit++
			var/old_throwforce = F.throwforce
			F.throwforce = clamp(max(old_throwforce, power * (1 + F.w_class) * 1.2), 0, 30)
			hit.hitby(F, TRUE, FALSE)
			if(!QDELETED(F))
				F.throwforce = old_throwforce

/// A jagged bit of a bomb's casing
/obj/item/blast_fragment
	name = "metal fragment"
	desc = "A jagged, scorched scrap of metal. It came off something that blew up."
	icon = 'icons/obj/shards.dmi'
	icon_state = "tiny"
	color = "#7d7468"
	w_class = WEIGHT_CLASS_TINY
	sharpness = IS_SHARP
	force = 4
	throwforce = 10
	throw_speed = 5
	embedding = list("embed_chance" = 65, "embedded_fall_chance" = 2, "embedded_ignore_throwspeed_threshold" = TRUE)
	materials = list(MAT_METAL = 100)
	resistance_flags = FIRE_PROOF

/// It's what's left of a blast already: the next one along only throws it about
/obj/item/blast_fragment/ex_act(severity, target)
	return FALSE

/obj/item/blast_fragment/Initialize()
	. = ..()
	pixel_x = rand(-8, 8)
	pixel_y = rand(-8, 8)
	transform = turn(transform, rand(0, 359))

/obj/item/blast_fragment/large
	name = "torn metal plate"
	icon_state = "small"
	w_class = WEIGHT_CLASS_SMALL
	throwforce = 14
	embedding = list("embed_chance" = 35, "embedded_fall_chance" = 4, "embedded_ignore_throwspeed_threshold" = TRUE)
	materials = list(MAT_METAL = 500)

#undef BLAST_FRAGMENTS_MAX
#undef BLAST_FRAGMENTS_PER_SECOND
