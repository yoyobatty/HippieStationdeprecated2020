// Calling the shuttle: how a shift ends.
//
// A round runs until somebody calls the emergency shuttle, and if nobody does it runs for ever. Among players that falls
// to a head of staff, usually somewhere past the hour mark or sooner if the station has had enough. They walk to a
// communications console, log in with their ID, give a reason and confirm (communications.dm: "login", "callshuttle",
// "callshuttle2"). The console takes only an ID with head of staff access, so this duty is theirs. A crew with no head
// left takes one off a body (goals/robust.dm): the game's own casualty auto-call is off in config, and it only counts players.

/// When a head of staff calls it a day, picked once a round. -1 is never: a Bot Shift and the Bot Gym end when they say.
GLOBAL_VAR_INIT(bot_shift_ends_at, 0)
/// How long the comms console can be out, once somebody has said so, before Central Command acts.
#define BOT_COMMS_DOWN_WAIT (10 MINUTES)
/// When a head of staff first found it couldn't call the shuttle.
GLOBAL_VAR_INIT(bot_comms_down_since, 0)

GLOBAL_LIST_INIT(bot_shuttle_wrap_up_reasons, list(
	"Shift's over, crew transfer.",
	"End of shift, bringing everyone home.",
	"Routine crew transfer, the shift has run its course.",
	"That's the shift done. Sending the crew home.",
	"Crew rotation is due, calling it for today.",
))

GLOBAL_LIST_INIT(bot_shuttle_casualty_reasons, list(
	"Too many dead, we need to get the survivors out.",
	"Heavy casualties, evacuating what's left of the crew.",
	"We've lost too many people. Evacuating the station.",
))

/// goals/sabotage_engine.dm: the tesla (or a singularity) out of its cage, and somebody's said so
GLOBAL_LIST_INIT(bot_shuttle_engine_reasons, list(
	"The engine's loose and there's no stopping it. Evacuating the station.",
	"Engine containment has failed. Everybody to the shuttle.",
))
GLOBAL_LIST_INIT(bot_shuttle_suit_reasons, list(
	"A Syndicate agent in a nanosuit is killing the crew and Security can't stop them. Evacuating.",
	"Hostile in a Syndicate suit, several dead. Getting everyone off the station.",
))
GLOBAL_LIST_INIT(bot_shuttle_called_lines, list(
	";Shuttle's been called, finish up what you're doing.",
	";I've called the shuttle, get to departures when it's close.",
	";Shuttle's on its way. Wrap things up.",
))

/datum/bot_brain
	/// Tried to call it and couldn't: not again before this.
	var/shuttle_call_blocked_until = 0
	/// Times this bot has called the shuttle. Only the Bot Gym counts these: its calls don't reach the real shuttle.
	var/shuttle_calls = 0

/proc/bot_shift_end_time()
	if(!GLOB.bot_shift_ends_at)
		if(BOT_ROUND_PARAMETER in world.params)
			var/minutes = text2num(world.params[BOT_ROUND_PARAMETER])
			GLOB.bot_shift_ends_at = minutes > 1 ? SSticker.round_start_time + minutes MINUTES : SSticker.round_start_time + rand(55 MINUTES, 85 MINUTES)
		else if((BOT_GYM_PARAMETER in world.params) || (BOT_SHIFT_PARAMETER in world.params))
			GLOB.bot_shift_ends_at = -1
		else
			GLOB.bot_shift_ends_at = SSticker.round_start_time + rand(55 MINUTES, 85 MINUTES)
	return GLOB.bot_shift_ends_at

/// Whether so many of the crew are dead that the survivors should leave.
/proc/bot_crew_decimated()
	var/crew = 0
	var/lost = 0
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(!H.mind?.assigned_role || !SSjob.GetJob(H.mind.assigned_role))
			continue //a station job: not an operative or the wizard, nor a body in a ruin
		crew++
		if(H.stat == DEAD)
			lost++
	return crew >= 6 && lost * 3 >= crew

/// Dead crew before a suit nobody's stopped is reason enough to leave.
#define BOT_SUIT_DEATHS_TO_LEAVE 4

