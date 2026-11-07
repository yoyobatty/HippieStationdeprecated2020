// Sabotage: the user's chaos list (2026-11-06), "traitors vandalize the station, plasma floods, singulos and teslas going loose,
// maxcaps in security/bridge, crazy chemist nades, lethal viruses, xenobio slimes going nuts". Their rulings:
//
//  - Who: a saboteur is a traitor who goes about it undercover like most (goals/robust.dm), with one or more acts of sabotage on top
//    of its objectives, by personality. At BOT_CHAOS 2 ordinary crew have accidents too (bot_chaos.dm).
//  - How often: by BOT_CHAOS. At 1, maybe one saboteur a round, from a traitor whose personality fits, with one act. At 2, up to three,
//    with two or three acts each, and they stack.
//  - Both sides: each act comes with the crew's answer to it, so a round can still be won. A plasma flood has the air alarms and the
//    firefighters already (respond_to_contamination.dm, respond_to_fire.dm); what the others need is with them.
//
// Each act is a /datum/bot_sabotage: how well it suits this bot (its job, what's on the station, what it's done already) and the goal
// it starts. Done unseen if it can be: it waits for the room to thin out, and anybody who does see it calls it in as Sabotage
// (bot_witness.dm's call_it_in()), which Security takes as seriously as it is.
//
// Test parameters: bot-traitor-plan=saboteur makes every traitor one, bot-sabotage=<act> picks the act, bot-sabotage-after=<seconds>
// says when it starts.

/// How long after its emag a saboteur's first act comes, and between one and the next.
#define BOT_SABOTAGE_FIRST_MIN (2 MINUTES)
#define BOT_SABOTAGE_FIRST_MAX (6 MINUTES)
#define BOT_SABOTAGE_GAP_MIN (6 MINUTES)
#define BOT_SABOTAGE_GAP_MAX (10 MINUTES)
/// How long it waits for nobody to be watching before it gets on with it anyway.
#define BOT_SABOTAGE_PATIENCE (30 SECONDS)
/// How many saboteurs a round has at most, by chaos level.
#define BOT_SABOTEURS_CHAOS_1 1
#define BOT_SABOTEURS_CHAOS_2 3

GLOBAL_VAR_INIT(bot_saboteurs, 0)
/// Every act of sabotage done this round: "act by Name at Place", for the round report.
GLOBAL_LIST_EMPTY(bot_sabotage_log)
GLOBAL_LIST_INIT(bot_sabotage_acts, init_bot_sabotage_acts())

/proc/init_bot_sabotage_acts()
	. = list()
	for(var/path in subtypesof(/datum/bot_sabotage))
		var/datum/bot_sabotage/S = new path
		if(S.id)
			. += S

/proc/bot_sabotage_act(id)
	for(var/datum/bot_sabotage/S as anything in GLOB.bot_sabotage_acts)
		if(S.id == id)
			return S
	return null

/datum/bot_brain
	/// A traitor with sabotage on its mind as well as its objectives (still undercover: traitor_plan stays BOT_TRAITOR_UNDERCOVER).
	var/saboteur = FALSE
	/// When an engineer last caught it at the engine (bot_witness_sabotage()).
	var/caught_at_it = 0
	var/sabotage_acts_left = 0
	var/next_sabotage_time = 0
	/// Acts it's done, by id.
	var/list/sabotage_done
	/// Bot Gym: where a crowd would be, in place of the station's busy rooms.
	var/turf/gym_sabotage_spot

/// From pick_traitor_plan() (goals/robust.dm), for a traitor going undercover: whether it's a saboteur as well.
/datum/bot_brain/proc/maybe_become_saboteur(forced = FALSE)
	var/level = GLOB.bot_chaos_level
	if(!forced)
		if(level < 1 || GLOB.bot_saboteurs >= (level >= 2 ? BOT_SABOTEURS_CHAOS_2 : BOT_SABOTEURS_CHAOS_1))
			return FALSE
		// Somebody who'd rather wreck the place than face anybody down: some nerve, and a temper, but no hothead (those go loud).
		var/fits = nerve >= 0.4 && temper >= 0.4
		if(!prob(fits ? (level >= 2 ? 85 : 50) : (level >= 2 ? 35 : 0)))
			return FALSE
	saboteur = TRUE
	GLOB.bot_saboteurs++
	sabotage_acts_left = level >= 2 ? rand(2, 3) : 1
	var/after = text2num(world.params["bot-sabotage-after"])
	next_sabotage_time = !isnull(after) ? world.time + after * 10 : traitor_business_after + rand(BOT_SABOTAGE_FIRST_MIN, BOT_SABOTAGE_FIRST_MAX)
	traitor_business_after = min(traitor_business_after, next_sabotage_time) //the uplink and the emag come before it, whenever that is
	bot_log(src, "SABOTAGE: a saboteur, [sabotage_acts_left] act\s planned")
	return TRUE

