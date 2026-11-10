/// A test round: a Bot Gym, a Bot Shift or tools/bot_gym/run_live_round.sh (bot-mode), and not bot-quiet, which turns the bot
/// logs off for measuring what a crew costs without them.
/proc/bot_ai_logging_wanted()
	return ((BOT_GYM_PARAMETER in world.params) || (BOT_SHIFT_PARAMETER in world.params) || ("bot-mode" in world.params)) && !(BOT_QUIET_PARAMETER in world.params) //bot-mode: tools/bot_gym/run_live_round.sh

/// The bots' logs go to the files in every round but a bot-quiet one: since 2026-11-10 they cost the game little (bot_chat.dm), and
/// the user's own rounds are read back as test rounds are. bot-quiet turns them off.
/proc/bot_ai_files_wanted()
	return !(BOT_QUIET_PARAMETER in world.params)

/// Set once: a test round (bot_ai_logging_wanted()). For what only a test round pays for, like a route search just for a log line.
GLOBAL_VAR_INIT(bot_ai_test_round, bot_ai_logging_wanted())
/// bot_log()'s lines in admin chat as well: a test round's, or with the admin verb below
GLOBAL_VAR_INIT(bot_ai_debug, bot_ai_logging_wanted())
/// bot_log()'s lines in game.log ("ADMIN: BOT AI: name: line"), the bots' decisions in plain English
GLOBAL_VAR_INIT(bot_ai_log, bot_ai_files_wanted())
/// The noisy, per-decision trace (pathing pass results, per-node stuck diagnostics, etc.), for reading a round back: bot_log_verbose()
/// (bot_chat.dm) writes it compressed to bot_trace.log.zst, never to admin chat or game.log.
GLOBAL_VAR_INIT(bot_ai_verbose, bot_ai_files_wanted())

/client/proc/admin_spawn_bot_crew()
	set name = "Spawn Bot Crew Member"
	set category = "Fun"
	set desc = "AI crew Milestone 1: spawns an autonomous crew member, in a job of your choosing, that joins via the normal late-join pipeline."

	if(!check_rights(R_FUN))
		return

	var/list/available = list()
	for(var/datum/job/J in SSjob.occupations)
		if(!J.title || istype(J, /datum/job/ai) || istype(J, /datum/job/cyborg))
			continue //bots use the ordinary human late-join pipeline - AI/cyborg spawn through their own separate systems, not this one
		if(J.total_positions != -1 && J.current_positions >= J.total_positions)
			continue //slot full
		available += J.title
	if(!available.len)
		to_chat(usr, "<span class='warning'>No jobs currently have open slots.</span>")
		return
	available = sortList(available)

	var/rank = tgui_input_list(usr, "Select a job for the bot crew member", "Spawn Bot Crew Member", available)
	if(!rank)
		return

	var/mob/living/carbon/human/H = spawn_bot_crew_member(rank)
	if(H)
		message_admins("[key_name(usr)] spawned a bot crew member ([H.real_name]) as [rank].")
	else
		to_chat(usr, "<span class='warning'>Failed to spawn bot crew member as [rank] - is the round in progress, or did the slot just fill?</span>")

/client/proc/admin_toggle_bot_ai_log()
	set name = "Toggle Bot AI Log"
	set category = "Fun"
	set desc = "Streams bot AI decisions/actions to admin chat in realtime (game.log has them either way)."

	if(!check_rights(R_FUN))
		return
	GLOB.bot_ai_debug = !GLOB.bot_ai_debug
	message_admins("[key_name(usr)] turned bot AI logging in admin chat [GLOB.bot_ai_debug ? "ON" : "OFF"].")

/client/proc/admin_toggle_bot_ai_verbose()
	set name = "Toggle Bot AI Verbose Log"
	set category = "Fun"
	set desc = "Writes detailed bot AI pathing/decision traces to bot_trace.log.zst for post-round analysis (silent - doesn't stream to admin chat)."

	if(!check_rights(R_FUN))
		return
	GLOB.bot_ai_verbose = !GLOB.bot_ai_verbose
	message_admins("[key_name(usr)] turned bot AI verbose logging [GLOB.bot_ai_verbose ? "ON" : "OFF"].")

/// at_post stands them where the job starts, for the crew who are on shift when the round begins. Otherwise they arrive like a latejoiner.
/proc/spawn_bot_crew_member(rank = "Assistant", at_post = FALSE)
	if(!SSticker?.IsRoundInProgress())
		return null

	var/mob/dead/new_player/NP = new()
	var/datum/bot_identity/identity = new(NP)
	NP.bot_identity = identity
	NP.real_name = identity.persona_name
	NP.mind_initialize()
	NP.ready = PLAYER_READY_TO_PLAY

	if(at_post && bot_post_free(rank))
		NP.join_at_post(rank)
	else
		NP.AttemptLateSpawn(rank)

	var/mob/living/carbon/human/H = identity.spawned_human
	if(!H)
		return null

	new /datum/bot_brain(H)
	return H