/// Somebody in a Syndicate suit loose, wanted, and the crew dying: the user's ruling (2026-11-04) is that the Captain or the acting
/// captain calls the shuttle early, as players do when a round's gone that way.
/proc/bot_unstoppable_suit()
	if(bot_dead_crew_count() < BOT_SUIT_DEATHS_TO_LEAVE) //goals/robust.dm
		return FALSE
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		if(H && H.stat != DEAD && !H.handcuffed && istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
			return TRUE
	return FALSE

#undef BOT_SUIT_DEATHS_TO_LEAVE

/// Why this bot should call the shuttle now, in its own words, or null if it shouldn't.
/datum/bot_brain/proc/reason_to_call_shuttle()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!gym_run && (!E || E.mode != SHUTTLE_IDLE))
		return null
	var/ends_at = bot_shift_end_time()
	if(ends_at == -1)
		return null
	if(GLOB.bot_engine_loose_called && bot_loose_engine())
		return pick(GLOB.bot_shuttle_engine_reasons)
	if(bot_crew_decimated())
		return pick(GLOB.bot_shuttle_casualty_reasons)
	if(bot_unstoppable_suit())
		return pick(GLOB.bot_shuttle_suit_reasons)
	if(GLOB.bot_ops_seen_at && world.time > GLOB.bot_ops_seen_at + 2 MINUTES && bot_operatives_loose()) //goals/nuke_defence.dm
		return pick(GLOB.bot_shuttle_ops_reasons)
	return world.time >= ends_at ? pick(GLOB.bot_shuttle_wrap_up_reasons) : null

/// A reason to call it that won't wait for the errand in hand: people dying, an engine loose, a suit nobody's stopped, operatives. Not
/// the shift's end, which can.
/datum/bot_brain/proc/emergency_to_call_shuttle()
	var/reason = reason_to_call_shuttle()
	return reason && !(reason in GLOB.bot_shuttle_wrap_up_reasons) ? reason : null

/// For the shuttle with people dying: whether to drop what it's doing and go. Not while its own life, or somebody else's in its hands,
/// is the errand. In round-20.48.49 a third of the crew was dead and the Head of Personnel ate some carrot fries, did a cargo round
/// and swapped jokes with the bartender for three minutes, then was killed with the shuttle never called.
/datum/bot_duty/proc/shuttle_cant_wait(datum/bot_brain/bot)
	var/next = bot.duty_next_check[src]
	if(bot_shift_gone_bad() && next > world.time + 20 SECONDS)
		next = world.time + 20 SECONDS //a look it booked before the bodies piled up comes sooner
		bot.duty_next_check[src] = next
	if(world.time < next || world.time < bot.shuttle_call_blocked_until)
		return FALSE
	for(var/datum/bot_goal/G in list(bot.current_goal, bot.suspended_goal))
		if(bot_goal_sees_to_shuttle(G))
			return FALSE //on it already
		if(istype(G, /datum/bot_goal/run_from) || istype(G, /datum/bot_goal/seek_air) || istype(G, /datum/bot_goal/revive_patient) || istype(G, /datum/bot_goal/escort_to_sleeper) || istype(G, /datum/bot_goal/brig_prisoner))
			return FALSE
	return !bot.other_seeing_to_shuttle() && !!bot.emergency_to_call_shuttle()

/proc/bot_goal_sees_to_shuttle(datum/bot_goal/G)
	return istype(G, /datum/bot_goal/call_shuttle) || istype(G, /datum/bot_goal/borrow_head_card) || istype(G, /datum/bot_goal/acquire_captains_id)

/// Somebody else already on their way to get the shuttle called: one's enough, as among players. With a drill's crew all told at once
/// (the stand-in duty dropping whatever they were doing), ten of them made for the Captain's locker together.
/datum/bot_brain/proc/other_seeing_to_shuttle()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B == src || QDELETED(B.owner) || B.owner.stat == DEAD || (gym_run && B.gym_run != gym_run))
			continue
		if(bot_goal_sees_to_shuttle(B.current_goal) || bot_goal_sees_to_shuttle(B.suspended_goal))
			return B
	return null

/datum/bot_duty/call_shuttle
	name = "calling the shuttle"
	tier = BOT_DUTY_URGENT
	priority = 50
	interval_min = 300
	interval_max = 900
	interrupts = TRUE

/datum/bot_duty/call_shuttle/applies_to(datum/bot_brain/bot)
	return bot.work_role() in GLOB.command_positions

/datum/bot_duty/call_shuttle/should_interrupt(datum/bot_brain/bot)
	return shuttle_cant_wait(bot)

/// Once the bodies are piling up, it's never far from mind: a look every 10-20 s, not every 30-90.
/datum/bot_duty/call_shuttle/next_look(datum/bot_brain/bot)
	return bot_shift_gone_bad() ? rand(100, 200) : ..()

