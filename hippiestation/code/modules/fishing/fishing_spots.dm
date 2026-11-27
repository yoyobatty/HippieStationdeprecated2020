// Where a line can be cast, and what lives there. Paradise's sea is the beach's water here, its pool is Hippie's pool, and its
// fish tank is left out (no fish tanks here).

/// Every kind of fishing spot. The first one that matches what was clicked is used, so the pickier ones go first
GLOBAL_LIST_INIT(fishing_spots, list(
	new /datum/fishing_spot/toilet,
	new /datum/fishing_spot/plasma,
	new /datum/fishing_spot/deep_lava,
	new /datum/fishing_spot/lava,
	new /datum/fishing_spot/chasm,
	new /datum/fishing_spot/sea,
	new /datum/fishing_spot/pool,
	new /datum/fishing_spot/space,
))

/// Finds the kind of fishing spot `target` is, if it is one
/proc/get_fishing_spot(atom/target)
	for(var/datum/fishing_spot/spot as anything in GLOB.fishing_spots)
		if(spot.matches(target))
			return spot

/// One kind of place a line can be cast into, and what lives there.
/datum/fishing_spot
	/// What the angler casts into, as in "You cast your line into lava."
	var/name = "the water"
	/// Types of turf or object that are this kind of spot
	var/list/spot_types
	/// Line flags a line needs to be used here
	var/required_line = NONE
	/// What can bite here. Type of catch = how common it is
	var/list/catches
	/// Shortest wait for a bite
	var/bite_wait_min = 6 SECONDS
	/// Longest wait for a bite
	var/bite_wait_max = 20 SECONDS
	/// Played when the bobber lands and when something bites
	var/splash_sound = 'sound/effects/slosh.ogg'
	/// Is there a surface for the bobber to float on? Without one it hangs on the line
	var/has_surface = TRUE
	/// Something that sometimes comes up after the angler instead of taking the bait
	var/mob/living/lurker_type
	/// Percent chance of that, each time something would bite
	var/lurker_chance = 0

/datum/fishing_spot/proc/matches(atom/target)
	return is_type_in_list(target, spot_types)

/// Gives the reason `rod` can't be used on `target` right now, or null if it can
/datum/fishing_spot/proc/why_not(atom/target, obj/item/fishing_rod/rod)
	if((required_line & FISHING_LINE_HEATPROOF) && !(rod.line.line_flags & FISHING_LINE_HEATPROOF))
		return "[rod.line] would burn up in [name]. You need a heat-proof line."
	if((required_line & FISHING_LINE_LONG) && !(rod.line.line_flags & FISHING_LINE_LONG))
		return "[rod.line] is too short to reach the bottom of [name]."
	if((required_line & FISHING_LINE_MAGMA) && !(rod.line.line_flags & FISHING_LINE_MAGMA))
		return "[rod.line] would burn through long before it reached anything living in [name]. It takes an exosuit's steel line."

/**
 * Picks what takes the hook.
 *
 * Arguments:
 * * target - The turf or object being fished in
 * * bait_kind - The kind of bait on the hook, or null for a bare hook
 */
/datum/fishing_spot/proc/pick_catch(atom/target, bait_kind)
	var/list/weights = list()
	for(var/catch_type in catches)
		var/datum/fishing_catch/entry = GLOB.fishing_catches[catch_type]
		var/weight = entry.bite_weight(catches[catch_type], bait_kind)
		// Fish don't care much for a bare hook, so junk turns up more often
		if(!bait_kind && entry.fights)
			weight = max(1, round(weight / 2))
		weights[entry] = weight
	return pickweight(weights)

/// Takes the catch out of the spot as it's landed. Returns FALSE if it isn't there to take any more.
/datum/fishing_spot/proc/take_catch(atom/target, datum/fishing_catch/entry)
	return TRUE

// MARK: Toilet

