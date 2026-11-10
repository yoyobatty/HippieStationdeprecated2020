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

// Upgrade rounds (2026-11-08). More letters: u a recharger, j a cell charger, A a destructive analyzer. An RPED waits on the lathe.
/datum/bot_scenario/duty/bench/round
	name = "upgrades: a scientist prints a whole round's parts, then fits the machines one after another"
	desc = "The user's ruling: upgrade rounds. A lathe, two rechargers and a cell charger in the lab, an empty RPED on the lathe. Everything they need is printed first, then fitted machine after machine: no going back to the lathe between them."
	layout = list(
		"##############",
		"#B.h.C.......#",
		"#............#",
		"#e.z.........#",
		"#..........u.#",
		"#.u........j.#",
		"##############")
	var/rped_type = /obj/item/storage/part_replacer
	/// Prints by the time the first machine was fitted.
	var/printed_at_first_fit

/datum/bot_scenario/duty/bench/round/setup()
	..()
	for(var/turf/T in markers["u"])
		place("u", new /obj/machinery/recharger(T))
	for(var/turf/T in markers["j"])
		place("j", new /obj/machinery/cell_charger(T))
	new rped_type(get_turf(first_placed("h")))

/// Whether every machine of this letter has its capacitors (or manipulators, for the lathe) past tier 1, panel shut.
/datum/bot_scenario/duty/bench/proc/all_upgraded(mark, part_type)
	for(var/obj/machinery/M in placed[mark])
		if(M.panel_open)
			return FALSE
		for(var/obj/item/stock_parts/P in M.component_parts)
			if(istype(P, part_type) && P.rating < 2)
				return FALSE
	return TRUE

/datum/bot_scenario/duty/bench/round/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.machines_upgraded && isnull(printed_at_first_fit))
		printed_at_first_fit = brain.designs_printed
	if(!isnull(printed_at_first_fit) && brain.designs_printed > printed_at_first_fit)
		fail_reason = "went back to print after fitting the first machine ([printed_at_first_fit] printed by then, [brain.designs_printed] now)"
		return BOT_GYM_FAIL
	var/obj/machinery/computer/rdconsole/C = first_placed("C")
	if(all_upgraded("u", /obj/item/stock_parts/capacitor) && all_upgraded("j", /obj/item/stock_parts/capacitor) && all_upgraded("h", /obj/item/stock_parts/manipulator) && C.linked_lathe == first_placed("h"))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/bench/full_rped
	name = "upgrades: an RPED full of old parts goes past the analyzer before more is printed into it"
	desc = "The user saw printed parts left on the lathe. The lab's RPED is full: fifty tier 1 parts. The scientist puts the old ones through the destructive analyzer until there's room, prints, picks every print up and fits the recharger. Nothing is left on the lathe."
	layout = list(
		"############",
		"#B.h.C.A...#",
		"#..........#",
		"#e.z.....u.#",
		"############")
	time_limit = 300 SECONDS // sixteen parts through the analyzer at a few seconds each, and the lathe can catch fire

/datum/bot_scenario/duty/bench/full_rped/setup()
	for(var/turf/T in markers["A"])
		place("A", new /obj/machinery/rnd/destructive_analyzer(T))
	..() // the console after the analyzer, so its Sync finds it
	for(var/turf/T in markers["u"])
		place("u", new /obj/machinery/recharger(T))
	var/obj/item/storage/part_replacer/R = new(get_turf(first_placed("h")))
	for(var/i in 1 to 10)
		for(var/path in list(/obj/item/stock_parts/capacitor, /obj/item/stock_parts/scanning_module, /obj/item/stock_parts/manipulator, /obj/item/stock_parts/micro_laser, /obj/item/stock_parts/matter_bin))
			new path(R)

/datum/bot_scenario/duty/bench/full_rped/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!all_upgraded("u", /obj/item/stock_parts/capacitor) || !all_upgraded("h", /obj/item/stock_parts/manipulator))
		return BOT_GYM_PENDING
	if(bot_parts_to_collect(first_placed("h")))
		return BOT_GYM_PENDING
	if(!brain.items_analyzed)
		fail_reason = "fitted with the RPED full and nothing through the analyzer"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/bench/brped_range
	name = "upgrades: a scientist with the bluespace RPED upgrades a machine from across the room, panel shut"
	desc = "The user's ruling: the bluespace RPED from range. It's on the lathe, the recharger six tiles off in plain sight. The parts go in from a distance: no screwdriver, no panel, the scientist never stands beside it."
	layout = list(
		"############",
		"#B.h.C.....#",
		"#..........#",
		"#e.z.......#",
		"#..........#",
		"#.........u#",
		"############")
	var/closest = 99
	var/panel_opened = FALSE

