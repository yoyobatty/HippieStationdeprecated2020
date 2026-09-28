// Bot Gym scenarios for experimental botany (goals/botany_projects.dm): hacking the seed vendor,
// mutating a species, splicing genes with the DNA manipulator, and using what comes out.
// Trays in these arenas run a time-lapse (cycledelay 2s instead of 20s) so growing and mutating
// fits in a test run; everything else is real time.

/datum/bot_scenario/botany/project
	time_limit = 150 SECONDS
	max_goal_attempts = 1000 //re-poll the botany round each second, like handle_wander() does in a real round
	/// Recipe the mad scientist works on.
	var/recipe_type
	var/time_lapse = 20

/datum/bot_scenario/botany/project/setup()
	for(var/obj/machinery/hydroponics/H in placed["H"])
		H.cycledelay = time_lapse

/datum/bot_scenario/botany/project/post_spawn()
	..()
	brain.botany_temperament = "mad scientist"
	brain.next_botany_project_time = 0
	if(recipe_type)
		brain.botany_project = new(locate(recipe_type) in GLOB.bot_botany_recipes)

/// Puts an item of path in the bot's backpack.
/datum/bot_scenario/botany/project/proc/pack(path)
	return bot.equip_to_slot_or_del(new path(bot), ITEM_SLOT_BACKPACK)

/datum/bot_scenario/botany/project/hack_megaseed
	name = "botanist hacks the MegaSeed for contraband"
	desc = "Screwdriver and multitool in the bag. Open the panel, pulse wires until the green contraband light is on, put back anything else a pulse changed (waiting out a shock), and screw the panel shut."
	layout = list(
		"#########",
		"#B.....M#",
		"#.......#",
		"#########")

/datum/bot_scenario/botany/project/hack_megaseed/post_spawn()
	..()
	pack(/obj/item/screwdriver)
	pack(/obj/item/multitool)

/datum/bot_scenario/botany/project/hack_megaseed/issue_goal()
	goal_attempts++
	if(goal_attempts > 3)
		return
	brain.assign_goal(new /datum/bot_goal/botany_project_errand/hack_seed_vendor(first_placed("M")))

/datum/bot_scenario/botany/project/hack_megaseed/botany_check()
	var/obj/machinery/vending/V = first_placed("M")
	if(!V.extended_inventory || V.panel_open || brain.current_goal)
		return BOT_GYM_PENDING
	if(V.shoot_inventory || !V.scan_id || V.shut_up)
		fail_reason = "left the vendor [V.shoot_inventory ? "throwing its stock" : (V.shut_up ? "muted" : "with ID checks off")]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/botany/project/splice_acid_melons
	name = "mad scientist splices acid melons"
	desc = "Death nettle, tomato and watermelon seeds plus two blank disks. Extract fluorosulfuric acid from the nettle and Liquid Contents from the tomato with the DNA manipulator, splice both into the watermelon and plant it."
	layout = list(
		"##########",
		"#B.......#",
		"#.H..Q.H.#",
		"#........#",
		"##########")
	recipe_type = /datum/botany_recipe/acid_melons

/datum/bot_scenario/botany/project/splice_acid_melons/post_spawn()
	..()
	pack(/obj/item/seeds/nettle/death)
	pack(/obj/item/seeds/tomato)
	pack(/obj/item/seeds/watermelon)
	pack(/obj/item/disk/plantgene)
	pack(/obj/item/disk/plantgene)

/datum/bot_scenario/botany/project/splice_acid_melons/botany_check()
	var/datum/botany_recipe/R = locate(/datum/botany_recipe/acid_melons) in GLOB.bot_botany_recipes
	for(var/obj/machinery/hydroponics/H in placed["H"])
		if(H.myseed && R.is_result(H.myseed))
			return BOT_GYM_PASS
		if(H.myseed)
			fail_reason = "planted [H.myseed] instead of the acid melon"
			return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/botany/project/mutagen_lemons
	name = "mad scientist mutates combustible lemons"
	desc = "Two lemon packets and a large beaker of 60u unstable mutagen. Plant the lemons, feed Left 4 Zed, pour 50u of mutagen for a guaranteed mutation, lock the species with Robust Harvest, harvest, and leave some on the counter."
	layout = list(
		"############",
		"#B.........#",
		"#.H..H..N..#",
		"#..........#",
		"#.u.K.Z..t.#",
		"############")
	recipe_type = /datum/botany_recipe/combustible_lemons
	time_limit = 180 SECONDS

