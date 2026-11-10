// Bot Gym scenarios for engineering upkeep: kitting up (goals/engineer_gear.dm), fixing cables
// mice chewed through (goals/repair_cables.dm), and crew squashing mice in passing (bot_human.dm).

/datum/bot_scenario/se_insulated_gloves
	name = "engineer puts on insulated gloves"
	desc = "A station engineer without insulated gloves fetches a pair from a locker and wears them - and leaves the toolbox in there."
	layout = list(
		"#########",
		"#B...L..#",
		"#########")
	job = "Station Engineer"
	time_limit = 30 SECONDS

/datum/bot_scenario/se_insulated_gloves/setup()
	var/obj/structure/closet/C = first_placed("L")
	new /obj/item/clothing/gloves/color/yellow(C)
	new /obj/item/storage/toolbox/electrical(C)

/datum/bot_scenario/se_insulated_gloves/make_goal()
	return new /datum/bot_goal/engineer_gear()

/datum/bot_scenario/se_insulated_gloves/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(locate(/obj/item/storage/toolbox) in bot.GetAllContents())
		fail_reason = "took the toolbox as well"
		return BOT_GYM_FAIL
	if(istype(bot.gloves, /obj/item/clothing/gloves/color/yellow))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/ce_cloak_and_gloves
	name = "CE takes cloak + gloves from own locker"
	desc = "The Chief Engineer, wearing their black gloves, goes to their locker, puts on the cloak and insulated gloves, and bags the black gloves instead of dropping them. Takes nothing else."
	layout = list(
		"#########",
		"#B...L..#",
		"#########")
	job = "Chief Engineer"
	time_limit = 40 SECONDS

/datum/bot_scenario/ce_cloak_and_gloves/setup()
	var/obj/structure/closet/plain = first_placed("L")
	var/turf/T = get_turf(plain)
	qdel(plain)
	var/obj/structure/closet/secure_closet/engineering_chief/locker = new(T)
	locker.locked = FALSE //no ID in the gym; the lock isn't what's being tested
	locker.update_icon()
	placed["L"] = list(locker)

/datum/bot_scenario/ce_cloak_and_gloves/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/clothing/gloves/color/black/ce(bot), ITEM_SLOT_GLOVES)

/datum/bot_scenario/ce_cloak_and_gloves/make_goal()
	return new /datum/bot_goal/engineer_gear()

/datum/bot_scenario/ce_cloak_and_gloves/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	var/list/carried = bot.GetAllContents()
	for(var/extra in list(/obj/item/storage/toolbox, /obj/item/areaeditor/blueprints, /obj/item/megaphone))
		if(locate(extra) in carried)
			fail_reason = "also took [extra]"
			return BOT_GYM_FAIL
	if(istype(bot.gloves, /obj/item/clothing/gloves/chief_engineer) && istype(bot.wear_neck, /obj/item/clothing/neck/cloak/ce))
		if(!(locate(/obj/item/clothing/gloves/color/black/ce) in carried))
			fail_reason = "dropped the black gloves instead of bagging them"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/repair_chewed_cable
	name = "engineer fixes a cable a mouse chewed"
	desc = "A yellow cable run with a chewed gap and the dropped bit of cable. Pick the bit up and click the plating with it; the run must be one powernet again."
	layout = list(
		"###########",
		"#B........#",
		"#PP===x===#",
		"###########")
	job = "Station Engineer"
	var/cable_type = /obj/structure/cable
	var/gap_char = "x"
	var/run_char = "="

/datum/bot_scenario/repair_chewed_cable/setup()
	bot_record_cable_break(first_marker(gap_char), cable_type)

/datum/bot_scenario/repair_chewed_cable/make_goal()
	return new /datum/bot_goal/repair_cable(first_marker(gap_char), cable_type)

/datum/bot_scenario/repair_chewed_cable/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	var/turf/gap = first_marker(gap_char)
	if(!bot_cable_break_fixed(gap, cable_type))
		return BOT_GYM_PENDING
	var/obj/structure/cable/left = locate(cable_type) in get_step(gap, WEST)
	var/obj/structure/cable/right = locate(cable_type) in get_step(gap, EAST)
	if(!left || !right || !left.powernet || left.powernet != right.powernet)
		fail_reason = "laid a cable but the run isn't one network (wrong layer?)"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/repair_chewed_cable/red_layer
	name = "engineer fixes a red-layer cable"
	desc = "Same, but the run is on the red layer and the engineer's own coil is set to yellow - it has to switch the coil's layer first."
	layout = list(
		"###########",
		"#B........#",
		"#PP~~~x~~~#",
		"###########")
	kit_backpack = list(/obj/item/stack/cable_coil)
	cable_type = /obj/structure/cable/layer1
	run_char = "~"

/datum/bot_scenario/crew_swats_mouse
	name = "crew squashes a mouse in passing"
	desc = "Walking past a mouse, the bot swats it (mice chew cables) and carries on."
	layout = list(
		"#########",
		"#B.....G#",
		"#...m...#",
		"#########")

/datum/bot_scenario/crew_swats_mouse/check()
	var/mob/living/simple_animal/mouse/M = first_placed("m")
	. = ..()
	if(. == BOT_GYM_PASS && M && !QDELETED(M) && M.stat != DEAD)
		fail_reason = "walked right past the mouse"
		return BOT_GYM_FAIL

/datum/bot_scenario/mouse_chews_engineer_notices
	name = "mouse chews a cable, engineer notices and fixes it"
	desc = "End to end: a mouse on bare plating chews through a cable (the real chew code, recorded by the break hook); the engineer's own cable round must notice it, claim it and fix it."
	layout = list(
		"###########",
		"#B........#",
		"#PP===P===#",
		"###########")
	job = "Station Engineer"
	var/turf/chew_spot
	var/mob/living/simple_animal/mouse/chewer

/datum/bot_scenario/mouse_chews_engineer_notices/setup()
	chew_spot = first_marker("P")
	for(var/turf/T in markers["P"]) //the P between the two cable runs
		if(locate(/obj/structure/cable) in get_step(T, WEST))
			chew_spot = T
	new /obj/structure/cable(chew_spot)
	chewer = new(chew_spot)
	chewer.stop_automated_movement = TRUE
	chewer.wander = FALSE
	chewer.chew_probability = 100
	// Simple mobs' AI idles with no players around, so drive its real chew routine directly.
	for(var/i in 1 to 200)
		if(!(locate(/obj/structure/cable) in chew_spot))
			break
		chewer.handle_automated_action()
	chewer.forceMove(get_step(chew_spot, NORTH)) //off the cable run, onto the walkway

/// No scripted goal: the engineer has to find the break through its own cable round.
/datum/bot_scenario/mouse_chews_engineer_notices/issue_goal()
	if(brain.try_cable_repair_round())
		goal_attempts++
		log_line("engineer's cable round picked up the break")

/datum/bot_scenario/mouse_chews_engineer_notices/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(!(chew_spot in GLOB.bot_cable_breaks) && !bot_cable_break_fixed(chew_spot, /obj/structure/cable) && goal_attempts == 0)
		fail_reason = "the chew was never recorded as a break"
		return BOT_GYM_FAIL
	if(!bot_cable_break_fixed(chew_spot, /obj/structure/cable))
		return BOT_GYM_PENDING
	var/obj/structure/cable/left = locate(/obj/structure/cable) in get_step(chew_spot, WEST)
	var/obj/structure/cable/right = locate(/obj/structure/cable) in get_step(chew_spot, EAST)
	if(!left || !right || left.powernet != right.powernet)
		fail_reason = "cable laid but the run isn't reconnected"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// An emitter's line of fire (bot_hazards.dm). Layout letter e: an emitter, pointed down the arena.
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/beam_on_stroll
	name = "hazards: an emitter switched on across the way stops a stroll planned before it was"
	desc = "Strolling down a corridor when an emitter comes on across it, a few tiles ahead. The route was planned before there was a beam to keep off: an engineer on Meta lit the supermatter's emitter, strolled across its line a second later and went down to four beams, every shift."
	// Room enough that it isn't shut in (bot_doors.dm is_shut_in(), sixty tiles): somebody shut in crosses a beam to get out
	layout = list(
		"####################",
		"#..............e...#",
		"#B................G#",
		"#..................#",
		"#..................#",
		"#..................#",
		"####################")
	time_limit = 12 SECONDS
	var/obj/machinery/power/emitter/emitter
	/// Since when it's been on. Its own `active` goes off again by itself: there's no wire under it here.
	var/lit = FALSE
	var/stepped_in = FALSE

/datum/bot_scenario/beam_on_stroll/setup()
	emitter = place("e", new /obj/machinery/power/emitter(first_marker("e")))
	emitter.anchored = TRUE
	emitter.state = 2 //EMITTER_WELDED
	emitter.active_power_usage = 0 //there's no wire under it here, and without one it switches itself off again
	emitter.setDir(SOUTH)

/datum/bot_scenario/beam_on_stroll/issue_goal()
	return

/datum/bot_scenario/beam_on_stroll/post_spawn()
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))
	brain.pursue(first_marker("G"), "wander", force = TRUE)
	addtimer(CALLBACK(src, PROC_REF(light_it)), 3)

/// Switched on, and on the map of places to keep out of, with the bot already on its way
/datum/bot_scenario/beam_on_stroll/proc/light_it()
	if(result != BOT_GYM_PENDING || QDELETED(emitter))
		return
	emitter.active = TRUE
	lit = TRUE
	bot_refresh_hazards()
	log_line("the emitter's on; the bot's at [bot.x - first_marker("B").x] tiles along")

/datum/bot_scenario/beam_on_stroll/proc/stepped()
	SIGNAL_HANDLER
	if(lit && bot.x == emitter.x && bot.y < emitter.y)
		stepped_in = TRUE

/datum/bot_scenario/beam_on_stroll/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(stepped_in)
		fail_reason = "walked into the emitter's line of fire"
		return BOT_GYM_FAIL
	if(!lit)
		return BOT_GYM_PENDING
	if(bot.x >= emitter.x)
		fail_reason = "was past the emitter before it came on: nothing tried"
		return BOT_GYM_FAIL
	return world.time > start_time + 6 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/beam_on_stroll/release_run()
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	if(!QDELETED(emitter))
		emitter.active = FALSE
	bot_refresh_hazards()
	return ..()

// Layout letters: R a reflector that turns the beam north, G a tile on the turned part of it.
/datum/bot_scenario/beam_on_stroll/turned
	name = "hazards: a beam turned by a reflector is out of bounds from its first shot"
	desc = "An emitter firing east at a reflector that sends the beam north, as in Box's laser room. Only the line from the muzzle to the reflector is known when it's switched on. The rest went on the map at the next redraw, up to three seconds after the beam had been up it, and three engineers were shot there in one shift in those seconds."
	layout = list(
		"##########",
		"#........#",
		"#...G....#",
		"#........#",
		"#.e.R....#",
		"#B.......#",
		"##########")

	/// Whether the tile was out of bounds a tenth of a second after the first beam crossed it. Looked at then and not at the next
	/// check(): every arena's emitter coming on redraws the one map, and with a few of these running the old code passed by luck.
	var/on_the_map
	var/beam_crossed = FALSE

/datum/bot_scenario/beam_on_stroll/turned/setup()
	..()
	emitter.setDir(EAST)
	var/obj/structure/reflector/single/anchored/mirror = place("R", new /obj/structure/reflector/single/anchored(first_marker("R")))
	mirror.setAngle(315) //what dir = 9 gives the ones on the map
	RegisterSignal(first_marker("G"), COMSIG_ATOM_ENTERED, PROC_REF(crossed))

/datum/bot_scenario/beam_on_stroll/turned/post_spawn()
	addtimer(CALLBACK(src, PROC_REF(light_it)), 10)

/datum/bot_scenario/beam_on_stroll/turned/proc/crossed(datum/source, atom/movable/AM)
	SIGNAL_HANDLER
	if(beam_crossed || !istype(AM, /obj/item/projectile/beam/emitter))
		return
	beam_crossed = TRUE
	addtimer(CALLBACK(src, PROC_REF(look_at_map)), 1)

/datum/bot_scenario/beam_on_stroll/turned/proc/look_at_map()
	on_the_map = bot_turf_in_beam(first_marker("G"))

/datum/bot_scenario/beam_on_stroll/turned/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(isnull(on_the_map))
		return BOT_GYM_PENDING //no beam's been turned up it yet
	if(on_the_map)
		return BOT_GYM_PASS
	fail_reason = "a beam had been across the tile and it wasn't yet somewhere to keep out of"
	return BOT_GYM_FAIL

/datum/bot_scenario/beam_on_stroll/turned/release_run()
	UnregisterSignal(first_marker("G"), COMSIG_ATOM_ENTERED)
	return ..()

/datum/bot_scenario/beam_on_stroll/stood_in_it
	name = "hazards: stood where an emitter comes on, it steps out of the line of fire"
	desc = "Stood still on the tile an emitter starts firing across. Everybody an emitter killed took the first beam walking and the rest standing where it hit them."
	layout = list(
		"#######",
		"#..e..#",
		"#..B..#",
		"#.....#",
		"#######")

/datum/bot_scenario/beam_on_stroll/stood_in_it/post_spawn()
	addtimer(CALLBACK(src, PROC_REF(light_it)), 10)

/datum/bot_scenario/beam_on_stroll/stood_in_it/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!lit)
		return BOT_GYM_PENDING
	if(bot.x != emitter.x)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

// Not a bot's doing, but the Bot Gym is where there's a world to try it in. Layout letter K: the camera.
/datum/bot_scenario/camera_assembly
	name = "cameras: a bomb on a camera's tile leaves what's inside it alone, and one that loses its assembly lets go of it"
	desc = "The bomb range's camera can't be destroyed, but every bomb landed on its tile took out the assembly inside it, and the camera kept hold of the deleted assembly: a hard delete for every test."
	time_limit = 10 SECONDS
	layout = list(
		"#####",
		"#B.K#",
		"#####")
	var/kept_whole
	var/let_go

/datum/bot_scenario/camera_assembly/issue_goal()
	return

/datum/bot_scenario/camera_assembly/post_spawn()
	var/obj/machinery/camera/C = place("K", new /obj/machinery/camera(first_marker("K")))
	kept_whole = C.prevent_content_explosion()
	qdel(C.assembly)
	let_go = isnull(C.assembly)

/datum/bot_scenario/camera_assembly/check()
	if(!kept_whole)
		fail_reason = "a bomb on its tile would blow the assembly up inside it"
		return BOT_GYM_FAIL
	if(!let_go)
		fail_reason = "kept hold of an assembly that had been deleted"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/repair_reachable_cable
	name = "engineer fixes the cable break it can get to, not the nearer one behind a locked door"
	desc = "Two chewed gaps in a yellow run. The nearer is behind a door the engineer's ID doesn't open; it goes to the other one and fixes it, without setting out for the first and giving up at the end of the route."
	layout = list(
		"###############",
		"#=x=D.B....=x=#",
		"###############")
	job = "Station Engineer"
	time_limit = 40 SECONDS

/datum/bot_scenario/repair_reachable_cable/proc/gaps()
	var/list/L = markers["x"]
	var/turf/a = L[1]
	var/turf/b = L[2]
	return a.x <= b.x ? list(a, b) : list(b, a)

/datum/bot_scenario/repair_reachable_cable/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)
	for(var/turf/T in gaps())
		bot_record_cable_break(T, /obj/structure/cable)
		var/list/info = GLOB.bot_cable_breaks[T]
		info["notice"] = 0

/datum/bot_scenario/repair_reachable_cable/post_spawn()
	give_job_id(list(ACCESS_ENGINE))

/datum/bot_scenario/repair_reachable_cable/make_goal()
	if(goal_attempts > 2)
		return null
	if(!brain.try_cable_repair_round())
		log_line("no repair started")
	return null

/datum/bot_scenario/repair_reachable_cable/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "giving up on /datum/bot_goal/repair_cable"))
			fail_reason = "set out for the break it couldn't get to"
			return BOT_GYM_FAIL
	var/list/G = gaps()
	return bot_cable_break_fixed(G[2], /obj/structure/cable) ? BOT_GYM_PASS : BOT_GYM_PENDING


// Layout letter Y: a crystal at power, behind a wall. Its radiation reaches two tiles, across the corridor.
/datum/bot_scenario/out_through_rads
	name = "hazards: somebody shut in by a crystal's radiation walks out through it"
	desc = "A dead end with the only way out through the radiation round a running crystal, as MetaStation's emitter room is once the crystal's at power. Nobody without a radiation suit steps into that, so there was no way to anywhere, and two engineers paced the room across the emitters' beams until they dropped."
	job = "Station Engineer"
	station_wide = TRUE //it stands in for the station's own crystal while it runs
	time_limit = 30 SECONDS
	layout = list(
		"#############",
		"#B.........s#",
		"#############",
		"######Y######",
		"#############")
	var/obj/item/screwdriver/wanted
	var/obj/machinery/power/supermatter_crystal/crystal
	var/obj/machinery/power/supermatter_crystal/stations_own

/datum/bot_scenario/out_through_rads/setup()
	wanted = new(first_marker("s"))
	crystal = place("Y", new /obj/machinery/power/supermatter_crystal/shard/hugbox(first_marker("Y")))
	crystal.anchored = TRUE
	SSair.stop_processing_machine(crystal) //it's only here for where its radiation would reach
	crystal.power = 160
	stations_own = GLOB.main_supermatter_engine
	GLOB.main_supermatter_engine = crystal
	bot_refresh_hazards()