/datum/bot_scenario/duty/bench/brped_range/setup()
	..()
	for(var/turf/T in markers["u"])
		place("u", new /obj/machinery/recharger(T))
	new /obj/item/storage/part_replacer/bluespace(get_turf(first_placed("h")))

/datum/bot_scenario/duty/bench/brped_range/post_spawn()
	..()
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))

/datum/bot_scenario/duty/bench/brped_range/proc/stepped(atom/movable/mover)
	SIGNAL_HANDLER
	var/obj/machinery/recharger/R = first_placed("u")
	if(R)
		closest = min(closest, get_dist(mover, R))

/datum/bot_scenario/duty/bench/brped_range/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/recharger/R = first_placed("u")
	if(R.panel_open)
		panel_opened = TRUE
	if(!all_upgraded("u", /obj/item/stock_parts/capacitor))
		return BOT_GYM_PENDING
	if(panel_opened || closest < 2)
		fail_reason = "upgraded the recharger [panel_opened ? "with its panel open" : "standing beside it"] (closest [closest] tiles)"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/bench/brped_range/release_run()
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	return ..()

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

/// An APC that's on the grid as far as anyone can tell: an arena has no grid to power it.
/obj/machinery/power/apc/bot_gym_on_grid

/obj/machinery/power/apc/bot_gym_on_grid/process()
	main_status = 2 // APC_HAS_POWER

// Letters: y the Engineering techfab, a an APC.
/datum/bot_scenario/duty/apc_cells
	name = "upgrades: an engineer prints a better cell and swaps it into the APC, cover unlocked, opened, shut and locked again"
	desc = "The user's ruling: engineers put better cells in the APCs, only while the grid powers them (cells print empty). ID swipe, the cover lock off, crowbar, RPED, crowbar, ID swipe: the APC ends with the high-capacity cell, shut and locked."
	duty_type = null //by name in New(): a build without the duty has none
	job = "Station Engineer"
	time_limit = 120 SECONDS
	kit_backpack = list(/obj/item/crowbar, /obj/item/screwdriver)
	layout = list(
		"##########",
		"#B..y...a#",
		"#........#",
		"##########")

/datum/bot_scenario/duty/apc_cells/New()
	. = ..()
	duty_type = text2path("/datum/bot_duty/apc_cells")

/datum/bot_scenario/duty/apc_cells/setup()
	for(var/turf/T in markers["y"])
		var/obj/machinery/rnd/production/techfab/department/engineering/fab = place("y", new /obj/machinery/rnd/production/techfab/department/engineering(T))
		var/datum/component/material_container/mats = fab.materials?.mat_container
		mats?.insert_amount(40000, MAT_METAL)
		mats?.insert_amount(30000, MAT_GLASS)
	for(var/turf/T in markers["a"])
		var/obj/machinery/power/apc/A = place("a", new /obj/machinery/power/apc/bot_gym_on_grid(T))
		A.main_status = 2
		if(!A.cell) // a mapped APC gets its cell at map load
			A.cell = new /obj/item/stock_parts/cell/upgraded(A)
	SSresearch.science_tech.research_node_id("engineering", TRUE, FALSE)

/datum/bot_scenario/duty/apc_cells/post_spawn()
	..()
	brain.diligence = 1
	var/obj/item/card/id/C = new(bot)
	C.registered_name = bot.real_name
	C.assignment = "Station Engineer"
	C.access = list(ACCESS_ENGINE, ACCESS_ENGINE_EQUIP)
	bot.equip_to_slot_or_del(C, ITEM_SLOT_ID)

/datum/bot_scenario/duty/apc_cells/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/power/apc/A = first_placed("a")
	if(!istype(A?.cell, /obj/item/stock_parts/cell/high))
		return BOT_GYM_PENDING
	if(A.opened || !A.locked || !A.coverlocked)
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

