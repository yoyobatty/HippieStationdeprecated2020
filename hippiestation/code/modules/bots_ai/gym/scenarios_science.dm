// Bot Gym scenarios for Science (goals/science.dm).
//
// Layout letters used here: C an R&D console.

/datum/bot_scenario/duty/science
	duty_type = /datum/bot_duty/research
	job = "Scientist"
	time_limit = 60 SECONDS

/datum/bot_scenario/duty/science/setup()
	for(var/turf/T in markers["C"])
		place("C", new /obj/machinery/computer/rdconsole/core(T))
	// The station's servers have barely started: enough in the bank for a couple of first-tier nodes.
	SSresearch.science_tech.add_point_list(list(TECHWEB_POINT_TYPE_GENERIC = 6000))

/datum/bot_scenario/duty/science/research
	name = "scientist unlocks research at the console"
	desc = "Points in the bank and an R&D console down the corridor. The scientist walks over and unlocks what the department can afford, one node per click - not from across the room."
	layout = list(
		"#########",
		"#B.....C#",
		"#########")

/datum/bot_scenario/duty/science/research/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (brain.nodes_researched && brain.state == BOT_STATE_WANDER) ? BOT_GYM_PASS : BOT_GYM_PENDING

// The bench (goals/rnd_bench.dm). Letters: C an R&D console, h a protolathe, e a stack of metal, z a stack of glass.
/datum/bot_scenario/duty/bench
	duty_type = /datum/bot_duty/rnd_bench
	job = "Scientist"
	time_limit = 240 SECONDS //long enough for the lathe to catch fire and the bot to start again
	kit_backpack = list(/obj/item/screwdriver)

/datum/bot_scenario/duty/bench/setup()
	for(var/turf/T in markers["h"])
		place("h", new /obj/machinery/rnd/production/protolathe(T))
	for(var/turf/T in markers["C"])
		var/obj/machinery/computer/rdconsole/core/C = place("C", new /obj/machinery/computer/rdconsole/core(T))
		C.SyncRDevices()
	for(var/turf/T in markers["e"])
		place("e", new /obj/item/stack/sheet/metal/fifty(T))
	for(var/turf/T in markers["z"])
		place("z", new /obj/item/stack/sheet/glass/fifty(T))
	SSresearch.science_tech.research_node_id("engineering", TRUE, FALSE)

/datum/bot_scenario/duty/bench/upgrade
	name = "scientist stocks the lathe, prints parts and upgrades it"
	desc = "A protolathe with an R&D console, the silo as it stands, and sheets on the floor. The scientist prints an RPED and better parts, carries them to the machine and fits them with the panel open, then syncs the console again: opening a lathe unlinks it."
	layout = list(
		"##########",
		"#B.h.C...#",
		"#........#",
		"#e.z.....#",
		"##########")

/datum/bot_scenario/duty/bench/upgrade/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/rnd/production/protolathe/L = first_placed("h")
	var/obj/machinery/computer/rdconsole/C = first_placed("C")
	if(!brain.machines_upgraded || L.panel_open)
		return BOT_GYM_PENDING
	var/rating = 0
	for(var/obj/item/stock_parts/manipulator/M in L.component_parts)
		rating = max(rating, M.rating)
	if(rating < 2)
		fail_reason = "it says it upgraded the lathe, and the lathe's manipulators are still tier [rating]"
		return BOT_GYM_FAIL
	return C.linked_lathe == L ? BOT_GYM_PASS : BOT_GYM_PENDING

// Slimes (goals/xenobiology.dm). Letters: X a slime console, y a slime behind glass, k a box of monkey cubes, a camera at n.
/datum/bot_scenario/duty/slimes
	duty_type = /datum/bot_duty/xenobiology
	job = "Scientist"
	time_limit = 90 SECONDS

/datum/bot_scenario/duty/slimes/setup()
	for(var/turf/T in markers["X"])
		place("X", new /obj/machinery/computer/camera_advanced/xenobio(T))
	for(var/turf/T in markers["k"])
		place("k", new /obj/item/storage/box/monkeycubes(T))
	for(var/turf/T in markers["y"])
		var/mob/living/simple_animal/slime/S = new(T)
		S.set_nutrition(S.get_hunger_nutrition() + 10)
		place("y", S)
	for(var/turf/T in markers["n"])
		var/obj/machinery/camera/cam = new(T)
		cam.network = list("ss13")
		cam.c_tag = "Bot Gym [REF(src)]"
		place("n", cam)

/datum/bot_scenario/duty/slimes/feed
	name = "scientist stocks the slime console and feeds the pen"
	desc = "A slime behind glass, a box of cubes on the floor, a console. The box goes to the console, a cube at a time, and a monkey comes down beside the slime without anybody going near it."
	layout = list(
		"#########",
		"#B.k....#",
		"#....X..#",
		"#wwwwwww#",
		"#y.....n#",
		"#########")

/datum/bot_scenario/duty/slimes/feed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return brain.monkeys_fed ? BOT_GYM_PASS : BOT_GYM_PENDING

// The E.X.P.E.R.I-MENTOR (goals/experimentor.dm). Letters: M the machine, C an R&D console, q a spare part.
/datum/bot_scenario/duty/experimentor
	duty_type = /datum/bot_duty/experimentor
	job = "Scientist"
	time_limit = 60 SECONDS

