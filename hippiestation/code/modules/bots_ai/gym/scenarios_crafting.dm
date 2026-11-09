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

// ---------------------------------------------------------------------------------------------
// Explosives against a suit (goals/chem_lab.dm, goals/fight_the_suit.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/chem_brew/suit_grenade
	name = "chem: a suit's been seen, so the chemist's next brew for itself is an explosive grenade for it"
	desc = "Potassium in one beaker, water in the other, into a case with cable and a screwdriver. Ahead of the heals: there's a suit about."
	label = "explosive"
	time_limit = 90 SECONDS
	station_wide = TRUE //"a suit's been seen" is the whole station's, and the chemist would take another arena's mutagen order: run by name, alone
	kit_backpack = list(/obj/item/reagent_containers/glass/beaker/large, /obj/item/reagent_containers/glass/beaker/large, /obj/item/stack/cable_coil, /obj/item/screwdriver)

/datum/bot_scenario/chem_brew/suit_grenade/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_NORMAL) //not a powergamer: it's the suit that has it making one
	GLOB.bot_suit_seen_at["gym suit"] = world.time
	new /obj/item/grenade/chem_grenade(first_marker("."))

/datum/bot_scenario/chem_brew/suit_grenade/make_goal()
	return new /datum/bot_goal/synthesize_medicine() //its own choice of brew (brew_for_self())

/datum/bot_scenario/chem_brew/suit_grenade/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return brain.bot_ready_bomb_grenade() ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chem_brew/suit_grenade/release_run()
	GLOB.bot_suit_seen_at -= "gym suit"
	return ..()

/datum/bot_scenario/griefed/suit/grenade
	name = "nanosuit: an explosive grenade thrown at it from a safe distance, and it holds back till it goes"
	desc = "Six tiles off with nobody else near it. Primed, thrown, and the thrower waits for the blast rather than walking into it."
	blast_margin = 4
	time_limit = 20 SECONDS
	kit_backpack = list(/obj/item/grenade/chem_grenade/bot_gym_explosive)
	layout = list(
		"##############",
		"#............#",
		"#.B.....C....#",
		"#............#",
		"##############")
	var/blasted = FALSE

/datum/bot_scenario/griefed/suit/grenade/post_spawn()
	..()
	brain.nerve = 0.5

/datum/bot_scenario/griefed/suit/grenade/grief()
	brain.look_out_for_trouble() //a scripted bot doesn't look round by itself

/datum/bot_scenario/griefed/suit/grenade/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(griefer.getBruteLoss() + griefer.getFireLoss() >= 10 && bot_transcript_has("throwing the chemical grenade")) //the gym's grenade is small: a light blast
		blasted = TRUE
	if(!blasted)
		return BOT_GYM_PENDING
	if(bot.getBruteLoss() + bot.getFireLoss() >= 20)
		fail_reason = "caught in its own blast"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/griefed/suit/no_grenade_in_a_crowd
	name = "nanosuit: with somebody fighting it, the grenade stays in the bag"
	desc = "It's for the suit, not the crew round it: somebody's right next to it, so no grenade."
	blast_margin = 4
	time_limit = 12 SECONDS
	kit_backpack = list(/obj/item/grenade/chem_grenade/bot_gym_explosive)
	layout = list(
		"##############",
		"#............#",
		"#.B.....VC...#",
		"#............#",
		"##############")
	var/mob/living/carbon/human/victim

/datum/bot_scenario/griefed/suit/no_grenade_in_a_crowd/post_spawn()
	..()
	victim = stand_in(first_marker("V"), "Vic Victim")
	brain.nerve = 0.5

/datum/bot_scenario/griefed/suit/no_grenade_in_a_crowd/grief()
	brain.look_out_for_trouble()

/datum/bot_scenario/griefed/suit/no_grenade_in_a_crowd/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_has("throwing the grenade") || bot_transcript_has("throwing the chemical grenade"))
		fail_reason = "grenaded the crew along with it"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/suit/no_grenade_in_a_crowd/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/griefed/suit/lance
	name = "nanosuit: a hothead with a spear and an explosive grenade makes a lance and drives it in"
	desc = "The spear and the grenade tied together at the crafting menu, then wielded and driven into the suit. It goes off on the suit, and on the one holding it."
	blast_margin = 4
	time_limit = 25 SECONDS
	kit_hands = list(/obj/item/twohanded/spear)
	kit_backpack = list(/obj/item/grenade/chem_grenade/bot_gym_explosive)
	layout = list(
		"##############",
		"#............#",
		"#.B.....C....#",
		"#............#",
		"##############")

/datum/bot_scenario/griefed/suit/lance/post_spawn()
	..()
	brain.nerve = 0.8
	brain.temper = 0.9

/datum/bot_scenario/griefed/suit/lance/grief()
	brain.look_out_for_trouble()

/datum/bot_scenario/griefed/suit/lance/check()
	if(!bot || QDELETED(bot))
		return BOT_GYM_FAIL
	if(bot.stat == DEAD)
		fail_reason = "killed itself with it"
		return BOT_GYM_FAIL
	return (bot_transcript_has("driving the explosive lance") && griefer.getBruteLoss() + griefer.getFireLoss() >= 20) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chem_brew/suit_grenade/toolbox
	name = "chem: a suit grenade with no cable or screwdriver on it, so it fetches an electrical toolbox for both"
	desc = "Chemists don't carry tools, and the nearest loose ones are usually behind Engineering's doors: a chemist in a real shift tried eight times and never made the grenade. An electrical toolbox has both."
	kit_backpack = list(/obj/item/reagent_containers/glass/beaker/large, /obj/item/reagent_containers/glass/beaker/large)