/// From the traitor duty (goals/traitor.dm): its next act, if one's due and it can start one. TRUE if it has.
/datum/bot_brain/proc/try_sabotage()
	if(!saboteur || sabotage_acts_left <= 0 || world.time < next_sabotage_time || gone_loud())
		return FALSE
	var/datum/bot_sabotage/act = pick_sabotage()
	if(!act)
		next_sabotage_time = world.time + 2 MINUTES //nothing it can do just now: another look later
		return FALSE
	return start_sabotage(act)

/datum/bot_brain/proc/start_sabotage(datum/bot_sabotage/act)
	// Three goes at the same thing that came to nothing (a canister it can't get to, a lab full of somebody else's plasma): something
	// else, for a good while. A chemist stuck on a canister behind a door it couldn't open never got round to its grenade.
	if(act == sabotage_underway && ++sabotage_tries > 3)
		bot_log(src, "SABOTAGE: [act.id] isn't working out - something else")
		LAZYSET(sabotage_given_up, act.id, world.time + 10 MINUTES)
		sabotage_underway = null
		sabotage_tries = 0
		next_sabotage_time = world.time + 30 SECONDS
		return FALSE
	if(act != sabotage_underway)
		sabotage_tries = 1
	if(!act.start(src))
		next_sabotage_time = world.time + 1 MINUTES
		return FALSE
	sabotage_underway = act
	bot_log(src, "SABOTAGE: going for [act.id]")
	return TRUE

/datum/bot_brain
	/// The act it's started on, which may take a few goals (a lighter to buy, a grenade to brew): it comes back to this one.
	var/datum/bot_sabotage/sabotage_underway
	var/sabotage_tries = 0
	/// Act id -> until when it's not tried again.
	var/list/sabotage_given_up

/// What it does next, as suits it: weighted by how well it suits this bot, and not the same thing twice while there's anything else.
/datum/bot_brain/proc/pick_sabotage()
	if(sabotage_underway && sabotage_underway.weight(src) > 0)
		return sabotage_underway
	var/forced = world.params["bot-sabotage"]
	if(forced)
		var/datum/bot_sabotage/S = bot_sabotage_act(forced)
		return S?.weight(src) > 0 ? S : null
	var/list/menu = list()
	var/list/again = list()
	for(var/datum/bot_sabotage/S as anything in GLOB.bot_sabotage_acts)
		if(LAZYACCESS(sabotage_given_up, S.id) > world.time)
			continue
		var/w = S.weight(src)
		if(w <= 0)
			continue
		if(S.id in sabotage_done)
			again[S] = w
		else
			menu[S] = w
	if(!length(menu))
		menu = again
	var/list/shown = list()
	for(var/datum/bot_sabotage/S as anything in menu)
		shown += "[S.id] [menu[S]]"
	bot_log(src, "SABOTAGE: could do [length(shown) ? jointext(shown, ", ") : "nothing"]")
	return length(menu) ? pickweight(menu) : null

/// Done: one fewer to go, and a while before the next.
/datum/bot_brain/proc/sabotage_finished(datum/bot_sabotage/act, where)
	LAZYOR(sabotage_done, act.id)
	sabotage_underway = null
	sabotage_acts_left--
	next_sabotage_time = world.time + rand(BOT_SABOTAGE_GAP_MIN, BOT_SABOTAGE_GAP_MAX)
	GLOB.bot_sabotage_log += "[act.id] by [owner.real_name] in [where]"
	bot_tally("sabotage: [act.id]")
	log_game("BOT SABOTAGE: [key_name(owner)] did [act.id] in [where]")