/datum/bot_scenario/out_through_rads/make_goal()
	if(goal_attempts > 2)
		return null
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	get.lawful = TRUE
	return get

/datum/bot_scenario/out_through_rads/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turf/by_the_crystal = first_marker("Y")
	var/turf/start = first_marker("B")
	if(!bot_in_crystal_rads(locate(by_the_crystal.x, start.y, start.z)))
		fail_reason = "the corridor isn't in the crystal's radiation: nothing tried"
		return BOT_GYM_FAIL
	return (wanted in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/out_through_rads/release_run()
	if(GLOB.main_supermatter_engine == crystal)
		GLOB.main_supermatter_engine = stations_own
	. = ..()
	bot_refresh_hazards()

/datum/bot_scenario/griefed/thrown_forgets
	name = "items: something thrown forgets who threw it once it's landed"
	desc = "A toolbox thrown across the room. It kept its thrower for good, which is what held on to a body deleted after: a hard delete for anybody gibbed or cremated who'd thrown something that was still about."
	time_limit = 10 SECONDS
	layout = list(
		"########",
		"#B.C...#",
		"########")
	var/obj/item/storage/toolbox/mechanical/thrown

/datum/bot_scenario/griefed/thrown_forgets/grief()
	thrown = place("C", new /obj/item/storage/toolbox/mechanical(griefer.loc))
	thrown.throw_at(get_step(get_step(griefer, EAST), EAST), 3, 1, griefer)

/datum/bot_scenario/griefed/thrown_forgets/check()
	if(!thrown || thrown.throwing || world.time < start_time + 5 SECONDS)
		return BOT_GYM_PENDING
	if(thrown.thrownby)
		fail_reason = "the toolbox still has [thrown.thrownby] as its thrower, lying on the floor"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// Layout letter K: the window.
/datum/bot_scenario/plasma_window_frame
	name = "windows: a plasma window takes the same undoing as a reinforced one"
	desc = "A plasma window came loose from the floor with one turn of a screwdriver, where a reinforced one has to be unscrewed from its frame, pried out and then unscrewed from the floor."
	time_limit = 10 SECONDS
	layout = list(
		"#####",
		"#B.K#",
		"#####")
	var/still_fastened
	var/comes_out

/datum/bot_scenario/plasma_window_frame/issue_goal()
	return

/datum/bot_scenario/plasma_window_frame/post_spawn()
	var/obj/structure/window/plasma/W = place("K", new /obj/structure/window/plasma(first_marker("K"), WEST))
	var/obj/item/screwdriver/screwdriver = place("K", new /obj/item/screwdriver(bot.loc))
	var/obj/item/crowbar/crowbar = place("K", new /obj/item/crowbar(bot.loc))
	screwdriver.toolspeed = 0
	crowbar.toolspeed = 0
	bot.forceMove(get_step(W, WEST))
	W.attackby(screwdriver, bot) //one turn
	still_fastened = W.anchored
	W.attackby(crowbar, bot) //out of the frame
	W.attackby(screwdriver, bot) //and off the floor
	comes_out = !W.anchored

/datum/bot_scenario/plasma_window_frame/check()
	if(!still_fastened)
		fail_reason = "loose from the floor after one turn of a screwdriver"
		return BOT_GYM_FAIL
	if(!comes_out)
		fail_reason = "still fastened after the screwdriver, the crowbar and the screwdriver again"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/suit_for_emitter
	name = "supermatter: for a failing crystal's emitter the far side of its radiation, a radiation suit goes on first"
	desc = "The crystal's losing integrity and its emitter is to be switched off. The emitter's a tile outside the radiation and the only way to it is through. The suit was only put on for something standing in the radiation itself, so there was no way to the emitter, and the crystal went."
	job = "Station Engineer"
	station_wide = TRUE //it stands in for the station's own crystal while it runs
	time_limit = 10 SECONDS
	layout = list(
		"###########",
		"#B.......e#",
		"###########",
		"#####Y#####",
		"###########")
	var/obj/machinery/power/supermatter_crystal/crystal
	var/obj/machinery/power/supermatter_crystal/stations_own
	var/suits_up
	var/failing

/datum/bot_scenario/suit_for_emitter/issue_goal()
	return

/datum/bot_scenario/suit_for_emitter/setup()
	crystal = place("Y", new /obj/machinery/power/supermatter_crystal/shard/hugbox(first_marker("Y")))
	crystal.anchored = TRUE
	SSair.stop_processing_machine(crystal)
	crystal.power = 160
	crystal.damage = crystal.explosion_point * 0.3
	stations_own = GLOB.main_supermatter_engine
	GLOB.main_supermatter_engine = crystal
	bot_refresh_hazards()

/datum/bot_scenario/suit_for_emitter/post_spawn()
	var/obj/machinery/power/emitter/E = place("e", new /obj/machinery/power/emitter(first_marker("e")))
	failing = brain.sm_crystal_failing() && !bot_in_crystal_rads(E)
	var/datum/bot_goal/setup_supermatter/G = new
	G.target = E
	var/list/strategies = G.get_strategies(brain)
	var/datum/bot_strategy/first = length(strategies) ? strategies[1] : null
	suits_up = first && istype(first.steps[1], /datum/bot_step/suit_up_for_rads)

/datum/bot_scenario/suit_for_emitter/check()
	if(!failing)
		fail_reason = "the crystal doesn't read as failing with its emitter outside the radiation: nothing tried"
		return BOT_GYM_FAIL
	if(!suits_up)
		fail_reason = "set off for the emitter with no radiation suit in the plan"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/suit_for_emitter/release_run()
	if(GLOB.main_supermatter_engine == crystal)
		GLOB.main_supermatter_engine = stations_own
	. = ..()
	bot_refresh_hazards()

/datum/bot_scenario/holotool_works
	name = "holotool: the colour button, the off switch, a multitool that links and a welder that's hot"
	desc = "The RD's holotool. Its two buttons were the same proc written twice, so the colour one opened the tool menu; there was no switching it off; its multitool had no buffer, so it linked nothing; and its welder was cold."
	time_limit = 10 SECONDS
	layout = list(
		"#####",
		"#B.K#",
		"#####")
	var/list/wrong
	/// Got to the end of it: the build before this throws part way, having none of the vars
	var/tried = FALSE

/datum/bot_scenario/holotool_works/issue_goal()
	return

/datum/bot_scenario/holotool_works/post_spawn()
	wrong = list()
	var/obj/item/holotool/H = place("K", new /obj/item/holotool(bot.loc))
	bot.put_in_hands(H)
	var/list/modes = H.vars["modes"] //by name: the build before this keeps none, and stops here
	var/datum/holotool_mode/multi = locate(/datum/holotool_mode/multitool) in modes
	var/datum/holotool_mode/weld = locate(/datum/holotool_mode/welder) in modes
	H.switch_tool(bot, multi)
	var/obj/machinery/computer/telecomms/monitor/machine = place("K", new /obj/machinery/computer/telecomms/monitor(first_marker("K")))
	var/obj/item/clicked_with
	if(H.vars["buffer_tool"])
		clicked_with = H.vars["buffer_tool"]
	if(!machine.multitool_check_buffer(null, clicked_with || H, TRUE))
		wrong += "the multitool has no buffer"
	H.switch_tool(bot, weld)
	if(!H.is_hot())
		wrong += "the welder is cold"
	H.switch_tool(bot, null)
	if(H.current_tool || H.tool_behaviour)
		wrong += "it doesn't switch off"
	if(!hascall(H, "open_menu")) //one menu, off the tool button and a use in hand
		wrong += "no menu to open"
	tried = TRUE

/datum/bot_scenario/holotool_works/check()
	if(!tried)
		fail_reason = "it has no modes of its own to try, nor a multitool"
		return BOT_GYM_FAIL
	if(length(wrong))
		fail_reason = english_list(wrong)
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/any_hardsuit
	name = "eva: an atmos tech with no atmos hardsuit to be had suits up in an engineering one"
	desc = "The Atmospherics hardsuits are gone, and an engineering hardsuit lies a few steps off. It went only for its own kind, found none, and gave up suiting up."
	job = "Atmospheric Technician"
	layout = list(
		"########",
		"#B...h.#",
		"########")
	time_limit = 30 SECONDS
	max_goal_attempts = 1
	kit_backpack = list(/obj/item/clothing/mask/gas, /obj/item/tank/internals/emergency_oxygen/engi)

/datum/bot_scenario/any_hardsuit/setup()
	place("h", new /obj/item/clothing/suit/space/hardsuit/engine(first_marker("h")))

/datum/bot_scenario/any_hardsuit/make_goal()
	return new /datum/bot_goal/gear_up_for_eva()

/datum/bot_scenario/any_hardsuit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return istype(bot.wear_suit, /obj/item/clothing/suit/space/hardsuit) ? BOT_GYM_PASS : BOT_GYM_PENDING