/datum/fishing_spot/toilet
	name = "a toilet"
	spot_types = list(/obj/structure/toilet)
	catches = list(
		/datum/fishing_catch/feederfish = 20,
		/datum/fishing_catch/goldfish = 12,
		/datum/fishing_catch/creature/mouse = 6,
		/datum/fishing_catch/junk/cigbutt = 18,
		/datum/fishing_catch/junk/can = 10,
		/datum/fishing_catch/junk/soap = 8,
		/datum/fishing_catch/junk/boot = 6,
		/datum/fishing_catch/junk/rubber_ducky = 6,
		/datum/fishing_catch/junk/coin = 3,
	)

/datum/fishing_spot/toilet/why_not(atom/target, obj/item/fishing_rod/rod)
	var/obj/structure/toilet/toilet = target
	if(!toilet.open)
		return "The lid of [toilet] is down."
	return ..()

// MARK: Lavaland

/datum/fishing_spot/plasma
	name = "liquid plasma"
	spot_types = list(/turf/open/lava/plasma)
	required_line = FISHING_LINE_HEATPROOF
	bite_wait_min = 8 SECONDS
	bite_wait_max = 25 SECONDS
	splash_sound = 'sound/effects/bubbles2.ogg'
	catches = list(
		/datum/fishing_catch/plasma_lungfish = 30,
		/datum/fishing_catch/rime_pike = 14,
		/datum/fishing_catch/junk/plasma_ore = 14,
		/datum/fishing_catch/junk/bones = 12,
		/datum/fishing_catch/junk/boot = 8,
		/datum/fishing_catch/junk/can = 6,
		/datum/fishing_catch/junk/titanium_ore = 4,
		/datum/fishing_catch/junk/diamond_ore = 1,
	)

/datum/fishing_spot/lava
	name = "lava"
	spot_types = list(/turf/open/lava)
	required_line = FISHING_LINE_HEATPROOF
	bite_wait_min = 8 SECONDS
	bite_wait_max = 25 SECONDS
	splash_sound = 'sound/effects/footstep/lava1.ogg'
	lurker_type = /mob/living/simple_animal/hostile/asteroid/magma_lurker
	lurker_chance = 6
	catches = list(
		/datum/fishing_catch/ash_perch = 34,
		/datum/fishing_catch/cinder_crab = 22,
		/datum/fishing_catch/magma_eel = 10,
		/datum/fishing_catch/junk/slag = 12,
		/datum/fishing_catch/junk/bones = 10,
		/datum/fishing_catch/junk/gold_ore = 5,
		/datum/fishing_catch/junk/diamond_ore = 1,
	)

/**
 * Lava with nothing but lava for two tiles all round. Out here live the biggest things in the lava, and the sunken
 * loot of the necropolis, but only an exosuit's steel line reaches them, and a firefighter Ripley can wade out to it.
 */
/datum/fishing_spot/deep_lava
	name = "deep lava"
	spot_types = list(/turf/open/lava)
	required_line = FISHING_LINE_HEATPROOF | FISHING_LINE_MAGMA
	bite_wait_min = 10 SECONDS
	bite_wait_max = 30 SECONDS
	splash_sound = 'sound/effects/footstep/lava1.ogg'
	lurker_type = /mob/living/simple_animal/hostile/asteroid/magma_lurker
	lurker_chance = 18
	catches = list(
		/datum/fishing_catch/magma_eel = 26,
		/datum/fishing_catch/lava_leviathan = 9,
		/datum/fishing_catch/creature/magma_lurker = 8,
		/datum/fishing_catch/junk/gold_ore_lode = 14,
		/datum/fishing_catch/junk/diamond_cluster = 9,
		/datum/fishing_catch/junk/bluespace_crystals = 7,
		/datum/fishing_catch/junk/ashdrake_hide = 6,
		/datum/fishing_catch/junk/slag = 10,
		/datum/fishing_catch/junk/necropolis_chest = 3,
	)