/// Anybody who saw it calls it in: from the moment it's done in front of them.
/// `engine`: it's the engine they're at, and an engineer who sees it with any nerve goes for them there and then (the user's ruling,
/// 2026-11-07: catch the saboteur in the act). Engineers put a sabotaged supermatter's loop back within seconds of the saboteur
/// finishing, and it went up all the same: eight pumps off one by one had the chamber at thousands of kelvin first.
/proc/bot_witness_sabotage(mob/living/carbon/human/saboteur, details, engine = FALSE)
	var/called = FALSE
	var/list/witnesses = bot_witnesses_of(saboteur, list(saboteur))
	// At the engine, an engineer in the engine room with them knows who's switching the pumps off, sight line or no: a Chief Engineer
	// put a supermatter's loop back on one side of its chamber while the saboteur switched the filters off on the other, five tiles off
	// with the chamber walls between, and never knew it.
	if(engine && istype(get_area(saboteur), /area/engine))
		for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
			var/mob/living/carbon/human/H = B.owner
			if(!(B in witnesses) && H != saboteur && !QDELETED(H) && H.stat == CONSCIOUS && H.z == saboteur.z && get_dist(H, saboteur) <= BOT_SIGHT_RANGE && istype(get_area(H), /area/engine))
				witnesses += B
	for(var/datum/bot_brain/B as anything in witnesses)
		if(B.bot_traitor || B.owner.incapacitated() || B.state == BOT_STATE_ARREST)
			continue
		if(engine && (B.work_role() in GLOB.engineering_positions) && B.nerve >= 0.3 && B.state != BOT_STATE_COMBAT)
			bot_say(B.owner, pick("Hey! Get away from that!", "What are you doing?! Leave the engine alone!", "Stop! Get off those pumps!"))
			bot_tally("saboteurs caught at the engine")
			log_game("BOT ENGINE: [key_name(B.owner)] caught [key_name(saboteur)] at the engine and went for them")
			if(saboteur.bot_brain)
				saboteur.bot_brain.caught_at_it = world.time
			B.step_in_against(saboteur) //bot_witness.dm: a fight, and a saboteur in a fight isn't switching anything off
		if(called)
			continue
		called = TRUE //one call does it: the rest heard it
		if(B.is_security_job())
			B.file_crime(saboteur, "Sabotage", "[capitalize(details)] in [get_area_name(saboteur, TRUE)].", BOT_CRIME_MAJOR)
			B.begin_arrest(saboteur)
		else
			B.call_it_in(saboteur, "Sabotage", details, BOT_CRIME_MAJOR)

/// Waits for the room to empty, for as long as it'll wait. TRUE once it's going ahead.
/datum/bot_brain/proc/sabotage_unwatched(started_waiting)
	return !watched_by_anyone() || world.time > started_waiting + BOT_SABOTAGE_PATIENCE

/// Where people are: the station's busy public rooms, the one with the most in it now. A player knows the Bar's where everybody is.
/datum/bot_brain/proc/sabotage_crowd_spot(list/area_types)
	if(gym_sabotage_spot)
		return gym_sabotage_spot
	var/static/list/public_rooms = list(/area/crew_quarters/bar, /area/crew_quarters/cafeteria, /area/hallway/primary, /area/crew_quarters/fitness, /area/hallway/secondary/exit/departure_lounge)
	var/list/counts = list()
	for(var/mob/living/carbon/human/H as anything in GLOB.carbon_list)
		if(!istype(H) || H == owner || H.stat == DEAD || H.z != owner.z)
			continue
		var/area/A = get_area(H)
		if(!A || !is_type_in_list(A, area_types || public_rooms))
			continue
		counts[A] += 1
	var/area/best
	for(var/area/A as anything in counts)
		if(!best || counts[A] > counts[best])
			best = A
	if(!best)
		return null
	// A bit of floor in it, near the middle of where they are, that it can get to.
	var/list/floors = list()
	for(var/mob/living/carbon/human/H in best)
		if(H != owner && H.stat != DEAD)
			floors += get_turf(H)
	var/tries = 0
	while(length(floors) && tries++ < 5)
		var/turf/T = pick_n_take(floors)
		for(var/turf/open/near in RANGE_TURFS(2, T))
			if(near.loc == best && !is_blocked_turf(near, TRUE) && !isspaceturf(near))
				return near
	return null

/datum/bot_sabotage
	var/id
	var/name

/// How much this bot is the one for it, 0 for not at all.
/datum/bot_sabotage/proc/weight(datum/bot_brain/bot)
	return 0

/// Gives the bot the goal for it. TRUE if it's on it.
/datum/bot_sabotage/proc/start(datum/bot_brain/bot)
	return FALSE

// ---------------------------------------------------------------------------------------------
// A plasma flood
// ---------------------------------------------------------------------------------------------
//
// A canister of plasma dragged into wherever people are, opened, and a lit lighter thrown in once it's had a few seconds to spread.
// The station's own alarms do the rest: the room's air alarm goes red, firelocks drop, and the atmos techs and engineers come to put it
// out and scrub it (respond_to_fire.dm, respond_to_contamination.dm).

