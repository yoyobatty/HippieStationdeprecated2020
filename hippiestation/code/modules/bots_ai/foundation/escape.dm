// Escape anything (the plan's foundation/escape.dm, M1).
//
// Breaking out. Smashing a window or a grille in its way was only ever allowed when the bot itself was in danger (urgency, bot_breach.dm):
// on fire, bad air, badly hurt. That's right for the crew about their day. It left an apex bot (every antagonist, by default) shut in a room
// on its own business and calm, waiting for somebody to let it out, the same as an assistant. Now an apex bot that isn't about its
// everyday work breaks through when there's no other way: when it's shut in, fighting, making an arrest for a major crime, or when it has
// already dropped its cover (gone_loud(), goals/robust.dm). A traitor keeping its cover doesn't smash its way round the station; one shut
// in somewhere gets out. Below apex nothing changes.

/datum/bot_brain
	/// breaks_out(), for the tick it was worked out in: route searches ask it for every window they look at
	var/breaks_out_known = FALSE
	var/breaks_out_at = -1

/// Breaks what's in its way when there's no other way, calm or not (above).
/datum/bot_brain/proc/breaks_out()
	if(breaks_out_at == world.time)
		return breaks_out_known
	breaks_out_at = world.time
	breaks_out_known = FALSE
	if(!pursuing_kind || pursuing_kind == "wander" || measuring_shut_in || !is_apex() || pursuit_is_lawful())
		return FALSE
	// An arrest only for a major crime: the user's ruling (2026-11-04), breaking in to chase is for serious crimes only
	// (minor_arrest_at_door(), goals/security_patrol.dm). An apex officer broke the Head of Security's office window with a baton over
	// low-threat trespassing (Bot Shift found_after run3).
	breaks_out_known = state == BOT_STATE_COMBAT || (state == BOT_STATE_ARREST && arrest_severity >= BOT_CRIME_MAJOR) || gone_loud() || is_shut_in()
	return breaks_out_known

/// The urgency breaking things goes by (bot_breach.dm): what it feels, or an emergency for an apex bot breaking out.
/datum/bot_brain/proc/breach_urgency()
	. = get_urgency()
	if(. < BOT_URGENCY_EMERGENCY && breaks_out())
		. = BOT_URGENCY_EMERGENCY

// ---------------------------------------------------------------------------------------------
// Cutting through a wall (escape rooms, 2026-11-13). Shut in with no door, window or anything else to get through, an apex bot breaking
// out cuts a plain wall toward where it's going, as a player with a toolbox does: a lit welder slices the plating off (try_decon(),
// walls.dm, 10 s), a wrench unsecures the girder that's left and a screwdriver takes it apart (girders.dm, 4 s each). Never a reinforced
// wall, and never one with space or bad air behind it. Missing a tool, it fetches it first: one fetch at a time (suspend_goal_for() holds
// one goal), and each time the walk comes back with no route the next is fetched, then the wall cut.
// ---------------------------------------------------------------------------------------------

GLOBAL_LIST_INIT(bot_wall_cut_tools, list(/obj/item/weldingtool, /obj/item/wrench, /obj/item/screwdriver))

/// How big a pocket of floor it looks for walls round: bigger than that, it isn't shut in anywhere a wall is the way out
#define BOT_CUT_POCKET_TILES 400

/datum/bot_brain
	/// Destination turf -> until when it doesn't try cutting its way to it again
	var/list/walls_cut_toward

/// A wall it could take apart with a welder, a wrench and a screwdriver
/proc/bot_wall_cuttable(turf/closed/wall/W)
	return istype(W) && !istype(W, /turf/closed/wall/r_wall) && !(W.flags_1 & NODECONSTRUCT_1) && W.slicing_duration <= 200