// Roboticists (goals/rped_rounds.dm). Letters: F the exosuit fabricator, C an R&D console (the fabricator syncs from one in sight), k a cell charger, R an RPED, o a cyborg, q an exosuit.
/datum/bot_scenario/duty/robotics_cells
	name = "upgrades: a roboticist prints a better cell, charges it, and swaps it into the cyborg stood in Robotics"
	desc = "The user's rulings: roboticists swap cyborg cells, and charge the new one first (lathes print them empty). The fabricator prints it, the charger fills it, the cyborg's cover is unlocked, opened, the RPED swaps the cell, and the cover is shut and locked again. The cyborg never gets a flat cell."
	duty_type = null
	job = "Roboticist"
	time_limit = 240 SECONDS // the charger fills a super cell in a minute or so
	kit_backpack = list(/obj/item/crowbar, /obj/item/screwdriver)
	layout = list(
		"###########",
		"#B..F..k..#",
		"#R..C.....#",
		"#.......o.#",
		"###########")

/datum/bot_scenario/duty/robotics_cells/New()
	. = ..()
	duty_type = text2path("/datum/bot_duty/robotics_cells")

/datum/bot_scenario/duty/robotics_cells/setup()
	for(var/turf/T in markers["F"])
		var/obj/machinery/mecha_part_fabricator/F = place("F", new /obj/machinery/mecha_part_fabricator(T))
		var/datum/component/material_container/mats = F.rmat?.mat_container
		mats?.insert_amount(40000, MAT_METAL)
		mats?.insert_amount(30000, MAT_GLASS)
		mats?.insert_amount(10000, MAT_GOLD)
		mats?.insert_amount(10000, MAT_SILVER)
	for(var/turf/T in markers["k"])
		place("k", new /obj/machinery/cell_charger(T))
	for(var/turf/T in markers["C"])
		place("C", new /obj/machinery/computer/rdconsole/core(T))
	for(var/turf/T in markers["R"])
		place("R", new /obj/item/storage/part_replacer(T))
	// A basic cell each, so the high-capacity one Industrial Engineering gives is better: research is the station's, shared by every
	// arena, and a node researched here changed what every other scenario's bots print
	for(var/turf/T in markers["o"])
		var/mob/living/silicon/robot/R = place("o", new /mob/living/silicon/robot(T))
		QDEL_NULL(R.cell)
		R.cell = new /obj/item/stock_parts/cell(R)
	for(var/turf/T in markers["q"])
		var/obj/mecha/M = place("q", new /obj/mecha/working/ripley(T))
		QDEL_NULL(M.cell)
		M.cell = new /obj/item/stock_parts/cell(M)
	SSresearch.science_tech.research_node_id("engineering", TRUE, FALSE)

/datum/bot_scenario/duty/robotics_cells/post_spawn()
	..()
	brain.diligence = 1
	var/obj/item/card/id/C = new(bot)
	C.registered_name = bot.real_name
	C.assignment = "Roboticist"
	C.access = list(ACCESS_ROBOTICS, ACCESS_RESEARCH, ACCESS_MECH_SCIENCE)
	bot.equip_to_slot_or_del(C, ITEM_SLOT_ID)

/datum/bot_scenario/duty/robotics_cells/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/mob/living/silicon/robot/R = first_placed("o")
	if(R.cell && R.cell.charge < R.cell.maxcharge * 0.1)
		fail_reason = "the cyborg was given a flat cell ([R.cell.charge]/[R.cell.maxcharge])"
		return BOT_GYM_FAIL
	if(!R.cell || R.cell.maxcharge <= 1000 || R.opened || !R.locked) // it starts with a basic one
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

/datum/bot_scenario/duty/robotics_cells/mech
	name = "upgrades: a roboticist sits in the parked Ripley to permit maintenance, and swaps a charged better cell into it"
	desc = "The user's ruling: a pilot has to permit maintenance protocols from the seat, so the roboticist climbs in to do it, climbs out, starts the protocols with its ID, swaps the cell with the RPED, ends the protocols, and takes the permission back."
	layout = list(
		"###########",
		"#B..F..k..#",
		"#R..C.....#",
		"#.......q.#",
		"###########")

/datum/bot_scenario/duty/robotics_cells/mech
	var/start_charge_max = 0

/datum/bot_scenario/duty/robotics_cells/mech/post_spawn()
	..()
	var/obj/mecha/M = first_placed("q")
	start_charge_max = M.cell?.maxcharge

