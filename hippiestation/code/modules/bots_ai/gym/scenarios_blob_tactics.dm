// Bot Gym scenarios for goals/blob_tactics.dm: the strain scanned and fought by, and Science's bomb on the blob.
//
// Layout letters: k a blob core (an overmind nobody drives, so it only grows round its core), b a plain bit of blob belonging to it.
// What only the fix adds is reached by name (vars["..."]), so "before" (ab_gym.sh) compiles.

/datum/bot_scenario/blob_tactic
	time_limit = 60 SECONDS
	var/obj/structure/blob/core/core
	/// The strain it's given, and whether the crew have been told it
	var/strain_type
	var/strain_known = FALSE
	var/list/blobs_at_start = list()

/datum/bot_scenario/blob_tactic/setup()
	var/list/blob_turfs = list()
	for(var/turf/T in markers["b"])
		blob_turfs += T
	core = gym_blob_core(first_marker("k"), blob_turfs)
	if(strain_type)
		core.overmind.set_strain(strain_type)
	if(strain_known && ("bot_strain_known" in core.overmind.vars))
		core.overmind.vars["bot_strain_known"] = TRUE
	core.bot_announced = TRUE //told of, as at three minutes into a round
	for(var/obj/structure/blob/normal/B in core.overmind.blobs_legit)
		blobs_at_start[B] = B.obj_integrity //a new blob doesn't start at its most

/datum/bot_scenario/blob_tactic/release_run()
	gym_blob_release(core)
	return ..()

/// The plain blob nearest the bot
/datum/bot_scenario/blob_tactic/proc/nearest_blob()
	var/obj/structure/blob/best
	for(var/obj/structure/blob/normal/B in blobs_at_start)
		if(!QDELETED(B) && (!best || get_dist(bot, B) < get_dist(bot, best)))
			best = B
	return best

/datum/bot_scenario/blob_tactic/make_goal()
	var/obj/structure/blob/B = nearest_blob()
	return B ? new /datum/bot_goal/fight_blob(B) : null

/// Any of the blob it started with hurt or gone
/datum/bot_scenario/blob_tactic/proc/blob_harmed()
	for(var/obj/structure/blob/B as anything in blobs_at_start)
		if(QDELETED(B) || B.obj_integrity < blobs_at_start[B])
			return TRUE
	return FALSE

/datum/bot_scenario/blob_tactic/proc/welder_lit()
	for(var/obj/item/weldingtool/W in bot.GetAllContents())
		if(W.isOn())
			return TRUE
	return FALSE

/datum/bot_scenario/blob_tactic/scans
	name = "blob: a scientist at a blob nobody's scanned puts an analyzer on it and tells the radio what it is"
	desc = "A scientist with an analyzer in its bag and a welder in hand, sent at a blob of replicating foam nobody has scanned. Before the first blow it puts the analyzer on the blob and says on the radio what strain it is and how to fight it. Nobody scanned a blob: the crew burned replicating foam, which grows when it's burnt."
	job = "Scientist"
	kit_hands = list(/obj/item/weldingtool)
	kit_backpack = list(/obj/item/analyzer)
	strain_type = /datum/blobstrain/reagent/replicating_foam
	layout = list(
		"##################",
		"#B..........bbbbk.#",
		"#...........bbbbb.#",
		"##################")

/datum/bot_scenario/blob_tactic/scans/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(core.overmind.vars["bot_strain_known"] && bot_transcript_said("replicating foam"))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/blob_tactic/foam
	name = "blob: told it's replicating foam, a volunteer hits it with an extinguisher, not its welder"
	desc = "Replicating foam, scanned and called out: burnt, it grows another blob. The volunteer has a welder in hand and an extinguisher in its bag. It leaves the welder off and beats the blob with the extinguisher. Before, it lit the welder, as for any blob."
	job = "Assistant"
	kit_hands = list(/obj/item/weldingtool)
	kit_backpack = list(/obj/item/extinguisher)
	strain_type = /datum/blobstrain/reagent/replicating_foam
	strain_known = TRUE
	time_limit = 40 SECONDS
	layout = list(
		"##################",
		"#B..........bbbbk.#",
		"#...........bbbbb.#",
		"##################")