/// do_repath() found no route at all (bot_movement.dm). TRUE if it's now fetching a tool for a wall, or cutting it.
/datum/bot_brain/proc/try_cut_way_through(turf/destination)
	if(state != BOT_STATE_GOAL || !current_goal || suspended_goal || in_mech() || !destination)
		return FALSE
	// Cuffed, it gets them off first (should_slip_cuffs(), bot_reflexes.dm): a cuffed traitor went for a screwdriver to cut its way out of
	// Customs (Bot Shift found2 run4)
	if(owner.handcuffed || owner.incapacitated())
		return FALSE
	if(LAZYACCESS(walls_cut_toward, destination) > world.time)
		return FALSE
	var/list/cut = wall_to_cut_toward(destination)
	if(!cut)
		return FALSE
	var/turf/wall = cut[1]
	for(var/obj/item/tool_type as anything in GLOB.bot_wall_cut_tools)
		if(!can_eventually_provide_tool(tool_type))
			bot_log(src, "the only way to [destination] is through [wall] @ [bot_coord(wall)] - getting \a [initial(tool_type.name)] to cut it")
			return seek_tool_for_obstacle(tool_type)
	if(LAZYLEN(walls_cut_toward) > 20)
		walls_cut_toward.Cut()
	LAZYSET(walls_cut_toward, destination, world.time + 3 MINUTES)
	bot_log(src, "no way to [destination] but through [wall] @ [bot_coord(wall)] - cutting through it")
	return suspend_goal_for(new /datum/bot_goal/cut_through_wall(wall, cut[2]))

/// The wall to cut: on the edge of the pocket of floor it can walk, with breathable floor behind it that's outside the pocket, nearest
/// where it's going. list(wall, tile to stand on), or null.
/datum/bot_brain/proc/wall_to_cut_toward(turf/destination)
	var/turf/start = get_turf(owner)
	if(!start)
		return null
	var/obj/item/card/id/id_card = route_card()
	var/simulated_only = !can_path_through_space()
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/at = 1
	while(at <= length(queue))
		var/turf/T = queue[at++]
		for(var/d in GLOB.cardinals)
			var/turf/N = get_step(T, d)
			if(!N || seen[N] || !T.bot_reachable_strict(owner, N, id_card, simulated_only))
				continue
			seen[N] = TRUE
			queue += N
			if(length(queue) >= BOT_CUT_POCKET_TILES)
				return null
	var/best_score
	var/turf/best_wall
	var/turf/best_from
	for(var/turf/T as anything in queue)
		for(var/d in GLOB.cardinals)
			var/turf/closed/wall/W = get_step(T, d)
			if(!bot_wall_cuttable(W))
				continue
			var/turf/beyond = get_step(W, d)
			if(!beyond || beyond.density || seen[beyond] || isspaceturf(beyond) || bot_turf_is_deadly(beyond))
				continue
			var/datum/gas_mixture/air = beyond.return_air()
			if(!air || air.return_pressure() < WARNING_LOW_PRESSURE)
				continue //not into vacuum or a room with the air gone
			var/score = get_dist(beyond, destination)
			if(isnull(best_score) || score < best_score)
				best_score = score
				best_wall = W
				best_from = T
	return best_wall ? list(best_wall, best_from) : null

/datum/bot_goal/cut_through_wall
	exclusive = TRUE
	doing = "cutting through a wall"
	/// The wall; target is the tile it's cut from
	var/turf/wall

/datum/bot_goal/cut_through_wall/New(turf/the_wall, turf/from)
	. = ..()
	wall = the_wall
	target = from

/datum/bot_goal/cut_through_wall/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/staged())
	return list(S)

/datum/bot_goal/cut_through_wall/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	var/obj/structure/girder/G = locate() in wall
	if(!iswallturf(wall) && !G)
		bot_log(bot, "cut through to [wall] @ [bot_coord(wall)]")
		bot_tally("walls cut through")
		return GOAL_STEP_SUCCESS
	if(istype(G, /obj/structure/girder/reinforced) || !bot.owner.Adjacent(wall))
		return GOAL_STEP_FAIL
	var/tool_type = iswallturf(wall) ? /obj/item/weldingtool : (G.state == GIRDER_DISPLACED ? /obj/item/screwdriver : /obj/item/wrench)
	var/obj/item/I = bot.find_or_transform_tool(tool_type)
	if(!I)
		return GOAL_STEP_FAIL
	var/obj/item/weldingtool/welder = I
	if(istype(welder) && !welder.isOn())
		if(!welder.get_fuel())
			return GOAL_STEP_FAIL
		bot.toggle_in_hand(welder)
		return step.again(bot, 5)
	var/before = "[wall.type]|[G?.type]|[G?.state]"
	bot.use_tool_on(I, G || wall) //walls.dm try_decon(), girders.dm wrench_act()/screwdriver_act(): it waits out the tool there
	if("[wall.type]|[locate(/obj/structure/girder) in wall]" == before && ++step.tries > 4)
		return GOAL_STEP_FAIL
	return step.again(bot, 3)

#undef BOT_CUT_POCKET_TILES
