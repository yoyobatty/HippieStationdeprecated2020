// Bot Gym scenarios for crafting (goals/crafting.dm): the parts laid out at its feet and the crafting menu's Make.

/datum/bot_scenario/craft
	time_limit = 45 SECONDS
	layout = list(
		"##########",
		"#B.......#",
		"#........#",
		"##########")
	var/recipe_type

/datum/bot_scenario/craft/make_goal()
	if(goal_attempts > 1)
		return null //one go: the goal fetches what it's short of itself
	return new /datum/bot_goal/craft(recipe_type)

/datum/bot_scenario/craft/proc/made()
	var/datum/crafting_recipe/R = bot_crafting_recipe(recipe_type)
	return R && (locate(R.result) in bot.GetAllContents())

/datum/bot_scenario/craft/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(!made())
		return BOT_GYM_PENDING
	var/problem = leftovers()
	if(problem)
		fail_reason = problem
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// What it set down to work with and didn't pick back up.
/datum/bot_scenario/craft/proc/leftovers()
	for(var/obj/item/stack/S in range(1, bot))
		if(isturf(S.loc))
			return "left [S] on the floor"
	return null

/datum/bot_scenario/craft/bola
	name = "crafting: a bola from cable and metal in its bag, through the crafting menu"
	desc = "Restraints from the coil's own menu, then the parts on the floor at its feet and Make. The spare metal goes back in the bag."
	kit_backpack = list(/obj/item/stack/cable_coil, /obj/item/stack/sheet/metal/ten)
	recipe_type = /datum/crafting_recipe/bola

/datum/bot_scenario/craft/bola/check()
	. = ..()
	if(. == BOT_GYM_PASS && bot.bot_brain.craft_part_count(/obj/item/stack/sheet/metal) != 4)
		fail_reason = "the four sheets left over didn't go back in the bag"
		return BOT_GYM_FAIL

/datum/bot_scenario/craft/fetches_metal
	name = "crafting: short of metal for a bola, it goes and gets some first"
	desc = "Cable in the bag and nothing else: the metal sheets across the room are fetched, then it's made."
	kit_backpack = list(/obj/item/stack/cable_coil)
	recipe_type = /datum/crafting_recipe/bola
	layout = list(
		"############",
		"#B.........#",
		"#.........h#",
		"############")

/datum/bot_scenario/craft/fetches_metal/setup()
	place("h", new /obj/item/stack/sheet/metal/ten(first_marker("h")))

/datum/bot_scenario/craft/spear
	name = "crafting: a spear, with the shard on the floor and rods made from metal"
	desc = "Restraints from cable, a rod from a metal sheet, the glass shard picked up off the floor: a spear."
	kit_backpack = list(/obj/item/stack/cable_coil, /obj/item/stack/sheet/metal/five)
	recipe_type = /datum/crafting_recipe/spear
	layout = list(
		"##########",
		"#B.......#",
		"#......h.#",
		"##########")

/datum/bot_scenario/craft/spear/setup()
	place("h", new /obj/item/shard(first_marker("h")))

/datum/bot_scenario/craft/stunprod
	name = "crafting: a stunprod, and a high-capacity cell found and put in it"
	desc = "Restraints, a rod and an igniter make the prod, which comes out with no cell: the cell across the room goes in."
	kit_backpack = list(/obj/item/stack/cable_coil, /obj/item/stack/sheet/metal/five, /obj/item/assembly/igniter)
	recipe_type = /datum/crafting_recipe/stunprod
	layout = list(
		"###########",
		"#B........#",
		"#........h#",
		"###########")

/datum/bot_scenario/craft/stunprod/setup()
	place("h", new /obj/item/stock_parts/cell/high(first_marker("h")))

/datum/bot_scenario/craft/stunprod/check()
	. = ..()
	if(. != BOT_GYM_PASS)
		return
	var/obj/item/melee/baton/cattleprod/P = locate() in bot.GetAllContents()
	if(!P?.cell)
		if(!istype(brain.current_goal, /datum/bot_goal/craft) && !brain.suspended_goal)
			fail_reason = "made the prod, but there's no cell in it"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING //off for the cell

/datum/bot_scenario/craft/ahead_of_time
	name = "crafting ahead: an engineer with cable and metal makes a bola for the bag in a quiet moment"
	desc = "Some of the crew make something just in case: the duty picks an engineer who'd do it, and the bola ends up in the bag."
	job = "Station Engineer"
	kit_backpack = list(/obj/item/stack/cable_coil, /obj/item/stack/sheet/metal/ten)
	recipe_type = /datum/crafting_recipe/bola

/datum/bot_scenario/craft/ahead_of_time/make_goal()
	if(goal_attempts > 1)
		return null
	if("kit_roll" in brain.vars) //only there with the fix
		brain.vars["kit_roll"] = 1 //the kind who would
	var/datum/bot_duty/D = bot_duty_of(text2path("/datum/bot_duty/make_kit"))
	if(!D?.try_start(brain)) //a scripted bot doesn't look for its own duties
		log_line("the duty didn't start")
	return null