/datum/bot_scenario/blob_tactic/foam/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(welder_lit())
		fail_reason = "lit its welder on replicating foam"
		return BOT_GYM_FAIL
	// the extinguisher in hand at the blob, and some of it hurt: a blob can come out of the arena's first second short of its most
	return (blob_harmed() && istype(bot.get_active_held_item(), /obj/item/extinguisher) && (locate(/obj/structure/blob) in range(1, bot))) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/blob_tactic/blazing_oil
	name = "blob: told it's blazing oil, a volunteer sprays it with an extinguisher, not its welder"
	desc = "Blazing oil, scanned and called out: burnt, it throws flames round it, and water does it harm. The volunteer has a welder in hand and an extinguisher in its bag. It sprays the blob from a tile or two back. Before, it walked up and burned it."
	job = "Assistant"
	kit_hands = list(/obj/item/weldingtool)
	kit_backpack = list(/obj/item/extinguisher)
	strain_type = /datum/blobstrain/reagent/blazing_oil
	strain_known = TRUE
	time_limit = 40 SECONDS
	layout = list(
		"##################",
		"#B..........bbbbk.#",
		"#...........bbbbb.#",
		"##################")
	var/water_at_start = 0

/datum/bot_scenario/blob_tactic/blazing_oil/post_spawn()
	var/obj/item/extinguisher/E = locate() in bot.GetAllContents()
	water_at_start = E?.reagents.total_volume

/datum/bot_scenario/blob_tactic/blazing_oil/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(welder_lit())
		fail_reason = "lit its welder on blazing oil"
		return BOT_GYM_FAIL
	var/obj/item/extinguisher/E = locate() in bot.GetAllContents()
	return (E && E.reagents.total_volume < water_at_start && blob_harmed()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Science's maxcap, made and on its valve with a timer: the blob's been announced, so it goes there and not to the range.
/datum/bot_scenario/blob_tactic/bomb
	name = "blob: Science's finished maxcap goes on the blob, not the test range, and the scientist gets clear"
	desc = "The toxins lab's bomb is made, on its valve with a timer, and a blob the station's been told of has grown big. The scientist says on the radio it's taking the bomb to the blob, sets it down a couple of tiles off the blob's edge on the side nearest the core, starts the timer and gets well clear. Before, it took the bomb to the range's mass driver and the blob was left alone. The tanks here are empty."
	job = "Scientist"
	time_limit = 60 SECONDS
	layout = list(
		"##########################################",
		"#B...........................bbbbbbbbbbbb#",
		"#............................bbbbbbbbbbbb#",
		"#............................bbbbbbbbbbkb#",
		"##########################################")
	var/obj/item/transfer_valve/bomb
	var/datum/bot_toxins/lab
	var/datum/bot_toxins/round_lab

/datum/bot_scenario/blob_tactic/bomb/post_spawn()
	bomb = bot_gym_tank_bomb(get_turf(bot))
	bot.put_in_hands(bomb)
	round_lab = GLOB.bot_toxins
	lab = new
	lab.found = TRUE
	lab.stage = 21
	lab.valve = bomb
	lab.worker = WEAKREF(bot)
	GLOB.bot_toxins = lab

/datum/bot_scenario/blob_tactic/bomb/make_goal()
	return lab.next_goal(brain)

/datum/bot_scenario/blob_tactic/bomb/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(bomb))
		fail_reason = "the bomb's gone"
		return BOT_GYM_FAIL
	var/obj/item/assembly/timer/T = bomb.attached_device
	if(!isturf(bomb.loc) || !T?.timing)
		return BOT_GYM_PENDING
	var/obj/structure/blob/near = locate() in range(3, bomb)
	if(!near)
		fail_reason = "set it going with no blob within three tiles of it"
		return BOT_GYM_FAIL
	if(get_dist(bomb, core) > 14)
		fail_reason = "set it [get_dist(bomb, core)] tiles from the core, not on its side of the blob"
		return BOT_GYM_FAIL
	return (get_dist(bot, bomb) >= 12 && bot_transcript_said("bomb to the blob")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/blob_tactic/bomb/release_run()
	if(GLOB.bot_toxins == lab)
		GLOB.bot_toxins = round_lab
	if(!QDELETED(bomb))
		qdel(bomb)
	return ..()

/// An officer, brave enough for a stranger's ticking bomb, near Science's bomb on the blob: told of on the radio.
/datum/bot_scenario/defuses_bomb/blob
	name = "blob: an officer near Science's bomb on the blob gets clear and leaves its timer alone"
	desc = "A tank bomb Science set by a blob, ticking, called out on the radio, five tiles from a security officer who'd pull the timer off a stranger's. It gets well clear and leaves it. Before, it walked over and took the timer off."
	layout = list(
		"##########################",
		"#.............B.....g....#",
		"#........................#",
		"##########################")

/datum/bot_scenario/defuses_bomb/blob/post_spawn()
	..()
	if("bot_for_blob" in bomb.vars)
		bomb.vars["bot_for_blob"] = TRUE

/datum/bot_scenario/defuses_bomb/blob/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(bomb) || !bomb.attached_device)
		fail_reason = "pulled the timer off Science's bomb"
		return BOT_GYM_FAIL
	return get_dist(bot, bomb) >= 12 ? BOT_GYM_PASS : BOT_GYM_PENDING

