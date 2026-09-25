GLOBAL_VAR_INIT(bot_ai_debug, TRUE)
// Separate from bot_ai_debug - this is the noisy, per-decision trace (pathing pass
// results, per-node stuck diagnostics, etc.) meant for post-round log analysis, not
// live admin chat. bot_log_verbose() (bot_chat.dm) writes it to game.log only, never
// message_admins(), so it doesn't flood anyone watching the live feed.
GLOBAL_VAR_INIT(bot_ai_verbose, TRUE)

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

	var/rank = input(usr, "Select a job for the bot crew member", "Spawn Bot Crew Member") as null|anything in available
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
	set desc = "Streams bot AI decisions/actions to admin chat in realtime."

	if(!check_rights(R_FUN))
		return
	GLOB.bot_ai_debug = !GLOB.bot_ai_debug
	message_admins("[key_name(usr)] turned bot AI logging [GLOB.bot_ai_debug ? "ON" : "OFF"].")

/client/proc/admin_toggle_bot_ai_verbose()
	set name = "Toggle Bot AI Verbose Log"
	set category = "Fun"
	set desc = "Writes detailed bot AI pathing/decision traces to game.log for post-round analysis (silent - doesn't stream to admin chat)."

	if(!check_rights(R_FUN))
		return
	GLOB.bot_ai_verbose = !GLOB.bot_ai_verbose
	message_admins("[key_name(usr)] turned bot AI verbose logging [GLOB.bot_ai_verbose ? "ON" : "OFF"].")

/proc/spawn_bot_crew_member(rank = "Assistant")
	if(!SSticker?.IsRoundInProgress())
		return null

	var/mob/dead/new_player/NP = new()
	var/datum/bot_identity/identity = new(NP)
	NP.bot_identity = identity
	NP.real_name = identity.persona_name
	NP.mind_initialize()
	NP.ready = PLAYER_READY_TO_PLAY

	NP.AttemptLateSpawn(rank)

	var/mob/living/carbon/human/H = identity.spawned_human
	if(!H)
		return null

	new /datum/bot_brain(H)
	return H