/datum/bot_scenario/botany/project/mutagen_lemons/post_spawn()
	..()
	pack(/obj/item/seeds/lemon)
	pack(/obj/item/seeds/lemon)
	var/obj/item/reagent_containers/glass/beaker/large/B = new(bot)
	B.reagents.add_reagent(/datum/reagent/toxin/mutagen, 60)
	bot.equip_to_slot_or_del(B, ITEM_SLOT_BACKPACK)

/datum/bot_scenario/botany/project/mutagen_lemons/botany_check()
	var/obj/structure/table/T = first_placed("t")
	if(locate(/obj/item/reagent_containers/food/snacks/grown/firelemon) in T.loc)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/botany/project/death_nettles_from_scratch
	name = "mad scientist breeds death nettles from scratch"
	desc = "No mutagen. Hack the MegaSeed for nettle seeds, plant two mutation trays on Left 4 Zed and harvest them until one turns into death nettles (1 in 16 per harvest), then harvest those."
	layout = list(
		"#############",
		"#B..........#",
		"#.H..H..H...#",
		"#...........#",
		"#.N..M..Z.t.#",
		"#...........#",
		"#.u.K.......#",
		"#############")
	recipe_type = /datum/botany_recipe/death_nettles
	time_limit = 420 SECONDS //a 1 in 16 chance per harvest - most runs take 1-3 minutes, a few much longer
	time_lapse = 10

/datum/bot_scenario/botany/project/death_nettles_from_scratch/post_spawn()
	..()
	pack(/obj/item/screwdriver)
	pack(/obj/item/multitool)

/datum/bot_scenario/botany/project/death_nettles_from_scratch/botany_check()
	if(locate(/obj/item/reagent_containers/food/snacks/grown/nettle/death) in bot.GetAllContents())
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/botany/project/throw_acid_melon
	name = "botanist throws an acid melon at an attacker"
	desc = "Carrying an acid melon when someone four tiles away attacks: throw it at them (it bursts, fluorosulfuric acid) instead of running up to punch."
	layout = list(
		"##########",
		"#B.......#",
		"#........#",
		"##########")
	var/mob/living/carbon/human/assailant
	var/thrown_at

/datum/bot_scenario/botany/project/throw_acid_melon/post_spawn()
	..()
	var/obj/item/seeds/watermelon/S = new
	S.genes += new /datum/plant_gene/reagent(/datum/reagent/toxin/acid/fluacid, 0.5)
	S.genes += new /datum/plant_gene/trait/squash
	S.reagents_from_genes()
	S.name = "experimental [S.name]"
	S.potency = 40
	var/obj/item/reagent_containers/food/snacks/grown/watermelon/W = new(bot, S)
	bot.equip_to_slot_or_del(W, ITEM_SLOT_BACKPACK)
	assailant = new(get_step(get_step(get_step(get_step(first_marker("B"), EAST), EAST), EAST), EAST))

/datum/bot_scenario/botany/project/throw_acid_melon/issue_goal()
	goal_attempts++
	if(goal_attempts > 1 || !assailant)
		return
	brain.on_attacked(assailant, "attacked") // the way a real hit starts a fight (sight/calm-down tracking included, bot_brain.dm)
	log_line("[assailant] attacks the bot from [get_dist(bot, assailant)] tiles")

/datum/bot_scenario/botany/project/throw_acid_melon/botany_check()
	if(locate(/obj/item/reagent_containers/food/snacks/grown/watermelon) in bot.GetAllContents())
		return BOT_GYM_PENDING
	if(!thrown_at)
		thrown_at = world.time
	if(assailant.getFireLoss() > 0)
		return BOT_GYM_PASS //burnt by the acid splash
	if(world.time > thrown_at + 5 SECONDS)
		fail_reason = "threw the melon but the acid didn't burn anyone"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING
