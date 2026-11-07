// Bot Gym scenarios for Science (goals/science.dm).
//
// Layout letters used here: C an R&D console.

/datum/bot_scenario/duty/science
	duty_type = /datum/bot_duty/research
	job = "Scientist"
	time_limit = 60 SECONDS

/datum/bot_scenario/duty/science/setup()
	// The station's servers have barely started: enough in the bank for the first node or two. A web of the console's own: two runs
	// sharing the station's spent each other's points.
	for(var/turf/T in markers["C"])
		place("C", private_rd_console(T, 8000))

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

// ---------------------------------------------------------------------------------------------
// Asked for research, the parts first, and the departments' own upgrades
// ---------------------------------------------------------------------------------------------

/// A console with a techweb of its own, so a run's research doesn't move every other arena's.
/datum/bot_scenario/proc/private_rd_console(turf/T, points)
	var/obj/machinery/computer/rdconsole/core/console = new(T)
	console.stored_research.consoles_accessing -= console
	console.stored_research = new /datum/techweb
	console.stored_research.consoles_accessing[console] = TRUE
	if(points)
		console.stored_research.add_point_list(list(TECHWEB_POINT_TYPE_GENERIC = points))
	return console

/// Nothing asked for from before this run. By name, so ab_gym.sh's build from before the asking was written still compiles.
/proc/gym_clear_research_wanted()
	if("bot_research_wanted" in GLOB.vars)
		var/list/wanted = GLOB.vars["bot_research_wanted"]
		wanted.Cut()

/// Mining asked for a material (goals/mining_requests.dm)
/datum/bot_scenario/chat/mining_request
	name = "mining: asked for silver, the miner says it'll dig some and puts silver first"
	desc = "Somebody tells a shaft miner Science needs silver. It says it'll get some, and silver goes to the top of what the miners dig. The user asked Mining for materials and for silver over the radio in a played round, and nobody answered: there was no call for the miners."
	job = "Shaft Miner"
	layout = list(
		"#########",
		"#B.C....#",
		"#########")
	time_limit = 15 SECONDS

/datum/bot_scenario/chat/mining_request/post_spawn()
	..()
	if("bot_wanted_minerals" in GLOB.vars)
		var/list/wanted = GLOB.vars["bot_wanted_minerals"]
		wanted.Cut()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Mining, science needs silver"), 2 SECONDS)

/datum/bot_scenario/chat/mining_request/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/wanted = GLOB.vars["bot_wanted_minerals"]
	var/list/lines = spoken()
	if(!length(lines) || !wanted?[MAT_SILVER])
		return BOT_GYM_PENDING
	if(findtext(lowertext(lines[1]), "where"))
		fail_reason = "asked where: \"[lines[1]]\""
		return BOT_GYM_FAIL
	log_line("said \"[lines[1]]\"")
	return BOT_GYM_PASS

/datum/bot_scenario/chat/research_request
	name = "science: asked to research stock parts, it says it's on it and researches the next of them"
	desc = "Somebody asks Science to its face to research stock parts. The scientist says it'll do it and researches the next node on the way to better parts. The user asked Science that on the radio in a played round and got \"where?\", and then nothing."
	job = "Scientist"
	layout = list(
		"#########",
		"#B.C...R#",
		"#########")
	time_limit = 40 SECONDS
	var/obj/machinery/computer/rdconsole/console

/datum/bot_scenario/chat/research_request/setup()
	for(var/turf/T in markers["R"])
		console = private_rd_console(T, 30000)
		place("R", console)

/datum/bot_scenario/chat/research_request/post_spawn()
	..()
	give_job_id(list(ACCESS_RESEARCH, ACCESS_TOX))
	gym_clear_research_wanted()
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Hey science, can you research stock parts?"), 2 SECONDS)

/datum/bot_scenario/chat/research_request/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/lines = spoken()
	if(length(lines) && findtext(lowertext(lines[1]), "where"))
		fail_reason = "asked where: \"[lines[1]]\""
		return BOT_GYM_FAIL
	return console.stored_research.researched_nodes["engineering"] ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chat/research_request/self_serve
	name = "science: asked for research, a less keen scientist says come and do it yourself, and lets them into R&D"
	desc = "The same request to a scientist who'd sooner not (the user's ruling: by personality, some say they'll let you in to research it yourself). It says so, and when the asker is outside R&D's door it opens it for them."
	layout = list(
		"###########",
		"#B.C....D.#",
		"#R......#.#",
		"###########")
	var/obj/machinery/door/airlock/door

/datum/bot_scenario/chat/research_request/self_serve/setup()
	..()
	door = first_placed("D")
	door.req_access = list(ACCESS_RESEARCH)
	door.req_access_txt = "[ACCESS_RESEARCH]"

/datum/bot_scenario/chat/research_request/self_serve/post_spawn()
	..()
	brain.diligence = 0.3
	brain.gym_scripted = FALSE //letting them in is a duty of its own
	addtimer(CALLBACK(src, PROC_REF(walk_round)), 6 SECONDS)

/// Off round to R&D's door, the far side of it.
/datum/bot_scenario/chat/research_request/self_serve/proc/walk_round()
	if(!QDELETED(visitor))
		visitor.forceMove(get_step(door, EAST))
		log_line("visitor at the door, outside")

/datum/bot_scenario/chat/research_request/self_serve/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/lines = spoken()
	if(!length(lines))
		return BOT_GYM_PENDING
	if(!findtext(lowertext(lines[1]), "yourself") && !findtext(lowertext(lines[1]), "let you in"))
		fail_reason = "said \"[lines[1]]\""
		return BOT_GYM_FAIL
	return door.density ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/research_saves_for_parts
	name = "science: research goes the way of better parts and the bluespace RPED, and saves up for them"
	desc = "Industrial Engineering in, 2,600 points in the bank and cheaper nodes to be had: the next node is Basic Bluespace Theory, on the way to the bluespace RPED (the user's ruling). Short of the points for the next step, it waits for them rather than spending them on something else."
	job = "Scientist"
	layout = list(
		"#####",
		"#B.R#",
		"#####")
	time_limit = 5 SECONDS
	var/obj/machinery/computer/rdconsole/console

/datum/bot_scenario/research_saves_for_parts/setup()
	for(var/turf/T in markers["R"])
		console = private_rd_console(T, 2600)
		place("R", console)
	console.stored_research.research_node_id("engineering", TRUE, FALSE)

/datum/bot_scenario/research_saves_for_parts/make_goal()
	return null

/datum/bot_scenario/research_saves_for_parts/check()
	gym_clear_research_wanted()
	var/first = brain.next_research_node(console)
	if(first != "bluespace_basic")
		fail_reason = "went for [first || "nothing"] with 2,600 points, not Basic Bluespace Theory on the way to the bluespace RPED"
		return BOT_GYM_FAIL
	console.stored_research.research_points[TECHWEB_POINT_TYPE_GENERIC] = 1500
	var/second = brain.next_research_node(console)
	if(second)
		fail_reason = "spent 1,500 points on [second] instead of saving for the next of the parts"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// Letters: y the Engineering techfab, u a recharger.
/datum/bot_scenario/duty/department_upgrades
	name = "upgrades: a keen engineer prints an RPED and parts at the Engineering techfab and fits the department's recharger"
	desc = "The user's ruling: department staff can upgrade too, by personality. A diligent engineer with the department's techfab prints an RPED and a better capacitor, and fits it to a recharger, the panel open and shut again."
	duty_type = null //set in New(), by name: see gym_clear_research_wanted()
	job = "Station Engineer"
	time_limit = 120 SECONDS
	kit_backpack = list(/obj/item/screwdriver)
	layout = list(
		"#########",
		"#B..y..u#",
		"#.......#",
		"#########")
	var/obj/machinery/recharger/recharger

/datum/bot_scenario/duty/department_upgrades/New()
	. = ..()
	duty_type = text2path("/datum/bot_duty/department_upgrades")

/datum/bot_scenario/duty/department_upgrades/setup()
	for(var/turf/T in markers["y"])
		var/obj/machinery/rnd/production/techfab/department/engineering/fab = place("y", new /obj/machinery/rnd/production/techfab/department/engineering(T))
		var/datum/component/material_container/mats = fab.materials?.mat_container
		mats?.insert_amount(40000, MAT_METAL)
		mats?.insert_amount(30000, MAT_GLASS)
	for(var/turf/T in markers["u"])
		recharger = place("u", new /obj/machinery/recharger(T))
	SSresearch.science_tech.research_node_id("engineering", TRUE, FALSE)

/datum/bot_scenario/duty/department_upgrades/post_spawn()
	..()
	brain.competence = 1

/datum/bot_scenario/duty/department_upgrades/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/stock_parts/capacitor/C in recharger.component_parts)
		if(C.rating >= 2 && !recharger.panel_open)
			return BOT_GYM_PASS
	return BOT_GYM_PENDING
