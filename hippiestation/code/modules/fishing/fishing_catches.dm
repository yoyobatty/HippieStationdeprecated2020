/// Every thing that can be fished up, by type
GLOBAL_LIST_INIT(fishing_catches, init_fishing_catches())

/proc/init_fishing_catches()
	. = list()
	for(var/datum/fishing_catch/catch_type as anything in subtypesof(/datum/fishing_catch))
		// Types without anything to land only group the others
		if(!initial(catch_type.catch_type))
			continue
		.[catch_type] = new catch_type

/// One thing that can end up on the hook.
/datum/fishing_catch
	/// What the angler is told they caught
	var/name = "something"
	/// What gets made when it's landed
	var/atom/movable/catch_type
	/// Shortest it can be, in cm. 0 for things that aren't measured
	var/min_length = 0
	/// Longest it can be, in cm
	var/max_length = 0
	/// How hard it pulls. A plain line snaps when a fish of about 32 is reeled against for a whole run
	var/strength = 10
	/// How many seconds of running it has in it before it's worn out
	var/stamina = 5
	/// How long one run lasts, in seconds
	var/run_time = 2
	/// How long it rests between runs, in seconds
	var/rest_time = 2.5
	/// Bait it likes. Kind of bait = how many times more likely it is to bite on it
	var/list/bait_likes
	/// Does it fight? Junk comes straight in
	var/fights = TRUE
	/// Rare catches get a louder message
	var/rare = FALSE
	/// How many come up at once, for stacks like ore
	var/amount = 1

/// Picks how long this one is, in cm. Most are small, a few are big.
/datum/fishing_catch/proc/roll_length()
	if(!max_length)
		return 0
	return round(min_length + (max_length - min_length) * (rand() ** 1.6), 0.1)

/// How much harder a fish of this length fights than the smallest of its kind. From 0.8 to 1.3.
/datum/fishing_catch/proc/size_factor(length)
	if(max_length <= min_length)
		return 1
	return 0.8 + 0.5 * ((length - min_length) / (max_length - min_length))

/// How likely this is to bite, given its place in a spot's table and the bait on the hook
/datum/fishing_catch/proc/bite_weight(base_weight, bait_kind)
	if(bait_kind && bait_likes && bait_likes[bait_kind])
		return round(base_weight * bait_likes[bait_kind])
	return base_weight

/// A word for how big the thing on the line feels, shown while reeling
/datum/fishing_catch/proc/pull_hint(fight_strength)
	switch(fight_strength)
		if(-INFINITY to 12)
			return "a light tug"
		if(12 to 24)
			return "a steady pull"
		if(24 to 36)
			return "a hard pull"
	return "a monstrous pull"

/**
 * Puts the catch in the world once it's reeled in.
 *
 * Arguments:
 * * user - The angler
 * * session - The cast that caught it
 */
/datum/fishing_catch/proc/land(mob/living/user, datum/fishing_session/session)
	var/turf/landing = get_turf(session.body)
	var/atom/movable/landed = ispath(catch_type, /obj/item/stack) ? new catch_type(landing, amount) : new catch_type(landing)
	if(max_length)
		// The top third of the size range counts as a big one
		var/big = size_factor(session.length_cm) >= 1.13
		landed.AddComponent(/datum/component/caught_fish, session.length_cm, big, user.real_name, session.spot.name)
	session.rod.receive_catch(landed, user)
	return landed

// MARK: Pool and sea fish

/datum/fishing_catch/goldfish
	name = "goldfish"
	catch_type = /obj/item/fish/goldfish
	min_length = 5
	max_length = 25
	strength = 12
	stamina = 6
	bait_likes = list(FISHING_BAIT_PLANT = 3, FISHING_BAIT_CHEESE = 2)

/datum/fishing_catch/feederfish
	name = "feeder fish"
	catch_type = /obj/item/fish/feederfish
	min_length = 2
	max_length = 6
	strength = 6
	stamina = 3
	bait_likes = list(FISHING_BAIT_PLANT = 2)

/datum/fishing_catch/shrimp
	name = "shrimp"
	catch_type = /obj/item/fish/shrimp
	min_length = 4
	max_length = 12
	strength = 6
	stamina = 3
	bait_likes = list(FISHING_BAIT_PLANT = 2, FISHING_BAIT_MEAT = 2)