/datum/bot_scenario/craft/ahead_of_time/check()
	. = ..()
	if(. != BOT_GYM_PASS)
		return
	var/obj/item/restraints/legcuffs/bola/B = locate() in bot.GetAllContents()
	if(B in bot.held_items)
		fail_reason = "made it but it's still in hand, not in the bag"
		return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// Used on a suit (goals/fight_the_suit.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/griefed/suit/kit
	time_limit = 25 SECONDS
	layout = list(
		"##############",
		"#............#",
		"#.B.....VC...#",
		"#............#",
		"##############")
	var/mob/living/carbon/human/victim

/datum/bot_scenario/griefed/suit/kit/post_spawn()
	..()
	if(first_marker("V"))
		victim = stand_in(first_marker("V"), "Vic Victim")
	brain.nerve = 0.5

/datum/bot_scenario/griefed/suit/kit/grief()
	keep_at_it("beat", 15)

/datum/bot_scenario/griefed/suit/kit/proc/beat()
	punch(victim)
	return victim.stat == CONSCIOUS

/datum/bot_scenario/griefed/suit/kit/bola
	name = "nanosuit: a bola in the bag gets thrown at its legs"
	desc = "Seven tiles off and beating somebody. The bola made for the bag comes out and goes at its legs, so it can't sprint off."
	kit_backpack = list(/obj/item/restraints/legcuffs/bola)

/datum/bot_scenario/griefed/suit/kit/bola/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return griefer.legcuffed ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/suit/kit/made_on_the_spot
	name = "nanosuit: cable and metal on it, a bola's made on the spot and thrown"
	desc = "No weapon, but the makings of a bola in the bag: two seconds at the crafting menu, then it's at its legs."
	kit_backpack = list(/obj/item/stack/cable_coil, /obj/item/stack/sheet/metal/ten)

/datum/bot_scenario/griefed/suit/kit/made_on_the_spot/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (griefer.legcuffed && bot_transcript_has("made a bola")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/suit/kit/prod
	name = "nanosuit: a stunprod up close, while it's on its feet"
	desc = "A quarter of a stun gets through the suit: enough for the rest to pile on. Charged, switched on, on help intent."
	kit_hands = list(/obj/item/melee/baton/cattleprod) //bulky: it won't go in a bag
	layout = list(
		"##########",
		"#.BC.....#",
		"##########")

/datum/bot_scenario/griefed/suit/kit/prod/post_spawn()
	..()
	var/obj/item/melee/baton/cattleprod/P = locate() in bot.held_items
	if(P && !P.cell)
		P.cell = new /obj/item/stock_parts/cell/high(P)

/datum/bot_scenario/griefed/suit/kit/prod/grief()
	keep_at_it("punch_bot", 20)

/datum/bot_scenario/griefed/suit/kit/prod/proc/punch_bot()
	return punch(bot)

/datum/bot_scenario/griefed/suit/kit/prod/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_has("stunning [griefer] with") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/suit/kit/spear
	name = "nanosuit: a spear's wielded two-handed against it"
	desc = "Eighteen force wielded against ten one-handed: a fire axe was the only two-hander anybody used to wield."
	layout = list(
		"##########",
		"#.BC.....#",
		"##########")
	kit_hands = list(/obj/item/twohanded/spear)

/datum/bot_scenario/griefed/suit/kit/spear/grief()
	keep_at_it("punch_bot", 20)

/datum/bot_scenario/griefed/suit/kit/spear/proc/punch_bot()
	return punch(bot)

/datum/bot_scenario/griefed/suit/kit/spear/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/twohanded/spear/S = locate() in bot.held_items
	return (S?.wielded && bot_transcript_has("hitting [griefer] with [S]")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/craft/spiked_bat
	name = "crafting: a spiked bat, from two barricades broken up for planks and rods made from metal"
	desc = "Bats are made from five planks, and planks come from breaking up the wooden barricades in maintenance (three from each). Then five rods hammered in."
	time_limit = 90 SECONDS
	kit_hands = list(/obj/item/storage/toolbox/mechanical)
	kit_backpack = list(/obj/item/stack/sheet/metal/five)
	recipe_type = /datum/crafting_recipe/bbat_spiked
	layout = list(
		"############",
		"#B.........#",
		"#.....k..k.#",
		"#..........#",
		"############")

/datum/bot_scenario/craft/spiked_bat/setup()
	for(var/turf/T in markers["k"])
		place("k", new /obj/structure/barricade/wooden(T))

/datum/bot_scenario/craft/spiked_bat/make_goal()
	if(goal_attempts > 1)
		return null
	return new /datum/bot_goal/craft(recipe_type, TRUE)

/datum/bot_scenario/craft/spiked_bat/leftovers()
	return null //a spare plank or two is fine