/datum/bot_duty/call_shuttle/try_start(datum/bot_brain/bot)
	if(world.time < bot.shuttle_call_blocked_until)
		return FALSE
	var/reason = bot.reason_to_call_shuttle()
	if(!reason || bot.other_seeing_to_shuttle())
		return FALSE
	if(!bot.find_comms_console())
		bot.shuttle_console_down(reason)
		return FALSE
	var/datum/bot_goal/call_shuttle/call_goal = new
	call_goal.reason = reason
	return bot.assign_goal(call_goal)

/// Time to go and no console that works: no power on the bridge, usually. The head says so, and if nothing has changed
/// a while later Central Command sends the transfer shuttle anyway, as it would for a station that stopped answering.
/// Without this a station that lost its power was a round that never ended.
/datum/bot_brain/proc/shuttle_console_down(reason, what_it_says = ";Comms console's dead, I can't call the shuttle. Engineering, we need power on the bridge.")
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!GLOB.bot_comms_down_since)
		GLOB.bot_comms_down_since = world.time
		bot_say(owner, what_it_says)
		return
	if(world.time < GLOB.bot_comms_down_since + BOT_COMMS_DOWN_WAIT || !E)
		return
	GLOB.bot_comms_down_since = 0
	bot_log(src, "Central Command is sending the shuttle: the comms console is down")
	E.request(null, set_coefficient = 1, reason = "Station not responding. Crew transfer shuttle dispatched by Central Command.")

/datum/bot_goal/call_shuttle
	lawful = TRUE
	exclusive = TRUE
	doing = "calling the shuttle"
	/// What goes in the box on the console.
	var/reason

/datum/bot_goal/call_shuttle/resolve_target(datum/bot_brain/bot)
	target = bot.find_comms_console()
	// No way to a console by its own doors and people dying: it gets in however it can. The Chief Engineer had "no path" to the console
	// in the Captain's Office while the Captain killed the crew, gave up, and nobody else tried (2026-11-10).
	if(target && bot_shift_gone_bad() && !bot.has_way_to(target))
		lawful = FALSE
		bot_log(bot, "no way to [target] by my own doors - breaking in")

/datum/bot_goal/call_shuttle/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/call_shuttle/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/call_shuttle())
	return list(S)

/datum/bot_goal/call_shuttle/on_give_up(datum/bot_brain/bot)
	bot.shuttle_call_blocked_until = world.time + 3 MINUTES

/datum/bot_strategy/call_shuttle/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// Whether the bot can still work this console: beside it, and it's up.
/datum/bot_brain/proc/at_working_console(obj/machinery/computer/communications/C)
	return istype(C) && !QDELETED(C) && owner.Adjacent(C) && !(C.stat & (BROKEN|NOPOWER)) && owner.stat == CONSCIOUS

/datum/bot_step/call_shuttle/execute(datum/bot_brain/bot)
	var/datum/bot_goal/call_shuttle/G = bot.current_goal
	var/obj/machinery/computer/communications/C = G?.target
	if(!bot.at_working_console(C))
		return GOAL_STEP_FAIL
	if(!C.check_access(bot.owner.get_idcard(TRUE)))
		bot_log(bot, "[C] won't take my ID")
		return GOAL_STEP_FAIL
	bot.owner.face_atom(C)
	bot.human_pause(C)
	if(!bot.at_working_console(C))
		return GOAL_STEP_FAIL
	bot.telemetry_ui_action(C, "log in")
	bot.human_pause(C)
	if(!bot.at_working_console(C))
		return GOAL_STEP_FAIL
	bot.telemetry_ui_action(C, "call emergency shuttle")
	sleep(bot_typing_time(G.reason))
	if(QDELETED(bot) || !bot.at_working_console(C))
		return GOAL_STEP_FAIL
	if(bot.gym_run)
		bot.shuttle_calls++
	else
		if(SSshuttle.emergency.mode != SHUTTLE_IDLE)
			return GOAL_STEP_SUCCESS //somebody else got there first
		SSshuttle.requestEvac(bot.owner, G.reason)
		if(SSshuttle.emergency.mode != SHUTTLE_CALL)
			bot_log(bot, "the console wouldn't call the shuttle (still refuelling?)")
			return GOAL_STEP_FAIL
		C.post_status("shuttle")
	bot_log(bot, "called the shuttle: \"[G.reason]\"")
	bot_say(bot.owner, pick(GLOB.bot_shuttle_called_lines))
	return GOAL_STEP_SUCCESS
#undef BOT_COMMS_DOWN_WAIT