/// The core in sight, a pillar of wall straight between: round it, and on to the blob.
/datum/bot_scenario/blob_tactic/round_the_wall
	name = "blob: a volunteer after the core with a wall in the straight way goes round it and gets to work on the blob"
	desc = "A volunteer with a lit welder's worth of fuel is after a blob core across a room, with a bit of wall straight between them. It steps round the wall and cuts its way in. Before, the straight step was the wall, it gave the core up at once and picked it again a moment later, hundreds of times a shift, and never struck a blow."
	job = "Assistant"
	kit_hands = list(/obj/item/weldingtool)
	time_limit = 15 SECONDS //the blob grows round to it in the end anyway: before, 22-36 s
	layout = list(
		"##############",
		"#............#",
		"#B..#....bbk.#",
		"#............#",
		"##############")

/datum/bot_scenario/blob_tactic/round_the_wall/make_goal()
	return new /datum/bot_goal/fight_blob(core)

/datum/bot_scenario/blob_tactic/round_the_wall/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return blob_harmed() ? BOT_GYM_PASS : BOT_GYM_PENDING //the blob between it and the core: the core comes after

/// Both hands full and the bag too: what it's only just picked up stays in hand, and the other hand's load goes down for the next thing.
/datum/bot_scenario/hands_keep_just_taken
	name = "hands: full hands and bag, picking up a second part keeps the first part, not the tool"
	desc = "A wrench in one hand, a screwdriver in the other, the bag full. It picks up a power cell (the screwdriver goes down for it), then an assembly: the wrench goes down, not the cell it's only just picked up. Before, the cell went down for the assembly and the assembly for the cell, 12 times running in a circuit build."
	job = "Scientist"
	time_limit = 20 SECONDS
	kit_hands = list(/obj/item/wrench, /obj/item/screwdriver)
	kit_backpack = list(/obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher)
	layout = list(
		"#######",
		"#Byz..#",
		"#######")
	var/obj/item/stock_parts/cell/part_one
	var/obj/item/electronic_assembly/part_two
	var/done = FALSE

/datum/bot_scenario/hands_keep_just_taken/setup()
	part_one = new(first_marker("y"))
	part_two = new(first_marker("z"))

/datum/bot_scenario/hands_keep_just_taken/make_goal()
	return null

/datum/bot_scenario/hands_keep_just_taken/post_spawn()
	INVOKE_ASYNC(src, PROC_REF(pick_both))

/datum/bot_scenario/hands_keep_just_taken/proc/pick_both()
	brain.take_in_hand(part_one)
	step(bot, EAST)
	brain.take_in_hand(part_two)
	done = TRUE

/datum/bot_scenario/hands_keep_just_taken/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!done)
		return BOT_GYM_PENDING
	if(!(part_two in bot.held_items))
		fail_reason = "the assembly isn't in hand"
		return BOT_GYM_FAIL
	if(!(part_one in bot.held_items))
		fail_reason = "set the cell it had only just picked up down for the assembly ([part_one.loc])"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