/datum/bot_scenario/chem_brew/suit_grenade/toolbox/post_spawn()
	..()
	new /obj/item/storage/toolbox/electrical(first_marker("."))

// ---------------------------------------------------------------------------------------------
// Hands full of tools, and what the errand's for on the floor (make_room_for_item(), bot_items.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/hands_full_of_tools
	name = "items: a welder and wirecutters in its hands and a full bag, and it still picks up the beaker it went for"
	desc = "Tools are never dropped for something noticed in passing. But this beaker is the errand: one tool goes down for it, to be fetched after. A chemist in a real shift failed every brew this way, 24 times."
	time_limit = 20 SECONDS
	kit_hands = list(/obj/item/weldingtool, /obj/item/wirecutters)
	kit_backpack = list(/obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher)
	layout = list(
		"##########",
		"#B.....h.#",
		"##########")

/datum/bot_scenario/hands_full_of_tools/setup()
	place("h", new /obj/item/reagent_containers/glass/beaker/large(first_marker("h")))

/datum/bot_scenario/hands_full_of_tools/post_spawn()
	..()
	for(var/slot in list(ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET))
		if(!bot.get_item_by_slot(slot))
			bot.equip_to_slot_or_del(new /obj/item/flashlight(bot), slot)
	if(!bot.get_item_by_slot(ITEM_SLOT_BELT))
		bot.equip_to_slot_or_del(new /obj/item/storage/belt/fannypack(bot), ITEM_SLOT_BELT)
	var/obj/item/storage/belt/fannypack/F = bot.get_item_by_slot(ITEM_SLOT_BELT)
	if(istype(F))
		for(var/i in 1 to 3)
			new /obj/item/flashlight(F)

/datum/bot_scenario/hands_full_of_tools/make_goal()
	if(goal_attempts > 1)
		return null
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/reagent_containers/glass/beaker
	get.lawful = TRUE
	return get

/datum/bot_scenario/hands_full_of_tools/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/reagent_containers/glass/beaker/large) in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// A full bag cleared out (goals/clear_bag.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/clear_bag
	name = "items: a bag nearly full of junk, the rubbish goes in the bin and the rest on a table, and what it needs stays"
	desc = "134 of 143 bags were full at the end of a shift, and every new thing pushed another out onto the floor. Cigarette butts to the bin; the salt, pepper, spare shoes, third drink, second screwdriver and second first-aid kit onto the table; one of each and two drinks kept."
	time_limit = 30 SECONDS
	kit_backpack = list(/obj/item/cigbutt, /obj/item/cigbutt, /obj/item/cigbutt, /obj/item/reagent_containers/food/condiment/saltshaker, /obj/item/reagent_containers/food/condiment/peppermill,
		/obj/item/clothing/shoes/sneakers/black, /obj/item/reagent_containers/food/drinks/soda_cans/cola, /obj/item/reagent_containers/food/drinks/soda_cans/cola, /obj/item/reagent_containers/food/drinks/soda_cans/cola,
		/obj/item/screwdriver, /obj/item/screwdriver, /obj/item/storage/firstaid/regular, /obj/item/storage/firstaid/regular)
	layout = list(
		"###########",
		"#B........#",
		"#....n..t.#",
		"###########")

/datum/bot_scenario/clear_bag/setup()
	place("n", new /obj/machinery/disposal/bin(first_marker("n")))

/datum/bot_scenario/clear_bag/make_goal()
	if(goal_attempts > 1)
		return null
	var/datum/bot_duty/D = bot_duty_of(text2path("/datum/bot_duty/clear_bag")) //only there with the fix
	if(!D?.try_start(brain)) //a scripted bot doesn't look for its own duties
		var/obj/item/storage/pack = bot.get_item_by_slot(ITEM_SLOT_BACK)
		var/datum/component/storage/S = pack?.GetComponent(/datum/component/storage)
		var/used = 0
		for(var/obj/item/I in pack?.contents)
			used += I.w_class
		log_line("the duty didn't start: [pack] holds [length(pack?.contents)] things, [used] of [S?.max_combined_w_class] ([S?.max_items] items max)")
	return null

/datum/bot_scenario/clear_bag/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/disposal/bin/B = first_placed("n")
	var/turf/table = first_marker("t")
	var/list/carried = bot.GetAllContents()
	var/butts_binned = 0
	for(var/obj/item/cigbutt/C in B)
		butts_binned++
	var/on_table = 0
	for(var/obj/item/I in table)
		on_table++
	var/screwdrivers = 0
	var/kits = 0
	var/drinks = 0
	for(var/obj/item/I in carried)
		if(istype(I, /obj/item/screwdriver))
			screwdrivers++
		else if(istype(I, /obj/item/storage/firstaid))
			kits++
		else if(istype(I, /obj/item/reagent_containers/food/drinks))
			drinks++
	if(screwdrivers < 1 || kits < 1 || drinks < 2)
		fail_reason = "cleared out what it needs (screwdrivers [screwdrivers], kits [kits], drinks [drinks])"
		return BOT_GYM_FAIL
	// salt, pepper, shoes, the third drink, the second screwdriver, the second kit
	return (butts_binned == 3 && on_table >= 6 && screwdrivers == 1 && kits == 1 && drinks == 2) ? BOT_GYM_PASS : BOT_GYM_PENDING