/datum/bot_sabotage/plasma
	id = "plasma"
	name = "a plasma flood"

/datum/bot_sabotage/plasma/weight(datum/bot_brain/bot)
	if(!bot_plasma_canister_for(bot))
		return 0
	. = 2
	if(bot.work_role() in list("Atmospheric Technician", "Station Engineer", "Chief Engineer", "Scientist", "Research Director"))
		. += 2 //knows where the canisters are and what they do

/datum/bot_sabotage/plasma/start(datum/bot_brain/bot)
	if(!bot.find_carried_tool(/obj/item/lighter) && !bot.find_carried_tool(/obj/item/weldingtool))
		return bot.assign_goal(new /datum/bot_goal/buy_smokes()) //goals/leisure.dm: a lighter with them, as anybody buys one
	var/obj/machinery/portable_atmospherics/canister/C = bot_plasma_canister_for(bot)
	var/turf/spot = bot.sabotage_crowd_spot()
	if(!C || !spot)
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/sabotage_plasma(C, spot, src))

/// A canister with a good lot of plasma in it, on this bot's level, loose or on a port, nearest first.
/proc/bot_plasma_canister_for(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/canister/best
	var/best_dist
	for(var/obj/machinery/portable_atmospherics/canister/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister))
		if(QDELETED(C) || C.z != bot.owner.z || C.valve_open || (C.stat & BROKEN) || C.holding)
			continue
		var/list/moles = C.air_contents.moles
		if(moles[/datum/gas/plasma] < 500)
			continue
		var/dist = get_dist(bot.owner, C)
		if(dist > 100 || (best && dist >= best_dist))
			continue
		best = C
		best_dist = dist
	return best

/datum/bot_goal/sabotage_plasma
	doing = "moving a canister"
	breaks_in = TRUE //the emag through any door (bot_doors.dm emag_for_doors())
	var/obj/machinery/portable_atmospherics/canister/canister
	var/turf/spot
	var/datum/bot_sabotage/act

/datum/bot_goal/sabotage_plasma/New(obj/machinery/portable_atmospherics/canister/C, turf/T, datum/bot_sabotage/A)
	. = ..()
	canister = C
	spot = T
	act = A

/datum/bot_goal/sabotage_plasma/resolve_target(datum/bot_brain/bot)
	if(!QDELETED(canister) && spot)
		target = canister

/datum/bot_goal/sabotage_plasma/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	var/datum/bot_step/move_to/to_spot = new
	to_spot.step_target = spot
	S.steps = list()
	if(canister.connected_port)
		S.steps += new /datum/bot_step/ensure_wrench()
	S.steps += list(new /datum/bot_step/move_to(), new /datum/bot_step/free_portable(canister), new /datum/bot_step/grab_portable(canister), to_spot,
		new /datum/bot_step/paced/sabotage_open_canister(src), new /datum/bot_step/move_to/sabotage_throw_spot(src), new /datum/bot_step/paced/sabotage_light_it(src))
	return list(S)

/datum/bot_goal/sabotage_plasma/on_success(datum/bot_brain/bot)
	bot.sabotage_finished(act, get_area_name(canister || spot, TRUE))
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/lay_low())) //goals/robust.dm

/datum/bot_goal/sabotage_plasma/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	// Open is done: the lighter's the extra. Counted as done, or it went and opened a second canister in the same hallway, and the
	// two of them burned thirteen of a Hippie Station crew.
	if(!QDELETED(canister) && canister.valve_open)
		bot.sabotage_finished(act, get_area_name(canister, TRUE))

/datum/bot_strategy/sabotage/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// At the spot: lets go, waits for the room to thin out, and opens it all the way.
/datum/bot_step/paced/sabotage_open_canister
	max_clicks = 40
	var/datum/bot_goal/sabotage_plasma/goal
	var/waiting_since = 0
	var/opened = FALSE

/datum/bot_step/paced/sabotage_open_canister/New(datum/bot_goal/sabotage_plasma/G)
	. = ..()
	goal = G

/datum/bot_step/paced/sabotage_open_canister/start(datum/bot_brain/bot)
	waiting_since = world.time
	return !QDELETED(goal.canister) && bot.owner.Adjacent(goal.canister)