/datum/bot_scenario/duty/experimentor/setup()
	for(var/turf/T in markers["M"])
		place("M", new /obj/machinery/rnd/experimentor(T))
	for(var/turf/T in markers["C"])
		place("C", new /obj/machinery/computer/rdconsole/core(T))
	for(var/turf/T in markers["q"])
		place("q", new /obj/item/stock_parts/capacitor(T))
	GLOB.bot_experiment_notes -= /obj/item/stock_parts/capacitor
	GLOB.bot_experiment_findings -= /obj/item/stock_parts/capacitor

/datum/bot_scenario/duty/experimentor/test
	name = "scientist puts a spare part through the experimentor"
	desc = "A loose capacitor and the machine, unlinked. The scientist carries the part over, links the machine to the console, loads it and runs tests on it, keeping notes on what's been tried."
	layout = list(
		"#########",
		"#B.q.M.C#",
		"#.......#",
		"#########")

/datum/bot_scenario/duty/experimentor/test/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return brain.experiments_run ? BOT_GYM_PASS : BOT_GYM_PENDING

// Digging (goals/mining.dm), without the shuttle. Letters: R plain rock, O a seam of iron, l lava.
/datum/bot_scenario/mining
	job = "Shaft Miner"
	time_limit = 60 SECONDS
	kit_hands = list(/obj/item/pickaxe)
	kit_backpack = list(/obj/item/t_scanner/adv_mining_scanner/lesser)

/datum/bot_scenario/mining/setup()
	arena_area.outdoors = TRUE
	for(var/turf/T in markers["R"])
		T.ChangeTurf(/turf/closed/mineral/volcanic, /turf/open/floor/plating/asteroid/basalt) //the base under it, or digging it leaves the reserved level's space
	for(var/turf/T in markers["O"])
		T.ChangeTurf(/turf/closed/mineral/iron/volcanic, /turf/open/floor/plating/asteroid/basalt)
	for(var/turf/T in markers["l"])
		T.ChangeTurf(/turf/open/lava/smooth)

/datum/bot_scenario/mining/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/storage/bag/ore(bot), ITEM_SLOT_RPOCKET)
	ADD_TRAIT(bot, TRAIT_NOBREATH, "bot gym") //a tunnel dug in the arena has no air in it, and that's not what's being tried here

/datum/bot_scenario/mining/make_goal()
	return new /datum/bot_goal/mine_ore()

/datum/bot_scenario/mining/tunnel
	name = "miner tunnels to a seam the scanner shows, and takes the ore"
	desc = "Walks to the rock face, pulses the scanner, digs through plain rock to the seam behind it and steps on the ore: it goes in the satchel worn in a pocket."
	layout = list(
		"###########",
		"#B.....RRR#",
		"#......ROR#",
		"#......RRR#",
		"###########")

/datum/bot_scenario/mining/tunnel/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return brain.ore_in_satchel() ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/mining/corner
	name = "miner's tunnel to a seam off to one side can be walked back out of"
	time_limit = 90 SECONDS
	max_goal_attempts = 1
	desc = "A seam up and across from the rock face. The tunnel goes square on, so there's a route back along it: it used to cut the corner, and bots don't route on the diagonal."
	layout = list(
		"###########",
		"#.....RRRO#",
		"#.....RRRR#",
		"#B....RRRR#",
		"###########")

/datum/bot_scenario/mining/corner/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!brain.ore_in_satchel())
		return BOT_GYM_PENDING
	var/turf/start = first_marker("B")
	if(get_turf(bot) == start)
		return BOT_GYM_PASS
	if(brain.state == BOT_STATE_WANDER && !istype(brain.current_goal, /datum/bot_goal/gym_reach))
		var/datum/bot_goal/gym_reach/back = new
		back.target = start
		brain.assign_goal(back)
	return BOT_GYM_PENDING

/datum/bot_scenario/mining/goliath
	name = "miner shoots a goliath that's in the way, without being attacked"
	desc = "A goliath standing in the only way through, doing nothing. The miner gets the accelerator out and shoots it."
	time_limit = 30 SECONDS
	kit_hands = list(/obj/item/pickaxe)
	kit_backpack = list(/obj/item/t_scanner/adv_mining_scanner/lesser, /obj/item/gun/energy/kinetic_accelerator)
	layout = list(
		"#########",
		"#B....y.#",
		"#########")

/datum/bot_scenario/mining/goliath/setup()
	..()
	for(var/turf/T in markers["y"])
		var/mob/living/simple_animal/hostile/asteroid/goliath/G = new(T)
		G.toggle_ai(AI_OFF)
		place("y", G)

/datum/bot_scenario/mining/goliath/make_goal()
	var/datum/bot_goal/gym_reach/G = new
	G.target = first_marker("y")
	return G

/datum/bot_scenario/mining/goliath/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/mob/living/simple_animal/hostile/asteroid/goliath/G = first_placed("y")
	return (QDELETED(G) || G.health < G.maxHealth) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/mining/lava
	name = "miner won't dig a seam on the edge of a lava lake"
	desc = "The only rock in reach is beside lava, where the air catches. The miner leaves it alone, and doesn't step in the lava either."
	time_limit = 20 SECONDS
	layout = list(
		"###########",
		"#B.....llR#",
		"#......lOR#",
		"#......llR#",
		"###########")

/datum/bot_scenario/mining/lava/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.ores_mined)
		fail_reason = "it dug a seam beside lava"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/mining/lava/on_timeout()
	return BOT_GYM_PASS
