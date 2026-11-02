// Xenobiology: a scientist runs the slime pens from the management console, the way it's done from the chair.
//
//  - monkey cubes go into the console a click at a time (xenobio attackby()); what's in it comes out as monkeys wherever the
//    camera is pointed. A slime that eats enough turns adult, and an adult that eats enough splits into four, some of them a
//    new colour (slime_mutation): that's the whole of breeding, and all it needs is feeding.
//  - when the pens fill up, the commonest colour goes: picked up with the console and dropped in the kill room, the refrigerated
//    cell at the end of the lab, where the cold does for it (slime handle_environment()). Nobody gets near a live slime: the
//    first bots carried them out of the pens and put them down with an extinguisher, and the ones that got away killed people.
//  - the body comes out the same way, and goes down by the processor, which pulls in a dead slime next to it
//    (processor/slime/process()) and has to be started by hand. The extract comes out on its tile and goes in the fridge.
//  - a colour nobody has seen yet this shift gets kept, and gets mentioned.

/// Slimes in the pens before the commonest colour gets thinned out.
#define BOT_XENO_PENS_FULL 5
/// Cubes in the console below which somebody tops it up.
#define BOT_XENO_LOW_CUBES 2
/// A slime isn't fed again this soon, however hungry it looks: it may still be on the last one.
#define BOT_XENO_FEED_GAP (40 SECONDS)

/// Slime colours bred so far this shift: colour -> TRUE.
GLOBAL_LIST_EMPTY(bot_slime_colours)
/// Slime -> when it was last fed.
GLOBAL_LIST_EMPTY(bot_slimes_fed)

/datum/bot_brain
	var/monkeys_fed = 0
	var/slimes_processed = 0
	var/extracts_stored = 0
	var/xeno_blocked_until = 0

/datum/bot_brain/proc/in_xenobiology(atom/A)
	var/area/where = get_area(A)
	return gym_run ? (where == get_area(owner)) : istype(where, /area/science/xenobiology)

/datum/bot_brain/proc/find_xeno_console()
	var/obj/machinery/computer/camera_advanced/xenobio/best
	var/best_dist
	for(var/obj/machinery/computer/camera_advanced/xenobio/X as anything in bot_instances_of(/obj/machinery/computer/camera_advanced/xenobio))
		if(QDELETED(X) || X.z != owner.z || (X.stat & (BROKEN|NOPOWER)) || !in_xenobiology(X) || taken_by_another(X))
			continue
		var/dist = get_dist(owner, X)
		if(!best || dist < best_dist)
			best = X
			best_dist = dist
	return best

/// A tile in the lab cold enough to kill a slime, and in sight of the console's cameras. What the room is called varies by map,
/// but it's the one the freezer feeds. Null if the lab hasn't got one, or it's warmed up: nothing gets harvested then.
/datum/bot_brain/proc/find_kill_room()
	var/area/lab = get_area(find_xeno_console())
	if(!lab)
		return null
	for(var/turf/open/T in lab)
		if(T.z == owner.z && T.return_air().temperature < T0C - 60 && !is_blocked_turf(T, TRUE) && bot_camera_sees(T))
			return T
	return null

/// Somewhere it can walk to that's within arm's reach of A, corners included. A route search only goes for the four sides of a
/// thing, and the cubes on Delta are on the end of a counter with floor only at the corner.
/datum/bot_brain/proc/spot_beside(atom/A)
	for(var/turf/open/T in orange(1, A))
		if(!is_blocked_turf(T, TRUE) && T.Adjacent(A) && can_walk_lawfully_to(T))
			return T
	return null

/// The live slimes in the pens.
/datum/bot_brain/proc/lab_slimes()
	. = list()
	for(var/mob/living/simple_animal/slime/S in GLOB.alive_mob_list)
		if(S.z == owner.z && !S.ckey && isturf(S.loc) && in_xenobiology(S))
			. += S

/// Whether the console's camera can see a tile. The net only works a chunk out once somebody's camera eye has been there, and
/// a bot in the chair hasn't got one to move about.
/proc/bot_camera_sees(turf/T)
	GLOB.cameranet.getCameraChunk(T.x, T.y, T.z)
	return GLOB.cameranet.checkTurfVis(T)

/// Whether a slime could do with a monkey.
/proc/bot_slime_wants_feeding(mob/living/simple_animal/slime/S)
	if(S.buckled || S.nutrition >= S.get_grow_nutrition() || world.time < GLOB.bot_slimes_fed[S] + BOT_XENO_FEED_GAP)
		return FALSE
	for(var/mob/living/carbon/monkey/M in range(2, S))
		if(M.stat != DEAD)
			return FALSE //its dinner is right there
	return TRUE

/datum/bot_brain/proc/find_monkey_cubes()
	var/obj/item/storage/box/monkeycubes/box = find_carried_tool(/obj/item/storage/box/monkeycubes)
	if(box)
		return box
	for(var/obj/item/storage/box/monkeycubes/B as anything in bot_instances_of(/obj/item/storage/box/monkeycubes))
		if(!QDELETED(B) && isturf(B.loc) && B.z == owner.z && in_xenobiology(B) && (locate(/obj/item/reagent_containers/food/snacks/monkeycube) in B))
			return B
	return null

/datum/bot_brain/proc/find_slime_processor()
	for(var/obj/machinery/processor/slime/P as anything in bot_instances_of(/obj/machinery/processor/slime))
		if(!QDELETED(P) && P.z == owner.z && !(P.stat & (BROKEN|NOPOWER)) && in_xenobiology(P) && !taken_by_another(P))
			return P
	return null

/// One of the colour there's most of, as long as there are two of it: one of each stays, to carry on the line. It has to have
/// eaten lately. A hungry slime out of its pen goes for the nearest person, and it took one scientist down to a corridor floor
/// and killed it there.
/proc/bot_commonest_slime(list/slimes)
	var/list/counts = list()
	for(var/mob/living/simple_animal/slime/S as anything in slimes)
		counts[S.colour]++
	var/best
	for(var/colour in counts)
		if(counts[colour] >= 2 && (!best || counts[colour] > counts[best]))
			best = colour
	if(!best)
		return null
	for(var/mob/living/simple_animal/slime/S as anything in slimes)
		if(S.colour == best && !S.buckled && !S.Target && !S.rabid && S.nutrition >= S.get_hunger_nutrition())
			return S
	return null

/datum/bot_duty/xenobiology
	name = "xenobiology"
	jobs = list("Scientist", "Research Director")
	interval_min = 200
	interval_max = 500

/datum/bot_duty/xenobiology/try_start(datum/bot_brain/bot)
	if(world.time < bot.xeno_blocked_until)
		return FALSE
	var/obj/machinery/computer/camera_advanced/xenobio/X = bot.find_xeno_console()
	if(!X)
		return FALSE
	var/list/slimes = bot.lab_slimes()
	if(!length(slimes))
		return FALSE
	bot.note_slime_colours(slimes)
	if(X.monkeys < BOT_XENO_LOW_CUBES)
		var/obj/item/storage/box/monkeycubes/box = bot.find_monkey_cubes()
		if(!box)
			bot.ask_cargo_for(/datum/supply_pack/critter/monkey, "some monkey cubes", "science", /obj/item/storage/box/monkeycubes) //bot_collabs.dm
		if(box)
			return bot.assign_goal(new /datum/bot_goal/xeno_work/stock_console(X, box))
	if(length(slimes) >= BOT_XENO_PENS_FULL)
		var/mob/living/simple_animal/slime/S = bot_commonest_slime(slimes)
		var/obj/machinery/processor/slime/P = bot.find_slime_processor()
		if(S && P && bot.find_kill_room())
			return bot.assign_goal(new /datum/bot_goal/xeno_work/harvest_slime(P, X, S))
	if(X.connected_recycler && bot.lab_monkey_corpse())
		return bot.assign_goal(new /datum/bot_goal/xeno_work/feed_slimes(X))
	if(X.monkeys >= 1)
		for(var/mob/living/simple_animal/slime/S as anything in slimes)
			if(bot_slime_wants_feeding(S))
				return bot.assign_goal(new /datum/bot_goal/xeno_work/feed_slimes(X))
	return FALSE

/// What a slime leaves of its dinner, somewhere the console can see it. The recycler turns those back into cubes, and that's what
/// keeps the pens going once the box on the table is gone.
/datum/bot_brain/proc/lab_monkey_corpse()
	for(var/mob/living/carbon/monkey/M in GLOB.mob_living_list)
		if(M.stat == DEAD && M.z == owner.z && isturf(M.loc) && in_xenobiology(M) && !M.buckled && bot_camera_sees(M.loc))
			return M
	return null

/// New colours get remarked on.
/datum/bot_brain/proc/note_slime_colours(list/slimes)
	var/list/fresh = list()
	for(var/mob/living/simple_animal/slime/S as anything in slimes)
		if(!GLOB.bot_slime_colours[S.colour])
			GLOB.bot_slime_colours[S.colour] = TRUE
			fresh += S.colour
	if(length(fresh) && length(GLOB.bot_slime_colours) > length(fresh) && !gym_scripted)
		say_after_typing(":n [english_list(fresh)] slime[length(fresh) > 1 ? "s" : ""] in the pens now.")

/datum/bot_strategy/xenobiology/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_goal/xeno_work
	lawful = TRUE
	exclusive = TRUE

/datum/bot_goal/xeno_work/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/xeno_work/on_give_up(datum/bot_brain/bot)
	bot.xeno_blocked_until = max(bot.xeno_blocked_until, world.time + 2 MINUTES)

/datum/bot_goal/xeno_work/on_success(datum/bot_brain/bot)
	var/datum/bot_duty/xenobiology/duty = bot_duty_of(/datum/bot_duty/xenobiology)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

// ---------------------------------------------------------------------------------------------
// Cubes in
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/xeno_work/stock_console
	doing = "stocking the slime console"
	var/obj/item/storage/box/monkeycubes/box

/datum/bot_goal/xeno_work/stock_console/New(obj/machinery/computer/camera_advanced/xenobio/X, obj/item/storage/box/monkeycubes/B)
	. = ..()
	target = X
	box = B

/datum/bot_goal/xeno_work/stock_console/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/xenobiology/S = new
	S.steps = list(new /datum/bot_step/fetch_cube_box(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/feed_cubes())
	return list(S)

/datum/bot_step/fetch_cube_box
	var/tries = 0

/datum/bot_step/fetch_cube_box/execute(datum/bot_brain/bot)
	var/datum/bot_goal/xeno_work/stock_console/G = bot.current_goal
	if(!istype(G) || QDELETED(G.box) || ++tries > 3)
		return GOAL_STEP_FAIL
	if(!isturf(G.box.loc))
		return GOAL_STEP_SUCCESS
	if(bot.owner.Adjacent(G.box))
		return bot.take_in_hand(G.box) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	var/turf/spot = bot.spot_beside(G.box)
	if(!spot)
		bot.xeno_blocked_until = world.time + 10 MINUTES //a lab it can't walk into, like Meta's, behind its cycling airlock
		return GOAL_STEP_FAIL
	return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(spot)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// One cube out of the box and into the console, a click for each, and the empty box left behind.
/datum/bot_step/paced/feed_cubes
	max_clicks = 8
	var/loaded = 0

/datum/bot_step/paced/feed_cubes/start(datum/bot_brain/bot)
	loaded = 0
	return TRUE

/datum/bot_step/paced/feed_cubes/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/xeno_work/stock_console/G = bot.current_goal
	var/obj/machinery/computer/camera_advanced/xenobio/X = G?.target
	if(!istype(G) || !istype(X) || QDELETED(X) || QDELETED(G.box) || !bot.owner.Adjacent(X))
		return FALSE
	var/obj/item/reagent_containers/food/snacks/monkeycube/cube = locate() in G.box
	if(!cube)
		return FALSE
	// The box in one hand, a cube in the other. Whatever the other hand had goes away first, or down for a moment.
	for(var/obj/item/held in bot.owner.held_items)
		if(held != G.box && !bot.put_away(held, FALSE))
			bot.owner.dropItemToGround(held)
			LAZYADD(bot.set_down_items, held)
	if(!SEND_SIGNAL(G.box, COMSIG_TRY_STORAGE_TAKE, cube, bot.owner.drop_location()))
		return FALSE
	if(!bot.owner.put_in_hands(cube) || !bot.use_tool_on(cube, X))
		return FALSE
	loaded++
	bot_log(bot, "put a monkey cube in [X], [X.monkeys] now")
	return TRUE

/datum/bot_step/paced/feed_cubes/finish(datum/bot_brain/bot)
	var/datum/bot_goal/xeno_work/stock_console/G = bot.current_goal
	if(istype(G) && !QDELETED(G.box) && (G.box in bot.owner.held_items))
		bot.owner.dropItemToGround(G.box)
	return loaded ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Feeding
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/xeno_work/feed_slimes
	doing = "feeding the slimes"

/datum/bot_goal/xeno_work/feed_slimes/New(obj/machinery/computer/camera_advanced/xenobio/X)
	. = ..()
	target = X

/datum/bot_goal/xeno_work/feed_slimes/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/xenobiology/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/feed_slimes())
	return list(S)

/// In the chair: the camera on a hungry slime, a monkey dropped beside it. The console only works where a camera can see.
/datum/bot_step/paced/feed_slimes
	max_clicks = 6
	var/fed = 0

/datum/bot_step/paced/feed_slimes/start(datum/bot_brain/bot)
	fed = 0
	return TRUE

/datum/bot_step/paced/feed_slimes/do_click(datum/bot_brain/bot)
	var/obj/machinery/computer/camera_advanced/xenobio/X = bot.current_goal?.target
	if(!istype(X) || QDELETED(X) || !bot.owner.Adjacent(X))
		return FALSE
	var/obj/machinery/monkey_recycler/recycler = X.connected_recycler
	var/mob/living/carbon/monkey/corpse = recycler ? bot.lab_monkey_corpse() : null
	if(corpse)
		bot.human_pause(X)
		if(QDELETED(corpse) || QDELETED(X) || QDELETED(recycler))
			return FALSE
		bot.telemetry_ui_action(X, "recycle monkey")
		corpse.visible_message("[corpse] vanishes as [corpse.p_theyre()] reclaimed for recycling!")
		recycler.use_power(500)
		X.monkeys = round(X.monkeys + recycler.cube_production, 0.1)
		qdel(corpse)
		fed++
		bot_log(bot, "recycled a monkey, [X.monkeys] cubes in the console")
		return TRUE
	if(X.monkeys < 1)
		return FALSE
	for(var/mob/living/simple_animal/slime/S as anything in bot.lab_slimes())
		if(!bot_slime_wants_feeding(S))
			continue
		var/turf/open/spot
		for(var/turf/open/T in orange(1, S))
			if(!is_blocked_turf(T, TRUE) && bot_camera_sees(T))
				spot = T
				break
		if(!spot)
			continue
		bot.human_pause(X)
		if(QDELETED(S) || QDELETED(X) || X.monkeys < 1)
			return FALSE
		bot.owner.face_atom(X)
		bot.telemetry_ui_action(X, "feed slime")
		var/mob/living/carbon/monkey/food = new(spot, TRUE, bot.owner)
		if(QDELETED(food))
			return FALSE
		food.LAssailant = bot.owner
		X.monkeys = round(X.monkeys - 1, 0.1)
		GLOB.bot_slimes_fed[S] = world.time
		bot.monkeys_fed++
		fed++
		bot_log(bot, "dropped a monkey in for [S]")
		return TRUE
	return FALSE

/datum/bot_step/paced/feed_slimes/finish(datum/bot_brain/bot)
	return fed ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Harvesting
// ---------------------------------------------------------------------------------------------

/// The processor is what's claimed: there's the one, however many consoles the lab has, and often the one tile beside it.
/datum/bot_goal/xeno_work/harvest_slime
	doing = "processing a slime"
	var/obj/machinery/computer/camera_advanced/xenobio/console
	var/mob/living/simple_animal/slime/slime

/datum/bot_goal/xeno_work/harvest_slime/New(obj/machinery/processor/slime/P, obj/machinery/computer/camera_advanced/xenobio/X, mob/living/simple_animal/slime/S)
	. = ..()
	target = P
	console = X
	slime = S

/datum/bot_goal/xeno_work/harvest_slime/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/xenobiology/S = new
	var/datum/bot_step/move_to/to_console = new
	to_console.step_target = console
	S.steps = list(to_console, new /datum/bot_step/paced/send_to_kill_room(), new /datum/bot_step/paced/run_processor())
	return list(S)

/// In the chair: the slime into the kill room, a watch on it, and the body out to the processor. The console reaches every pen.
/datum/bot_step/paced/send_to_kill_room
	max_clicks = 120
	var/sent = FALSE

/datum/bot_step/paced/send_to_kill_room/start(datum/bot_brain/bot)
	sent = FALSE
	return TRUE

/datum/bot_step/paced/send_to_kill_room/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/xeno_work/harvest_slime/G = bot.current_goal
	var/obj/machinery/computer/camera_advanced/xenobio/X = G?.console
	var/mob/living/simple_animal/slime/S = G?.slime
	var/obj/machinery/processor/slime/P = G?.target
	clicks++
	if(!istype(G) || !istype(X) || QDELETED(X) || QDELETED(S) || !istype(P) || QDELETED(P) || !bot.owner.Adjacent(X))
		return FALSE
	if(!sent)
		var/turf/kill_room = bot.find_kill_room()
		if(!kill_room || S.buckled)
			return FALSE
		bot.human_pause(X)
		if(QDELETED(S) || S.buckled || !bot.owner.Adjacent(X))
			return FALSE
		bot.owner.face_atom(X)
		bot.telemetry_ui_action(X, "move slime")
		bot_warp_slime(S, kill_room)
		sent = TRUE
		bot_log(bot, "put [S] in the kill room")
		wait_for = 30
		return TRUE
	if(S.stat != DEAD)
		wait_for = 30
		return TRUE
	var/turf/open/spot
	for(var/turf/open/T in orange(1, P))
		if(!is_blocked_turf(T, TRUE) && bot_camera_sees(T))
			spot = T
			break
	if(!spot)
		return FALSE
	bot.human_pause(X)
	if(QDELETED(S))
		return FALSE
	bot.telemetry_ui_action(X, "move slime")
	bot_warp_slime(S, spot)
	bot_log(bot, "moved [S] over to [P]")
	return FALSE

/datum/bot_step/paced/send_to_kill_room/finish(datum/bot_brain/bot)
	var/datum/bot_goal/xeno_work/harvest_slime/G = bot.current_goal
	return (istype(G) && !QDELETED(G.slime) && G.slime.stat == DEAD) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/proc/bot_warp_slime(mob/living/simple_animal/slime/S, turf/T)
	S.visible_message("[S] vanishes in a flash of light!")
	S.forceMove(T)
	S.visible_message("[S] warps in!")

/// Over to the processor, waits for it to take the body, switches it on, and puts what comes out in the fridge.
/datum/bot_step/paced/run_processor
	max_clicks = 50
	optional = TRUE
	var/running = FALSE
	var/stored = 0

/datum/bot_step/paced/run_processor/start(datum/bot_brain/bot)
	running = FALSE
	stored = 0
	return TRUE

/datum/bot_step/paced/run_processor/do_click(datum/bot_brain/bot)
	var/obj/machinery/processor/slime/P = bot.current_goal?.target
	clicks++ //the walks and waits here count against it too: somebody else in the only spot beside it doesn't get waited out for good
	if(!istype(P) || QDELETED(P) || (P.stat & (BROKEN|NOPOWER)))
		return FALSE
	if(!bot.owner.Adjacent(P))
		if(bot.pursuing_kind != "follow")
			bot.pursue(P, "follow", force = TRUE)
		wait_for = 5
		return TRUE
	bot.stop_pursuit()
	wait_for = 10
	if(P.processing)
		running = TRUE
		return TRUE
	if(!running && (locate(/mob/living/simple_animal/slime) in P))
		bot.human_pause(P)
		bot.telemetry_ui_action(P, "turn on")
		INVOKE_ASYNC(P, TYPE_PROC_REF(/atom, interact), bot.owner)
		running = TRUE
		return TRUE
	var/obj/item/slime_extract/extract = locate() in get_turf(P)
	if(!extract)
		return !running && clicks < 20 //the body hasn't gone in yet
	var/obj/machinery/smartfridge/extract/fridge = locate() in range(4, P)
	if(!fridge)
		return FALSE
	if(!bot.owner.Adjacent(fridge))
		if(!bot.take_in_hand(extract))
			return FALSE
		bot.pursue(fridge, "follow", force = TRUE)
		return TRUE
	return bot.store_extract(extract, fridge) || TRUE

/datum/bot_brain/proc/store_extract(obj/item/slime_extract/extract, obj/machinery/smartfridge/extract/fridge)
	if(!bot_near_pickup(extract))
		return FALSE
	if(!use_tool_on(extract, fridge))
		return FALSE
	extracts_stored++
	bot_log(src, "put [extract] in [fridge]")
	return TRUE

/datum/bot_brain/proc/bot_near_pickup(obj/item/I)
	return (I in owner.held_items) || take_in_hand(I)

/datum/bot_step/paced/run_processor/finish(datum/bot_brain/bot)
	if(running)
		bot.slimes_processed++
		bot_log(bot, "processed a slime")
	return GOAL_STEP_SUCCESS

#undef BOT_XENO_PENS_FULL
#undef BOT_XENO_LOW_CUBES
#undef BOT_XENO_FEED_GAP
