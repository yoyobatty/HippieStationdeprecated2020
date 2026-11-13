// The crew-kill planner (the plan's apex/kill_planner.dm, M5). An apex traitor out to kill everybody (BOT_TRAITOR_RAMPAGE, goals/robust.dm)
// used to do it one at a time: the next name, walk up, swing. A player who means it opens with the thing that takes the most of them at once,
// then mops up. So it plans the round in two parts:
//  1. The strike: one act of sabotage (goals/sabotage.dm), the deadliest it can manage where it is, not one picked to suit its
//     personality: a maxcap where the crew gathers, a superboom, a plasma fire, a grenade, a virus, the engine, the slimes, in that order.
//     It goes about it the way a saboteur does, quietly and unseen if it can.
//  2. The hunt: the rampage it was going to have anyway, one name after the next, with the director to find them (foundation/hunt.dm).
// Apex only; a rampaging traitor below apex goes straight to the hunt as before.

/// How many of the crew each act takes, roughly, as a multiplier on how well it suits the bot
GLOBAL_LIST_INIT(bot_sabotage_lethality, list("maxcap" = 6, "superboom" = 5, "plasma" = 4, "grenade" = 3, "virus" = 3, "engine" = 2, "slimes" = 1))

/datum/bot_brain
	/// It's an apex rampager's opening strike (plan_crew_kill()): sabotage picked by how many it'll take
	var/apex_strike = FALSE
	/// Past this with no strike made, it gives it up for the hunt
	var/apex_strike_deadline = 0

/// How long it'll work at a strike before it gives up on it and goes hunting: long enough for the toxins lab to come up with a bomb
#define BOT_STRIKE_PATIENCE (20 MINUTES)

/// From pick_traitor_plan() (goals/robust.dm), once it's decided to kill everybody.
/datum/bot_brain/proc/plan_crew_kill()
	if(apex_strike || saboteur || traitor_plan != BOT_TRAITOR_RAMPAGE || !is_apex())
		return FALSE
	saboteur = TRUE
	apex_strike = TRUE
	sabotage_acts_left = 1
	next_sabotage_time = traitor_business_after
	apex_strike_deadline = traitor_business_after + BOT_STRIKE_PATIENCE
	bot_log(src, "KILL PLAN: open with the deadliest sabotage it can manage, then hunt down whoever's left")
	bot_tally("crew-kill plans")
	return TRUE

/// What an act's weight is multiplied by for an apex rampager's strike (pick_sabotage(), goals/sabotage.dm)
/datum/bot_brain/proc/sabotage_lethality(datum/bot_sabotage/S)
	if(!apex_strike || !S)
		return 1
	return GLOB.bot_sabotage_lethality[S.id] || 1

/// From the traitor duty (goals/traitor.dm), before the hunt: TRUE if it's started on the strike; FALSE while one it's started is still
/// coming together (a bomb the lab's making, a grenade to brew), and it goes about its job meanwhile rather than give itself away by killing
/// first; null for the hunt (no strike planned, done, or none to be had).
/datum/bot_brain/proc/apex_strike_turn()
	if(!apex_strike || sabotage_acts_left <= 0)
		return null
	if(world.time > apex_strike_deadline)
		sabotage_acts_left = 0
		sabotage_underway = null
		bot_log(src, "KILL PLAN: no strike to be had - straight to the hunt")
		return null
	if(try_sabotage())
		return TRUE
	return sabotage_underway ? FALSE : null

#undef BOT_STRIKE_PATIENCE

// ---------------------------------------------------------------------------------------------
// Denying escape
// ---------------------------------------------------------------------------------------------
// The shuttle's the crew's way off. Once it's called, the ones at departures or aboard are the ones about to get away, and all in one
// place: an apex rampager goes for them before anybody but its marks and the Captain.

/// Rank to add in next_victim() (goals/robust.dm: lower comes sooner), between the Captain's and Security's
#define BOT_ESCAPE_DENIAL_RANK -700

/datum/bot_scenario
	/// A Bot Gym run standing in for the shuttle being on its way, and for where departures is (escape_denial_rank())
	var/evac_under_way = FALSE
	var/list/departure_turfs

/datum/bot_brain/proc/escape_denial_rank(mob/living/carbon/human/H)
	if(traitor_plan != BOT_TRAITOR_RAMPAGE || !is_apex() || !shuttle_on_its_way() || !getting_away(H))
		return 0
	return BOT_ESCAPE_DENIAL_RANK

/datum/bot_brain/proc/shuttle_on_its_way()
	if(gym_run)
		return gym_run.evac_under_way
	return SSshuttle.emergency && (SSshuttle.emergency.mode == SHUTTLE_CALL || bot_shuttle_boarding()) //goals/evacuate.dm

/datum/bot_brain/proc/getting_away(mob/living/H)
	if(gym_run)
		return (get_turf(H) in gym_run.departure_turfs) ? TRUE : FALSE
	return bot_in_departures(H) || bot_aboard_shuttle(H)

#undef BOT_ESCAPE_DENIAL_RANK