/datum/fishing_catch/salmon
	name = "salmon"
	catch_type = /obj/item/fish/salmon
	min_length = 40
	max_length = 110
	strength = 28
	stamina = 12
	bait_likes = list(FISHING_BAIT_LIVE = 3, FISHING_BAIT_MEAT = 2, FISHING_BAIT_SHINY = 2)

/datum/fishing_catch/catfish
	name = "catfish"
	catch_type = /obj/item/fish/catfish
	min_length = 30
	max_length = 130
	strength = 30
	stamina = 14
	rest_time = 3
	bait_likes = list(FISHING_BAIT_CHEESE = 3, FISHING_BAIT_MEAT = 2)

/datum/fishing_catch/glofish
	name = "glofish"
	catch_type = /obj/item/fish/glofish
	min_length = 3
	max_length = 8
	strength = 8
	stamina = 4
	bait_likes = list(FISHING_BAIT_GLOW = 4)

/datum/fishing_catch/electric_eel
	name = "electric eel"
	catch_type = /obj/item/fish/electric_eel
	min_length = 60
	max_length = 200
	strength = 34
	stamina = 12
	run_time = 1.5
	rest_time = 2
	bait_likes = list(FISHING_BAIT_LIVE = 3, FISHING_BAIT_MEAT = 2)

/datum/fishing_catch/clownfish
	name = "clown fish"
	catch_type = /obj/item/fish/clownfish
	min_length = 6
	max_length = 15
	bait_likes = list(FISHING_BAIT_PLANT = 3)

/datum/fishing_catch/shark
	name = "shark"
	catch_type = /obj/item/fish/shark
	min_length = 150
	max_length = 400
	strength = 45
	stamina = 22
	run_time = 2.5
	bait_likes = list(FISHING_BAIT_LIVE = 4, FISHING_BAIT_MEAT = 3)
	rare = TRUE

/datum/fishing_catch/babycarp
	name = "baby space carp"
	catch_type = /obj/item/fish/babycarp
	min_length = 20
	max_length = 60
	strength = 22
	stamina = 9
	bait_likes = list(FISHING_BAIT_MEAT = 3, FISHING_BAIT_LIVE = 2)

// MARK: Lava fish

/datum/fishing_catch/magma_eel
	name = "magma eel"
	catch_type = /obj/item/fish/wild/magma_eel
	min_length = 50
	max_length = 180
	strength = 36
	stamina = 14
	run_time = 1.5
	rest_time = 2
	bait_likes = list(FISHING_BAIT_MEAT = 3, FISHING_BAIT_LIVE = 3)
	rare = TRUE

/datum/fishing_catch/ash_perch
	name = "ash perch"
	catch_type = /obj/item/fish/wild/ash_perch
	min_length = 15
	max_length = 45
	strength = 18
	stamina = 8
	bait_likes = list(FISHING_BAIT_PLANT = 2, FISHING_BAIT_CHEESE = 2)

/datum/fishing_catch/cinder_crab
	name = "cinder crab"
	catch_type = /obj/item/fish/wild/cinder_crab
	min_length = 10
	max_length = 30
	strength = 14
	stamina = 6
	rest_time = 3.5
	bait_likes = list(FISHING_BAIT_MEAT = 2, FISHING_BAIT_SHINY = 3)

// MARK: Plasma fish

/datum/fishing_catch/plasma_lungfish
	name = "plasma lungfish"
	catch_type = /obj/item/fish/wild/plasma_lungfish
	min_length = 40
	max_length = 120
	strength = 30
	stamina = 16
	rest_time = 3
	bait_likes = list(FISHING_BAIT_GLOW = 3, FISHING_BAIT_LIVE = 2)

/datum/fishing_catch/rime_pike
	name = "rime pike"
	catch_type = /obj/item/fish/wild/rime_pike
	min_length = 50
	max_length = 150
	strength = 38
	stamina = 12
	run_time = 1.5
	bait_likes = list(FISHING_BAIT_LIVE = 3, FISHING_BAIT_SHINY = 3)
	rare = TRUE

// MARK: Chasm fish

/datum/fishing_catch/cave_blindfish
	name = "cave blindfish"
	catch_type = /obj/item/fish/wild/cave_blindfish
	min_length = 8
	max_length = 25
	strength = 12
	stamina = 6
	bait_likes = list(FISHING_BAIT_CHEESE = 2, FISHING_BAIT_MEAT = 2)

/datum/fishing_catch/glowmaw_angler
	name = "glowmaw angler"
	catch_type = /obj/item/fish/wild/glowmaw_angler
	min_length = 30
	max_length = 90
	strength = 32
	stamina = 14
	bait_likes = list(FISHING_BAIT_GLOW = 4, FISHING_BAIT_LIVE = 2)
	rare = TRUE

