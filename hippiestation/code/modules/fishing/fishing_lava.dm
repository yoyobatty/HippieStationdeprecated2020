// What lives in the lava: the magma lurker that comes up after anglers, the lava leviathan, and the treasure of deep lava

// ---- Magma lurker

/**
  * A long, low thing of black crust and glowing cracks that lives in the lava.
  *
  * Fishing in lava sometimes brings one up after the angler instead of a fish, more often out in deep lava, and one can be
  * hooked and hauled out too. Either way it comes out fighting.
  */
/mob/living/simple_animal/hostile/asteroid/magma_lurker
	name = "magma lurker"
	desc = "A long, low thing of black crust and glowing cracks that lives in the lava. It doesn't like being fished for."
	icon = FISHING_ICON
	icon_state = "magma_lurker"
	icon_living = "magma_lurker"
	icon_aggro = "magma_lurker"
	icon_dead = "magma_lurker_dead"
	maxHealth = 110
	health = 110
	melee_damage_lower = 10
	melee_damage_upper = 15
	melee_damage_type = BURN
	obj_damage = 35
	attacktext = "bites"
	attack_sound = 'sound/weapons/bite.ogg'
	deathmessage = "goes still, and the glow in its cracks fades."
	move_to_delay = 4
	vision_range = 5
	aggro_vision_range = 9
	butcher_results = list(/obj/item/stack/sheet/sinew = 2, /obj/item/stack/sheet/bone = 3, /obj/item/stack/ore/gold = 2)

/mob/living/simple_animal/hostile/asteroid/magma_lurker/Initialize(mapload)
	. = ..()
	set_light(2, 1, "#FF6A1F")
	// Climbing up out of the lava
	alpha = 0
	pixel_y = -10
	animate(src, alpha = 255, pixel_y = 0, time = 0.8 SECONDS, easing = SINE_EASING | EASE_OUT)

/mob/living/simple_animal/hostile/asteroid/magma_lurker/death(gibbed)
	. = ..()
	set_light(0)

/datum/fishing_catch/creature/magma_lurker
	name = "magma lurker"
	catch_type = /mob/living/simple_animal/hostile/asteroid/magma_lurker
	strength = 46
	stamina = 18
	bait_likes = list(FISHING_BAIT_MEAT = 3)
	rare = TRUE

// ---- Lava leviathan

/// The biggest thing in the lava, and only out in the deep.
/obj/item/fish/wild/lava_leviathan
	name = "lava leviathan"
	desc = "A huge armoured fish from deep in the lava, plated like cooled rock with fire showing through the seams. It's still hot enough to cook on."
	icon_state = "lava_leviathan"
	w_class = WEIGHT_CLASS_HUGE
	force = 12
	fillet_type = /obj/item/reagent_containers/food/snacks/fish_fillet/magma
	fillet_amount = 6

/obj/item/fish/wild/lava_leviathan/Initialize(mapload)
	. = ..()
	set_light(3, 1.5, "#FF7B2E")

/datum/fishing_catch/lava_leviathan
	name = "lava leviathan"
	catch_type = /obj/item/fish/wild/lava_leviathan
	min_length = 150
	max_length = 420
	strength = 58
	stamina = 26
	run_time = 3
	bait_likes = list(FISHING_BAIT_MEAT = 2, FISHING_BAIT_LIVE = 3)
	rare = TRUE

// ---- Deep lava treasure

/datum/fishing_catch/junk/gold_ore_lode
	name = "lump of gold ore"
	catch_type = /obj/item/stack/ore/gold
	amount = 8

/datum/fishing_catch/junk/diamond_cluster
	name = "cluster of diamonds"
	catch_type = /obj/item/stack/ore/diamond
	amount = 3
	rare = TRUE

/datum/fishing_catch/junk/bluespace_crystals
	name = "handful of bluespace crystals"
	catch_type = /obj/item/stack/ore/bluespace_crystal
	amount = 2
	rare = TRUE

/datum/fishing_catch/junk/ashdrake_hide
	name = "ash drake hide"
	catch_type = /obj/item/stack/sheet/animalhide/ashdrake
	amount = 2

/// A necropolis chest that sank into the lava long ago, still full
/datum/fishing_catch/junk/necropolis_chest
	name = "sunken necropolis chest"
	catch_type = /obj/structure/closet/crate/necropolis/tendril
	rare = TRUE