/datum/bot_scenario/duty/robotics_cells/mech/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/mecha/M = first_placed("q")
	if(M.cell && M.cell.charge < M.cell.maxcharge * 0.1)
		fail_reason = "the exosuit was given a flat cell"
		return BOT_GYM_FAIL
	if(!M.cell || M.cell.maxcharge <= start_charge_max || M.occupant || M.state || M.maint_access)
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

// Vending machines (goals/rped_rounds.dm). Letters: V a cola machine, K a crate with its refill canister in.
/// Down to a tenth of its stock.
/proc/bot_gym_empty_vendor(obj/machinery/vending/V)
	for(var/datum/data/vending_product/R in V.product_records)
		R.amount = round(R.max_amount * 0.1)

/datum/bot_scenario/duty/restock_vendor
	name = "cargo: a cargo tech opens the refill crate and restocks the nearly empty cola machine, service panel shut again"
	desc = "The user's ruling: Cargo restocks vending machines that run low. The cola machine is down to a tenth, reported, and its refill crate is in the bay. The crate is opened, the canister carried over, the service panel opened, the canister clicked in, and the panel screwed shut."
	duty_type = null
	job = "Cargo Technician"
	time_limit = 60 SECONDS
	kit_backpack = list(/obj/item/screwdriver)
	layout = list(
		"##########",
		"#B.K...V.#",
		"#........#",
		"##########")

/datum/bot_scenario/duty/restock_vendor/New()
	. = ..()
	duty_type = text2path("/datum/bot_duty/restock_vendors")

/datum/bot_scenario/duty/restock_vendor/setup()
	var/obj/machinery/vending/V = first_placed("V")
	bot_gym_empty_vendor(V)
	var/list/low = GLOB.vars["bot_vendors_low"]
	low?[V] = world.time
	for(var/turf/T in markers["K"])
		var/obj/structure/closet/crate/C = place("K", new /obj/structure/closet/crate(T))
		new /obj/item/vending_refill/cola(C)

/datum/bot_scenario/duty/restock_vendor/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/vending/V = first_placed("V")
	var/have = 0
	var/full = 0
	for(var/datum/data/vending_product/R in V.product_records)
		have += R.amount
		full += R.max_amount
	return (have >= full * 0.9 && !V.panel_open) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/restock_vendor/release_run()
	var/list/low = GLOB.vars["bot_vendors_low"]
	low?.Remove(first_placed("V"))
	return ..()

/datum/bot_scenario/vendor_report
	name = "cargo: buying from a nearly empty cola machine, a bot tells Cargo on the radio and the refill crate is asked for"
	desc = "The user's ruling: Cargo restocks vendors that run low. Nobody knows a vendor's stock without looking: whoever buys the last few cans says so, and Cargo has the cola refill crate to order."
	job = "Assistant"
	time_limit = 20 SECONDS
	layout = list(
		"######",
		"#BV..#",
		"######")

/datum/bot_scenario/vendor_report
	station_wide = TRUE // Cargo's ask cooldown and the request list are the station's: a second run alongside saw the first one's ask

/datum/bot_scenario/vendor_report/setup()
	bot_gym_empty_vendor(first_placed("V"))

/datum/bot_scenario/vendor_report/post_spawn()
	..()
	give_job_id()
	var/obj/machinery/vending/V = first_placed("V")
	var/datum/data/vending_product/R = locate() in V.product_records
	INVOKE_ASYNC(brain, TYPE_PROC_REF(/datum/bot_brain, vend_from), V, R.product_path)

/datum/bot_scenario/vendor_report/make_goal()
	return null

/datum/bot_scenario/vendor_report/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/datum/bot_request/BR as anything in GLOB.bot_cargo_requests)
		if(BR.detail == /datum/supply_pack/service/vending/cola && BR.caller_ref?.resolve() == bot)
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/vendor_report/release_run()
	for(var/datum/bot_request/BR as anything in GLOB.bot_cargo_requests.Copy())
		if(BR.caller_ref?.resolve() == bot)
			GLOB.bot_cargo_requests -= BR
	GLOB.bot_cargo_asked -= /datum/supply_pack/service/vending/cola
	var/list/low = GLOB.vars["bot_vendors_low"]
	low?.Remove(first_placed("V"))
	return ..()