// MARK: Space fish

/datum/fishing_catch/void_ray
	name = "void ray"
	catch_type = /obj/item/fish/wild/void_ray
	min_length = 80
	max_length = 250
	strength = 40
	stamina = 18
	run_time = 2.5
	rest_time = 3
	bait_likes = list(FISHING_BAIT_SHINY = 4, FISHING_BAIT_GLOW = 2)
	rare = TRUE

/datum/fishing_catch/comet_minnow
	name = "comet minnow"
	catch_type = /obj/item/fish/wild/comet_minnow
	min_length = 5
	max_length = 15
	stamina = 4
	run_time = 1
	rest_time = 1.5
	bait_likes = list(FISHING_BAIT_SHINY = 2, FISHING_BAIT_PLANT = 2)

// MARK: Living catches

/// Things that come up alive and walk off on their own.
/datum/fishing_catch/creature

/datum/fishing_catch/creature/land(mob/living/user, datum/fishing_session/session)
	return new catch_type(get_turf(session.body))

/datum/fishing_catch/creature/mouse
	name = "mouse"
	catch_type = /mob/living/simple_animal/mouse
	fights = FALSE
	bait_likes = list(FISHING_BAIT_CHEESE = 5)

/datum/fishing_catch/creature/space_carp
	name = "space carp"
	catch_type = /mob/living/simple_animal/hostile/carp
	strength = 42
	stamina = 16
	run_time = 2.5
	bait_likes = list(FISHING_BAIT_MEAT = 3, FISHING_BAIT_LIVE = 3)
	rare = TRUE

// MARK: Junk and treasure

/// Things that just come up on the hook without a fight.
/datum/fishing_catch/junk
	fights = FALSE

/datum/fishing_catch/junk/boot
	name = "old boot"
	catch_type = /obj/item/clothing/shoes/sneakers/black

/datum/fishing_catch/junk/can
	name = "crushed can"
	catch_type = /obj/item/trash/can

/datum/fishing_catch/junk/cigbutt
	name = "cigarette butt"
	catch_type = /obj/item/cigbutt

/datum/fishing_catch/junk/soap
	name = "bar of soap"
	catch_type = /obj/item/soap

/datum/fishing_catch/junk/rubber_ducky
	name = "rubber ducky"
	catch_type = /obj/item/bikehorn/rubberducky

/datum/fishing_catch/junk/shard
	name = "shard of glass"
	catch_type = /obj/item/shard

/datum/fishing_catch/junk/rods
	name = "metal rod"
	catch_type = /obj/item/stack/rods

/datum/fishing_catch/junk/bones
	name = "bone"
	catch_type = /obj/item/stack/sheet/bone

/datum/fishing_catch/junk/sinew
	name = "strand of sinew"
	catch_type = /obj/item/stack/sheet/sinew

/datum/fishing_catch/junk/slag
	name = "lump of slag"
	catch_type = /obj/item/stack/ore/slag

/datum/fishing_catch/junk/coin
	name = "lost coin"
	catch_type = /obj/item/coin/silver
	bait_likes = list(FISHING_BAIT_SHINY = 2)

/datum/fishing_catch/junk/gold_coin
	name = "gold coin"
	catch_type = /obj/item/coin/gold
	bait_likes = list(FISHING_BAIT_SHINY = 2)
	rare = TRUE

/datum/fishing_catch/junk/iron_ore
	name = "chunk of iron ore"
	catch_type = /obj/item/stack/ore/iron

/datum/fishing_catch/junk/silver_ore
	name = "chunk of silver ore"
	catch_type = /obj/item/stack/ore/silver

/datum/fishing_catch/junk/gold_ore
	name = "chunk of gold ore"
	catch_type = /obj/item/stack/ore/gold

/datum/fishing_catch/junk/plasma_ore
	name = "chunk of plasma ore"
	catch_type = /obj/item/stack/ore/plasma

/datum/fishing_catch/junk/titanium_ore
	name = "chunk of titanium ore"
	catch_type = /obj/item/stack/ore/titanium

/datum/fishing_catch/junk/uranium_ore
	name = "chunk of uranium ore"
	catch_type = /obj/item/stack/ore/uranium

/datum/fishing_catch/junk/diamond_ore
	name = "rough diamond"
	catch_type = /obj/item/stack/ore/diamond
	rare = TRUE