/datum/bot_step/paced/sabotage_open_canister/do_click(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/canister/C = goal.canister
	if(opened || QDELETED(C) || !bot.owner.Adjacent(C))
		return FALSE
	if(bot.owner.pulling == C)
		bot.owner.stop_pulling()
	if(!bot.sabotage_unwatched(waiting_since))
		wait_for = 10
		return TRUE
	bot.human_pause(C)
	bot.telemetry_ui_action(C, "open valve")
	C.release_pressure = C.can_max_release_pressure
	C.valve_open = TRUE
	C.update_icon()
	C.investigate_log("valve opened at [C.release_pressure] kPa by [key_name(bot.owner)] (bot saboteur).", INVESTIGATE_ATMOS)
	log_game("BOT SABOTAGE: [key_name(bot.owner)] opened [C] at [AREACOORD(C)]")
	opened = TRUE
	bot_witness_sabotage(bot.owner, "is letting plasma out of a canister")
	return FALSE

/datum/bot_step/paced/sabotage_open_canister/finish(datum/bot_brain/bot)
	return opened ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// A few steps back from it, still with a clear line to it: where the lighter's thrown from, on the side of the way out.
/datum/bot_step/move_to/sabotage_throw_spot
	var/datum/bot_goal/sabotage_plasma/goal

/datum/bot_step/move_to/sabotage_throw_spot/New(datum/bot_goal/sabotage_plasma/G)
	. = ..()
	goal = G

/datum/bot_step/move_to/sabotage_throw_spot/execute(datum/bot_brain/bot)
	if(!step_target)
		step_target = bot.sabotage_throw_spot(goal.canister)
	if(!step_target)
		return GOAL_STEP_SUCCESS //nowhere: it throws from where it is
	return ..()

/// Open floor 3 to 5 tiles from it that can see it, in the same room (across a counter it can see the Kitchen, and went for a fire axe
/// to get in there), nearest to a door.
/datum/bot_brain/proc/sabotage_throw_spot(atom/at)
	var/turf/best
	var/best_score
	var/area/room = get_area(at)
	for(var/turf/open/T in view(5, at))
		var/d = get_dist(T, at)
		if(d < 3 || T.loc != room || is_blocked_turf(T, TRUE) || isspaceturf(T))
			continue
		var/obj/machinery/door/airlock/door = locate() in range(6, T)
		var/score = (door ? get_dist(T, door) : 10) + get_dist(T, owner)
		if(!best || score < best_score)
			best = T
			best_score = score
	return best

/// A few seconds for it to spread, then the lighter goes in, lit. No lighter, no fire: the plasma alone is enough to clear the room.
/datum/bot_step/paced/sabotage_light_it
	max_clicks = 20
	var/datum/bot_goal/sabotage_plasma/goal
	var/opened_at = 0
	var/thrown = FALSE

/datum/bot_step/paced/sabotage_light_it/New(datum/bot_goal/sabotage_plasma/G)
	. = ..()
	goal = G

/datum/bot_step/paced/sabotage_light_it/start(datum/bot_brain/bot)
	opened_at = world.time
	return TRUE

/datum/bot_step/paced/sabotage_light_it/do_click(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/canister/C = goal.canister
	if(thrown || QDELETED(C))
		return FALSE
	if(world.time < opened_at + 6 SECONDS)
		wait_for = 10
		return TRUE
	var/obj/item/lighter/L = bot.find_carried_tool(/obj/item/lighter)
	if(!L)
		return FALSE
	if(!bot.ready_in_hand(L))
		return FALSE
	if(!L.lit)
		bot.human_pause(L)
		L.attack_self(bot.owner)
		if(!L.lit)
			return TRUE //another go at it
	bot.owner.face_atom(C)
	bot_log(bot, "SABOTAGE: throwing [L], lit, at [C]")
	log_game("BOT SABOTAGE: [key_name(bot.owner)] threw a lit [L] into the plasma at [AREACOORD(C)]")
	bot.owner.throw_item(get_turf(C))
	thrown = TRUE
	bot_witness_sabotage(bot.owner, "set the plasma alight")
	return FALSE

/datum/bot_step/paced/sabotage_light_it/finish(datum/bot_brain/bot)
	return GOAL_STEP_SUCCESS

#undef BOT_SABOTAGE_FIRST_MIN
#undef BOT_SABOTAGE_FIRST_MAX
#undef BOT_SABOTAGE_GAP_MIN
#undef BOT_SABOTAGE_GAP_MAX
#undef BOT_SABOTEURS_CHAOS_1
#undef BOT_SABOTEURS_CHAOS_2