/// The research experiments (goals/experiment_rounds.dm): a scientist with the experiment scanner finds ore lying about and scans it
/datum/bot_scenario/duty/experiment_ores
	name = "science: a scientist takes its experiment scanner to the ore lying about and finishes the Geological Survey"
	desc = "Five kinds of ore on the floor of the room, and a scientist with the experiment scanner every scientist starts with. It goes to each and scans it; five kinds finishes the Geological Survey, 7,500 points. Nobody used the experiments."
	job = "Scientist"
	time_limit = 60 SECONDS
	kit_backpack = list(/obj/item/experi_scanner)
	layout = list(
		"###########",
		"#B..1.2.3.#",
		"#....4.5..#",
		"###########")
	var/datum/science_experiment/geology/survey

/datum/bot_scenario/duty/experiment_ores/setup()
	duty_type = text2path("/datum/bot_duty/experiment_rounds") // by name: a build without the fix has no such duty
	var/list/ores = list("1" = /obj/item/stack/ore/iron, "2" = /obj/item/stack/ore/silver, "3" = /obj/item/stack/ore/gold, "4" = /obj/item/stack/ore/uranium, "5" = /obj/item/stack/ore/plasma)
	for(var/mark in ores)
		var/path = ores[mark]
		place(mark, new path(first_marker(mark)))
	for(var/datum/science_experiment/geology/G in science_experiments())
		survey = G
		survey.done = list()
		survey.completed = FALSE

/datum/bot_scenario/duty/experiment_ores/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!survey)
		fail_reason = "no Geological Survey"
		return BOT_GYM_FAIL
	return survey.completed ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/experiment_ores/on_timeout()
	fail_reason = "scanned [length(survey?.done)] of 5"
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// Mining points (goals/mining_points.dm). Layout letter R: the ore redemption machine. M: the equipment vendor.
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/mining_points
	name = "miner cashes its voucher, claims the points in the machine and spends them at the vendor"
	desc = "A miner back from a trip with its voucher still in its bag and 1,500 points waiting in the redemption machine. The voucher goes to the vendor for the capsule and webbing, the card into the machine for the points, then into the vendor for the scanner that reads the whole screen and a first-aid kit, and back on its chest each time. Miners never went near either screen."
	job = "Shaft Miner"
	time_limit = 90 SECONDS
	max_goal_attempts = 8
	kit_backpack = list(/obj/item/mining_voucher)
	layout = list(
		"###########",
		"#B...M...R#",
		"#.........#",
		"###########")
	var/obj/item/card/id/card
	var/obj/machinery/mineral/ore_redemption/machine

/datum/bot_scenario/mining_points/build_tile(turf/T, char)
	switch(char)
		if("R")
			machine = place(char, new /obj/machinery/mineral/ore_redemption(T))
		if("M")
			place(char, new /obj/machinery/mineral/equipment_vendor(T))
		else
			return ..()

/datum/bot_scenario/mining_points/post_spawn()
	card = give_job_id()
	machine.points = 1500

/// The round a miner does between trips, as the mining duty asks it on the station (the gym's level isn't one)
/datum/bot_scenario/mining_points/issue_goal()
	goal_attempts++
	if(!brain.try_mining_points())
		log_line("nothing to do about points (attempt [goal_attempts]/[max_goal_attempts])")

/datum/bot_scenario/mining_points/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(card))
		fail_reason = "its card's gone"
		return BOT_GYM_FAIL
	if(card.mining_points != 100 || machine.points) //1,500 less the scanner (800) and the kit (600)
		return BOT_GYM_PENDING
	if(bot.get_idcard(FALSE) != card || !bot.wear_id)
		fail_reason = "it isn't wearing its card"
		return BOT_GYM_FAIL
	if(brain.find_carried_tool(/obj/item/mining_voucher))
		fail_reason = "the voucher's still in its bag"
		return BOT_GYM_FAIL
	if(!brain.find_carried_tool(/obj/item/storage/belt/mining/vendor) || !brain.find_carried_tool(/obj/item/storage/firstaid/brute))
		fail_reason = "it left what it got at the vendor"
		return BOT_GYM_FAIL
	if(brain.mining_scan_range() < 7)
		fail_reason = "its scanner still reads [brain.mining_scan_range()] tiles"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