/datum/fishing_spot/deep_lava/matches(atom/target)
	if(!..())
		return FALSE
	for(var/turf/T as anything in RANGE_TURFS(2, target))
		if(!istype(T, /turf/open/lava) || istype(T, /turf/open/lava/plasma))
			return FALSE
	return TRUE

/datum/fishing_spot/chasm
	name = "a chasm"
	spot_types = list(/turf/open/chasm)
	required_line = FISHING_LINE_LONG
	bite_wait_min = 10 SECONDS
	bite_wait_max = 30 SECONDS
	splash_sound = null
	has_surface = FALSE
	catches = list(
		/datum/fishing_catch/cave_blindfish = 36,
		/datum/fishing_catch/glowmaw_angler = 8,
		/datum/fishing_catch/junk/bones = 16,
		/datum/fishing_catch/junk/iron_ore = 12,
		/datum/fishing_catch/junk/sinew = 8,
		/datum/fishing_catch/junk/silver_ore = 6,
		/datum/fishing_catch/junk/boot = 6,
		/datum/fishing_catch/junk/diamond_ore = 1,
	)

// MARK: Water

/datum/fishing_spot/sea
	name = "the sea"
	spot_types = list(/turf/open/water)
	catches = list(
		/datum/fishing_catch/salmon = 20,
		/datum/fishing_catch/shrimp = 16,
		/datum/fishing_catch/feederfish = 10,
		/datum/fishing_catch/clownfish = 10,
		/datum/fishing_catch/catfish = 8,
		/datum/fishing_catch/electric_eel = 8,
		/datum/fishing_catch/glofish = 5,
		/datum/fishing_catch/shark = 4,
		/datum/fishing_catch/junk/boot = 5,
		/datum/fishing_catch/junk/can = 5,
		/datum/fishing_catch/junk/shard = 4,
		/datum/fishing_catch/junk/gold_coin = 1,
	)

/datum/fishing_spot/pool
	name = "the pool"
	spot_types = list(/turf/open/pool)
	catches = list(
		/datum/fishing_catch/goldfish = 22,
		/datum/fishing_catch/feederfish = 18,
		/datum/fishing_catch/shrimp = 14,
		/datum/fishing_catch/catfish = 10,
		/datum/fishing_catch/salmon = 10,
		/datum/fishing_catch/glofish = 5,
		/datum/fishing_catch/clownfish = 4,
		/datum/fishing_catch/electric_eel = 3,
		/datum/fishing_catch/junk/boot = 5,
		/datum/fishing_catch/junk/can = 5,
		/datum/fishing_catch/junk/rubber_ducky = 2,
		/datum/fishing_catch/junk/coin = 2,
	)

// A drained pool has nothing in it
/datum/fishing_spot/pool/why_not(atom/target, obj/item/fishing_rod/rod)
	var/turf/open/pool/water = target
	if(!water.filled)
		return "[water] has been drained."
	return ..()

// MARK: Space

/datum/fishing_spot/space
	name = "space"
	spot_types = list(/turf/open/space)
	bite_wait_min = 10 SECONDS
	bite_wait_max = 30 SECONDS
	splash_sound = null
	has_surface = FALSE
	catches = list(
		/datum/fishing_catch/comet_minnow = 32,
		/datum/fishing_catch/babycarp = 22,
		/datum/fishing_catch/void_ray = 6,
		/datum/fishing_catch/creature/space_carp = 4,
		/datum/fishing_catch/junk/rods = 10,
		/datum/fishing_catch/junk/shard = 8,
		/datum/fishing_catch/junk/titanium_ore = 5,
		/datum/fishing_catch/junk/can = 4,
		/datum/fishing_catch/junk/uranium_ore = 3,
	)

// Nothing lives in the blur outside a moving shuttle
/datum/fishing_spot/space/matches(atom/target)
	return ..() && !istype(target, /turf/open/space/transit)
